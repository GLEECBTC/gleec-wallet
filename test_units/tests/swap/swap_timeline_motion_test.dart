import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/views/swap/common/swap_copy.dart';
import 'package:web_dex/views/swap/execution/swap_timeline_view.dart';
import 'package:web_dex/views/swap/motion/swap_motion.dart';

import 'swap_common_ui_fakes.dart';

/// Covers how the timeline moves when a swap moves on: in order, within its
/// limit, with the screen-reader labels and single icons right at once.
void main() {
  group('timeline motion', () {
    useSwapUi();

    const d = SwapStepStatus.done;
    const c = SwapStepStatus.current;
    const n = SwapStepStatus.notStarted;
    const e = SwapStepStatus.error;

    List<SwapTimelineStep> steps(List<SwapStepStatus> statuses) => [
      for (final (i, status) in statuses.indexed)
        SwapTimelineStep(title: 'Step $i', detail: 'Detail $i', status: status),
    ];

    Future<void> show(
      WidgetTester tester,
      List<SwapStepStatus> statuses, {
      bool animate = true,
      bool reduceMotion = false,
      bool settle = false,
    }) => pumpSwapUi(
      tester,
      SwapTimelineView(steps: steps(statuses), animate: animate),
      media: (
        textScale: 1,
        boldText: false,
        reduceMotion: reduceMotion,
        announces: false,
      ),
      settle: settle,
    );

    Finder effectOf(IconData icon) => find.ancestor(
      of: find.byIcon(icon),
      matching: find.byType(SwapPaintEffect),
    );

    SwapStepLine line(WidgetTester tester, int index) => tester
        .widgetList<SwapStepLine>(find.byType(SwapStepLine))
        .elementAt(index);

    testWidgets('shows a change at once unless asked to animate', (
      tester,
    ) async {
      await show(tester, [c, n, n], animate: false, settle: true);
      await show(tester, [d, c, n], animate: false);
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.byType(SwapPaintEffect), findsNothing);
    });

    testWidgets('passes a change down the steps in order', (tester) async {
      await show(tester, [c, n, n], settle: true);
      await show(tester, [d, c, n]);
      await tester.pump(const Duration(milliseconds: 150));

      expect(
        tester.renderObject(effectOf(Icons.more_horiz_rounded)),
        paintsNothing,
      );
      expect(
        tester.renderObject(effectOf(Icons.check_rounded)),
        isNot(paintsNothing),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('says the new state to screen readers at once', (tester) async {
      await show(tester, [c, n, n], settle: true);
      await show(tester, [d, c, n]);

      final label = tester.getSemantics(find.byType(SwapTimelineView)).label;
      expect(label, contains('Completed: Step 0. Detail 0'));
      expect(label, contains('Current: Step 1. Detail 1'));
      await tester.pumpAndSettle();
    });

    testWidgets('keeps one icon per step in every frame', (tester) async {
      await show(tester, [c, n, n], settle: true);
      await show(tester, [d, c, n]);
      for (var frame = 0; frame < 8; frame++) {
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);
        expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
        expect(find.byIcon(Icons.circle_outlined), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
    });

    testWidgets('fills the line below a step as it completes', (tester) async {
      await show(tester, [c, n, n], settle: true);
      expect(line(tester, 0).fill.value, 0);

      await show(tester, [d, c, n]);
      await tester.pump(SwapMotion.step);
      expect(line(tester, 0).fill.value, inExclusiveRange(0, 1));

      await tester.pumpAndSettle();
      expect(line(tester, 0).fill.value, 1);
      expect(line(tester, 1).fill.value, 0);
    });

    testWidgets('sends out one ripple from a step that completes', (
      tester,
    ) async {
      await show(tester, [c, n, n], settle: true);
      await show(tester, [d, c, n]);
      await tester.pump(SwapMotion.ring ~/ 2);

      final ripple = tester.renderObject(
        find
            .descendant(
              of: find.byType(SwapPulse).first,
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      expect(ripple, paints..rrect(style: PaintingStyle.stroke));
      await tester.pumpAndSettle();
    });

    testWidgets('fits a jump of many steps into its limit', (tester) async {
      await show(tester, [c, n, n, n, n], settle: true);
      await show(tester, [d, d, d, d, c]);
      await tester.pump();
      await tester.pump(SwapMotion.cascadeLimit);
      for (var i = 0; i < 3; i++) {
        expect(line(tester, i).fill.value, 1);
      }
      await tester.pumpAndSettle();
    });

    testWidgets('an error pops in without overshoot and marks one step', (
      tester,
    ) async {
      await show(tester, [d, c, n], settle: true);
      await show(tester, [d, e, n]);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.priority_high_rounded), findsOneWidget);
    });

    testWidgets('shows a change at once with less motion', (tester) async {
      await show(tester, [c, n, n], reduceMotion: true, settle: true);
      await show(tester, [d, c, n], reduceMotion: true);
      expect(tester.hasRunningAnimations, isFalse);
      expect(line(tester, 0).fill.value, 1);
    });

    testWidgets('shows a change in the number of steps at once', (
      tester,
    ) async {
      await show(tester, [c, n, n], settle: true);
      await show(tester, [d, c, n, n]);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}

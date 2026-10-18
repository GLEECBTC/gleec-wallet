import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/common/swap_copy.dart';
import 'package:web_dex/views/swap/execution/swap_execution_view.dart';
import 'package:web_dex/views/swap/execution/swap_timeline_view.dart';
import 'package:web_dex/views/swap/motion/swap_motion.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

import 'swap_common_ui_fakes.dart';
import 'swap_surface_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the pulse on the step a swap is on: short bursts when something
/// happens, none while the engine is silent, and never more than five
/// seconds of motion at a time (WCAG 2.2.2).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const d = SwapStepStatus.done;
  const c = SwapStepStatus.current;
  const n = SwapStepStatus.notStarted;

  final current = find.byWidgetPredicate(
    (widget) => widget is SwapPulse && widget.onMount && widget.active,
  );

  RenderObject pulseOf(WidgetTester tester) => tester.renderObject(
    find.descendant(of: current, matching: find.byType(CustomPaint)).first,
  );

  /// How long motion runs from now, in 100 ms frames.
  Future<Duration> motionFrom(WidgetTester tester) async {
    var elapsed = Duration.zero;
    while (tester.hasRunningAnimations) {
      await tester.pump(const Duration(milliseconds: 100));
      elapsed += const Duration(milliseconds: 100);
    }
    return elapsed;
  }

  group('the step pulse', () {
    useSwapUi();

    List<SwapTimelineStep> steps(List<SwapStepStatus> statuses) => [
      for (final (i, status) in statuses.indexed)
        SwapTimelineStep(title: 'Step $i', detail: 'Detail $i', status: status),
    ];

    Future<void> show(
      WidgetTester tester,
      List<SwapStepStatus> statuses, {
      bool tracking = true,
      bool animate = true,
      Object? event,
      int resumes = 0,
      bool reduceMotion = false,
    }) => pumpSwapUi(
      tester,
      SwapTimelineView(
        steps: steps(statuses),
        animate: animate,
        tracking: tracking,
        event: event,
        resumes: resumes,
      ),
      media: (
        textScale: 1,
        boldText: false,
        reduceMotion: reduceMotion,
        announces: false,
      ),
      settle: false,
    );

    testWidgets('beats three times when the step first appears, then rests', (
      tester,
    ) async {
      await show(tester, [d, c, n]);
      expect(current, findsOneWidget);
      await tester.pump(SwapMotion.screen + SwapMotion.beat ~/ 2);
      expect(pulseOf(tester), paints..rrect(style: PaintingStyle.stroke));

      final total =
          SwapMotion.screen + SwapMotion.beat ~/ 2 + await motionFrom(tester);
      final burst =
          SwapMotion.screen + SwapMotion.beatSpacing * 2 + SwapMotion.beat;
      expect(total.inMilliseconds, closeTo(burst.inMilliseconds, 200));
      expect(pulseOf(tester), isNot(paints..rrect()));
    });

    testWidgets('does not beat while the engine is not answering', (
      tester,
    ) async {
      await show(tester, [d, c, n], tracking: false);
      expect(current, findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('beats twice once the steps have moved on', (tester) async {
      await show(tester, [c, n, n], event: 1);
      await tester.pumpAndSettle();
      await show(tester, [d, c, n], event: 2);
      await tester.pump();

      expect(pulseOf(tester), isNot(paints..rrect()));
      final total = await motionFrom(tester);
      expect(total, lessThanOrEqualTo(const Duration(seconds: 5)));
      expect(
        total,
        greaterThanOrEqualTo(SwapMotion.beatSpacing + SwapMotion.beat),
      );
    });

    testWidgets('beats once for any other news of the swap', (tester) async {
      await show(tester, [d, c, n], event: 1);
      await tester.pumpAndSettle();
      await show(tester, [d, c, n], event: 2);
      await tester.pump(SwapMotion.beat ~/ 2);
      expect(pulseOf(tester), paints..rrect(style: PaintingStyle.stroke));

      final total = await motionFrom(tester);
      expect(total, lessThan(SwapMotion.beat));
    });

    testWidgets('beats three times each time the app comes back', (
      tester,
    ) async {
      await show(tester, [d, c, n]);
      await tester.pumpAndSettle();
      await show(tester, [d, c, n], resumes: 1);
      expect(tester.hasRunningAnimations, isTrue);
      final total = await motionFrom(tester);
      expect(total, greaterThan(SwapMotion.beatSpacing * 2));
      expect(total, lessThanOrEqualTo(const Duration(seconds: 5)));
    });

    testWidgets('does not beat for a change it did not see happen', (
      tester,
    ) async {
      await show(tester, [c, n, n], animate: false, event: 1);
      await tester.pumpAndSettle();
      await show(tester, [d, c, n], animate: false, event: 2);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('stays still with less motion', (tester) async {
      await show(tester, [d, c, n], reduceMotion: true);
      expect(tester.hasRunningAnimations, isFalse);
      await show(tester, [d, c, n], reduceMotion: true, event: 2);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('the progress screen', () {
    late GatedExecutor routed;
    late SwapExecutionRegistry registry;
    late SurfaceServices services;
    late RecordingSwapBloc swap;
    late SwapShellController shell;

    setUpAll(loadSurfaceCopy);

    setUp(() {
      routed = GatedExecutor(SwapLiquiditySource.routed);
      registry = SwapExecutionRegistry(
        executors: [routed],
        inFlight: () async => const [],
      );
      services = SurfaceServices(registry);
      swap = RecordingSwapBloc(registry);
      shell = SwapShellController();
    });

    tearDown(() async {
      await swap.close();
      await registry.dispose();
      await services.dispose();
      shell.dispose();
      resetSurfaceCopy();
    });

    Future<FakeHandle> open(
      WidgetTester tester,
      SwapExecutionSnapshot snapshot,
    ) async {
      final handle = FakeHandle(snapshot);
      routed.resumable[snapshot.id] = handle;
      await pumpSurface(
        tester,
        SwapExecutionView(id: snapshot.id, context: SwapExecutionContext.flow),
        services: services,
        swap: swap,
        shell: shell,
        settle: false,
      );
      // The watch answers after a frame; the timeline appears with it.
      await tester.pump();
      await tester.pump();
      return handle;
    }

    testWidgets('pulses the step while the engine answers', (tester) async {
      await open(tester, snapshotOf());
      expect(current, findsOneWidget);
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
    });

    for (final (name, snapshot) in [
      ('delayed', snapshotOf(delayedSince: DateTime(2026, 9, 30))),
      (
        'waiting on the user',
        snapshotOf(stage: SwapProgressStage.actionRequired),
      ),
      ('finished', snapshotOf(outcome: completed())),
    ]) {
      testWidgets('keeps still when $name', (tester) async {
        await open(tester, snapshot);
        expect(current, findsNothing);
        await tester.pumpAndSettle();
      });
    }

    testWidgets('pulses again when the app comes back to the foreground', (
      tester,
    ) async {
      await open(tester, snapshotOf());
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);

      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
    });

    testWidgets('pulses after the swap moves on while watched', (tester) async {
      final handle = await open(tester, snapshotOf());
      await tester.pumpAndSettle();

      handle.push(snapshotOf(stage: SwapProgressStage.awaitingDelivery));
      await tester.pump();
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue);
      expect(
        await motionFrom(tester),
        lessThanOrEqualTo(const Duration(seconds: 5)),
      );
    });
  });
}

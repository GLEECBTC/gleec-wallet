import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/motion/swap_motion.dart';

import 'swap_common_ui_fakes.dart';
import 'swap_motion_fakes.dart';

/// Covers the status hero following a swap: tone, icon and copy move in on a
/// change, one of each on screen at every frame, and nothing moves unless
/// asked.
void main() {
  group('status hero motion', () {
    useSwapUi();

    const dark = SwapPalette.dark;

    Color tileColor(WidgetTester tester) =>
        (tester
                    .widget<Container>(
                      find
                          .ancestor(
                            of: find.byType(Icon),
                            matching: find.byType(Container),
                          )
                          .first,
                    )
                    .decoration!
                as BoxDecoration)
            .color!;

    Future<void> show(
      WidgetTester tester, {
      IconData icon = Icons.timer_outlined,
      String title = 'Confirming on Ethereum',
      String? body = 'Waiting for the network.',
      SwapTone tone = SwapTone.brand,
      SwapHeroMotion? motion = const SwapHeroMotion(),
      bool reduceMotion = false,
      bool settle = false,
    }) => pumpSwapUi(
      tester,
      SwapStatusHero(
        icon: icon,
        title: title,
        body: body,
        tone: tone,
        motion: motion,
      ),
      media: (
        textScale: 1,
        boldText: false,
        reduceMotion: reduceMotion,
        announces: false,
      ),
      settle: settle,
    );

    testWidgets('a hero without motion builds as it always has', (
      tester,
    ) async {
      await show(tester, motion: null, settle: true);
      expect(find.byType(SwapPop), findsNothing);
      expect(find.byType(SwapReveal), findsNothing);
      expect(find.byType(SwapPulse), findsNothing);
      expect(tileColor(tester), dark.selected);
    });

    testWidgets('nothing moves when it first appears', (tester) async {
      await show(tester);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('blends to a new tone, read through the tile', (tester) async {
      await show(tester, settle: true);
      await show(tester, tone: SwapTone.success, icon: Icons.check_circle);
      await tester.pump(SwapMotion.colour ~/ 2);
      expect(tileColor(tester), isNot(dark.selected));
      expect(tileColor(tester), isNot(dark.successBg));

      await tester.pumpAndSettle();
      expect(tileColor(tester), dark.successBg);
    });

    testWidgets('pops a new icon in, one icon in every frame', (tester) async {
      await show(tester, settle: true);
      await show(tester, icon: Icons.route_outlined);
      await tester.pump(SwapMotion.pop ~/ 4);
      expect(find.byType(Icon), findsOneWidget);
      expect(find.byIcon(Icons.timer_outlined), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.route_outlined), findsOneWidget);
    });

    testWidgets('raises new copy in, never two titles at once', (tester) async {
      await show(tester, settle: true);
      final still = opacityLayers(tester).length;
      await show(tester, title: 'Arriving on Ethereum');
      expect(find.text('Arriving on Ethereum'), findsOneWidget);
      expect(find.text('Confirming on Ethereum'), findsNothing);
      await tester.pump(SwapMotion.reveal ~/ 3);
      expect(opacityLayers(tester).length, greaterThan(still));

      await tester.pumpAndSettle();
      expect(opacityLayers(tester).length, still);
    });

    testWidgets('shows a change at once when it did not happen live', (
      tester,
    ) async {
      const still = SwapHeroMotion(animate: false);
      await show(tester, motion: still, settle: true);
      await show(
        tester,
        motion: still,
        tone: SwapTone.success,
        icon: Icons.check_circle,
        title: 'You received 3,001 USDC',
      );
      expect(tester.hasRunningAnimations, isFalse);
      expect(tileColor(tester), dark.successBg);
    });

    testWidgets('stays still with less motion', (tester) async {
      await show(tester, reduceMotion: true, settle: true);
      await show(
        tester,
        reduceMotion: true,
        tone: SwapTone.success,
        icon: Icons.check_circle,
        title: 'You received 3,001 USDC',
      );
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('turns an icon that unwinds as it settles', (tester) async {
      await show(tester, settle: true);
      await show(
        tester,
        icon: Icons.undo_rounded,
        motion: const SwapHeroMotion(
          iconTurns: 1,
          iconDuration: SwapMotion.ring,
        ),
      );
      await tester.pump();
      await tester.pump(SwapMotion.ring ~/ 5);
      expect(effectTransform(tester)!.entry(0, 1), isNot(0));
      await tester.pumpAndSettle();
    });

    testWidgets('pops its icon again when only the tone changes', (
      tester,
    ) async {
      await show(
        tester,
        icon: Icons.undo_rounded,
        tone: SwapTone.warning,
        settle: true,
      );
      await show(
        tester,
        icon: Icons.undo_rounded,
        tone: SwapTone.success,
        motion: const SwapHeroMotion(
          iconTurns: 1,
          iconDuration: SwapMotion.ring,
        ),
      );
      await tester.pump();
      await tester.pump(SwapMotion.ring ~/ 5);
      expect(effectTransform(tester), isNotNull);
      await tester.pumpAndSettle();
    });

    testWidgets('pops its icon again when only its key changes, as a refund '
        'lands', (tester) async {
      await show(
        tester,
        icon: Icons.undo_rounded,
        tone: SwapTone.warning,
        settle: true,
      );
      await show(
        tester,
        icon: Icons.undo_rounded,
        tone: SwapTone.warning,
        motion: const SwapHeroMotion(
          iconTurns: 1,
          iconDuration: SwapMotion.ring,
          iconKey: 'refunded',
        ),
      );
      await tester.pump();
      await tester.pump(SwapMotion.ring ~/ 5);
      expect(effectTransform(tester), isNotNull);
      await tester.pumpAndSettle();
    });

    testWidgets('spreads its ring once, when asked, and not on first show', (
      tester,
    ) async {
      await show(
        tester,
        motion: const SwapHeroMotion(ring: 'done'),
        settle: true,
      );
      expect(tester.hasRunningAnimations, isFalse);

      await show(tester, settle: true);
      await show(tester, motion: const SwapHeroMotion(ring: 'done'));
      await tester.pump(SwapMotion.ring ~/ 2);
      final ring = tester.renderObject(
        find
            .descendant(
              of: find.byType(SwapPulse),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      expect(ring, paints..rrect(style: PaintingStyle.stroke));
      await tester.pumpAndSettle();
      expect(ring, isNot(paints..rrect(style: PaintingStyle.stroke)));
    });

    testWidgets('keeps its spacing once settled', (tester) async {
      await pumpSwapUi(
        tester,
        const SwapStatusHero(
          icon: Icons.check,
          title: 'You received 3,001 USDC',
          body: 'Received on Ethereum.',
          action: Text('Start another'),
          motion: SwapHeroMotion(),
        ),
      );
      final title = tester.getRect(find.text('You received 3,001 USDC'));
      final body = tester.getRect(find.text('Received on Ethereum.'));
      expect(body.top, title.bottom + 8);
      expect(
        tester.getTopLeft(find.text('Start another')).dy,
        body.bottom + 16,
      );
    });
  });
}

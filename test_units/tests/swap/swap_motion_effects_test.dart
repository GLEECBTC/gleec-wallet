import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/views/swap/motion/swap_motion.dart';

import 'swap_motion_fakes.dart';

/// Covers the paint-only effects: each changes how its child is painted and
/// nothing else, finishes on its own, and stays still under reduced motion.
void main() {
  group('SwapReveal', () {
    testWidgets('fades and rises in on first appearance, then paints plainly', (
      tester,
    ) async {
      await tester.pumpWidget(motionApp(const SwapReveal(child: Text('Sent'))));
      await tester.pump(SwapMotion.reveal ~/ 2);
      final alpha = opacityLayers(tester).single.alpha!;
      expect(alpha, inExclusiveRange(0, 255));
      expect(effectTransform(tester)!.getTranslation().y, greaterThan(0));

      await tester.pumpAndSettle();
      expect(opacityLayers(tester), isEmpty);
      expect(effectTransform(tester), isNull);
    });

    testWidgets('leaves layout, taps and semantics where they settle', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(
        motionApp(
          SwapReveal(
            child: GestureDetector(
              onTap: () => taps++,
              child: const Text('Received'),
            ),
          ),
        ),
      );
      final early = tester.getRect(find.text('Received'));
      expect(find.text('Received'), findsOneWidget);
      expect(find.bySemanticsLabel('Received'), findsOneWidget);
      await tester.tap(find.text('Received'));
      expect(taps, 1);

      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('Received')), early);
      semantics.dispose();
    });

    testWidgets('paints nothing while it waits out its delay', (tester) async {
      await tester.pumpWidget(
        motionApp(
          const SwapReveal(
            delay: Duration(milliseconds: 200),
            child: Text('Later'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.renderObject(find.byType(SwapReveal)), paintsNothing);
      expect(find.text('Later'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(opacityLayers(tester), isEmpty);
    });

    testWidgets('plays again only when its key changes, and only if asked', (
      tester,
    ) async {
      Widget reveal(Object key, {bool animate = true}) => motionApp(
        SwapReveal(
          revealKey: key,
          onMount: false,
          animate: animate,
          child: Text('$key'),
        ),
      );
      await tester.pumpWidget(reveal('a'));
      expect(tester.hasRunningAnimations, isFalse);

      await tester.pumpWidget(reveal('a'));
      expect(tester.hasRunningAnimations, isFalse);

      await tester.pumpWidget(reveal('b'));
      expect(tester.hasRunningAnimations, isTrue);
      expect(find.text('a'), findsNothing);
      await tester.pumpAndSettle();

      await tester.pumpWidget(reveal('c', animate: false));
      expect(tester.hasRunningAnimations, isFalse);
      expect(opacityLayers(tester), isEmpty);
    });

    testWidgets('a screen arrives from the end edge going forward, mirrored '
        'right to left', (tester) async {
      Future<double> shiftOf({
        required bool forward,
        required TextDirection direction,
      }) async {
        await tester.pumpWidget(
          motionApp(
            SwapReveal.screen(
              revealKey: 'form',
              forward: forward,
              child: const Text('Page'),
            ),
            direction: direction,
          ),
        );
        await tester.pumpWidget(
          motionApp(
            SwapReveal.screen(
              revealKey: 'progress',
              forward: forward,
              child: const Text('Page'),
            ),
            direction: direction,
          ),
        );
        await tester.pump(SwapMotion.screen ~/ 3);
        final shift = effectTransform(tester)!.getTranslation().x;
        await tester.pumpAndSettle();
        return shift;
      }

      expect(
        await shiftOf(forward: true, direction: TextDirection.ltr),
        greaterThan(0),
      );
      expect(
        await shiftOf(forward: false, direction: TextDirection.ltr),
        lessThan(0),
      );
      expect(
        await shiftOf(forward: true, direction: TextDirection.rtl),
        lessThan(0),
      );
    });

    testWidgets('does not move when the user asked for less motion', (
      tester,
    ) async {
      await tester.pumpWidget(
        motionApp(const SwapReveal(child: Text('Still')), reduceMotion: true),
      );
      expect(tester.hasRunningAnimations, isFalse);
      expect(opacityLayers(tester), isEmpty);
    });

    testWidgets('finishes at once when less motion is asked for midway', (
      tester,
    ) async {
      await tester.pumpWidget(motionApp(const SwapReveal(child: Text('Go'))));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.hasRunningAnimations, isTrue);

      await tester.pumpWidget(
        motionApp(const SwapReveal(child: Text('Go')), reduceMotion: true),
      );
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      expect(opacityLayers(tester), isEmpty);
    });
  });

  group('SwapPop', () {
    Widget pop(Object trigger, {double turns = 0}) => motionApp(
      SwapPop(
        trigger: trigger,
        turns: turns,
        child: const SizedBox(width: 40, height: 40),
      ),
    );

    testWidgets('does not pop on first appearance', (tester) async {
      await tester.pumpWidget(pop(1));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('grows from smaller when its trigger changes', (tester) async {
      await tester.pumpWidget(pop(1));
      await tester.pumpWidget(pop(2));
      await tester.pump(SwapMotion.pop ~/ 4);
      expect(scaleOf(effectTransform(tester)!), lessThan(1));

      await tester.pumpAndSettle();
      expect(effectTransform(tester), isNull);
    });

    testWidgets('unwinds a turn as it settles', (tester) async {
      await tester.pumpWidget(pop(1, turns: 0.25));
      await tester.pumpWidget(pop(2, turns: 0.25));
      await tester.pump(SwapMotion.pop ~/ 4);
      expect(effectTransform(tester)!.entry(0, 1), isNot(0));
      await tester.pumpAndSettle();
    });
  });

  group('SwapPressScale', () {
    late int taps;

    Widget pressable({bool enabled = true}) => motionApp(
      SwapPressScale(
        enabled: enabled,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => taps++,
          child: const SizedBox(width: 120, height: 48),
        ),
      ),
    );

    setUp(() => taps = 0);

    testWidgets('presses down while held and lets the tap through', (
      tester,
    ) async {
      await tester.pumpWidget(pressable());
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SwapPressScale)),
      );
      await tester.pump();
      await tester.pump(SwapMotion.press);
      expect(scaleOf(effectTransform(tester)!), closeTo(0.97, 1e-6));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(effectTransform(tester), isNull);
      expect(taps, 1);
    });

    testWidgets('lets go once the pointer moves away', (tester) async {
      await tester.pumpWidget(pressable());
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SwapPressScale)),
      );
      await tester.pump();
      await tester.pump(SwapMotion.press);
      await gesture.moveBy(const Offset(0, kTouchSlop * 2));
      await tester.pumpAndSettle();
      expect(effectTransform(tester), isNull);
      await gesture.up();
    });

    testWidgets('stays still when disabled', (tester) async {
      await tester.pumpWidget(pressable(enabled: false));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SwapPressScale)),
      );
      await tester.pump();
      await tester.pump(SwapMotion.press);
      expect(effectTransform(tester), isNull);
      await gesture.up();
    });
  });

  group('SwapHaptics', () {
    testWidgets('plays on iOS and Android only', (tester) async {
      final played = recordHaptics(tester);
      for (final platform in TargetPlatform.values) {
        debugDefaultTargetPlatformOverride = platform;
        SwapHaptics.success();
      }
      debugDefaultTargetPlatformOverride = null;
      await tester.pump();

      expect(played, [
        'HapticFeedbackType.successNotification',
        'HapticFeedbackType.successNotification',
      ]);
    });

    testWidgets('maps each event to its pattern', (tester) async {
      final played = recordHaptics(tester);
      SwapHaptics.selection();
      SwapHaptics.light();
      SwapHaptics.medium();
      SwapHaptics.warning();
      SwapHaptics.error();
      await tester.pump();

      expect(played, [
        'HapticFeedbackType.selectionClick',
        'HapticFeedbackType.lightImpact',
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.warningNotification',
        'HapticFeedbackType.errorNotification',
      ]);
    });

    testWidgets('ignores a platform that refuses it', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (_) async => throw PlatformException(code: 'no-haptics'),
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      SwapHaptics.success();
      await tester.pump();
    });
  });

  testWidgets('a duration is none when the user asked for less motion', (
    tester,
  ) async {
    Future<Duration> durationWith({required bool reduceMotion}) async {
      late Duration duration;
      await tester.pumpWidget(
        motionApp(
          Builder(
            builder: (context) {
              duration = SwapMotion.of(context, SwapMotion.reveal);
              return const SizedBox.shrink();
            },
          ),
          reduceMotion: reduceMotion,
        ),
      );
      return duration;
    }

    expect(await durationWith(reduceMotion: false), SwapMotion.reveal);
    expect(await durationWith(reduceMotion: true), Duration.zero);
  });
}

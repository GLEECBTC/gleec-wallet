import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/views/swap/motion/swap_motion.dart';

import 'swap_motion_fakes.dart';

/// Covers the motion that follows content and state: blocks that grow to new
/// content, and the pulse that marks where a swap is.
void main() {
  group('SwapSmoothSize', () {
    Widget sized(
      double height, {
      bool animate = true,
      bool reduceMotion = false,
      VoidCallback? onTap,
    }) => motionApp(
      Align(
        alignment: Alignment.topCenter,
        child: SwapSmoothSize(
          animate: animate,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: SizedBox(width: 100, height: height),
          ),
        ),
      ),
      reduceMotion: reduceMotion,
    );

    double heightOf(WidgetTester tester) =>
        tester.getSize(find.byType(SwapSmoothSize)).height;

    testWidgets('takes its first size at once', (tester) async {
      await tester.pumpWidget(sized(40));
      expect(heightOf(tester), 40);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('grows to new content instead of jumping', (tester) async {
      await tester.pumpWidget(sized(40));
      await tester.pumpWidget(sized(100));
      await tester.pump(SwapMotion.grow ~/ 2);
      expect(heightOf(tester), inExclusiveRange(40, 100));
      expect(tester.layers.whereType<ClipRectLayer>(), isEmpty);

      await tester.pumpAndSettle();
      expect(heightOf(tester), 100);
    });

    testWidgets('lets a tap reach new content before the size catches up', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(sized(40, onTap: () => taps++));
      await tester.pumpWidget(sized(100, onTap: () => taps++));
      expect(heightOf(tester), lessThan(100));

      final top = tester.getTopLeft(find.byType(SwapSmoothSize));
      await tester.tapAt(top + const Offset(50, 90));
      expect(taps, 1);
      await tester.pumpAndSettle();
    });

    testWidgets('keeps growing when its content is replaced outright', (
      tester,
    ) async {
      Widget replaced(Key key, double height) => motionApp(
        Align(
          alignment: Alignment.topCenter,
          child: SwapSmoothSize(
            child: SizedBox(key: key, width: 100, height: height),
          ),
        ),
      );
      await tester.pumpWidget(replaced(const ValueKey(1), 40));
      await tester.pumpWidget(replaced(const ValueKey(2), 100));
      await tester.pump(SwapMotion.grow ~/ 2);
      await tester.pumpWidget(replaced(const ValueKey(3), 60));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(heightOf(tester), 60);
    });

    testWidgets('follows the content exactly when asked to', (tester) async {
      await tester.pumpWidget(sized(40, animate: false));
      await tester.pumpWidget(sized(100, animate: false));
      await tester.pump();
      expect(heightOf(tester), 100);
    });

    testWidgets('follows the content exactly with less motion', (tester) async {
      await tester.pumpWidget(sized(40, reduceMotion: true));
      await tester.pumpWidget(sized(100, reduceMotion: true));
      await tester.pump();
      expect(heightOf(tester), 100);
    });
  });

  group('SwapPulse', () {
    const color = Color(0xFF5A67F2);

    Widget pulse(
      Object trigger, {
      int beats = 3,
      bool active = true,
      bool onMount = false,
      bool reduceMotion = false,
      Duration delay = Duration.zero,
    }) => motionApp(
      SwapPulse(
        trigger: trigger,
        color: color,
        beats: beats,
        active: active,
        onMount: onMount,
        delay: delay,
        child: const SizedBox(width: 32, height: 32),
      ),
      reduceMotion: reduceMotion,
    );

    RenderObject painter(WidgetTester tester) => tester.renderObject(
      find.descendant(
        of: find.byType(SwapPulse),
        matching: find.byType(CustomPaint),
      ),
    );

    testWidgets('does nothing on first appearance unless asked', (
      tester,
    ) async {
      await tester.pumpWidget(pulse(1));
      expect(tester.hasRunningAnimations, isFalse);

      await tester.pumpWidget(pulse(1, onMount: true));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('beats on first appearance when asked', (tester) async {
      await tester.pumpWidget(pulse(1, onMount: true));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
    });

    testWidgets('beats each time its trigger changes, then stops', (
      tester,
    ) async {
      await tester.pumpWidget(pulse(1));
      await tester.pumpWidget(pulse(2));
      await tester.pump();
      await tester.pump(SwapMotion.beat ~/ 2);
      expect(painter(tester), paints..rrect(style: PaintingStyle.stroke));

      await tester.pump(SwapMotion.beatSpacing * 3);
      expect(tester.hasRunningAnimations, isFalse);
      expect(painter(tester), isNot(paints..rrect()));
    });

    testWidgets('lets pumpAndSettle return after a burst', (tester) async {
      await tester.pumpWidget(pulse(1));
      await tester.pumpWidget(pulse(2));
      final frames = await tester.pumpAndSettle();
      final burst = SwapMotion.beatSpacing * 2 + SwapMotion.beat;
      expect(frames, lessThanOrEqualTo(burst.inMilliseconds ~/ 100 + 2));
    });

    testWidgets('never runs a burst longer than five seconds', (tester) async {
      await tester.pumpWidget(pulse(1, delay: const Duration(seconds: 3)));
      expect(tester.takeException(), isAssertionError);
    });

    testWidgets('stays still while inactive or with less motion', (
      tester,
    ) async {
      await tester.pumpWidget(pulse(1, active: false));
      await tester.pumpWidget(pulse(2, active: false));
      expect(tester.hasRunningAnimations, isFalse);

      await tester.pumpWidget(pulse(1, reduceMotion: true));
      await tester.pumpWidget(pulse(2, reduceMotion: true));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('stops at once when it becomes inactive', (tester) async {
      await tester.pumpWidget(pulse(1));
      await tester.pumpWidget(pulse(2));
      await tester.pump(SwapMotion.beat ~/ 2);
      await tester.pumpWidget(pulse(2, active: false));
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      expect(painter(tester), isNot(paints..rrect()));
    });
  });
}

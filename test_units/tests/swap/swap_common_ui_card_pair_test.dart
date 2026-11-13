import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/views/swap/common/swap_card_pair.dart';

class _Recorder extends CustomPainter {
  _Recorder(this.name, this.log);

  final String name;
  final List<String> log;

  @override
  void paint(Canvas canvas, Size size) => log.add(name);

  @override
  bool shouldRepaint(_Recorder oldDelegate) => false;
}

/// The pay and receive cards with the switch over the seam between them.
void main() {
  const topKey = Key('top');
  const bottomKey = Key('bottom');
  const switchKey = Key('switch');

  SwapCardPair pair({
    Widget? top,
    Widget? bottom,
    Widget? switcher,
    double gap = 32,
  }) => SwapCardPair(
    top: top ?? const SizedBox(key: topKey, width: 100, height: 120),
    bottom: bottom ?? const SizedBox(key: bottomKey, width: 180, height: 80),
    switcher: switcher ?? const SizedBox(key: switchKey, width: 48, height: 48),
    gap: gap,
  );

  Future<void> pumpPair(
    WidgetTester tester,
    Widget child, {
    double width = 300,
    EnginePhase phase = EnginePhase.sendSemanticsUpdate,
  }) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, child: child),
      ),
    ),
    phase: phase,
  );

  RenderBox renderOf(WidgetTester tester) =>
      tester.renderObject<RenderBox>(find.byType(SwapCardPair));

  group('swap card pair', () {
    testWidgets('stacks full-width cards a gap apart, the switch centred on '
        'the seam', (tester) async {
      await pumpPair(tester, pair());

      expect(
        tester.getRect(find.byKey(topKey)),
        const Rect.fromLTWH(0, 0, 300, 120),
      );
      expect(
        tester.getRect(find.byKey(bottomKey)),
        const Rect.fromLTWH(0, 152, 300, 80),
      );
      expect(
        tester.getRect(find.byKey(switchKey)),
        const Rect.fromLTWH(126, 112, 48, 48),
      );
      expect(renderOf(tester).size, const Size(300, 232));
    });

    testWidgets('the switch never rises above the pair', (tester) async {
      await pumpPair(
        tester,
        pair(top: const SizedBox(key: topKey, height: 0), gap: 16),
      );

      expect(tester.getTopLeft(find.byKey(switchKey)), const Offset(126, 0));
    });

    testWidgets('the switch keeps its own size, within the width', (
      tester,
    ) async {
      await pumpPair(
        tester,
        pair(switcher: const SizedBox(key: switchKey, width: 400, height: 60)),
      );

      expect(
        tester.getRect(find.byKey(switchKey)),
        const Rect.fromLTWH(0, 106, 300, 60),
      );
    });

    testWidgets('paints both cards before the switch', (tester) async {
      final log = <String>[];
      CustomPaint painted(String name) => CustomPaint(
        painter: _Recorder(name, log),
        child: const SizedBox(height: 60),
      );
      await pumpPair(
        tester,
        pair(
          top: painted('top'),
          bottom: painted('bottom'),
          switcher: painted('switch'),
        ),
      );

      expect(log, ['top', 'bottom', 'switch']);
    });

    testWidgets('a tap on the seam reaches the switch, not the card beneath', (
      tester,
    ) async {
      final taps = <String>[];
      Widget tappable(String name, double width, double height) =>
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps.add(name),
            child: SizedBox(width: width, height: height),
          );
      await pumpPair(
        tester,
        pair(
          top: tappable('top', 300, 120),
          bottom: tappable('bottom', 300, 80),
          switcher: tappable('switch', 48, 48),
        ),
      );

      for (final (point, expected) in [
        (const Offset(150, 115), ['switch']),
        (const Offset(150, 155), ['switch']),
        (const Offset(150, 50), ['top']),
        (const Offset(150, 200), ['bottom']),
        (const Offset(20, 136), <String>[]),
      ]) {
        taps.clear();
        await tester.tapAt(point);
        await tester.pump();
        expect(taps, expected, reason: '$point');
      }
    });

    testWidgets('a new gap moves the bottom card; the same gap changes '
        'nothing', (tester) async {
      await pumpPair(tester, pair());
      expect(tester.getTopLeft(find.byKey(bottomKey)).dy, 152);

      await pumpPair(tester, pair(gap: 8), phase: EnginePhase.build);
      expect(renderOf(tester).debugNeedsLayout, isTrue);
      await pumpPair(tester, pair(gap: 8));
      expect(tester.getTopLeft(find.byKey(bottomKey)).dy, 128);
      expect(tester.getTopLeft(find.byKey(switchKey)).dy, 100);

      await pumpPair(tester, pair(gap: 8), phase: EnginePhase.build);
      expect(renderOf(tester).debugNeedsLayout, isFalse);
    });

    testWidgets('measures itself without laying out', (tester) async {
      await pumpPair(tester, pair());
      final box = renderOf(tester);

      expect(
        box.getDryLayout(const BoxConstraints(maxWidth: 200)),
        const Size(200, 232),
      );
      expect(
        box.getDryLayout(const BoxConstraints(maxWidth: 200, maxHeight: 100)),
        const Size(200, 100),
      );
    });

    testWidgets('a card that wraps measures taller when narrower', (
      tester,
    ) async {
      await pumpPair(
        tester,
        pair(
          top: const Text(
            'aaaa bbbb cccc',
            style: TextStyle(fontSize: 10, height: 1),
          ),
        ),
      );
      final box = renderOf(tester);

      expect(box.getDryLayout(const BoxConstraints(maxWidth: 140)).height, 122);
      expect(box.getDryLayout(const BoxConstraints(maxWidth: 40)).height, 142);
      expect(box.getMinIntrinsicHeight(40), 142);
      expect(box.getMaxIntrinsicHeight(140), 122);
      expect(box.getMinIntrinsicWidth(double.infinity), 180);
    });

    testWidgets('its height is both cards and the gap, its width the wider '
        'card', (tester) async {
      await pumpPair(tester, pair());
      final box = renderOf(tester);

      expect(box.getMinIntrinsicHeight(300), 232);
      expect(box.getMaxIntrinsicHeight(300), 232);
      expect(box.getMinIntrinsicWidth(500), 180);
      expect(box.getMaxIntrinsicWidth(500), 180);
    });

    testWidgets('sized to its intrinsic width, it is as wide as the wider '
        'card', (tester) async {
      await pumpPair(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: IntrinsicWidth(child: pair()),
        ),
      );

      expect(renderOf(tester).size, const Size(180, 232));
      expect(tester.getSize(find.byKey(topKey)), const Size(180, 120));
      expect(tester.getTopLeft(find.byKey(switchKey)).dx, 66);
    });
  });
}

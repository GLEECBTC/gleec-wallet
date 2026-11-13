import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

/// `AutoScrollText` waits before its first scroll, and again between passes.
/// Those waits used to be plain `Future.delayed`s, which cannot be cancelled,
/// so a widget disposed of mid-wait left the delay running. The test binding
/// fails on a timer that outlives the tree, so every widget test rendering one
/// - a DEX coin row, a transaction row, a withdrawal amount - failed on
/// `!timersPending` instead of on whatever it was written to assert, and the
/// suites worked around it by unmounting and pumping the delay away.
///
/// Both tests below assert by finishing: that same pending-timer check at
/// teardown is what catches a wait outliving its widget again.
void main() {
  testWidgets('disposing during the wait before the first scroll leaves no '
      'timer behind', (tester) async {
    await tester.pumpWidget(_host());

    // Part-way into the initial pause, so the wait is still outstanding.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('disposing between scroll passes leaves no timer behind', (
    tester,
  ) async {
    await tester.pumpWidget(_host());

    // Past the initial pause. The text is far wider than its column, so the
    // animation really did start and the pause under test is a real one.
    await tester.pump(const Duration(seconds: 3));
    expect(
      find.byKey(const ValueKey('AutoScrollText-Container')),
      findsOneWidget,
    );

    // Past the outbound pass, into the pause before it scrolls back.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('at ${scale}x text the scroll reaches the end of the text', (
      tester,
    ) async {
      await tester.pumpWidget(_host(textScale: scale));

      // Past the initial pause and the outbound pass.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 5));

      final paragraph = tester.renderObject<RenderParagraph>(find.text(_text));
      final textEnd =
          tester.getTopLeft(find.text(_text)).dx +
          paragraph.getMaxIntrinsicWidth(double.infinity);
      final columnEnd = tester.getTopRight(find.byKey(_column)).dx;
      expect(textEnd, closeTo(columnEnd, 1));

      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('a scrolling text fades at the edges where it is cut off', (
    tester,
  ) async {
    await tester.pumpWidget(_fadeHost());
    // At rest only its end is hidden.
    var edges = await _brightness(tester, [1, 50, 98]);
    expect(edges[0], 255);
    expect(edges[1], 255);
    expect(edges[2], lessThan(128));

    // Part-way through the pass, both ends are hidden. The pass starts on
    // the frame after the initial pause ends.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 2));
    edges = await _brightness(tester, [1, 50, 98]);
    expect(edges[0], lessThan(128));
    expect(edges[1], 255);
    expect(edges[2], lessThan(128));

    // At the end of the pass only its start is hidden.
    await tester.pump(const Duration(seconds: 3));
    edges = await _brightness(tester, [1, 50, 98]);
    expect(edges[0], lessThan(128));
    expect(edges[1], 255);
    expect(edges[2], 255);

    // Scrolled back to its start, only its end is hidden again.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 5));
    edges = await _brightness(tester, [1, 50, 98]);
    expect(edges[0], 255);
    expect(edges[1], 255);
    expect(edges[2], lessThan(128));

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

const _text = 'A coin name far too long for its column';
const _column = ValueKey('column');

Widget _host({double textScale = 1}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: const Scaffold(
      body: Center(
        child: SizedBox(
          key: _column,
          width: 40,
          child: AutoScrollText(text: _text),
        ),
      ),
    ),
  ),
);

const _shot = ValueKey('shot');

/// A solid white bar of text, 300 wide in the test font's square glyphs, in
/// a column 100 wide on black: a pixel's brightness says how far it is faded.
Widget _fadeHost() => MaterialApp(
  home: Scaffold(
    body: Center(
      child: RepaintBoundary(
        key: _shot,
        child: ColoredBox(
          color: Colors.black,
          child: SizedBox(
            width: 100,
            child: AutoScrollText(
              text: 'X' * 30,
              style: const TextStyle(fontSize: 10, color: Colors.white),
            ),
          ),
        ),
      ),
    ),
  ),
);

/// The brightness, 0 to 255, of the column's pixels [xs] across its middle.
Future<List<int>> _brightness(WidgetTester tester, List<double> xs) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_shot),
  );
  final image = (await tester.runAsync(boundary.toImage))!;
  final data = (await tester.runAsync(image.toByteData))!;
  final y = image.height ~/ 2;
  final result = [
    for (final x in xs) data.getUint8((y * image.width + x.round()) * 4),
  ];
  image.dispose();
  return result;
}

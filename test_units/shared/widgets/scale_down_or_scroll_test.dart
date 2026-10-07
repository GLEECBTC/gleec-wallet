import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

const _child = ValueKey('child');
const _box = ValueKey('box');

/// A child [childWidth] wide in a box [boxWidth] wide.
Widget _host({
  required double boxWidth,
  double childWidth = 200,
  VoidCallback? onTap,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        key: _box,
        width: boxWidth,
        child: ScaleDownOrScroll(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: SizedBox(key: _child, width: childWidth, height: 20),
          ),
        ),
      ),
    ),
  ),
);

/// How far the child is shrunk: 1 at full size.
double _scaleOf(WidgetTester tester) =>
    tester.getRect(find.byKey(_child)).width / 200;

/// Past the scroll's initial pause and its outbound pass.
Future<void> _scrollOut(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(seconds: 5));
}

void main() {
  testWidgets('a child that fits is drawn at full size and never moves', (
    tester,
  ) async {
    await tester.pumpWidget(_host(boxWidth: 300));
    final start = tester.getRect(find.byKey(_child));
    expect(_scaleOf(tester), 1);

    await _scrollOut(tester);
    expect(tester.getRect(find.byKey(_child)), start);
  });

  testWidgets('a child a little too wide shrinks to fit', (tester) async {
    await tester.pumpWidget(_host(boxWidth: 180));
    expect(_scaleOf(tester), closeTo(0.9, 0.001));
    expect(
      tester.getRect(find.byKey(_child)).right,
      lessThanOrEqualTo(tester.getRect(find.byKey(_box)).right + 0.01),
    );
  });

  testWidgets('a child too wide to shrink legibly scrolls to its end', (
    tester,
  ) async {
    await tester.pumpWidget(_host(boxWidth: 100));
    expect(_scaleOf(tester), closeTo(0.8, 0.001));
    // Starts at its leading edge.
    expect(
      tester.getRect(find.byKey(_child)).left,
      closeTo(tester.getRect(find.byKey(_box)).left, 0.01),
    );

    await _scrollOut(tester);
    expect(
      tester.getRect(find.byKey(_child)).right,
      closeTo(tester.getRect(find.byKey(_box)).right, 0.5),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an overflow too small to scroll shrinks a little further', (
    tester,
  ) async {
    // At 0.8 the child is 160 wide: 3 px over, under the scroll threshold.
    await tester.pumpWidget(_host(boxWidth: 157));
    expect(_scaleOf(tester), closeTo(157 / 200, 0.001));

    await _scrollOut(tester);
    expect(
      tester.getRect(find.byKey(_child)).right,
      lessThanOrEqualTo(tester.getRect(find.byKey(_box)).right + 0.01),
    );
  });

  testWidgets('taps reach the part of the child drawn under them', (
    tester,
  ) async {
    final taps = <String>[];
    Widget half(String name) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => taps.add(name),
      child: const SizedBox(width: 100, height: 20),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              key: _box,
              width: 100,
              child: ScaleDownOrScroll(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [half('start'), half('end')],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final box = tester.getRect(find.byKey(_box));

    // At rest the box shows the child's start; scrolled, its end.
    await tester.tapAt(box.centerRight - const Offset(2, 0));
    await _scrollOut(tester);
    await tester.tapAt(box.centerLeft + const Offset(2, 0));
    await tester.tapAt(box.centerRight - const Offset(2, 0));
    expect(taps, ['end', 'start', 'end']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('room to fit stops the scroll and puts the child back', (
    tester,
  ) async {
    await tester.pumpWidget(_host(boxWidth: 100));
    await tester.pump(const Duration(seconds: 4));

    await tester.pumpWidget(_host(boxWidth: 300));
    await tester.pump();
    final rest = tester.getRect(find.byKey(_child));
    expect(_scaleOf(tester), 1);

    // No scroll left running unseen: it would keep asking for frames.
    var framesAsked = 0;
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (tester.binding.hasScheduledFrame) framesAsked++;
    }
    expect(framesAsked, 0);
    expect(tester.getRect(find.byKey(_child)), rest);
  });

  testWidgets('disposing during a pause leaves no timer behind', (
    tester,
  ) async {
    await tester.pumpWidget(_host(boxWidth: 100));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

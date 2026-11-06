import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';

import 'swap_accessibility_checks.dart';
import 'swap_common_ui_fakes.dart';

/// A detail row's value sits at the row's end and still wraps at 200% text,
/// and a ticker monogram always reads in capitals.
void main() {
  group('swap widget fixes', () {
    useSwapUi();

    group('detail row value', () {
      RenderParagraph paragraphOf(WidgetTester tester, String text) =>
          tester.renderObject<RenderParagraph>(find.text(text));

      testWidgets('is drawn against the right edge, however short', (
        tester,
      ) async {
        await pumpSwapUi(
          tester,
          const SizedBox(
            width: 400,
            child: SwapDetailRow(label: 'Network fee', value: r'$3.20'),
          ),
        );

        final paragraph = paragraphOf(tester, r'$3.20');
        final ink = paragraph.getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 5),
        );
        final left = paragraph.localToGlobal(Offset(ink.first.left, 0)).dx;
        final right = paragraph.localToGlobal(Offset(ink.last.right, 0)).dx;
        expect(right, moreOrLessEquals(400, epsilon: 0.5));
        expect(right - left, lessThan(100));
      });

      testWidgets('wraps within its half at 200% text, cutting nothing', (
        tester,
      ) async {
        const value =
            'Stops before anything is sent if the latest price would pay '
            'less than the minimum';
        await pumpSwapUi(
          tester,
          const SizedBox(
            width: 400,
            child: SwapDetailRow(label: 'Minimum guard', value: value),
          ),
          media: (
            textScale: 2,
            boldText: false,
            reduceMotion: false,
            announces: false,
          ),
        );

        expect(tester.takeException(), isNull);
        final label = tester.getRect(find.text('Minimum guard'));
        final rect = tester.getRect(find.text(value));
        expect(rect.left, label.right + 18);
        expect(rect.right, 400);
        final lines = paragraphOf(tester, value)
            .getBoxesForSelection(
              const TextSelection(baseOffset: 0, extentOffset: value.length),
            )
            .map((box) => box.top.round())
            .toSet();
        expect(lines.length, greaterThan(2));
        await expectSwapAccessible(tester, largeText: true);
      });
    });

    testWidgets('a ticker monogram is capitals, or "?" when blank', (
      tester,
    ) async {
      for (final (ticker, shown) in [
        ('eth', 'ETH'),
        ('stETH', 'STE'),
        ('wBtc', 'WBT'),
        ('  ', '?'),
        ('', '?'),
      ]) {
        await pumpSwapUi(tester, Center(child: SwapTokenIcon(ticker: ticker)));
        expect(find.text(shown), findsOneWidget, reason: '"$ticker"');
      }
    });
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/views/wallet/wallet_page/common/mobile_coin_row_title.dart';

/// The app's font, under a name no other test uses: the default test font
/// draws every glyph as a square, which says nothing about real fit.
const _font = 'MobileRowManrope';
const _iconWidth = 34.0;
const _name = 'Verus Coin';

const _amountStyle = TextStyle(
  fontFamily: _font,
  fontSize: 16,
  fontWeight: FontWeight.w700,
);
const _smallStyle = TextStyle(fontFamily: _font, fontSize: 12);

Future<void> _loadFont() async {
  final loader = FontLoader(_font);
  for (final weight in ['Regular', 'Bold']) {
    final bytes = File('assets/fonts/Manrope-$weight.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

/// The title's width for a phone [screen] wide: the row's padding, expand
/// chevron and actions menu take 120 px of it.
double _titleWidth(double screen) => screen - 120;

/// The most either value column may take.
double _valueMax(double title) => (title - _iconWidth - 8 - 8) / 2;

Future<void> _pump(
  WidgetTester tester, {
  required double screen,
  required String amount,
  String price = r'↑ $0.20 (+1.01%)',
  String fiat = r'$2,954.53',
  double textScale = 1,
  TextStyle amountStyle = _amountStyle,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: _titleWidth(screen),
              child: MobileCoinRowTitle(
                icon: const SizedBox(width: _iconWidth, height: _iconWidth),
                name: const Text(
                  _name,
                  style: _amountStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                price: Text(price, style: _smallStyle),
                amount: amount,
                amountStyle: amountStyle,
                fiat: Text(fiat, style: _smallStyle),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// How far [text] is shrunk to fit: 1 when it is drawn at full size.
double _scaleOf(WidgetTester tester, String text) {
  final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
  // Drawn width over laid-out width: the rect carries any scaling above it.
  return tester.getRect(find.text(text)).width / paragraph.size.width;
}

/// Whether [amount] scrolls rather than shrinking further.
bool _scrolls(WidgetTester tester, String amount) => find
    .ancestor(of: find.text(amount), matching: find.byType(AutoScrollText))
    .evaluate()
    .isNotEmpty;

/// The font size [amount] is drawn at, after the text size setting and any
/// shrinking to fit.
double _drawnSize(WidgetTester tester, String amount) {
  final paragraph = tester.renderObject<RenderParagraph>(find.text(amount));
  final size = paragraph.textScaler.scale(paragraph.text.style!.fontSize!);
  return _scrolls(tester, amount) ? size : size * _scaleOf(tester, amount);
}

/// The smallest the amount may be drawn at [textScale].
double _minSize(double textScale) =>
    MobileCoinRowTitle.minScale * _amountStyle.fontSize! * textScale;

/// Unmounts the row, so a scrolling amount leaves no timer running.
Future<void> _unmount(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox.shrink());

void testMobileCoinRowTitle() {
  group('Mobile wallet row title', () {
    setUpAll(_loadFont);

    for (final screen in [320.0, 360.0, 412.0]) {
      for (final textScale in [1.0, 2.0]) {
        for (final amount in [
          '14,772.12 VRSC',
          '4,430 KMD',
          '1,234.56 USDT-ERC20',
          '0.0123 GLEEC',
          '123,456,789.12 SHIB',
          '**** VRSC',
        ]) {
          testWidgets(
            'shows "$amount" whole and legible on a ${screen.toInt()} dp '
            'phone at ${textScale}x text',
            (tester) async {
              await _pump(
                tester,
                screen: screen,
                amount: amount,
                textScale: textScale,
              );

              expect(tester.takeException(), isNull);
              final valueMax = _valueMax(_titleWidth(screen));
              // Shrinking rather than scrolling an overflow too small to
              // scroll may go below the minimum by that overflow.
              final allowance = _scrolls(tester, amount)
                  ? 1
                  : valueMax /
                        (valueMax + AutoScrollText.animationThresholdWidth);
              expect(
                _drawnSize(tester, amount),
                greaterThanOrEqualTo(_minSize(textScale) * allowance - 0.01),
              );
              if (_scrolls(tester, amount)) {
                // Too wide to shrink further: it scrolls within its column.
                expect(
                  tester.getSize(find.byType(AutoScrollText)).width,
                  lessThanOrEqualTo(valueMax + 0.01),
                );
              } else {
                // Laid out at its full width, then scaled: no digit is cut.
                final paragraph = tester.renderObject<RenderParagraph>(
                  find.text(amount),
                );
                expect(
                  paragraph.size.width,
                  closeTo(
                    paragraph.getMaxIntrinsicWidth(double.infinity),
                    0.01,
                  ),
                );
                final fitted = tester.getSize(
                  find
                      .ancestor(
                        of: find.text(amount),
                        matching: find.byType(FittedBox),
                      )
                      .first,
                );
                expect(fitted.width, lessThanOrEqualTo(valueMax + 0.01));
              }
              await _unmount(tester);
            },
          );
        }
      }
    }

    testWidgets('on a 360 dp phone the reported balances stay legible', (
      tester,
    ) async {
      await _pump(tester, screen: 360, amount: '14,772.12 VRSC');
      expect(_scrolls(tester, '14,772.12 VRSC'), isFalse);
      expect(_scaleOf(tester, '14,772.12 VRSC'), greaterThanOrEqualTo(0.8));
      // The name still fits beside it.
      final name = tester.renderObject<RenderParagraph>(find.text(_name));
      expect(name.didExceedMaxLines, isFalse);

      await _pump(tester, screen: 360, amount: '4,430 KMD');
      expect(_scaleOf(tester, '4,430 KMD'), 1);
    });

    testWidgets('an amount too wide to shrink scrolls to its last digit', (
      tester,
    ) async {
      const amount = '123,456,789.12 SHIB';
      await _pump(tester, screen: 320, amount: amount, textScale: 2);
      expect(_scrolls(tester, amount), isTrue);

      // Past the scroll's initial pause and its outbound pass.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 5));

      final paragraph = tester.renderObject<RenderParagraph>(find.text(amount));
      final textEnd =
          tester.getTopLeft(find.text(amount)).dx +
          paragraph.getMaxIntrinsicWidth(double.infinity);
      expect(
        textEnd,
        closeTo(tester.getTopRight(find.byType(AutoScrollText)).dx, 1),
      );
      await _unmount(tester);
    });

    // Overflows at the smallest size too little for AutoScrollText to scroll.
    for (final overflow in [1.0, 2.5, 4.5]) {
      testWidgets(
        'an amount ${overflow}px too wide at its smallest is not cut short',
        (tester) async {
          const amount = '14,772.12 VRSC';
          // Not inheriting the theme's letter spacing, so this painter
          // measures what the row draws.
          final style = _amountStyle.copyWith(inherit: false);
          final painter = TextPainter(
            text: TextSpan(
              text: amount,
              style: style.copyWith(
                fontSize: style.fontSize! * MobileCoinRowTitle.minScale,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          final valueMax = painter.width - overflow;
          painter.dispose();
          await _pump(
            tester,
            screen: 2 * valueMax + _iconWidth + 16 + 120,
            amount: amount,
            amountStyle: style,
          );

          // Past the scroll's initial pause and its outbound pass.
          await tester.pump(const Duration(seconds: 3));
          await tester.pump(const Duration(seconds: 5));

          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(amount),
          );
          final drawnEnd = _scrolls(tester, amount)
              ? tester.getTopLeft(find.text(amount)).dx +
                    paragraph.getMaxIntrinsicWidth(double.infinity)
              : tester.getTopRight(find.text(amount)).dx;
          final columnEnd = tester
              .getTopRight(find.byType(MobileCoinRowTitle))
              .dx;
          expect(drawnEnd, lessThanOrEqualTo(columnEnd + 0.5));
          await _unmount(tester);
        },
      );
    }

    testWidgets('the amount grows with the text size setting', (tester) async {
      const amount = '14,772.12 VRSC';
      await _pump(tester, screen: 360, amount: amount);
      final normal = _drawnSize(tester, amount);

      await _pump(tester, screen: 360, amount: amount, textScale: 1.5);
      final large = _drawnSize(tester, amount);

      expect(large, greaterThan(normal));
      expect(large, greaterThanOrEqualTo(_minSize(1.5) - 0.01));
      await _unmount(tester);
    });

    testWidgets('a long price is not squeezed by a long amount', (
      tester,
    ) async {
      await _pump(
        tester,
        screen: 360,
        amount: '0.12345678 BTC',
        price: r'↑ $64,123.45 (+2.45%)',
        fiat: r'$7,913.45',
      );

      expect(tester.takeException(), isNull);
      expect(_scaleOf(tester, r'↑ $64,123.45 (+2.45%)'), 1);
    });

    for (final screen in [320.0, 360.0, 412.0]) {
      for (final textScale in [1.0, 2.0]) {
        for (final price in [
          r'↑ $0.20 (+1.01%)',
          r'↑ $64,123.45 (+2.45%)',
          r'↓ $0.000012 (-13.10%)',
        ]) {
          testWidgets(
            'shows the price "$price" legibly on a ${screen.toInt()} dp '
            'phone at ${textScale}x text',
            (tester) async {
              await _pump(
                tester,
                screen: screen,
                amount: '14,772.12 VRSC',
                price: price,
                textScale: textScale,
              );

              expect(tester.takeException(), isNull);
              final column = tester.getRect(find.byType(ScaleDownOrScroll));
              // Shrinking rather than scrolling an overflow too small to
              // scroll may go below the minimum by that overflow.
              final allowance =
                  column.width /
                  (column.width + AutoScrollText.animationThresholdWidth);
              expect(
                _scaleOf(tester, price),
                greaterThanOrEqualTo(
                  MobileCoinRowTitle.minScale * allowance - 0.001,
                ),
              );
              // At rest it starts inside its column.
              expect(
                tester.getRect(find.text(price)).left,
                greaterThanOrEqualTo(column.left - 0.01),
              );
              await _unmount(tester);
            },
          );
        }
      }
    }

    testWidgets('a price too wide to shrink scrolls to its end', (
      tester,
    ) async {
      const price = r'↑ $64,123.45 (+2.45%)';
      await _pump(
        tester,
        screen: 320,
        amount: '14,772.12 VRSC',
        price: price,
        textScale: 2,
      );
      final column = tester.getRect(find.byType(ScaleDownOrScroll));
      expect(tester.getRect(find.text(price)).right, greaterThan(column.right));

      // Past the scroll's initial pause and its outbound pass.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 5));

      expect(
        tester.getRect(find.text(price)).right,
        closeTo(column.right, 0.5),
      );
      await _unmount(tester);
    });

    testWidgets('large text shrinks or scrolls instead of overflowing', (
      tester,
    ) async {
      await _pump(
        tester,
        screen: 320,
        amount: '14,772.12 VRSC',
        price: r'↑ $64,123.45 (+2.45%)',
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('14,772.12 VRSC'), findsOneWidget);
      await _unmount(tester);
    });
  });
}

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
                amountStyle: _amountStyle,
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
  final fitted = tester.getSize(
    find.ancestor(of: find.text(text), matching: find.byType(FittedBox)).first,
  );
  // A box that fills its column is wider than text drawn at full size.
  return math.min(1, fitted.width / paragraph.size.width);
}

void testMobileCoinRowTitle() {
  group('Mobile wallet row title', () {
    setUpAll(_loadFont);

    for (final screen in [320.0, 360.0, 412.0]) {
      for (final amount in [
        '14,772.12 VRSC',
        '4,430 KMD',
        '1,234.56 USDT-ERC20',
        '0.0123 GLEEC',
        '123,456,789.12 SHIB',
        '**** VRSC',
      ]) {
        testWidgets('shows "$amount" whole on a ${screen.toInt()} dp phone', (
          tester,
        ) async {
          await _pump(tester, screen: screen, amount: amount);

          expect(tester.takeException(), isNull);
          // Laid out at its full width, then scaled: no digit is cut off.
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(amount),
          );
          expect(
            paragraph.size.width,
            closeTo(paragraph.getMaxIntrinsicWidth(double.infinity), 0.01),
          );
          final fitted = tester.getSize(
            find
                .ancestor(
                  of: find.text(amount),
                  matching: find.byType(FittedBox),
                )
                .first,
          );
          expect(
            fitted.width,
            lessThanOrEqualTo(_valueMax(_titleWidth(screen)) + 0.01),
          );
        });
      }
    }

    testWidgets('on a 360 dp phone the reported balances stay legible', (
      tester,
    ) async {
      await _pump(tester, screen: 360, amount: '14,772.12 VRSC');
      expect(_scaleOf(tester, '14,772.12 VRSC'), greaterThanOrEqualTo(0.8));
      // The name still fits beside it.
      final name = tester.renderObject<RenderParagraph>(find.text(_name));
      expect(name.didExceedMaxLines, isFalse);

      await _pump(tester, screen: 360, amount: '4,430 KMD');
      expect(_scaleOf(tester, '4,430 KMD'), 1);
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

    testWidgets('large text shrinks to fit instead of overflowing', (
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
    });
  });
}

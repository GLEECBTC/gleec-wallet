// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/views/swap/entry/swap_amount_cards.dart';
import 'package:web_dex/views/swap/entry/swap_entry_view.dart';

import 'swap_accessibility_checks.dart';
import 'swap_entry_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the two amount cards: the addresses under them, which copy in
/// full, and how the amount and the asset share a card at every width and
/// text size.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpSwapUi();

  late RecordingSwapBloc swap;
  late FakeSwapServices services;

  setUp(() {
    swap = RecordingSwapBloc();
    services = FakeSwapServices();
  });

  tearDown(() => swap.close());

  const payAddress = '0x5520D7F51C8e3108FA2d9C6220bF4Aa8F9c17B91';
  const receiveAddress = '0x80A1c2d4E5f60718293a4B5c6D7e8F9012A342F0';

  Future<void> pump(
    WidgetTester tester,
    UnifiedSwapState state, {
    Size size = const Size(420, 1600),
    double textScale = 1,
  }) async {
    swap.emit(state);
    await pumpSwapUi(
      tester,
      const SwapEntryView(),
      bloc: swap,
      services: services,
      size: size,
      textScale: textScale,
    );
  }

  group('the addresses', () {
    testWidgets('are shortened under each card, and copy in full on tap', (
      tester,
    ) async {
      final copied = recordClipboard(tester);
      await pump(
        tester,
        swapPricedForm().copyWith(
          payAddress: payAddress,
          receiveAddress: receiveAddress,
        ),
      );

      expect(find.text('From 0x5520…7B91'), findsOneWidget);
      expect(
        tester.getSemantics(find.text('From 0x5520…7B91')),
        isSemantics(
          label: 'From $payAddress. Copy address',
          isButton: true,
          hasTapAction: true,
        ),
      );

      await tester.tap(find.text('From 0x5520…7B91'));
      await tester.pumpAndSettle();
      expect(copied, [payAddress]);
      expect(find.text('Address copied'), findsOneWidget);

      await tester.tap(find.text('To 0x80A1…42F0'));
      await tester.pumpAndSettle();
      expect(copied, [payAddress, receiveAddress]);
    });

    testWidgets('an option reports its own, which win over the wallet\'s', (
      tester,
    ) async {
      final quote = quoteWith(
        quoteOf(),
        fromAddress: '0xFROM000000000000000000000000000000000001',
        toAddress: '0xTO00000000000000000000000000000000000002',
      );
      await pump(
        tester,
        swapPricedForm(
          ranked: [quote],
        ).copyWith(payAddress: payAddress, receiveAddress: receiveAddress),
      );

      expect(find.text('From 0xFROM…0001'), findsOneWidget);
      expect(find.text('To 0xTO00…0002'), findsOneWidget);
      expect(find.text('From 0x5520…7B91'), findsNothing);
    });

    testWidgets('before either is known, nothing is offered to copy', (
      tester,
    ) async {
      await pump(tester, swapPricedForm());

      expect(find.textContaining('From '), findsNothing);
      expect(find.textContaining('To '), findsNothing);
      expect(find.bySemanticsLabel(RegExp('Copy address')), findsNothing);
    });
  });

  testWidgets('each asset button names its side, asset and network', (
    tester,
  ) async {
    await pump(tester, swapPricedForm());

    final pills = find.byType(SwapAssetPill);
    expect(
      tester.getSemantics(pills.first),
      isSemantics(
        label: 'You pay: ETH, Ethereum',
        isButton: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(pills.last),
      isSemantics(label: 'You receive: USDC, Ethereum', isButton: true),
    );
  });

  group('the amount and the asset', () {
    final field = find.byKey(const Key('swap-amount'));
    final payPill = find.byType(SwapAssetPill).first;

    void expectSideBySide(WidgetTester tester) {
      expect(
        tester.getTopLeft(payPill).dx,
        greaterThan(tester.getTopRight(field).dx),
      );
      expect(
        tester.getTopLeft(payPill).dy,
        lessThan(tester.getBottomLeft(field).dy),
      );
    }

    void expectStacked(WidgetTester tester) {
      expect(above(tester, field, payPill), isTrue);
      expect(tester.getTopLeft(payPill).dx, tester.getTopLeft(field).dx);
    }

    testWidgets('sit side by side on a phone', (tester) async {
      await pump(tester, swapPricedForm());
      expectSideBySide(tester);
      // The pill takes at most half the row.
      final row = tester.getSize(find.byType(SwapPayCard));
      expect(tester.getSize(payPill).width, lessThanOrEqualTo(row.width / 2));
    });

    testWidgets('stack on a screen too narrow to share', (tester) async {
      await pump(tester, swapPricedForm(), size: const Size(300, 1600));
      expectStacked(tester);
    });

    testWidgets('stack at 200% text on a phone, nothing cut or split', (
      tester,
    ) async {
      await pump(
        tester,
        swapPricedForm().copyWith(payAddress: payAddress),
        size: const Size(375, 2400),
        textScale: 2,
      );
      expectStacked(tester);
      await expectSwapAccessible(tester, largeText: true);
    });

    testWidgets('stack at 200% text on a wide screen, the pill kept whole', (
      tester,
    ) async {
      await pump(
        tester,
        swapPricedForm(),
        size: const Size(1024, 2400),
        textScale: 2,
      );
      expectStacked(tester);
      await expectSwapAccessible(tester, largeText: true);
    });

    testWidgets('share a row at slightly larger text where the pill fits', (
      tester,
    ) async {
      await pump(
        tester,
        swapPricedForm(),
        size: const Size(1024, 1600),
        textScale: 1.2,
      );
      expectSideBySide(tester);
    });
  });
}

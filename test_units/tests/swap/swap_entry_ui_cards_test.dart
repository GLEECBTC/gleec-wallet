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

/// Full-width asset identities stay above amounts at every width and text
/// size. Wallet addresses belong to review and never crowd entry.
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

  testWidgets('wallet and quote addresses are kept out of ordinary entry', (
    tester,
  ) async {
    final quote = quoteWith(
      quoteOf(),
      fromAddress: '0xFROM000000000000000000000000000000000001',
      toAddress: '0xTO00000000000000000000000000000000000002',
    );
    await pump(
      tester,
      swapPricedForm(ranked: [quote])
          .copyWith(payAddress: payAddress, receiveAddress: receiveAddress),
    );

    expect(find.textContaining('From 0x'), findsNothing);
    expect(find.textContaining('To 0x'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Copy address')), findsNothing);
    expect(find.text('Ethereum'), findsNWidgets(2));
  });

  testWidgets('while its swap may be running, the amount takes no edits', (
    tester,
  ) async {
    await pump(
      tester,
      swapPricedForm().copyWith(
        review: SwapReview(
          quote: quoteOf(),
          status: SwapReviewStatus.unconfirmed,
        ),
      ),
    );
    final before = List.of(swap.events);

    final field = find.byKey(const Key('swap-amount'));
    expect(tester.widget<TextField>(field).enabled, isFalse);
    await tester.tap(find.text('Max'));
    await tester.tap(find.byTooltip('Enter amount in USD'));
    await tester.pump();

    expect(swap.events, before);
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

    void expectStacked(WidgetTester tester) {
      expect(above(tester, payPill, field), isTrue);
      expect(tester.getTopLeft(payPill).dx, tester.getTopLeft(field).dx);
      expect(tester.getSize(payPill).width, tester.getSize(field).width);
    }

    testWidgets('put the full-width identity above the amount on a phone', (
      tester,
    ) async {
      await pump(tester, swapPricedForm());
      expectStacked(tester);
    });

    testWidgets('keep the same order on a narrow screen', (tester) async {
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

    testWidgets('keep the same order on a wide screen', (tester) async {
      await pump(
        tester,
        swapPricedForm(),
        size: const Size(1024, 1600),
        textScale: 1.2,
      );
      expectStacked(tester);
    });
  });
}

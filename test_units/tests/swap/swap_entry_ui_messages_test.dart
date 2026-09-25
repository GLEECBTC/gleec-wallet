// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/entry/swap_entry_view.dart';

import 'swap_entry_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the lines under the cards: one error, else the warnings and notes
/// that apply, else one hint about what the form is doing.
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

  Future<void> pump(
    WidgetTester tester,
    UnifiedSwapState state, {
    bool settle = true,
  }) async {
    swap.emit(state);
    await pumpSwapUi(
      tester,
      const SwapEntryView(),
      bloc: swap,
      services: services,
      settle: settle,
    );
  }

  /// Every helper line under the cards, top to bottom.
  List<String> lines(WidgetTester tester) => [
    for (final line in tester.widgetList<SwapHelperLine>(
      find.byType(SwapHelperLine),
    ))
      line.text,
  ];

  SwapTone toneOf(WidgetTester tester, String text) => tester
      .widget<SwapHelperLine>(
        find.ancestor(
          of: find.text(text),
          matching: find.byType(SwapHelperLine),
        ),
      )
      .tone;

  group('warnings', () {
    testWidgets('steps that changed under review are pointed out', (
      tester,
    ) async {
      await pump(tester, swapPricedForm().copyWith(structuralNotice: true));

      const notice =
          'The swap steps changed, so we checked fresh options. Review them '
          'before you continue.';
      expect(lines(tester), [notice]);
      expect(toneOf(tester, notice), SwapTone.warning);
    });

    testWidgets('a high price impact is warned about on both sides', (
      tester,
    ) async {
      await pump(
        tester,
        swapPricedForm(
          ranked: [quoteOf(pricing: pricingOf(expected: '2700'))],
        ).copyWith(structuralNotice: true),
      );

      expect(lines(tester), hasLength(2));
      expect(
        lines(tester).last,
        'High price impact: you may receive 10% less than the current market '
        'estimate. Review the minimum carefully.',
      );
      final vsMarket = tester.widget<Text>(find.text('−10% vs market'));
      expect(vsMarket.style!.color, SwapPalette.dark.warning);
    });

    testWidgets('a small impact is only a figure beside the value', (
      tester,
    ) async {
      await pump(
        tester,
        swapPricedForm(
          ranked: [quoteOf(pricing: pricingOf(expected: '2940'))],
        ),
      );

      expect(lines(tester), isEmpty);
      final vsMarket = tester.widget<Text>(find.text('−2% vs market'));
      expect(vsMarket.style!.color, SwapPalette.dark.textTertiary);
      expect(find.text(r'$2,940.00'), findsOneWidget);
    });

    testWidgets('receiving more than the market estimate reads as a gain', (
      tester,
    ) async {
      await pump(
        tester,
        swapPricedForm(
          ranked: [quoteOf(pricing: pricingOf(expected: '3030'))],
        ),
      );

      expect(find.text('+1% vs market'), findsOneWidget);
    });
  });

  group('a source that could not answer beside one that did', () {
    Future<void> pumpMissing(WidgetTester tester, SwapQuoteFailure failure) =>
        pump(tester, swapPricedForm(failures: [failure]));

    testWidgets('the order book is said to be missing', (tester) async {
      await pumpMissing(
        tester,
        const SwapQuoteFailure(
          source: SwapLiquiditySource.atomic,
          kind: SwapQuoteFailureKind.timeout,
        ),
      );

      expect(lines(tester), [
        "Order-book prices couldn't be checked, so only cross-network prices "
            'are shown.',
      ]);
    });

    testWidgets('cross-network routes are said to be missing', (tester) async {
      await pumpMissing(
        tester,
        const SwapQuoteFailure(
          source: SwapLiquiditySource.routed,
          kind: SwapQuoteFailureKind.serviceError,
        ),
      );

      expect(lines(tester), [
        "Cross-network prices couldn't be checked, so only order-book prices "
            'are shown.',
      ]);
    });

    testWidgets('cross-network routes held back by a rate limit are paused', (
      tester,
    ) async {
      await pumpMissing(
        tester,
        const SwapQuoteFailure(
          source: SwapLiquiditySource.routed,
          kind: SwapQuoteFailureKind.rateLimited,
        ),
      );

      expect(lines(tester), [
        'Cross-network prices are paused briefly and will be back shortly.',
      ]);
    });

    testWidgets('a source that looked and found nothing goes unmentioned', (
      tester,
    ) async {
      await pumpMissing(
        tester,
        const SwapQuoteFailure(
          source: SwapLiquiditySource.atomic,
          kind: SwapQuoteFailureKind.noRoute,
        ),
      );

      expect(lines(tester), isEmpty);
    });
  });

  group('after Max', () {
    UnifiedSwapState maxed(
      SwapMaxAmount max, {
      AssetId? pay,
      AssetId? receive,
    }) =>
        swapPricedForm().copyWith(pay: pay, receive: receive, maxApplied: max);

    testWidgets('a native coin says what it kept back for fees', (
      tester,
    ) async {
      await pump(
        tester,
        maxed(SwapMaxAmount(amount: d('1.99'), reservedForFees: d('0.01'))),
      );

      expect(lines(tester), [
        'Max uses 1.99 ETH. We kept 0.01 ETH for network fees.',
      ]);
    });

    testWidgets('a reserve held in another coin is given in that coin', (
      tester,
    ) async {
      await pump(
        tester,
        maxed(
          SwapMaxAmount(
            amount: d('100'),
            reservedForFees: d('0.002'),
            feeAsset: eth,
          ),
          pay: usdc,
          receive: eth,
        ),
      );

      expect(lines(tester), [
        'Max uses 100 USDC. We kept 0.002 ETH for network fees.',
      ]);
    });

    testWidgets('a token says its fees are paid in the network coin', (
      tester,
    ) async {
      await pump(
        tester,
        maxed(
          SwapMaxAmount(amount: d('100'), reservedForFees: d('0')),
          pay: usdc,
          receive: eth,
        ),
      );

      expect(lines(tester), [
        'Max uses 100 USDC. Network fees are paid separately in ETH.',
      ]);
    });

    testWidgets('an order-book coin says its fees are kept back', (
      tester,
    ) async {
      await pump(
        tester,
        maxed(
          SwapMaxAmount(amount: d('0.5'), reservedForFees: d('0')),
          pay: btc,
        ),
      );

      expect(lines(tester), [
        'Max uses 0.5 BTC. Trading and network fees are kept back.',
      ]);
    });
  });

  testWidgets('without a market price, what is still known is said', (
    tester,
  ) async {
    await pump(
      tester,
      swapPricedForm(ranked: [quoteOf(pricing: pricingOf(expected: null))]),
    );

    expect(lines(tester), [
      'Price estimate unavailable. Token amounts, minimum received, and costs '
          'remain available.',
    ]);
    // The receive side too, where its dollar value would be.
    expect(find.text('Price estimate unavailable'), findsOneWidget);
  });

  testWidgets('while the assets load the form says it is looking', (
    tester,
  ) async {
    await pump(
      tester,
      swapBaseForm().copyWith(loadingAssets: true),
      settle: false,
    );

    expect(lines(tester), ['Checking what this wallet can swap…']);
  });

  testWidgets('short of the network coin, the fees and holding are given', (
    tester,
  ) async {
    final quote = quoteOf(
      from: usdc,
      to: eth,
      sell: '100',
      expected: '0.033',
      guaranteed: '0.032',
      fees: [
        SwapFeeComponent(
          kind: SwapFeeKind.network,
          amount: d('0.0015'),
          deductedFromReceive: false,
          asset: eth,
        ),
        // Already out of what arrives, so not needed up front.
        SwapFeeComponent(
          kind: SwapFeeKind.network,
          amount: d('0.0005'),
          deductedFromReceive: true,
          asset: eth,
        ),
        SwapFeeComponent(
          kind: SwapFeeKind.swap,
          amount: d('0.3'),
          deductedFromReceive: false,
          asset: usdc,
        ),
      ],
    );
    await pump(
      tester,
      swapPricedForm(ranked: [quote]).copyWith(
        pay: usdc,
        receive: eth,
        inputText: '100',
        balance: d('500'),
        feeBalance: d('0.00012'),
        issue: SwapFormIssue.insufficientForFees,
      ),
    );

    expect(lines(tester), [
      'You need about 0.0015 ETH for network fees. This address has '
          '0.00012 ETH.',
    ]);
    expect(swapPrimaryLabel(tester), 'Not enough ETH');
  });

  testWidgets('the network fees needed leave out a swap fee in that coin', (
    tester,
  ) async {
    SwapFeeComponent fee(SwapFeeKind kind, String amount) => SwapFeeComponent(
      kind: kind,
      amount: d(amount),
      deductedFromReceive: false,
      asset: eth,
    );
    final quote = quoteOf(
      from: usdc,
      to: eth,
      fees: [
        fee(SwapFeeKind.network, '0.0015'),
        fee(SwapFeeKind.approvalNetwork, '0.0005'),
        fee(SwapFeeKind.swap, '0.001'),
      ],
    );
    await pump(
      tester,
      swapPricedForm(ranked: [quote]).copyWith(
        pay: usdc,
        receive: eth,
        feeBalance: d('0.00012'),
        issue: SwapFormIssue.insufficientForFees,
      ),
    );

    expect(lines(tester).single, startsWith('You need about 0.002 ETH '));
  });

  testWidgets('a quiet re-price says it is checking under the option', (
    tester,
  ) async {
    await pump(
      tester,
      swapPricedForm().copyWith(evaluation: SwapEvaluationStatus.checking),
      settle: false,
    );

    expect(lines(tester), ['Checking swap options…']);
  });
}

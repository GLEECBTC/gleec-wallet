// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_pricing.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/entry/swap_entry_view.dart';
import 'package:web_dex/views/swap/review/swap_review_view.dart';

import 'swap_entry_ui_fakes.dart';
import 'swap_test_fixtures.dart';

SwapFeeComponent _fee(
  SwapFeeKind kind,
  String amount, {
  AssetId? asset,
  String? symbol,
  String? usd,
  bool deducted = false,
}) => SwapFeeComponent(
  kind: kind,
  amount: d(amount),
  deductedFromReceive: deducted,
  asset: asset,
  symbol: symbol,
  usdValue: usd == null ? null : d(usd),
);

/// Covers keeping fees out of the price impact: a small swap that loses most
/// of its value to fees reads as costly, not as a bad rate.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('price impact leaves fees out', () {
    final pricing = SwapPricingService(
      FakePriceSource({eth: d('2730'), usdc: d('1')}),
    );

    test('for the reported swap, the 35% "impact" was fees', () {
      // 0.259426 USDC for ETH: LI.FI's 0.25% fee and the bridge relayer's fee
      // come out of the USDC; only the source gas is paid on top.
      final quote = pricing.price(
        quoteOf(
          from: usdc,
          to: eth,
          sell: '0.259426',
          expected: '0.00006173',
          guaranteed: '0.00006142',
          fees: [
            _fee(SwapFeeKind.swap, '0.000648565', asset: usdc, deducted: true),
            _fee(SwapFeeKind.swap, '0.09', asset: usdc, deducted: true),
            _fee(SwapFeeKind.network, '0.000004', asset: eth),
          ],
          pricing: const SwapQuotePricing(),
        ),
      );

      expect(quote.pricing.deductedCostUsd, d('0.090648565'));
      expect(quote.pricing.priceImpact!, lessThan(d('0.01')));
      expect(quote.pricing.feeShare!, greaterThan(d('0.39')));
      expect(quote.pricing.feeShare!, lessThan(d('0.40')));
    });

    test('a fee added back is priced like the amounts it is compared with', () {
      final quote = pricing.price(
        quoteOf(
          fees: [
            _fee(SwapFeeKind.swap, '1', asset: usdc, usd: '5', deducted: true),
          ],
          pricing: const SwapQuotePricing(),
        ),
      );

      // The provider's $5 still prices the cost shown; the impact uses $1.
      expect(quote.fees.single.usdValue, d('5'));
      expect(quote.pricing.deductedCostUsd, d('1'));
    });

    test('a fee with no price stays in the impact, which may then overstate '
        'the loss but never hides it', () {
      final quote = pricing.price(
        quoteOf(
          fees: [_fee(SwapFeeKind.swap, '7', symbol: 'XYZ', deducted: true)],
          pricing: const SwapQuotePricing(),
        ),
      );

      expect(quote.pricing.deductedCostUsd, Decimal.zero);
      expect(quote.pricing.priceImpact, isNotNull);
      expect(quote.pricing.isComplete, isFalse);
      expect(quote.pricing.feeShare, isNull);
    });

    test('an order-book fee paid from the sold volume is not added back', () {
      // Only a fee in the received coin reduces an order-book receive.
      final quote = pricing.price(
        quoteOf(
          source: SwapLiquiditySource.atomic,
          fees: [
            _fee(SwapFeeKind.dexFee, '0.001', asset: eth, deducted: true),
            _fee(SwapFeeKind.network, '0.5', asset: usdc, deducted: true),
          ],
          pricing: const SwapQuotePricing(),
        ),
      );

      expect(quote.feesInReceive.single.asset, usdc);
      expect(quote.pricing.deductedCostUsd, d('0.5'));
    });

    test('the fee share counts every cost and needs them all priced', () {
      expect(pricingOf(pay: '100', network: '4', swap: '6').feeShare, d('0.1'));
      expect(
        pricingOf(
          pay: '100',
          network: '4',
          swap: '6',
          complete: false,
        ).feeShare,
        isNull,
      );
      expect(pricingOf(pay: '0').feeShare, isNull);
    });
  });

  group('a loss that is all fees', () {
    setUpSwapUi();

    late RecordingSwapBloc swap;
    late FakeSwapServices services;

    setUp(() {
      swap = RecordingSwapBloc();
      services = FakeSwapServices();
    });

    tearDown(() => swap.close());

    // $100 in, $60 out, $39 of it taken by fees and $1 of gas on top.
    final quote = quoteOf(
      fees: [
        _fee(SwapFeeKind.swap, '39', asset: usdc, usd: '39', deducted: true),
        _fee(SwapFeeKind.network, '0.001', asset: eth, usd: '1'),
      ],
      pricing: pricingOf(
        pay: '100',
        expected: '60',
        network: '1',
        swap: '39',
        deducted: '39',
      ),
    );

    testWidgets('warns about the fees on the form, not about the price', (
      tester,
    ) async {
      swap.emit(swapPricedForm(ranked: [quote]));
      await pumpSwapUi(
        tester,
        const SwapEntryView(),
        bloc: swap,
        services: services,
      );

      final lines = [
        for (final line in tester.widgetList<SwapHelperLine>(
          find.byType(SwapHelperLine),
        ))
          line.text,
      ];
      expect(lines, [
        "High fees: about 40% of this swap's value goes to network and "
            'provider fees.',
      ]);
      expect(find.text('−1% vs market'), findsOneWidget);
    });

    testWidgets('on the review, calls out the fees and what the receive '
        'already lost to them', (tester) async {
      swap.emit(
        swapPricedForm(ranked: [quote]).copyWith(
          view: UnifiedSwapView.review,
          review: SwapReview(quote: quote, status: SwapReviewStatus.ready),
        ),
      );
      await pumpSwapUi(
        tester,
        const SwapReviewView(),
        bloc: swap,
        services: services,
        size: const Size(420, 2400),
      );

      expect(find.text('High fees'), findsOneWidget);
      expect(find.text('High price impact'), findsNothing);

      await tester.tap(find.text('Costs & protection'));
      await tester.pumpAndSettle();
      final row = find.widgetWithText(
        SwapDetailRow,
        'Already taken from what you receive',
      );
      expect(tester.widget<SwapDetailRow>(row).value, r'$39.00');
    });
  });
}

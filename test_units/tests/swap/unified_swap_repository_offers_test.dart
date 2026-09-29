import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_order_book_offers.dart';
import 'package:web_dex/shared/swap/swap_pricing.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';

import 'swap_offer_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the repository's view of the order book's offers, and which of two
/// failures of one kind it explains a result with.
void main() {
  final pricing = SwapPricingService(FakePriceSource({}));
  final avn = assetOf('AVN', subClass: CoinSubClass.utxo, chainId: 0);

  group('the failure shown when two sources fail alike', () {
    UnifiedSwapQuotes both(SwapQuoteFailure a, SwapQuoteFailure b) =>
        UnifiedSwapQuotes(
          ranked: const [],
          unrankable: const [],
          failures: [a, b],
        );

    SwapQuoteFailure of(
      SwapLiquiditySource source,
      SwapQuoteFailureKind kind, {
      String? minimum,
      String? maximum,
      List<String> reasons = const [],
      SwapOrderBookOffers? offers,
    }) => SwapQuoteFailure(
      source: source,
      kind: kind,
      minimum: minimum == null ? null : d(minimum),
      maximum: maximum == null ? null : d(maximum),
      reasons: reasons,
      offers: offers,
    );

    test('the lower minimum and the higher maximum win', () {
      final lowMin = of(
        SwapLiquiditySource.atomic,
        SwapQuoteFailureKind.belowMinimum,
        minimum: '0.5',
      );
      final highMin = of(
        SwapLiquiditySource.routed,
        SwapQuoteFailureKind.belowMinimum,
        minimum: '2',
      );
      final lowMax = of(
        SwapLiquiditySource.atomic,
        SwapQuoteFailureKind.aboveMaximum,
        maximum: '1',
      );
      final highMax = of(
        SwapLiquiditySource.routed,
        SwapQuoteFailureKind.aboveMaximum,
        maximum: '9',
      );

      expect(both(highMin, lowMin).primaryFailure, lowMin);
      expect(both(lowMin, highMin).primaryFailure, lowMin);
      expect(both(lowMax, highMax).primaryFailure, highMax);
      expect(both(highMax, lowMax).primaryFailure, highMax);
    });

    test('a miss naming amounts that fill wins, then one saying why', () {
      final gap = of(
        SwapLiquiditySource.atomic,
        SwapQuoteFailureKind.noRoute,
        offers: SwapOrderBookOffers([SwapOfferBand(d('1'), d('2'))]),
      );
      final empty = of(
        SwapLiquiditySource.atomic,
        SwapQuoteFailureKind.noRoute,
        offers: const SwapOrderBookOffers(),
      );
      final why = of(
        SwapLiquiditySource.routed,
        SwapQuoteFailureKind.noRoute,
        reasons: ['amount too low (hop)'],
      );

      expect(both(why, gap).primaryFailure, gap);
      expect(both(empty, why).primaryFailure, why);
    });
  });

  group('offers', () {
    test('asks the order book about the assets only it trades', () async {
      final atomic = FakeOfferSource(tradable: {eth, usdc, btc, avn})
        ..offeredBy = {
          usdc: {btc: true, avn: false},
        };
      final routed = FakeQuoteSource(
        SwapLiquiditySource.routed,
        tradable: {eth, usdc},
      );
      final repo = UnifiedSwapRepository(
        sources: [routed, atomic],
        pricing: pricing,
      );
      await repo.catalog();

      final paying = await repo.offeredWith(usdc, anchorPays: true);
      await repo.offeredWith(avn, anchorPays: false);

      expect(paying, {btc: true, avn: false});
      expect(atomic.offeredCalls.first.candidates, unorderedEquals([btc, avn]));
      expect(atomic.offeredCalls.first.anchorPays, isTrue);
      // Every pair with AVN is the order book's alone.
      expect(
        atomic.offeredCalls.last.candidates,
        unorderedEquals([eth, usdc, btc]),
      );
      expect(atomic.offeredCalls.last.anchorPays, isFalse);
    });

    test('a pair only the order book trades is order-book only', () async {
      final repo = UnifiedSwapRepository(
        sources: [
          FakeQuoteSource(SwapLiquiditySource.routed, tradable: {eth, usdc}),
          FakeOfferSource(tradable: {eth, usdc, avn}),
        ],
        pricing: pricing,
      );
      expect(repo.orderBookOnly(usdc, avn), isFalse);

      await repo.catalog();

      expect(repo.orderBookOnly(usdc, avn), isTrue);
      expect(repo.orderBookOnly(avn, usdc), isTrue);
      expect(repo.orderBookOnly(eth, usdc), isFalse);
    });

    test('reads a pair\'s offers from the order book', () async {
      final offers = SwapOrderBookOffers([SwapOfferBand(d('1'), d('2'))]);
      final atomic = FakeOfferSource()..pairOffers = {(btc, eth): offers};
      final repo = UnifiedSwapRepository(sources: [atomic], pricing: pricing);

      expect(await repo.offers(btc, eth), offers);
      expect(await repo.offers(eth, btc), isNull);
    });

    test('is unknown without an order book, a catalog or an answer', () async {
      final bare = UnifiedSwapRepository(
        sources: [FakeQuoteSource(SwapLiquiditySource.routed)],
        pricing: pricing,
      );
      final atomic = FakeOfferSource()..offersError = StateError('offline');
      final failing = UnifiedSwapRepository(
        sources: [atomic],
        pricing: pricing,
      );

      expect(await bare.offers(btc, eth), isNull);
      await bare.catalog();
      expect(await bare.offeredWith(btc, anchorPays: true), isNull);
      expect(await failing.offeredWith(btc, anchorPays: true), isNull);
      expect(await failing.offers(btc, eth), isNull);
    });
  });
}

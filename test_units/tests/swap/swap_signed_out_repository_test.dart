import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/atomic_swap_source.dart';
import 'package:web_dex/shared/swap/routed_swap_source.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_pricing.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';

import 'swap_src_fakes.dart' show SrcRoutedSwaps, SrcTrading;
import 'swap_test_fixtures.dart';

/// Covers how the repository prices a swap before sign-in: only sources that
/// need no wallet are asked, and those that do are reported as waiting for
/// one.
void main() {
  final clock = DateTime(2026, 9, 24, 12);
  final paxg = assetOf('PAXG-ERC20', parent: eth);

  late FakeQuoteSource routed;
  late FakeQuoteSource atomic;

  // An order-book offer: no fees read, as when nothing is active.
  List<SwapQuoteResult> offer(SwapQuoteRequest request) => [
    SwapQuoteAvailable(
      quoteOf(
        id: 'atomic',
        source: SwapLiquiditySource.atomic,
        routeKind: SwapRouteKind.direct,
        order: null,
        from: request.from,
        to: request.to,
        sell: request.amount.toString(),
        fees: const [],
        quotedAt: clock,
        pricing: const SwapQuotePricing(),
      ),
    ),
  ];

  setUp(() {
    routed = FakeQuoteSource(
      SwapLiquiditySource.routed,
      tradable: {eth, usdc, paxg},
      respond: (request) => [
        SwapQuoteAvailable(
          quoteOf(
            id: 'routed',
            from: request.from,
            to: request.to,
            sell: request.amount.toString(),
            quotedAt: clock,
          ),
        ),
      ],
    );
    atomic = FakeQuoteSource(
      SwapLiquiditySource.atomic,
      tradable: {eth, usdc, btc},
      respond: offer,
    );
  });

  group('the repository', () {
    Future<UnifiedSwapRepository> catalogued() async {
      final repository = UnifiedSwapRepository(
        sources: [routed, atomic],
        pricing: SwapPricingService(
          FakePriceSource({eth: d('3000'), usdc: d('1')}),
        ),
        activatedAssets: () async => {},
      );
      await repository.catalog();
      return repository;
    }

    SwapQuoteRequest request(
      AssetId from,
      AssetId to, {
      bool signedOut = true,
    }) => SwapQuoteRequest(
      from: from,
      to: to,
      amount: d('1'),
      indicative: signedOut,
      signedOut: signedOut,
    );

    test('asks the order book only, and routes wait for a wallet', () async {
      final quotes = await (await catalogued()).quote(request(eth, usdc));

      expect(routed.requests, isEmpty);
      expect(atomic.requests.single.signedOut, isTrue);
      expect(quotes.options.single.source, SwapLiquiditySource.atomic);
      expect(quotes.failures.map((f) => (f.source, f.kind)), [
        (SwapLiquiditySource.routed, SwapQuoteFailureKind.signedOut),
      ]);
    });

    test('a pair only routes trade asks nobody', () async {
      final quotes = await (await catalogued()).quote(request(eth, paxg));

      expect(routed.requests, isEmpty);
      expect(atomic.requests, isEmpty);
      expect(quotes.isEmpty, isTrue);
      expect(quotes.primaryFailure!.kind, SwapQuoteFailureKind.signedOut);
    });

    test('a pair only the order book trades has nothing waiting', () async {
      final quotes = await (await catalogued()).quote(request(eth, btc));

      expect(quotes.options.single.source, SwapLiquiditySource.atomic);
      expect(quotes.failures, isEmpty);
    });

    test('a pair no source trades still says so', () async {
      final quotes = await (await catalogued()).quote(request(btc, paxg));

      expect(atomic.requests, isEmpty);
      expect(quotes.failures.map((f) => f.kind).toSet(), {
        SwapQuoteFailureKind.pairUnsupported,
      });
    });

    test('signed in, an inactive asset still waits to be activated', () async {
      final quotes = await (await catalogued()).quote(
        request(eth, usdc, signedOut: false),
      );

      expect(atomic.requests, isEmpty);
      expect(quotes.primaryFailure!.kind, SwapQuoteFailureKind.assetInactive);
    });

    test('what the order book said explains more than a waiting route', () {
      UnifiedSwapQuotes answer(SwapQuoteFailureKind atomicKind) =>
          UnifiedSwapQuotes(
            ranked: const [],
            unrankable: const [],
            failures: [
              const SwapQuoteFailure(
                source: SwapLiquiditySource.routed,
                kind: SwapQuoteFailureKind.signedOut,
              ),
              SwapQuoteFailure(
                source: SwapLiquiditySource.atomic,
                kind: atomicKind,
              ),
            ],
          );

      for (final kind in [
        SwapQuoteFailureKind.noRoute,
        SwapQuoteFailureKind.serviceError,
        SwapQuoteFailureKind.unknown,
      ]) {
        expect(answer(kind).primaryFailure!.kind, kind);
      }
    });

    test('the real sources: only the order book is asked, fee-less', () async {
      final trading = SrcTrading();
      final routedSwaps = SrcRoutedSwaps();
      final networks = SwapNetworks([eth, usdc]);
      final orderBook = AtomicSwapQuoteSource(
        trading: trading,
        networks: () => networks,
      );
      final routes = RoutedSwapQuoteSource(
        routedSwaps,
        networks: () => networks,
      );
      expect(orderBook.pricesSignedOut, isTrue);
      expect(routes.pricesSignedOut, isFalse);

      final repository = UnifiedSwapRepository(
        sources: [routes, orderBook],
        pricing: SwapPricingService(
          FakePriceSource({eth: d('3000'), usdc: d('1')}),
        ),
        knownAssets: () => {eth, usdc},
        activatedAssets: () async => {},
      );
      await repository.catalog();
      final quotes = await repository.quote(request(eth, usdc));

      expect(routedSwaps.quotes, isEmpty);
      expect(trading.books, isNotEmpty);
      expect(trading.preimages, isEmpty);
      expect(quotes.options.single.feesKnown, isFalse);
      expect(quotes.failures.single.kind, SwapQuoteFailureKind.signedOut);
    });
  });
}

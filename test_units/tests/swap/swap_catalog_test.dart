// The analyzer does not treat test_units as tests, so @visibleForTesting
// members read as violations here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/atomic_swap_source.dart';
import 'package:web_dex/shared/swap/routed_swap_source.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_pricing.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';

import 'swap_test_fixtures.dart';

/// Covers who gets asked for a price. The aggregator's request budget is
/// small and shared, so a source that cannot price a pair is not asked, and
/// a pair nobody can price is explained without asking anyone.
void main() {
  // GLEEC on its own EVM chain, which the aggregator does not serve.
  final gleecEvm = assetOf(
    'GLEEC',
    subClass: CoinSubClass.grc20,
    chainId: 11169,
  );
  // A token only the aggregator can trade: wallet-only for the orderbook.
  final paxg = assetOf('PAXG-ERC20', parent: eth);

  SwapSourceAssets list(
    SwapLiquiditySource source,
    Set<AssetId> assets, {
    SwapCatalogStatus status = SwapCatalogStatus.fresh,
  }) => SwapSourceAssets(source: source, quotable: assets, status: status);

  final catalog = SwapCatalog(
    sources: [
      list(SwapLiquiditySource.atomic, {eth, usdc, gleecEvm, btc}),
      list(SwapLiquiditySource.routed, {eth, usdc, paxg}),
    ],
    activated: {eth, usdc, gleecEvm, btc, paxg},
  );

  group('catalog: which sources can price a pair', () {
    test('a pair both sources trade is priced by both', () {
      expect(catalog.support(eth, usdc).sources, {
        SwapLiquiditySource.atomic,
        SwapLiquiditySource.routed,
      });
    });

    test('GLEEC pairs are order-book only, and say which side is why', () {
      final support = catalog.support(gleecEvm, usdc);
      expect(support.sources, {SwapLiquiditySource.atomic});
      expect(support.routesUnavailableFor, gleecEvm);
    });

    test('two assets on different sources is a gap, not an outage', () {
      final support = catalog.support(gleecEvm, paxg);
      expect(support.isSupported, isFalse);
      expect(support.gap, SwapPairGap.sourcesDisjoint);
      expect(support.limitingAsset, gleecEvm);
      expect(support.routesOnlyAsset, paxg);
    });

    test('an asset no source trades is named', () {
      final unknown = assetOf('NOPE');
      final support = catalog.support(eth, unknown);
      expect(support.gap, SwapPairGap.notTradable);
      expect(support.limitingAsset, unknown);
    });

    test('a list that could not refresh marks the catalog incomplete', () {
      final stale = SwapCatalog(
        sources: [
          list(SwapLiquiditySource.routed, {
            eth,
          }, status: SwapCatalogStatus.stale),
        ],
      );
      expect(stale.isIncomplete, isTrue);
      expect(catalog.isIncomplete, isFalse);
      // Activation that could not be read counts as active.
      expect(stale.isActive(usdc), isTrue);
    });
  });

  group('repository: only sources that can answer are asked', () {
    late FakeQuoteSource routed;
    late FakeQuoteSource atomic;
    late Set<AssetId> activated;

    UnifiedSwapRepository repository() => UnifiedSwapRepository(
      sources: [routed, atomic],
      pricing: SwapPricingService(FakePriceSource()),
      activatedAssets: () async => activated,
    );

    SwapQuoteRequest request(AssetId from, AssetId to) =>
        SwapQuoteRequest(from: from, to: to, amount: d('1'));

    setUp(() {
      activated = {eth, usdc, gleecEvm, paxg};
      routed = FakeQuoteSource(
        SwapLiquiditySource.routed,
        tradable: {eth, usdc, paxg},
        results: [rejected(SwapQuoteFailureKind.serviceError)],
      );
      atomic = FakeQuoteSource(
        SwapLiquiditySource.atomic,
        tradable: {eth, usdc, gleecEvm},
        results: [
          rejected(
            SwapQuoteFailureKind.noRoute,
            source: SwapLiquiditySource.atomic,
          ),
        ],
      );
    });

    test('a GLEEC pair never reaches the aggregator', () async {
      final repo = repository();
      await repo.catalog();
      final result = await repo.quote(request(gleecEvm, usdc));

      expect(routed.requests, isEmpty);
      expect(atomic.requests, hasLength(1));
      // The order book's "nothing right now", not a service outage.
      expect(result.primaryFailure!.kind, SwapQuoteFailureKind.noRoute);
    });

    test('a pair nobody trades is answered without asking', () async {
      final repo = repository();
      await repo.catalog();
      final result = await repo.quote(request(gleecEvm, paxg));

      expect(routed.requests, isEmpty);
      expect(atomic.requests, isEmpty);
      expect(
        result.failures.map((f) => f.kind),
        everyElement(SwapQuoteFailureKind.pairUnsupported),
      );
    });

    test('an inactive asset is answered without asking', () async {
      activated = {usdc};
      final repo = repository();
      await repo.catalog();
      final result = await repo.quote(request(eth, usdc));

      expect(routed.requests, isEmpty);
      expect(atomic.requests, isEmpty);
      expect(result.primaryFailure!.kind, SwapQuoteFailureKind.assetInactive);
      expect(result.primaryFailure!.asset, eth);
    });

    test('before any catalog, every source is asked', () async {
      final result = await repository().quote(request(gleecEvm, usdc));
      expect(routed.requests, hasLength(1));
      expect(atomic.requests, hasLength(1));
      expect(result.failures, hasLength(2));
    });

    test('a firm no-route outranks a source that could not answer', () async {
      final repo = repository();
      await repo.catalog();
      final result = await repo.quote(request(eth, usdc));

      expect(result.primaryFailure!.kind, SwapQuoteFailureKind.noRoute);
      expect(
        result.failures.singleWhere((f) => f.isTransient).source,
        SwapLiquiditySource.routed,
      );
    });

    test('Max is only asked of sources that can sell the pair', () async {
      final repo = repository();
      await repo.catalog();
      atomic.max = SwapMaxAmount(amount: d('0.9'), reservedForFees: d('0.1'));
      routed.max = SwapMaxAmount(amount: d('1'), reservedForFees: d('0'));
      final maxes = await repo.maxAmounts(
        from: gleecEvm,
        to: usdc,
        balance: d('1'),
      );
      expect(maxes.keys, [SwapLiquiditySource.atomic]);
    });
  });

  group('atomic: the orderbook catalog', () {
    test('active assets now, inactive once active, wallet-only never', () {
      final assets = AtomicSwapQuoteSource.catalogFor(
        known: {eth, usdc, btc, paxg},
        activated: {eth, paxg},
        isWalletOnly: (asset) => asset == paxg,
      );
      expect(assets.quotable, {eth});
      expect(assets.onceActive, {usdc, btc});
    });
  });

  group('routed: the aggregator catalog', () {
    late _Script script;
    late RoutedSwapQuoteSource source;

    setUp(() {
      script = _Script();
      final byTicker = {
        for (final a in [eth, usdc, gleecEvm, btc, paxg]) a.id: a,
      };
      source = RoutedSwapQuoteSource(
        RoutedSwapManager(client: script, resolveAsset: (t) => byTicker[t]),
        networks: () => SwapNetworks(byTicker.values),
      );
    });

    Future<SwapSourceAssets> read() => source.assets(
      known: {eth, usdc, gleecEvm, btc, paxg},
      activated: {eth, usdc, gleecEvm},
    );

    test('lists what KDF lists, and guesses the rest by network', () async {
      script.coins = ['ETH', 'USDC-ERC20'];
      final assets = await read();
      expect(assets.status, SwapCatalogStatus.fresh);
      expect(assets.quotable, {eth, usdc});
      // An inactive token on a served network may be routed once active;
      // GLEEC's network is not served and BTC is not EVM.
      expect(assets.onceActive, {paxg});
    });

    test('an outage keeps the last list instead of emptying it', () async {
      script.coins = ['ETH', 'USDC-ERC20'];
      await read();
      script.coins = null;
      final assets = await read();
      expect(assets.status, SwapCatalogStatus.stale);
      expect(assets.quotable, {eth, usdc});
    });

    test('with nothing ever loaded, it falls back to the network', () async {
      script.coins = null;
      final assets = await read();
      expect(assets.status, SwapCatalogStatus.unavailable);
      expect(assets.quotable, {eth, usdc});
    });
  });
}

/// Answers `routed_swap::supported_coins` with [coins], or fails when null.
class _Script implements ApiClient {
  List<String>? coins;

  @override
  Future<JsonMap> executeRpc(JsonMap request) async {
    final listed = coins;
    if (listed == null) throw StateError('KDF unreachable');
    return {
      'mmrpc': '2.0',
      'result': {
        'provider': 'lifi',
        'coins': [
          for (final coin in listed) {'coin': coin, 'chain_id': 1},
        ],
      },
    };
  }
}

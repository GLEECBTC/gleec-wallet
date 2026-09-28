import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/shared/swap/routed_swap_source.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_preferences.dart';
import 'package:web_dex/shared/swap/swap_pricing.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/swap/swap_terms_repository.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';

import 'swap_test_fixtures.dart';

/// Covers what the swap form can offer without a wallet. Nothing is active,
/// so the list is built without asking the wallet or KDF: either answer can
/// keep the form waiting, and both are known already.
void main() {
  group('the repository', () {
    late _Source source;
    late int reads;

    UnifiedSwapRepository repository() => UnifiedSwapRepository(
      sources: [source],
      pricing: SwapPricingService(FakePriceSource({})),
      knownAssets: () => {eth, usdc},
      activatedAssets: () async {
        reads++;
        return {eth};
      },
    );

    setUp(() {
      source = _Source();
      reads = 0;
    });

    test(
      'signed out, counts nothing active without asking the wallet',
      () async {
        final catalog = await repository().catalog(signedIn: false);

        expect(reads, 0);
        expect(catalog.activated, isEmpty);
        expect(source.activated, [<AssetId>{}]);
        expect(source.known, [
          {eth, usdc},
        ]);
      },
    );

    test('signed in, asks the wallet what is active', () async {
      final catalog = await repository().catalog();

      expect(reads, 1);
      expect(catalog.activated, {eth});
      expect(source.activated, [
        {eth},
      ]);
    });
  });

  group('the form', () {
    late Completer<Set<AssetId>> wallet;
    late int reads;

    UnifiedSwapBloc open({required bool signedIn}) {
      final storage = MemoryStorage();
      final registry = SwapExecutionRegistry(
        executors: const [],
        inFlight: () async => const [],
      );
      final bloc =
          UnifiedSwapBloc(
              repository: UnifiedSwapRepository(
                sources: [FakeQuoteSource(SwapLiquiditySource.atomic)],
                pricing: SwapPricingService(FakePriceSource({})),
                knownAssets: () => {eth, usdc},
                activatedAssets: () {
                  reads++;
                  return wallet.future;
                },
              ),
              registry: registry,
              terms: SwapTermsRepository(
                walletKey: () async => null,
                storage: storage,
              ),
              preferences: SwapPreferences(
                walletKey: () async => null,
                storage: storage,
              ),
              spendableBalance: (_) async => null,
              addressOf: (_) async => null,
              resolveAsset: (_) => null,
            )
            ..add(
              UnifiedSwapCapabilitiesChanged(
                tradingEnabled: true,
                clockValid: true,
                signedIn: signedIn,
              ),
            )
            ..add(const UnifiedSwapStarted());
      addTearDown(() async {
        await bloc.close();
        await registry.dispose();
      });
      return bloc;
    }

    setUp(() {
      wallet = Completer<Set<AssetId>>();
      reads = 0;
    });

    test('signed out, lists what it offers without the wallet', () async {
      final bloc = open(signedIn: false);
      await pumpEventQueue();

      expect(bloc.state.loadingAssets, isFalse);
      expect(bloc.state.catalog.activated, isEmpty);

      bloc.add(const UnifiedSwapCatalogRefreshRequested());
      await pumpEventQueue();
      expect(reads, 0);
    });

    test('signed in, waits for the wallet to say what is active', () async {
      final bloc = open(signedIn: true);
      await pumpEventQueue();
      expect(bloc.state.loadingAssets, isTrue);
      expect(reads, 1);

      wallet.complete({eth});
      await pumpEventQueue();
      expect(bloc.state.loadingAssets, isFalse);
      expect(bloc.state.catalog.activated, {eth});
    });
  });

  group('the aggregator', () {
    late _Kdf kdf;
    late RoutedSwapQuoteSource source;

    setUp(() {
      kdf = _Kdf();
      final byTicker = {
        for (final asset in [eth, usdc, btc]) asset.id: asset,
      };
      source = RoutedSwapQuoteSource(
        RoutedSwapManager(client: kdf, resolveAsset: (t) => byTicker[t]),
        networks: () => SwapNetworks(byTicker.values),
        catalogTimeout: const Duration(milliseconds: 100),
      );
    });

    test('with nothing active, answers without asking KDF', () async {
      // KDF not answering would hold the list back until the timeout.
      kdf.gate = Completer<void>();
      final assets = await source.assets(
        known: {eth, usdc, btc},
        activated: {},
      );

      expect(kdf.calls, 0);
      expect(assets.status, SwapCatalogStatus.fresh);
      expect(assets.quotable, isEmpty);
      // What it can route once active: served EVM networks, so not BTC.
      expect(assets.onceActive, {eth, usdc});
    });

    test('with anything active, KDF decides', () async {
      final assets = await source.assets(
        known: {eth, usdc, btc},
        activated: {btc},
      );

      expect(kdf.calls, 1);
      expect(assets.quotable, {eth});
      expect(assets.onceActive, {eth, usdc});
    });
  });
}

/// A source that records what it was told.
class _Source implements SwapQuoteSource {
  final List<Set<AssetId>> known = [];
  final List<Set<AssetId>> activated = [];

  @override
  SwapLiquiditySource get source => SwapLiquiditySource.atomic;

  @override
  Future<SwapSourceAssets> assets({
    required Set<AssetId> known,
    required Set<AssetId> activated,
  }) async {
    this.known.add(known);
    this.activated.add(activated);
    return SwapSourceAssets(source: source);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// KDF listing ETH as its only routable active coin, once [gate] opens.
class _Kdf implements ApiClient {
  int calls = 0;
  Completer<void>? gate;

  @override
  Future<JsonMap> executeRpc(JsonMap request) async {
    calls++;
    await gate?.future;
    return {
      'mmrpc': '2.0',
      'result': {
        'provider': 'lifi',
        'coins': [
          {'coin': 'ETH', 'chain_id': 1},
        ],
      },
    };
  }
}

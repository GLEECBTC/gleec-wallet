import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_sdk/src/assets/asset_manager.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/coins_bloc/asset_coin_extension.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/trading_status/trading_status_service.dart';
import 'package:web_dex/model/coin.dart';

Map<String, dynamic> _utxoConfig({String coin = 'KMD'}) => {
  'coin': coin,
  'type': 'UTXO',
  'name': 'Komodo',
  'fname': 'Komodo',
  'wallet_only': false,
  'mm2': 1,
  'chain_id': 141,
  'decimals': 8,
  'is_testnet': false,
  'required_confirmations': 1,
  'derivation_path': "m/44'/141'/0'",
  'protocol': {'type': 'UTXO'},
};

Asset _assetFromConfig(Map<String, dynamic> config) =>
    Asset.fromJson(config, knownIds: const {});

Coin _coin(Asset asset, CoinState state) =>
    asset.toCoin().copyWith(state: state);

/// The bloc learns about activation exclusively through [CoinsRepo]'s
/// `enabledAssetsChanges` broadcast. A broadcast stream discards events
/// delivered while nothing is listening, so a subscription that is established
/// late - or an event that is genuinely lost - leaves a row on
/// [CoinState.activating] with no balance watcher, no addresses and nothing to
/// retrigger it. These tests pin the two properties that keep that from being
/// permanent.
void testCoinsBlocActivationRecovery() {
  group('CoinsBloc activation recovery', () {
    late Asset asset;

    setUp(() {
      asset = _assetFromConfig(_utxoConfig());
    });

    test(
      'observes repo broadcasts from construction, before CoinsStarted runs',
      () async {
        // Regression guard. The subscriptions used to be established in
        // _onCoinsStarted *after* `await _tradingStatusService
        // .initialStatusReady` - an unbounded network wait. A login that landed
        // inside that window ran its whole activation fan-out against a
        // listener-less stream and every `active` broadcast was dropped, so
        // every row stayed on `activating` for the rest of the session.
        final repo = _FakeCoinsRepo();
        final bloc = CoinsBloc(
          _FakeSdk(
            assets: _FakeAssetManager({asset.id: asset}),
            pubkeys: _FakePubkeyManager(),
          ),
          repo,
          // Never completes: stands in for a hung or very slow geo endpoint.
          _FakeTradingStatusService(
            initialStatusReady: Completer<void>().future,
          ),
        );
        addTearDown(bloc.close);

        // Deliberately no `bloc.add(CoinsStarted())`.
        repo.enabledAssetsChanges.add(_coin(asset, CoinState.active));

        await expectLater(
          bloc.stream.firstWhere(
            (state) => state.walletCoins[asset.id.id]?.isActive ?? false,
          ),
          completes,
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'reconcile promotes a coin KDF reports as enabled',
      () async {
        final repo = _FakeCoinsRepo(activatedAssetIds: {asset.id});
        final bloc = CoinsBloc(
          _FakeSdk(
            assets: _FakeAssetManager({asset.id: asset}),
            pubkeys: _FakePubkeyManager(),
          ),
          repo,
          _FakeTradingStatusService(),
        );
        addTearDown(bloc.close);

        // Row seeded as `activating`, mirroring _prePopulateListWithActivatingCoins.
        bloc.add(CoinsWalletCoinUpdated(_coin(asset, CoinState.activating)));
        await bloc.stream.firstWhere(
          (state) => state.walletCoins.containsKey(asset.id.id),
        );
        expect(bloc.state.walletCoins[asset.id.id]!.isActive, isFalse);

        // The `active` broadcast never arrives - it was dropped in transit.
        bloc.add(CoinsActivationReconciled());

        await expectLater(
          bloc.stream.firstWhere(
            (state) => state.walletCoins[asset.id.id]?.isActive ?? false,
          ),
          completes,
        );
        expect(repo.ensureBalanceWatchersCalls, isNotEmpty);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'reconcile leaves a coin KDF does not report as enabled alone',
      () async {
        final repo = _FakeCoinsRepo(activatedAssetIds: const {});
        final bloc = CoinsBloc(
          _FakeSdk(
            assets: _FakeAssetManager({asset.id: asset}),
            pubkeys: _FakePubkeyManager(),
          ),
          repo,
          _FakeTradingStatusService(),
        );
        addTearDown(bloc.close);

        bloc.add(CoinsWalletCoinUpdated(_coin(asset, CoinState.activating)));
        await bloc.stream.firstWhere(
          (state) => state.walletCoins.containsKey(asset.id.id),
        );

        bloc.add(CoinsActivationReconciled());
        await Future<void>.delayed(const Duration(milliseconds: 300));

        expect(bloc.state.walletCoins[asset.id.id]!.isActive, isFalse);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}

void main() {
  testCoinsBlocActivationRecovery();
}

class _FakePubkeyManager implements PubkeyManager {
  @override
  Future<AssetPubkeys> getPubkeys(Asset asset) async => AssetPubkeys(
    assetId: asset.id,
    keys: const [],
    availableAddressesCount: 0,
    syncStatus: SyncStatusEnum.success,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAssetManager implements AssetManager {
  _FakeAssetManager(this._assets);

  final Map<AssetId, Asset> _assets;

  @override
  Map<AssetId, Asset> get available => _assets;

  @override
  Asset? fromId(AssetId id) => _assets[id];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSdk implements KomodoDefiSdk {
  _FakeSdk({required this.assets, required this.pubkeys});

  @override
  final AssetManager assets;

  @override
  final PubkeyManager pubkeys;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCoinsRepo implements CoinsRepo {
  _FakeCoinsRepo({this.activatedAssetIds = const {}});

  final Set<AssetId> activatedAssetIds;
  final List<List<AssetId>> ensureBalanceWatchersCalls = <List<AssetId>>[];

  @override
  final StreamController<Coin> enabledAssetsChanges =
      StreamController<Coin>.broadcast();

  @override
  final StreamController<Coin> balanceChanges =
      StreamController<Coin>.broadcast();

  @override
  Map<String, Coin> getKnownCoinsMap({bool excludeExcludedAssets = false}) =>
      <String, Coin>{};

  @override
  Future<Set<AssetId>> getActivatedAssetIds({
    bool forceRefresh = false,
  }) async => activatedAssetIds;

  @override
  int ensureBalanceWatchers(Iterable<AssetId> assetIds) {
    ensureBalanceWatchersCalls.add(assetIds.toList());
    return 0;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTradingStatusService implements TradingStatusService {
  _FakeTradingStatusService({Future<void>? initialStatusReady})
    : _initialStatusReady = initialStatusReady ?? Future<void>.value();

  final Future<void> _initialStatusReady;

  @override
  Future<void> get initialStatusReady => _initialStatusReady;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

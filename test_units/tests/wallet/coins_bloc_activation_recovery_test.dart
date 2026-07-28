import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_sdk/src/assets/asset_manager.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/coins_bloc/asset_coin_extension.dart';
import 'package:web_dex/bloc/coins_bloc/coin_activation_state_bridge.dart';
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

/// The bloc learns about activation from the SDK's activation-state stream,
/// bridged through [CoinsRepo]. That stream replays current state to a late
/// subscriber, which is what makes a lost transition impossible - the defect
/// that used to leave rows on [CoinState.activating] with no balance watcher,
/// no addresses and nothing to retrigger them.
void testCoinsBlocActivationRecovery() {
  group('CoinsBloc activation stream', () {
    late Asset asset;

    CoinsBloc buildBloc(
      _FakeCoinsRepo repo, {
      Future<void>? initialStatusReady,
    }) {
      final bloc = CoinsBloc(
        _FakeSdk(
          assets: _FakeAssetManager({asset.id: asset}),
          pubkeys: _FakePubkeyManager(),
        ),
        repo,
        _FakeTradingStatusService(initialStatusReady: initialStatusReady),
      );
      addTearDown(bloc.close);
      return bloc;
    }

    setUp(() {
      asset = _assetFromConfig(_utxoConfig());
    });

    test(
      'observes the activation stream from construction',
      () async {
        // The subscription used to be established in _onCoinsStarted, *after*
        // `await _tradingStatusService.initialStatusReady` - an unbounded network
        // wait. A login landing inside that window ran its whole activation
        // fan-out against a listener-less stream and every `active` event was
        // dropped, leaving every row on `activating` for the session.
        final repo = _FakeCoinsRepo();
        // Never completes: stands in for a hung or very slow geo endpoint.
        final bloc = buildBloc(
          repo,
          initialStatusReady: Completer<void>().future,
        );

        // Deliberately no `bloc.add(CoinsStarted())`.
        repo.activationStates.add(_coin(asset, CoinState.active));

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
      'replays state that landed before the bloc existed',
      () async {
        // The property that makes the old reconcile pass unnecessary: state is
        // no longer lost just because nothing was listening yet.
        final repo = _FakeCoinsRepo()..seed(_coin(asset, CoinState.active));
        final bloc = buildBloc(
          repo,
          initialStatusReady: Completer<void>().future,
        );

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
      'an SDK-internal activation creates a row',
      () async {
        // Nothing in the app asked for this coin: the SDK activated it on its
        // own behalf (pubkey, balance, withdrawal or tx-history manager). Before
        // the stream existed the app could not see this at all.
        final repo = _FakeCoinsRepo();
        final bloc = buildBloc(repo);

        repo.activationStates.add(_coin(asset, CoinState.active));

        await expectLater(
          bloc.stream.firstWhere(
            (state) => state.walletCoins.containsKey(asset.id.id),
          ),
          completes,
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'a later active event restores a row the app suspended',
      () async {
        // The app publishes `suspended` when its own retry budget runs out, and
        // CoinsBloc evicts the row. If KDF turns out to have enabled the coin
        // anyway, the stream must bring it back.
        final repo = _FakeCoinsRepo();
        final bloc = buildBloc(repo);

        repo.activationStates.add(_coin(asset, CoinState.suspended));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(bloc.state.walletCoins.containsKey(asset.id.id), isFalse);

        repo.activationStates.add(_coin(asset, CoinState.active));

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
      'repair re-drives addresses and balance watchers',
      () async {
        // Activation state itself is no longer repaired here; what remains is
        // the app-owned work that follows it and has no other retrigger.
        final repo = _FakeCoinsRepo();
        final bloc = buildBloc(repo);

        repo.activationStates.add(_coin(asset, CoinState.active));
        await bloc.stream.firstWhere(
          (state) => state.walletCoins[asset.id.id]?.isActive ?? false,
        );

        bloc.add(CoinsWalletRepairRequested());
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(repo.ensureBalanceWatchersCalls, isNotEmpty);
        expect(repo.ensureBalanceWatchersCalls.last, contains(asset.id));
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
  final List<List<AssetId>> ensureBalanceWatchersCalls = <List<AssetId>>[];

  /// Backed by the real bridge, so the fake has the same retain-and-replay
  /// behaviour as [CoinsRepo] rather than a bare broadcast controller that
  /// would drop anything pushed before the bloc's subscription attaches.
  final StreamController<Coin> activationStates =
      StreamController<Coin>.broadcast();

  late final CoinActivationStateBridge _bridge = CoinActivationStateBridge(
    sdkStates: activationStates.stream,
    sdkSnapshot: () => const <Coin>[],
  );

  /// Seeds state that existed before the bloc was built.
  void seed(Coin coin) => _bridge.publishAppState(coin);

  @override
  Stream<Coin> watchCoinActivationState() => _bridge.watch();

  @override
  final StreamController<Coin> balanceChanges =
      StreamController<Coin>.broadcast();

  @override
  Map<String, Coin> getKnownCoinsMap({bool excludeExcludedAssets = false}) =>
      <String, Coin>{};

  @override
  Future<Set<AssetId>> getActivatedAssetIds({
    bool forceRefresh = false,
  }) async => const <AssetId>{};

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

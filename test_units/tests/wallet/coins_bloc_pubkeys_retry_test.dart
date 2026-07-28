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

/// Pubkey fetches are dispatched from activation-state broadcasts, which only
/// fire on a state transition. Once a coin has settled on `active` nothing
/// re-triggers the fetch, so a transient failure must be retried inside the
/// handler or the coin's addresses stay missing for the whole session.
void testCoinsBlocPubkeysRetry() {
  group('CoinsBloc pubkeys', () {
    late Asset asset;

    setUp(() {
      asset = _assetFromConfig(_utxoConfig());
    });

    test(
      'retries a transient getPubkeys failure and lands the result',
      () async {
        var attempts = 0;
        final pubkeys = _FakePubkeyManager((requested) async {
          attempts++;
          if (attempts == 1) {
            throw StateError('transient RPC failure');
          }
          return _assetPubkeys(requested);
        });

        final bloc = CoinsBloc(
          _FakeSdk(
            assets: _FakeAssetManager({asset.id: asset}),
            pubkeys: pubkeys,
          ),
          _FakeCoinsRepo(),
          _FakeTradingStatusService(),
        );
        addTearDown(bloc.close);

        bloc.add(CoinsWalletCoinUpdated(_coin(asset, CoinState.active)));

        await expectLater(
          bloc.stream.firstWhere(
            (state) => state.pubkeys.containsKey(asset.id.id),
          ),
          completes,
        );

        expect(attempts, greaterThanOrEqualTo(2));
        expect(bloc.state.pubkeys[asset.id.id], isNotNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test('does not fetch pubkeys for a coin that is not active', () async {
      var attempts = 0;
      final pubkeys = _FakePubkeyManager((requested) async {
        attempts++;
        return _assetPubkeys(requested);
      });

      final bloc = CoinsBloc(
        _FakeSdk(
          assets: _FakeAssetManager({asset.id: asset}),
          pubkeys: pubkeys,
        ),
        _FakeCoinsRepo(),
        _FakeTradingStatusService(),
      );
      addTearDown(bloc.close);

      bloc.add(CoinsWalletCoinUpdated(_coin(asset, CoinState.activating)));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(attempts, 0);
      expect(bloc.state.pubkeys, isEmpty);
    });
  });
}

void main() {
  testCoinsBlocPubkeysRetry();
}

AssetPubkeys _assetPubkeys(Asset asset) => AssetPubkeys(
  assetId: asset.id,
  keys: const [],
  availableAddressesCount: 0,
  syncStatus: SyncStatusEnum.success,
);

class _FakePubkeyManager implements PubkeyManager {
  _FakePubkeyManager(this._handler);

  final Future<AssetPubkeys> Function(Asset asset) _handler;

  @override
  Future<AssetPubkeys> getPubkeys(Asset asset) => _handler(asset);

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
  @override
  Map<String, Coin> getKnownCoinsMap({bool excludeExcludedAssets = false}) =>
      <String, Coin>{};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTradingStatusService implements TradingStatusService {
  @override
  Future<void> get initialStatusReady async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_sdk/src/assets/asset_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/coins_bloc/asset_coin_extension.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/trading_status/trading_status_service.dart';
import 'package:web_dex/model/cex_price.dart';
import 'package:web_dex/model/coin.dart';

/// What `_onBalanceChanged` may and may not skip.
///
/// The handler used to copy `state.walletCoins` **and** spread the whole
/// ~800-entry `coins` catalogue on every balance tick, then hand both to
/// `emit`. `Coin.props` excludes `sendableBalance`, `state` is preserved
/// explicitly, and `Coin.address` is never assigned anywhere in `lib/` - so on
/// a balance-only tick the merged coin compares equal, both maps compare equal,
/// and `Bloc.emit`'s `if (state == _state) return` drops the emit. The work was
/// two map allocations plus an ~840-`Coin` deep equality walk to reach a no-op.
///
/// Guarding that is only safe if the cases that *do* change state still emit.
/// These tests are written against the original handler and must keep passing
/// unchanged afterwards: they are the proof the guard is behaviour-preserving,
/// not a description of the optimisation.
void testCoinsBlocBalanceEmit() {
  group('CoinsBloc balance emits:', () {
    late Asset asset;

    setUp(() => asset = _assetFromConfig(_utxoConfig()));

    /// A bloc with [asset] active in `walletCoins` **and** present in the
    /// `coins` catalogue.
    ///
    /// Seeding the catalogue matters. `_onBalanceChanged` writes
    /// `coins: {...state.coins, assetId: merged}`, so against an empty
    /// catalogue it genuinely *adds* an entry and the state legitimately
    /// changes - which would make a "no emit" assertion pass or fail for the
    /// wrong reason. In the app the catalogue is populated from
    /// `getKnownCoinsMap()` before login (`coins_bloc.dart:239`), so the write
    /// is a replacement.
    Future<CoinsBloc> seededBloc() async {
      final catalogueCoin = _coin(asset, CoinState.active);
      final bloc = CoinsBloc(
        _FakeSdk(assets: _FakeAssetManager({asset.id: asset})),
        _FakeCoinsRepo({asset.id.id: catalogueCoin}),
        _FakeTradingStatusService(),
      );
      addTearDown(bloc.close);

      bloc.add(CoinsWalletCoinUpdated(catalogueCoin));
      await bloc.stream.firstWhere(
        (s) => s.walletCoins.containsKey(asset.id.id),
      );
      // Seeding an active coin also dispatches `CoinsPubkeysRequested`
      // (`coins_bloc.dart:349`), whose handler emits on its own schedule. Let
      // that land before the caller starts counting, or the pubkey emission is
      // mistaken for a balance emission.
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // One balance tick to reach the steady state.
      //
      // `_onBalanceChanged` writes `coins: {...state.coins, id: merged}`, and
      // in the app `state.coins` is the ~800-entry catalogue loaded from
      // `getKnownCoinsMap()` before login (`coins_bloc.dart:239`) - an event
      // this test never dispatches, so the first tick genuinely *adds* the
      // entry and legitimately emits. Every tick after it is a replacement,
      // which is the case these tests are about.
      bloc.add(CoinsBalanceChanged(catalogueCoin));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return bloc;
    }

    test('a balance-only change emits nothing', () async {
      final bloc = await seededBloc();

      final emissions = <CoinsState>[];
      final sub = bloc.stream.listen(emissions.add);
      addTearDown(sub.cancel);

      bloc.add(
        CoinsBalanceChanged(
          _coin(asset, CoinState.active).copyWith(sendableBalance: 42),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(emissions, isEmpty);
    });

    test('a price change still emits - usdPrice is in Coin.props', () async {
      final bloc = await seededBloc();

      final emissions = <CoinsState>[];
      final sub = bloc.stream.listen(emissions.add);
      addTearDown(sub.cancel);

      bloc.add(
        CoinsBalanceChanged(
          _coin(asset, CoinState.active).copyWith(
            usdPrice: CexPrice(
              assetId: asset.id,
              price: Decimal.parse('1.23'),
              change24h: Decimal.zero,
              lastUpdated: DateTime(2026),
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(emissions, hasLength(1));
      expect(
        emissions.single.walletCoins[asset.id.id]?.usdPrice?.price,
        Decimal.parse('1.23'),
      );
    });

    test(
      'a balance tick cannot deactivate a coin, so it cannot remove it',
      () async {
        // Measured, not assumed: the handler merges with `state: existing.state`,
        // so an incoming `suspended` coin is rewritten to the state already held.
        // `merged.isActive` therefore stays true and the `walletCoins.remove`
        // branch is unreachable from this event. Any guard must not "fix" that -
        // deactivation arrives via `CoinsWalletCoinUpdated`, not here.
        final bloc = await seededBloc();

        final emissions = <CoinsState>[];
        final sub = bloc.stream.listen(emissions.add);
        addTearDown(sub.cancel);

        bloc.add(CoinsBalanceChanged(_coin(asset, CoinState.suspended)));
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(emissions, isEmpty);
        expect(bloc.state.walletCoins.containsKey(asset.id.id), isTrue);
        expect(bloc.state.walletCoins[asset.id.id]?.state, CoinState.active);
      },
    );

    test('deactivation still works through CoinsWalletCoinUpdated', () async {
      // The channel that *is* allowed to change membership. Guarding
      // `_onBalanceChanged` must leave this path untouched, or a suspended coin
      // keeps its row for the rest of the session.
      final bloc = await seededBloc();

      bloc.add(CoinsWalletCoinUpdated(_coin(asset, CoinState.suspended)));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(bloc.state.walletCoins.containsKey(asset.id.id), isFalse);
    });

    test('an unknown coin is ignored', () async {
      final bloc = await seededBloc();
      final other = _assetFromConfig(_utxoConfig(coin: 'DOC'));

      final emissions = <CoinsState>[];
      final sub = bloc.stream.listen(emissions.add);
      addTearDown(sub.cancel);

      bloc.add(CoinsBalanceChanged(_coin(other, CoinState.active)));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(emissions, isEmpty);
    });

    test('the activation state survives a balance tick', () async {
      // `_onBalanceChanged` merges with `state: existing.state` precisely so a
      // balance broadcast cannot knock a coin out of `active`. Any guard has to
      // preserve that.
      final bloc = await seededBloc();

      bloc.add(
        CoinsBalanceChanged(
          _coin(asset, CoinState.inactive).copyWith(sendableBalance: 7),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(bloc.state.walletCoins[asset.id.id]?.state, CoinState.active);
    });
  });
}

void main() => testCoinsBlocBalanceEmit();

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

class _FakeSdk implements KomodoDefiSdk {
  _FakeSdk({required this.assets});

  @override
  final AssetManager assets;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAssetManager implements AssetManager {
  _FakeAssetManager(this._assets);

  final Map<AssetId, Asset> _assets;

  @override
  Map<AssetId, Asset> get available => _assets;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCoinsRepo implements CoinsRepo {
  _FakeCoinsRepo([this._catalogue = const <String, Coin>{}]);

  final Map<String, Coin> _catalogue;

  @override
  Stream<Coin> watchCoinActivationState() => const Stream<Coin>.empty();

  @override
  final StreamController<Coin> balanceChanges =
      StreamController<Coin>.broadcast();

  @override
  Map<String, Coin> getKnownCoinsMap({bool excludeExcludedAssets = false}) =>
      Map<String, Coin>.of(_catalogue);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTradingStatusService implements TradingStatusService {
  @override
  Future<void> get initialStatusReady async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

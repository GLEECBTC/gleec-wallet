import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
// These managers are reachable off KomodoDefiSdk but not exported by name, and
// the fakes have to declare the types they implement. Same approach as the
// other bloc tests in this suite.
import 'package:komodo_defi_sdk/src/assets/asset_manager.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_history_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/transaction_history/transaction_history_bloc.dart';
import 'package:web_dex/bloc/transaction_history/transaction_history_event.dart';
import 'package:web_dex/bloc/transaction_history/transaction_history_state.dart';
import 'package:web_dex/model/coin.dart';

import 'coin_details_test_harness.dart';

/// The asset details page builds a fresh [TransactionHistoryBloc] per open, so
/// it always starts at `transactions: []` with `loading: true` - and the list
/// renders a spinner for exactly as long as that pair holds.
///
/// The bloc used to await `pubkeys.lastKnown(id) ?? getPubkeys(asset)` before
/// subscribing. `lastKnown` reads only the in-memory cache, and `getPubkeys`
/// falls through to a fresh fetch that awaits `activateAsset` with retry, so
/// an unbounded network call sat in front of a transaction cache that was
/// already on disk. These pin the ordering that fixes it.
void testTransactionHistoryBloc() {
  group('TransactionHistoryBloc', () {
    late Coin coin;
    late AssetId assetId;

    setUp(() {
      coin = buildTestCoin();
      assetId = coin.id;
    });

    test(
      'renders transactions while getPubkeys never completes',
      () async {
        final pubkeys = _FakePubkeyManager(
          // Models a persisted-pubkey miss falling through to activation.
          getPubkeysFuture: Completer<AssetPubkeys>().future,
        );
        final sdk = _FakeSdk(
          pubkeys: pubkeys,
          transactions: _FakeTransactionHistoryManager(
            Stream.value([buildTestTransaction(assetId: assetId)]),
          ),
          assetId: assetId,
        );

        final bloc = TransactionHistoryBloc(sdk: sdk)
          ..add(TransactionHistorySubscribe(coin: coin));
        addTearDown(bloc.close);

        final state = await bloc.stream
            .firstWhere((s) => s.transactions.isNotEmpty)
            .timeout(const Duration(seconds: 5));

        expect(state.transactions, hasLength(1));
        expect(
          state.loading,
          isFalse,
          reason: 'the spinner must clear on the cached rows, not on pubkeys',
        );
        expect(
          pubkeys.getPubkeysCalls,
          greaterThan(0),
          reason: 'pubkeys are still resolved, just not awaited first',
        );
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );

    test('re-sorts recipients once wallet addresses arrive', () async {
      // sanitize() only needs the address set to order recipients, so the list
      // paints without it and is corrected when it resolves.
      const mine = 'my-address';
      final transaction = buildTestTransaction(
        assetId: assetId,
        from: const ['someone-else'],
        to: const ['other-party', mine],
      );

      final hydrated = Completer<AssetPubkeys?>();
      final sdk = _FakeSdk(
        pubkeys: _FakePubkeyManager(
          hydratedFuture: hydrated.future,
          getPubkeysFuture: Completer<AssetPubkeys>().future,
        ),
        transactions: _FakeTransactionHistoryManager(
          Stream.value([transaction]),
        ),
        assetId: assetId,
      );

      final bloc = TransactionHistoryBloc(sdk: sdk)
        ..add(TransactionHistorySubscribe(coin: coin));
      addTearDown(bloc.close);

      final before = await bloc.stream
          .firstWhere((s) => s.transactions.isNotEmpty)
          .timeout(const Duration(seconds: 5));
      expect(
        before.transactions.single.to,
        ['other-party', mine],
        reason: 'rendered before addresses are known',
      );

      hydrated.complete(_pubkeysWith(assetId, const [mine]));

      final after = await bloc.stream
          .firstWhere((s) => s.transactions.single.to.first == mine)
          .timeout(const Duration(seconds: 5));
      expect(after.transactions.single.to, [mine, 'other-party']);
    });

    test('a pubkey failure does not surface as a history error', () async {
      final sdk = _FakeSdk(
        pubkeys: _FakePubkeyManager(
          getPubkeysError: StateError('pubkeys unavailable'),
        ),
        transactions: _FakeTransactionHistoryManager(
          Stream.value([buildTestTransaction(assetId: assetId)]),
        ),
        assetId: assetId,
      );

      final bloc = TransactionHistoryBloc(sdk: sdk)
        ..add(TransactionHistorySubscribe(coin: coin));
      addTearDown(bloc.close);

      final state = await bloc.stream
          .firstWhere((s) => s.transactions.isNotEmpty)
          .timeout(const Duration(seconds: 5));

      expect(state.error, isNull);
      expect(state.transactions, hasLength(1));
    });
  });
}

AssetPubkeys _pubkeysWith(AssetId assetId, List<String> addresses) =>
    AssetPubkeys(
      assetId: assetId,
      keys: [
        for (final address in addresses)
          PubkeyInfo(
            address: address,
            derivationPath: null,
            chain: null,
            balance: BalanceInfo.zero(),
            coinTicker: assetId.id,
          ),
      ],
      availableAddressesCount: addresses.length,
      syncStatus: SyncStatusEnum.success,
    );

class _FakeSdk implements KomodoDefiSdk {
  _FakeSdk({
    required _FakePubkeyManager pubkeys,
    required _FakeTransactionHistoryManager transactions,
    required AssetId assetId,
  }) : _pubkeys = pubkeys,
       _transactions = transactions,
       _assetId = assetId;

  final _FakePubkeyManager _pubkeys;
  final _FakeTransactionHistoryManager _transactions;
  final AssetId _assetId;

  @override
  PubkeyManager get pubkeys => _pubkeys;

  @override
  TransactionHistoryManager get transactions => _transactions;

  @override
  AssetManager get assets => _FakeAssetManager(_assetId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAssetManager implements AssetManager {
  _FakeAssetManager(this._assetId);
  final AssetId _assetId;

  @override
  Map<AssetId, Asset> get available => {
    _assetId: Asset(
      id: _assetId,
      protocol: UtxoProtocol.fromJson({
        'type': 'UTXO',
        'is_testnet': true,
        'protocol': {'type': 'UTXO'},
        'electrum': <Map<String, dynamic>>[],
      }),
      isWalletOnly: false,
      signMessagePrefix: null,
    ),
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePubkeyManager implements PubkeyManager {
  _FakePubkeyManager({
    Future<AssetPubkeys>? getPubkeysFuture,
    Future<AssetPubkeys?>? hydratedFuture,
    this.getPubkeysError,
  }) : _getPubkeysFuture = getPubkeysFuture,
       _hydratedFuture = hydratedFuture ?? Future.value();

  final Future<AssetPubkeys>? _getPubkeysFuture;
  final Future<AssetPubkeys?> _hydratedFuture;

  /// Raised from inside [getPubkeys] rather than handed over as a pre-built
  /// error future, which the test framework would report as unhandled during
  /// the window before the bloc awaits it.
  final Object? getPubkeysError;
  int getPubkeysCalls = 0;

  @override
  AssetPubkeys? lastKnown(AssetId assetId) => null;

  @override
  Future<AssetPubkeys?> hydratedPubkeys(Asset asset) => _hydratedFuture;

  @override
  Future<AssetPubkeys> getPubkeys(Asset asset) async {
    getPubkeysCalls++;
    final error = getPubkeysError;
    if (error != null) throw error;
    return _getPubkeysFuture ?? Completer<AssetPubkeys>().future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTransactionHistoryManager implements TransactionHistoryManager {
  _FakeTransactionHistoryManager(this._merged);
  final Stream<List<Transaction>> _merged;

  @override
  Stream<List<Transaction>> watchTransactionHistoryMerged(
    Asset asset, {
    Transaction Function(Transaction transaction)? transform,
  }) => _merged;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

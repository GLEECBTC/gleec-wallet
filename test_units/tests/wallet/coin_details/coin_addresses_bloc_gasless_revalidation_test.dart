import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_sdk/src/assets/asset_manager.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/analytics/events/transaction_events.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/analytics/analytics_event.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_bloc.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_event.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_state.dart';
import 'package:web_dex/shared/gasless/tron_gasless_receive_reason.dart';

const _assetId = 'USDT-TRC20';
const _walletHash = 'wallet-a-pubkey-hash';

Map<String, dynamic> _trxConfig() => {
  'coin': 'TRX',
  'type': 'TRX',
  'name': 'TRON',
  'fname': 'TRON',
  'wallet_only': true,
  'mm2': 1,
  'decimals': 6,
  'required_confirmations': 1,
  'derivation_path': "m/44'/195'",
  'protocol': {
    'type': 'TRX',
    'protocol_data': {'network': 'Mainnet'},
  },
  'nodes': <Map<String, dynamic>>[],
};

Map<String, dynamic> _trc20Config() => {
  'coin': _assetId,
  'type': 'TRC-20',
  'name': 'Tether',
  'fname': 'Tether',
  'wallet_only': true,
  'mm2': 1,
  'decimals': 6,
  'derivation_path': "m/44'/195'",
  'protocol': {
    'type': 'TRC20',
    'protocol_data': {
      'platform': 'TRX',
      'contract_address': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
    },
  },
  'contract_address': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
  'parent_coin': 'TRX',
  'nodes': <Map<String, dynamic>>[],
};

Asset _asset() {
  final parent = Asset.fromJson(_trxConfig(), knownIds: const {});
  return Asset.fromJson(_trc20Config(), knownIds: {parent.id});
}

PubkeyInfo _pubkey(String suffix) => PubkeyInfo(
  address: 'TStandardAddress$suffix',
  derivationPath: "m/44'/195'/0'/0/0",
  chain: 'external',
  balance: BalanceInfo(
    total: Decimal.zero,
    spendable: Decimal.zero,
    unspendable: Decimal.zero,
  ),
  coinTicker: _assetId,
  gasfreeAddress: 'TGasFreeAddress$suffix',
);

KdfUser _user({String name = 'wallet-a', String pubkeyHash = _walletHash}) =>
    KdfUser(
      walletId: WalletId.withPubkeyHash(
        name,
        const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
        pubkeyHash,
      ),
      isBip39Seed: true,
    );

class _ControlledAuth implements KomodoDefiLocalAuth {
  _ControlledAuth(this.user);

  KdfUser user;
  Completer<KdfUser?>? _nextUser;
  int currentUserCalls = 0;

  void setUser(KdfUser value) {
    user = value;
  }

  void pauseNextCurrentUser() {
    _nextUser = Completer<KdfUser?>();
  }

  void releaseCurrentUser() {
    final pending = _nextUser!;
    _nextUser = null;
    pending.complete(user);
  }

  @override
  Future<KdfUser?> get currentUser {
    currentUserCalls += 1;
    final pending = _nextUser;
    if (pending != null) {
      return pending.future;
    }
    return Future<KdfUser?>.value(user);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePubkeyManager implements PubkeyManager {
  _FakePubkeyManager(this.asset, this.keys, {this.error});

  final Asset asset;
  List<PubkeyInfo> keys;

  /// Thrown instead of returning [keys], to drive the handlers' catch blocks.
  final Object? error;

  @override
  Future<AssetPubkeys> getPubkeys(Asset asset) async {
    final failure = error;
    if (failure != null) throw failure;
    return AssetPubkeys(
      assetId: this.asset.id,
      keys: keys,
      availableAddressesCount: keys.length,
      syncStatus: SyncStatusEnum.success,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAssetManager implements AssetManager {
  _FakeAssetManager(this.asset);

  final Asset asset;

  @override
  Set<Asset> findAssetsByConfigId(String ticker) =>
      ticker == asset.id.id ? {asset} : const {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSdk implements KomodoDefiSdk {
  _FakeSdk({required this.assets, required this.auth, required this.pubkeys});

  @override
  final AssetManager assets;

  @override
  final KomodoDefiLocalAuth auth;

  @override
  final PubkeyManager pubkeys;

  @override
  bool canReceiveGasless(Asset asset) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingAnalyticsBloc implements AnalyticsBloc {
  final List<GaslessReceiveAnalyticsEventData> receiveEvents = [];

  @override
  void add(AnalyticsEvent event) {
    if (event case AnalyticsSendDataEvent(
      data: final GaslessReceiveAnalyticsEventData data,
    )) {
      receiveEvents.add(data);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestCoinAddressesBloc extends CoinAddressesBloc {
  _TestCoinAddressesBloc(super.sdk, super.assetId, super.analyticsBloc);

  void seedReady(CoinAddressesState ready) {
    // This harness seeds the pre-race state; all subsequent behavior is the
    // production event handler.
    // ignore: invalid_use_of_visible_for_testing_member
    emit(ready);
  }
}

void testCoinAddressesBlocGaslessRevalidation() {
  group('GasFree account-status error boundary', () {
    for (final testCase in <(String, Object)>[
      (
        'MmRpcException lifecycle string',
        const GetFeeEstimationRequestErrorCoinNotFoundException(),
      ),
      (
        'GeneralErrorResponse security string',
        GeneralErrorResponse(
          mmrpc: '2.0',
          error: 'token decimals mismatch',
          errorPath: 'gasless.account_status',
          errorTrace: null,
          errorType: 'TokenDecimalMismatch',
          errorData: null,
          object: const <String, dynamic>{},
        ),
      ),
    ]) {
      test('${testCase.$1} is not interpreted by the app', () {
        expect(
          // ignore: invalid_use_of_visible_for_testing_member
          CoinAddressesBloc.mapGaslessAccountStatusErrorForTesting(testCase.$2),
          isNull,
        );
      });
    }

    test('typed SDK error code retains its exact security mapping', () {
      // ignore: invalid_use_of_visible_for_testing_member
      final mapped = CoinAddressesBloc.mapGaslessAccountStatusErrorForTesting(
        GaslessTransferException(
          kind: GaslessTransferErrorKind.providerResponse,
          code: GaslessTransferErrorCode.tokenDecimalMismatch,
          stage: GaslessTransferStage.status,
          message: 'token decimals mismatch',
          retryable: false,
          terminal: true,
        ),
      );

      expect(mapped, (
        status: GaslessReceiveStatus.securityMismatch,
        reason: GaslessReceiveReasonCode.tokenDecimalsMismatch,
        shouldRefresh: false,
      ));
    });

    test('retryable capabilityNotReady remains temporary after a superseded '
        'status probe', () {
      // ignore: invalid_use_of_visible_for_testing_member
      final mapped = CoinAddressesBloc.mapGaslessAccountStatusErrorForTesting(
        GaslessTransferException(
          kind: GaslessTransferErrorKind.capabilityNotReady,
          code: GaslessTransferErrorCode.capabilityNotReady,
          stage: GaslessTransferStage.status,
          message: 'A newer account-status probe superseded this one',
          retryable: true,
          terminal: false,
        ),
      );

      expect(mapped, (
        status: GaslessReceiveStatus.temporarilyUnavailable,
        reason: GaslessReceiveReasonCode.accountStatusUnavailable,
        shouldRefresh: true,
      ));
    });

    for (final testCase
        in <
          (
            String,
            GaslessTransferErrorCode,
            GaslessReceiveStatus,
            GaslessReceiveReasonCode,
          )
        >[
          (
            'CoinNotSupported',
            GaslessTransferErrorCode.coinNotSupported,
            GaslessReceiveStatus.unsupported,
            GaslessReceiveReasonCode.assetUnsupported,
          ),
          (
            'NotEthCoin',
            GaslessTransferErrorCode.notEthCoin,
            GaslessReceiveStatus.unsupported,
            GaslessReceiveReasonCode.assetUnsupported,
          ),
          (
            'GaslessNotConfigured',
            GaslessTransferErrorCode.gaslessNotConfigured,
            GaslessReceiveStatus.disabled,
            GaslessReceiveReasonCode.reactivationRequired,
          ),
          (
            'CoinNotFound',
            GaslessTransferErrorCode.coinNotFound,
            GaslessReceiveStatus.disabled,
            GaslessReceiveReasonCode.reactivationRequired,
          ),
        ]) {
      test('${testCase.$1} retains its exact KDF receive classification', () {
        // ignore: invalid_use_of_visible_for_testing_member
        final mapped = CoinAddressesBloc.mapGaslessAccountStatusErrorForTesting(
          GaslessTransferException(
            kind: GaslessTransferErrorKind.configuration,
            code: testCase.$2,
            stage: GaslessTransferStage.status,
            message: testCase.$1,
            retryable: false,
            terminal: true,
          ),
        );

        expect(mapped, (
          status: testCase.$3,
          reason: testCase.$4,
          shouldRefresh: false,
        ));
      });
    }
  });

  for (final testCase in <(String, List<PubkeyInfo>)>[
    ('replacement', [_pubkey('Replacement')]),
    ('duplicate candidates', [_pubkey('DuplicateA'), _pubkey('DuplicateB')]),
  ]) {
    test(
      'pubkey ${testCase.$1} revokes ready evidence before first await',
      () async {
        final asset = _asset();
        final original = _pubkey('Original');
        final auth = _ControlledAuth(_user());
        final pubkeys = _FakePubkeyManager(asset, testCase.$2);
        final analytics = _RecordingAnalyticsBloc();
        final bloc = _TestCoinAddressesBloc(
          _FakeSdk(
            assets: _FakeAssetManager(asset),
            auth: auth,
            pubkeys: pubkeys,
          ),
          asset.id.id,
          analytics,
        );
        addTearDown(bloc.close);
        bloc.seedReady(
          CoinAddressesState(
            addresses: [original],
            gaslessReceiveStatus: GaslessReceiveStatus.ready,
            verifiedGasfreeAddress: original.gasfreeAddress,
            gaslessReceiveWalletPubkeyHash: _walletHash,
          ),
        );
        auth.pauseNextCurrentUser();

        final firstEmission = bloc.stream.first;
        bloc.add(CoinAddressesPubkeysUpdated(testCase.$2));
        final checking = await firstEmission.timeout(
          const Duration(seconds: 1),
        );

        expect(auth.currentUserCalls, 1);
        expect(checking.addresses, isEmpty);
        expect(checking.gaslessReceiveStatus, GaslessReceiveStatus.checking);
        expect(checking.verifiedGasfreeAddress, isNull);
        expect(checking.gaslessReceiveWalletPubkeyHash, isNull);
        expect(analytics.receiveEvents, hasLength(1));
        expect(
          analytics.receiveEvents.single.parameters,
          containsPair('status', 'revoked'),
        );
        expect(
          analytics.receiveEvents.single.parameters,
          containsPair('code', 'custody_address_mismatch'),
        );

        final settledFuture = bloc.stream
            .firstWhere(
              (state) =>
                  state.gaslessReceiveStatus != GaslessReceiveStatus.checking,
            )
            .timeout(const Duration(seconds: 1));
        auth.releaseCurrentUser();
        final settled = await settledFuture;

        expect(settled.addresses, testCase.$2);
        expect(settled.gaslessReceiveStatus, isNot(GaslessReceiveStatus.ready));
        expect(settled.verifiedGasfreeAddress, isNull);
        expect(settled.gaslessReceiveWalletPubkeyHash, isNull);
      },
    );
  }

  group('the address-list load always reaches a terminal form status', () {
    // `_onPubkeysUpdated` emits `submitting` with an empty address list before
    // its first await (the revocation tested above). The GasFree-only handlers
    // supersede the *GasFree* evaluation without ever emitting a `FormStatus`,
    // so when both counters were one and the same, a 30-second refresh landing
    // mid-load aborted the load and left `CoinAddresses` rendering a spinner
    // under the address list until the coin page was reopened.

    /// Spins the microtask queue until [condition] holds, so the test does not
    /// depend on how many turns a concurrently-running handler needs.
    Future<void> pumpUntil(
      bool Function() condition, {
      required String reason,
    }) async {
      for (var turn = 0; turn < 1000; turn++) {
        if (condition()) return;
        await Future<void>.delayed(Duration.zero);
      }
      fail(reason);
    }

    test(
      'a superseding GasFree refresh cannot strand it at submitting',
      () async {
        final asset = _asset();
        final original = _pubkey('Original');
        // Three unused addresses so `getCantCreateNewAddressReasons` returns a
        // non-null set: the pre-emit nulls that field too, and it drives the
        // create-address button's disabled reasons.
        final replacements = [_pubkey('A'), _pubkey('B'), _pubkey('C')];
        final auth = _ControlledAuth(_user());
        final analytics = _RecordingAnalyticsBloc();
        final bloc = _TestCoinAddressesBloc(
          _FakeSdk(
            assets: _FakeAssetManager(asset),
            auth: auth,
            pubkeys: _FakePubkeyManager(asset, replacements),
          ),
          asset.id.id,
          analytics,
        );
        addTearDown(bloc.close);
        bloc.seedReady(
          CoinAddressesState(
            status: FormStatus.success,
            addresses: [original],
            gaslessReceiveStatus: GaslessReceiveStatus.ready,
            verifiedGasfreeAddress: original.gasfreeAddress,
            gaslessReceiveWalletPubkeyHash: _walletHash,
          ),
        );

        auth.pauseNextCurrentUser();
        final pendingFuture = bloc.stream.first;
        bloc.add(CoinAddressesPubkeysUpdated(replacements));
        final pending = await pendingFuture.timeout(const Duration(seconds: 1));
        expect(pending.status, FormStatus.submitting);
        expect(pending.addresses, isEmpty);

        // The scheduled GasFree refresh fires while the load is still awaiting
        // its first wallet read, bumping the GasFree evaluation generation.
        final callsBeforeRefresh = auth.currentUserCalls;
        bloc.add(const CoinAddressesGaslessReceiveRefreshRequested());
        await pumpUntil(
          () => auth.currentUserCalls > callsBeforeRefresh,
          reason: 'the GasFree refresh never reached its first wallet read',
        );

        final settledFuture = bloc.stream
            .firstWhere((state) => state.status != FormStatus.submitting)
            .timeout(const Duration(seconds: 1));
        auth.releaseCurrentUser();
        final settled = await settledFuture;

        expect(settled.status, FormStatus.success);
        expect(settled.addresses, replacements);
        expect(
          settled.cantCreateNewAddressReasons,
          contains(CantCreateNewAddressReason.maxGapLimitReached),
        );

        // The superseding refresh settles afterwards and must not put the form
        // back into a loading state it will never leave.
        await pumpUntil(
          () =>
              bloc.state.gaslessReceiveStatus != GaslessReceiveStatus.checking,
          reason: 'the GasFree refresh never settled',
        );
        expect(bloc.state.status, FormStatus.success);
        expect(bloc.state.addresses, replacements);
      },
    );

    test(
      'a failed load reports the failure instead of loading forever',
      () async {
        final asset = _asset();
        final original = _pubkey('Original');
        final auth = _ControlledAuth(_user());
        final analytics = _RecordingAnalyticsBloc();
        final bloc = _TestCoinAddressesBloc(
          _FakeSdk(
            assets: _FakeAssetManager(asset),
            auth: auth,
            pubkeys: _FakePubkeyManager(
              asset,
              const [],
              error: StateError('pubkey read failed'),
            ),
          ),
          asset.id.id,
          analytics,
        );
        addTearDown(bloc.close);
        bloc.seedReady(
          CoinAddressesState(
            status: FormStatus.success,
            addresses: [original],
            gaslessReceiveStatus: GaslessReceiveStatus.ready,
            verifiedGasfreeAddress: original.gasfreeAddress,
            gaslessReceiveWalletPubkeyHash: _walletHash,
          ),
        );

        final settledFuture = bloc.stream
            .firstWhere((state) => state.errorMessage != null)
            .timeout(const Duration(seconds: 1));
        bloc.add(CoinAddressesPubkeysUpdated([original]));
        final settled = await settledFuture;

        // `ErrorDisplay` is gated on `FormStatus.failure`, so leaving `status` at
        // the pre-emit's `submitting` hid the error behind a permanent spinner.
        expect(settled.status, FormStatus.failure);
        expect(settled.errorMessage, isNotNull);
      },
    );
  });

  test(
    'queued previous-wallet pubkeys are never rendered after a wallet switch',
    () async {
      final asset = _asset();
      final walletAAddress = _pubkey('WalletA');
      final walletBAddress = _pubkey('WalletB');
      final auth = _ControlledAuth(_user());
      final pubkeys = _FakePubkeyManager(asset, [walletBAddress]);
      final analytics = _RecordingAnalyticsBloc();
      final bloc = _TestCoinAddressesBloc(
        _FakeSdk(
          assets: _FakeAssetManager(asset),
          auth: auth,
          pubkeys: pubkeys,
        ),
        asset.id.id,
        analytics,
      );
      addTearDown(bloc.close);
      bloc.seedReady(
        CoinAddressesState(
          addresses: [walletAAddress],
          gaslessReceiveStatus: GaslessReceiveStatus.ready,
          verifiedGasfreeAddress: walletAAddress.gasfreeAddress,
          gaslessReceiveWalletPubkeyHash: _walletHash,
        ),
      );
      auth.setUser(_user(name: 'wallet-b', pubkeyHash: 'wallet-b-pubkey-hash'));

      final emissions = <CoinAddressesState>[];
      final subscription = bloc.stream.listen(emissions.add);
      addTearDown(subscription.cancel);
      final settledFuture = bloc.stream
          .firstWhere(
            (state) =>
                state.gaslessReceiveStatus != GaslessReceiveStatus.checking,
          )
          .timeout(const Duration(seconds: 1));

      // This payload was queued by wallet A's old watcher after wallet B
      // became active.
      bloc.add(CoinAddressesPubkeysUpdated([walletAAddress]));
      final settled = await settledFuture;

      expect(emissions, isNotEmpty);
      expect(emissions.first.addresses, isEmpty);
      expect(
        emissions.expand((state) => state.addresses),
        isNot(contains(walletAAddress)),
      );
      expect(settled.addresses, [walletBAddress]);
      expect(settled.gaslessReceiveStatus, isNot(GaslessReceiveStatus.ready));
    },
  );
}

void main() {
  testCoinAddressesBlocGaslessRevalidation();
}

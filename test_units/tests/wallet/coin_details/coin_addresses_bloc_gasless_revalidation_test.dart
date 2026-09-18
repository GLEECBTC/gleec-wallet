import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_sdk/src/assets/asset_manager.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_sdk/src/withdrawals/withdrawal_manager.dart';
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

KdfUser _user({String name = 'wallet-a', String? pubkeyHash = _walletHash}) =>
    KdfUser(
      walletId: WalletId(
        name: name,
        authOptions: const AuthOptions(
          derivationMethod: DerivationMethod.hdWallet,
        ),
        pubkeyHash: pubkeyHash,
      ),
      isBip39Seed: true,
    );

class _ControlledAuth implements KomodoDefiLocalAuth {
  _ControlledAuth(this.user);

  KdfUser user;
  Completer<KdfUser?>? _nextUser;
  int currentUserCalls = 0;
  int? pauseAtCall;
  KdfUser? Function(int call)? userAtCall;
  final pausedRead = Completer<void>();

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
    if (currentUserCalls == pauseAtCall) {
      pauseNextCurrentUser();
      pausedRead.complete();
    }
    final pending = _nextUser;
    if (pending != null) {
      return pending.future;
    }
    return Future<KdfUser?>.value(
      userAtCall == null ? user : userAtCall!(currentUserCalls),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePubkeyManager implements PubkeyManager {
  _FakePubkeyManager(this.asset, this.keys);

  final Asset asset;
  List<PubkeyInfo> keys;
  Object? readError;
  Object? precacheError;
  int readCalls = 0;
  int watchCalls = 0;
  int watchCancellations = 0;
  StreamController<AssetPubkeys>? updates;
  final watchStarted = Completer<void>();

  @override
  Future<void> precachePubkeys(Asset asset) async {
    final error = precacheError;
    if (error != null) throw error;
  }

  @override
  Stream<AssetPubkeys> watchPubkeys(
    Asset asset, {
    bool activateIfNeeded = true,
  }) {
    if (!watchStarted.isCompleted) watchStarted.complete();
    watchCalls += 1;
    updates = StreamController<AssetPubkeys>.broadcast(
      onCancel: () => watchCancellations += 1,
    );
    return _ClockLocalStream(updates!.stream);
  }

  @override
  Future<AssetPubkeys> getPubkeys(Asset asset) async {
    readCalls += 1;
    final error = readError;
    if (error != null) throw error;
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

// Dart's broadcast cancel may return a shared completed future created outside
// FakeAsync. Give cancellation a future owned by the current test clock.
class _ClockLocalStream extends Stream<AssetPubkeys> {
  _ClockLocalStream(this.source);
  final Stream<AssetPubkeys> source;

  @override
  StreamSubscription<AssetPubkeys> listen(
    void Function(AssetPubkeys)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _ClockLocalSubscription(
    source.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    ),
  );
}

class _ClockLocalSubscription implements StreamSubscription<AssetPubkeys> {
  _ClockLocalSubscription(this.source);
  final StreamSubscription<AssetPubkeys> source;

  @override
  Future<void> cancel() async {
    unawaited(source.cancel());
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
  _FakeSdk({
    required this.assets,
    required this.auth,
    required this.pubkeys,
    this.statusAddress,
  });

  final String? statusAddress;

  @override
  WithdrawalManager get withdrawals => _FakeWithdrawalManager(statusAddress!);

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

class _FakeWithdrawalManager implements WithdrawalManager {
  _FakeWithdrawalManager(this.address);
  final String address;

  @override
  Future<GaslessAccountStatusResponse> gaslessAccountStatus(
    AssetId assetId,
  ) async => GaslessAccountStatusResponse.parse({
    'mmrpc': '2.0',
    'result': {
      'gasfree_address': address,
      'on_chain_balance': '25',
      'availability': 'available',
      'service_provider': 'TLntW9Z59LYY5KEi9cmwk3PKjQga828ird',
      'active': true,
      'frozen_balance': '0',
      'spendable_balance': '25',
      'transfer_fee': '1',
      'activation_fee': null,
      'max_withdrawable': '24',
    },
  });

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
  _TestCoinAddressesBloc(super.sdk, super.assetId, super.analyticsBloc) {
    _clockBlocs?.add(this);
  }

  void seedReady(CoinAddressesState ready) {
    // This harness seeds the pre-race state; all subsequent behavior is the
    // production event handler.
    // ignore: invalid_use_of_visible_for_testing_member
    emit(ready);
  }
}

List<_TestCoinAddressesBloc>? _clockBlocs;

void _testWithClock(String description, void Function(FakeAsync) body) {
  test(description, () {
    fakeAsync((clock) {
      final blocs = <_TestCoinAddressesBloc>[];
      _clockBlocs = blocs;
      try {
        body(clock);
      } finally {
        for (final bloc in blocs) {
          final auth = bloc.sdk.auth as _ControlledAuth;
          auth.userAtCall = null;
          if (auth._nextUser != null) auth.releaseCurrentUser();
          unawaited(bloc.close());
        }
        clock.flushMicrotasks();
        _clockBlocs = null;
      }
    });
  });
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

  group('address subscription recovery', () {
    for (final hashFirst in [true, false]) {
      _testWithClock(
        'same-session identity ${hashFirst ? 'degradation' : 'enrichment'} keeps address observation live',
        (clock) {
          final asset = Asset.fromJson(_trxConfig(), knownIds: const {});
          final address = _pubkey('Standard');
          // Bound the original bug's loop so it fails instead of starving tests.
          final auth = _ControlledAuth(_user())
            ..pauseAtCall = 25
            ..userAtCall = (call) =>
                _user(pubkeyHash: call.isOdd == hashFirst ? _walletHash : null);
          final pubkeys = _FakePubkeyManager(asset, [address]);
          final bloc = _TestCoinAddressesBloc(
            _FakeSdk(
              assets: _FakeAssetManager(asset),
              auth: auth,
              pubkeys: pubkeys,
            ),
            asset.id.id,
            _RecordingAnalyticsBloc(),
          );
          bloc.add(const CoinAddressesSubscriptionRequested());
          clock.flushMicrotasks();

          expect(bloc.state.status, FormStatus.success);
          expect(bloc.state.addresses, [address]);
          expect(pubkeys.watchCalls, 1);
          expect(auth.currentUserCalls, lessThan(25));
        },
      );
    }

    for (final failure in ['read', 'precache']) {
      _testWithClock(
        'standard asset automatically recovers a transient $failure failure',
        (clock) {
          final asset = Asset.fromJson(_trxConfig(), knownIds: const {});
          final address = _pubkey('Standard');
          final pubkeys = _FakePubkeyManager(asset, [address]);
          if (failure == 'read') {
            pubkeys.readError = StateError('Temporary read failure');
          } else {
            pubkeys.precacheError = StateError('Temporary precache failure');
          }
          final bloc = _TestCoinAddressesBloc(
            _FakeSdk(
              assets: _FakeAssetManager(asset),
              auth: _ControlledAuth(_user()),
              pubkeys: pubkeys,
            ),
            asset.id.id,
            _RecordingAnalyticsBloc(),
          );
          bloc.add(const CoinAddressesSubscriptionRequested());
          clock.flushMicrotasks();
          expect(bloc.state.status, FormStatus.failure);
          expect(pubkeys.watchCalls, 0);

          pubkeys.readError = null;
          pubkeys.precacheError = null;
          clock.elapse(const Duration(seconds: 1));
          clock.flushMicrotasks();
          expect(bloc.state.status, FormStatus.success);
          expect(bloc.state.addresses, [address]);
          expect(pubkeys.watchCalls, 1);
        },
      );
    }

    _testWithClock(
      'hashless identity keeps standard rows but cannot authorize GasFree actions',
      (clock) {
        final asset = _asset();
        final address = _pubkey('Standard');
        final auth = _ControlledAuth(_user(pubkeyHash: null));
        final pubkeys = _FakePubkeyManager(asset, [address]);
        final bloc = _TestCoinAddressesBloc(
          _FakeSdk(
            assets: _FakeAssetManager(asset),
            auth: auth,
            pubkeys: pubkeys,
            statusAddress: address.gasfreeAddress,
          ),
          asset.id.id,
          _RecordingAnalyticsBloc(),
        );
        bloc.add(const CoinAddressesSubscriptionRequested());
        clock.flushMicrotasks();
        expect(bloc.state.status, FormStatus.success);
        expect(bloc.state.addresses, [address]);
        expect(
          bloc.state.gaslessReceiveStatus,
          isNot(GaslessReceiveStatus.ready),
        );
        expect(bloc.state.verifiedGasfreeAddress, isNull);
        expect(bloc.state.gaslessReceiveWalletPubkeyHash, isNull);
        expect(
          bloc.revalidateGaslessReceiveForAction(
            custodyAddress: address.gasfreeAddress!,
            walletEpoch: '',
          ),
          isFalse,
        );
        clock.flushMicrotasks();
      },
    );

    _testWithClock('hash loss at final check cannot grant GasFree Ready', (
      clock,
    ) {
      final asset = _asset();
      final address = _pubkey('Standard');
      // initial identity, post-address identity, create restriction identity,
      // pre-status identity, final identity.
      final auth = _ControlledAuth(_user())
        ..userAtCall = (call) =>
            _user(pubkeyHash: call >= 5 ? null : _walletHash);
      final pubkeys = _FakePubkeyManager(asset, [address]);
      final bloc = _TestCoinAddressesBloc(
        _FakeSdk(
          assets: _FakeAssetManager(asset),
          auth: auth,
          pubkeys: pubkeys,
          statusAddress: address.gasfreeAddress,
        ),
        asset.id.id,
        _RecordingAnalyticsBloc(),
      );
      final emissions = <CoinAddressesState>[];
      bloc.stream.listen(emissions.add);
      bloc.add(const CoinAddressesSubscriptionRequested());
      clock.flushMicrotasks();
      expect(
        emissions.map((state) => state.gaslessReceiveStatus),
        isNot(contains(GaslessReceiveStatus.ready)),
      );
      expect(bloc.state.verifiedGasfreeAddress, isNull);
      expect(bloc.state.gaslessReceiveWalletPubkeyHash, isNull);
    });

    _testWithClock(
      'repeated wallet mismatch backs off without rendering crossed addresses',
      (clock) {
        final asset = Asset.fromJson(_trxConfig(), knownIds: const {});
        final auth = _ControlledAuth(_user())
          ..pauseAtCall = 25
          ..userAtCall = (call) =>
              _user(pubkeyHash: call.isOdd ? _walletHash : 'other-wallet-hash');
        final pubkeys = _FakePubkeyManager(asset, [_pubkey('Previous')]);
        final bloc = _TestCoinAddressesBloc(
          _FakeSdk(
            assets: _FakeAssetManager(asset),
            auth: auth,
            pubkeys: pubkeys,
          ),
          asset.id.id,
          _RecordingAnalyticsBloc(),
        );
        bloc.add(const CoinAddressesSubscriptionRequested());
        clock.flushMicrotasks();
        expect(pubkeys.readCalls, 1);
        expect(bloc.state.status, FormStatus.failure);
        expect(bloc.state.addresses, isEmpty);
        clock.elapse(const Duration(milliseconds: 999));
        clock.flushMicrotasks();
        expect(pubkeys.readCalls, 1);
        clock.elapse(const Duration(milliseconds: 1));
        clock.flushMicrotasks();
        expect(pubkeys.readCalls, 2);
        clock.elapse(const Duration(seconds: 1));
        clock.flushMicrotasks();
        expect(pubkeys.readCalls, 2);
        clock.elapse(const Duration(seconds: 1));
        clock.flushMicrotasks();
        expect(pubkeys.readCalls, 3);
        expect(pubkeys.watchCalls, 0);
      },
    );

    _testWithClock(
      'background cancels address recovery and resume restores it',
      (clock) {
        final asset = Asset.fromJson(_trxConfig(), knownIds: const {});
        final pubkeys = _FakePubkeyManager(asset, [_pubkey('Standard')])
          ..readError = StateError('Temporary read failure');
        final bloc = _TestCoinAddressesBloc(
          _FakeSdk(
            assets: _FakeAssetManager(asset),
            auth: _ControlledAuth(_user()),
            pubkeys: pubkeys,
          ),
          asset.id.id,
          _RecordingAnalyticsBloc(),
        );
        bloc.add(const CoinAddressesSubscriptionRequested());
        clock.flushMicrotasks();
        bloc.add(const CoinAddressesGaslessReceiveVisibilityChanged(false));
        clock.flushMicrotasks();
        pubkeys.readError = null;
        clock.elapse(const Duration(minutes: 2));
        clock.flushMicrotasks();
        expect(pubkeys.readCalls, 1);
        bloc.add(const CoinAddressesGaslessReceiveVisibilityChanged(true));
        clock.flushMicrotasks();
        expect(bloc.state.status, FormStatus.success);
        expect(pubkeys.watchCalls, 1);
      },
    );

    for (final startsEnriched in [true, false]) {
      _testWithClock(
        'a ${startsEnriched ? 'retained' : 'newly enriched'} hash rejects a later same-name wallet switch',
        (clock) {
          final asset = Asset.fromJson(_trxConfig(), knownIds: const {});
          final auth = _ControlledAuth(_user())
            ..userAtCall = (call) => _user(
              pubkeyHash: switch (call) {
                1 => startsEnriched ? _walletHash : null,
                2 => null,
                3 || 4 => startsEnriched ? 'wallet-b-hash' : _walletHash,
                _ => 'wallet-b-hash',
              },
            );
          final pubkeys = _FakePubkeyManager(asset, [_pubkey('Previous')]);
          final bloc = _TestCoinAddressesBloc(
            _FakeSdk(
              assets: _FakeAssetManager(asset),
              auth: auth,
              pubkeys: pubkeys,
            ),
            asset.id.id,
            _RecordingAnalyticsBloc(),
          );
          bloc.add(const CoinAddressesSubscriptionRequested());
          clock.flushMicrotasks();
          expect(bloc.state.status, FormStatus.failure);
          expect(bloc.state.addresses, isEmpty);
          expect(pubkeys.watchCalls, 0);
          expect(pubkeys.readCalls, 2);
        },
      );
    }

    _testWithClock(
      'persistent failures cap retry delay and successful recovery resets it',
      (clock) {
        final asset = Asset.fromJson(_trxConfig(), knownIds: const {});
        final pubkeys = _FakePubkeyManager(asset, [_pubkey('Standard')])
          ..readError = StateError('Temporary read failure');
        final bloc = _TestCoinAddressesBloc(
          _FakeSdk(
            assets: _FakeAssetManager(asset),
            auth: _ControlledAuth(_user()),
            pubkeys: pubkeys,
          ),
          asset.id.id,
          _RecordingAnalyticsBloc(),
        );
        bloc.add(const CoinAddressesSubscriptionRequested());
        clock.flushMicrotasks();
        var expectedReads = 1;
        for (final seconds in [1, 2, 4, 8, 16, 30, 30]) {
          clock.elapse(Duration(seconds: seconds));
          clock.flushMicrotasks();
          expect(pubkeys.readCalls, ++expectedReads);
        }
        pubkeys.readError = null;
        clock.elapse(const Duration(seconds: 30));
        clock.flushMicrotasks();
        expect(bloc.state.status, FormStatus.success);
        expect(pubkeys.watchCalls, 1);
        clock.elapse(const Duration(seconds: 30));
        clock.flushMicrotasks();
        pubkeys.updates!.addError(StateError('Stream disconnected'));
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 1));
        clock.flushMicrotasks();
        expect(bloc.state.status, FormStatus.success);
        expect(pubkeys.watchCalls, 2);
      },
    );

    _testWithClock('a watcher that fails in background reconnects on resume', (
      clock,
    ) {
      final asset = Asset.fromJson(_trxConfig(), knownIds: const {});
      final pubkeys = _FakePubkeyManager(asset, [_pubkey('Standard')]);
      final bloc = _TestCoinAddressesBloc(
        _FakeSdk(
          assets: _FakeAssetManager(asset),
          auth: _ControlledAuth(_user()),
          pubkeys: pubkeys,
        ),
        asset.id.id,
        _RecordingAnalyticsBloc(),
      );
      bloc.add(const CoinAddressesSubscriptionRequested());
      clock.flushMicrotasks();
      bloc.add(const CoinAddressesGaslessReceiveVisibilityChanged(false));
      clock.flushMicrotasks();
      pubkeys.updates!.addError(
        StateError('Activation failed while backgrounded'),
      );
      clock.flushMicrotasks();
      clock.elapse(const Duration(minutes: 1));
      clock.flushMicrotasks();
      expect(pubkeys.watchCalls, 1);
      expect(pubkeys.watchCancellations, 1);
      bloc.add(const CoinAddressesGaslessReceiveVisibilityChanged(true));
      clock.flushMicrotasks();
      expect(pubkeys.watchCalls, 2);
      expect(bloc.state.status, FormStatus.success);
    });

    _testWithClock(
      'repeated watcher startup errors keep exponential backoff after cached emissions',
      (clock) {
        final asset = Asset.fromJson(_trxConfig(), knownIds: const {});
        final pubkeys = _FakePubkeyManager(asset, [_pubkey('Standard')]);
        final bloc = _TestCoinAddressesBloc(
          _FakeSdk(
            assets: _FakeAssetManager(asset),
            auth: _ControlledAuth(_user()),
            pubkeys: pubkeys,
          ),
          asset.id.id,
          _RecordingAnalyticsBloc(),
        );
        bloc.add(const CoinAddressesSubscriptionRequested());
        clock.flushMicrotasks();
        var watches = 1;
        for (final seconds in [1, 2, 4, 8, 16, 30, 30]) {
          pubkeys.updates!.add(
            AssetPubkeys(
              assetId: asset.id,
              keys: pubkeys.keys,
              availableAddressesCount: 1,
              syncStatus: SyncStatusEnum.success,
            ),
          );
          clock.flushMicrotasks();
          pubkeys.updates!.addError(StateError('Live watcher startup failed'));
          clock.flushMicrotasks();
          clock.elapse(Duration(milliseconds: seconds * 1000 - 1));
          clock.flushMicrotasks();
          expect(pubkeys.watchCalls, watches);
          clock.elapse(const Duration(milliseconds: 1));
          clock.flushMicrotasks();
          expect(pubkeys.watchCalls, ++watches);
        }
      },
    );

    _testWithClock('a recovered live update cancels a pending address reload', (
      clock,
    ) {
      final asset = Asset.fromJson(_trxConfig(), knownIds: const {});
      final pubkeys = _FakePubkeyManager(asset, [_pubkey('Standard')]);
      final bloc = _TestCoinAddressesBloc(
        _FakeSdk(
          assets: _FakeAssetManager(asset),
          auth: _ControlledAuth(_user()),
          pubkeys: pubkeys,
        ),
        asset.id.id,
        _RecordingAnalyticsBloc(),
      );
      bloc.add(const CoinAddressesSubscriptionRequested());
      clock.flushMicrotasks();
      final update = AssetPubkeys(
        assetId: asset.id,
        keys: pubkeys.keys,
        availableAddressesCount: 1,
        syncStatus: SyncStatusEnum.success,
      );
      pubkeys.readError = StateError('Transient read error');
      pubkeys.updates!.add(update);
      clock.flushMicrotasks();
      expect(bloc.state.status, FormStatus.failure);
      pubkeys.readError = null;
      pubkeys.updates!.add(update);
      clock.flushMicrotasks();
      expect(bloc.state.status, FormStatus.success);
      clock.elapse(const Duration(seconds: 1));
      clock.flushMicrotasks();
      expect(pubkeys.watchCalls, 1);
      expect(pubkeys.watchCancellations, 0);
    });

    _testWithClock(
      'an obsolete mismatched read cannot schedule retry after backgrounding',
      (clock) {
        final asset = Asset.fromJson(_trxConfig(), knownIds: const {});
        final auth = _ControlledAuth(_user())..pauseAtCall = 2;
        final pubkeys = _FakePubkeyManager(asset, [_pubkey('Previous')]);
        final bloc = _TestCoinAddressesBloc(
          _FakeSdk(
            assets: _FakeAssetManager(asset),
            auth: auth,
            pubkeys: pubkeys,
          ),
          asset.id.id,
          _RecordingAnalyticsBloc(),
        );
        bloc.add(const CoinAddressesSubscriptionRequested());
        clock.flushMicrotasks();
        bloc.add(const CoinAddressesGaslessReceiveVisibilityChanged(false));
        clock.flushMicrotasks();
        auth.setUser(_user(pubkeyHash: 'wallet-b-hash'));
        auth.releaseCurrentUser();
        clock.flushMicrotasks();
        clock.elapse(const Duration(minutes: 2));
        clock.flushMicrotasks();
        expect(pubkeys.readCalls, 1);
        expect(pubkeys.watchCalls, 0);
        expect(bloc.state.addresses, isEmpty);
      },
    );

    _testWithClock(
      'old subscription events cannot invalidate a replacement watcher',
      (clock) {
        final asset = Asset.fromJson(_trxConfig(), knownIds: const {});
        final address = _pubkey('Standard');
        final pubkeys = _FakePubkeyManager(asset, [address]);
        final bloc = _TestCoinAddressesBloc(
          _FakeSdk(
            assets: _FakeAssetManager(asset),
            auth: _ControlledAuth(_user()),
            pubkeys: pubkeys,
          ),
          asset.id.id,
          _RecordingAnalyticsBloc(),
        );
        bloc.add(const CoinAddressesSubscriptionRequested());
        clock.flushMicrotasks();
        bloc.add(const CoinAddressesSubscriptionRequested());
        clock.flushMicrotasks();
        expect(pubkeys.watchCalls, 2);
        final readCalls = pubkeys.readCalls;
        bloc.add(
          CoinAddressesPubkeysUpdated([
            _pubkey('Previous'),
          ], subscriptionGeneration: 2),
        );
        bloc.add(
          const CoinAddressesPubkeysSubscriptionFailed(
            'Old stream failed',
            subscriptionGeneration: 2,
          ),
        );
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 31));
        clock.flushMicrotasks();
        expect(bloc.state.status, FormStatus.success);
        expect(bloc.state.addresses, [address]);
        expect(pubkeys.readCalls, readCalls);
        expect(pubkeys.watchCalls, 2);
      },
    );

    _testWithClock('close cancels address recovery', (clock) {
      final asset = Asset.fromJson(_trxConfig(), knownIds: const {});
      final pubkeys = _FakePubkeyManager(asset, [_pubkey('Standard')])
        ..readError = StateError('Temporary read failure');
      final bloc = _TestCoinAddressesBloc(
        _FakeSdk(
          assets: _FakeAssetManager(asset),
          auth: _ControlledAuth(_user()),
          pubkeys: pubkeys,
        ),
        asset.id.id,
        _RecordingAnalyticsBloc(),
      );
      bloc.add(const CoinAddressesSubscriptionRequested());
      clock.flushMicrotasks();
      unawaited(bloc.close());
      clock.flushMicrotasks();
      pubkeys.readError = null;
      clock.elapse(const Duration(minutes: 2));
      clock.flushMicrotasks();
      expect(pubkeys.readCalls, 1);
    });

    for (final termination in ['error', 'completion']) {
      _testWithClock('standard watcher $termination reconnects automatically', (
        clock,
      ) {
        final asset = Asset.fromJson(_trxConfig(), knownIds: const {});
        final pubkeys = _FakePubkeyManager(asset, [_pubkey('Standard')]);
        final bloc = _TestCoinAddressesBloc(
          _FakeSdk(
            assets: _FakeAssetManager(asset),
            auth: _ControlledAuth(_user()),
            pubkeys: pubkeys,
          ),
          asset.id.id,
          _RecordingAnalyticsBloc(),
        );
        bloc.add(const CoinAddressesSubscriptionRequested());
        clock.flushMicrotasks();
        expect(pubkeys.watchCalls, 1);
        if (termination == 'error') {
          pubkeys.updates!.addError(StateError('Stream disconnected'));
        } else {
          unawaited(pubkeys.updates!.close());
        }
        clock.flushMicrotasks();
        expect(bloc.state.status, FormStatus.failure);
        clock.elapse(const Duration(seconds: 1));
        clock.flushMicrotasks();
        expect(bloc.state.status, FormStatus.success);
        expect(pubkeys.watchCalls, 2);
      });
    }
  });

  test(
    'pubkey read failure ends loading and a later update recovers',
    () async {
      final asset = _asset();
      final address = _pubkey('Original');
      final pubkeys = _FakePubkeyManager(asset, [address])
        ..readError = StateError('Address read failed');
      final bloc = _TestCoinAddressesBloc(
        _FakeSdk(
          assets: _FakeAssetManager(asset),
          auth: _ControlledAuth(_user()),
          pubkeys: pubkeys,
        ),
        asset.id.id,
        _RecordingAnalyticsBloc(),
      );
      addTearDown(bloc.close);
      bloc.seedReady(
        CoinAddressesState(
          status: FormStatus.success,
          addresses: [address],
          gaslessReceiveStatus: GaslessReceiveStatus.ready,
          verifiedGasfreeAddress: address.gasfreeAddress,
          gaslessReceiveWalletPubkeyHash: _walletHash,
        ),
      );

      final failedFuture = bloc.stream
          .firstWhere((state) => state.errorMessage != null)
          .timeout(const Duration(seconds: 1));
      bloc.add(CoinAddressesPubkeysUpdated([address]));
      final failed = await failedFuture;

      // The panel renders its error only for failure. Leaving submitting here
      // would show an endless spinner after revoking the stale addresses.
      expect(failed.status, FormStatus.failure);
      expect(failed.addresses, isEmpty);
      expect(failed.verifiedGasfreeAddress, isNull);

      pubkeys.readError = null;
      final recoveredFuture = bloc.stream
          .firstWhere((state) => state.status == FormStatus.success)
          .timeout(const Duration(seconds: 1));
      bloc.add(CoinAddressesPubkeysUpdated([address]));
      final recovered = await recoveredFuture;
      expect(recovered.addresses, [address]);
      expect(recovered.errorMessage, isNull);
    },
  );

  test(
    'resume completes an interrupted initial address subscription',
    () async {
      final asset = _asset();
      final address = _pubkey('Original');
      final auth = _ControlledAuth(_user())..pauseNextCurrentUser();
      final pubkeys = _FakePubkeyManager(asset, [address]);
      final bloc = _TestCoinAddressesBloc(
        _FakeSdk(
          assets: _FakeAssetManager(asset),
          auth: auth,
          pubkeys: pubkeys,
        ),
        asset.id.id,
        _RecordingAnalyticsBloc(),
      );
      addTearDown(bloc.close);

      final loading = bloc.stream.first.timeout(const Duration(seconds: 1));
      bloc.add(const CoinAddressesSubscriptionRequested());
      expect((await loading).status, FormStatus.submitting);
      bloc.add(const CoinAddressesGaslessReceiveVisibilityChanged(false));
      await Future<void>.delayed(Duration.zero);
      auth.releaseCurrentUser();
      await Future<void>.delayed(Duration.zero);
      expect(pubkeys.watchStarted.isCompleted, isFalse);

      bloc.add(const CoinAddressesGaslessReceiveVisibilityChanged(true));
      await pubkeys.watchStarted.future.timeout(const Duration(seconds: 1));
      expect(bloc.state.status, FormStatus.success);
      expect(bloc.state.addresses, [address]);
      expect(bloc.state.errorMessage, isNull);
    },
  );

  test('background revocation survives a pending final wallet check', () async {
    final asset = _asset();
    final address = _pubkey('Original');
    // The refresh reads identity before/after pubkeys, then once more before
    // committing its resolved status. Pause that final asynchronous check.
    final auth = _ControlledAuth(_user());
    final pubkeys = _FakePubkeyManager(asset, [address]);
    final bloc = _TestCoinAddressesBloc(
      _FakeSdk(assets: _FakeAssetManager(asset), auth: auth, pubkeys: pubkeys),
      asset.id.id,
      _RecordingAnalyticsBloc(),
    );
    addTearDown(bloc.close);
    bloc.add(const CoinAddressesSubscriptionRequested());
    await pubkeys.watchStarted.future.timeout(const Duration(seconds: 1));
    auth.currentUserCalls = 0;
    auth.pauseAtCall = 3;
    bloc.seedReady(
      CoinAddressesState(
        status: FormStatus.success,
        addresses: [address],
        gaslessReceiveStatus: GaslessReceiveStatus.ready,
        verifiedGasfreeAddress: address.gasfreeAddress,
        gaslessReceiveWalletPubkeyHash: _walletHash,
        gaslessAccountStatusObservedAt: DateTime.now().toUtc(),
      ),
    );
    bloc.add(const CoinAddressesGaslessReceiveRefreshRequested());
    await auth.pausedRead.future.timeout(const Duration(seconds: 1));
    final backgrounded = bloc.stream
        .firstWhere(
          (state) => state.gaslessReceiveStatus == GaslessReceiveStatus.stale,
        )
        .timeout(const Duration(seconds: 1));
    bloc.add(const CoinAddressesGaslessReceiveVisibilityChanged(false));
    await backgrounded;

    auth.releaseCurrentUser();
    await Future<void>.delayed(Duration.zero);
    expect(bloc.state.gaslessReceiveStatus, GaslessReceiveStatus.stale);
    expect(
      bloc.state.gaslessReceiveReason,
      GaslessReceiveReasonCode.appBackgrounded,
    );
    expect(bloc.state.verifiedGasfreeAddress, isNull);
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

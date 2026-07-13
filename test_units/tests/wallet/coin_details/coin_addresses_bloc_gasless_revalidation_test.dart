import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_sdk/src/assets/asset_manager.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_bloc.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_event.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_state.dart';
import 'package:web_dex/shared/gasless/tron_gasless_receive_gate.dart';

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

KdfUser _user() => KdfUser(
  walletId: WalletId.withPubkeyHash(
    'wallet-a',
    const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
    _walletHash,
  ),
  isBip39Seed: true,
);

class _ControlledAuth implements KomodoDefiLocalAuth {
  _ControlledAuth(this.user);

  final KdfUser user;
  Completer<KdfUser?>? _nextUser;
  int currentUserCalls = 0;

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
  _FakePubkeyManager(this.asset, this.keys);

  final Asset asset;
  List<PubkeyInfo> keys;

  @override
  Future<AssetPubkeys> getPubkeys(Asset asset) async => AssetPubkeys(
    assetId: this.asset.id,
    keys: keys,
    availableAddressesCount: keys.length,
    syncStatus: SyncStatusEnum.success,
  );

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

class _NoopAnalyticsBloc implements AnalyticsBloc {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DisabledReceiveGate implements TronGaslessReceiveGate {
  @override
  Future<TronGaslessReceiveGateDecision> evaluate() async =>
      const TronGaslessReceiveGateDecision(
        outcome: TronGaslessReceiveGateOutcome.disabled,
        reason: GaslessReceiveReasonCode.remoteDisabled,
      );

  @override
  void dispose() {}
}

class _TestCoinAddressesBloc extends CoinAddressesBloc {
  _TestCoinAddressesBloc(
    super.sdk,
    super.assetId,
    super.analyticsBloc, {
    required super.gaslessReceiveGate,
  });

  void seedReady(CoinAddressesState ready) {
    // This harness seeds the pre-race state; all subsequent behavior is the
    // production event handler.
    // ignore: invalid_use_of_visible_for_testing_member
    emit(ready);
  }
}

void testCoinAddressesBlocGaslessRevalidation() {
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
        final bloc = _TestCoinAddressesBloc(
          _FakeSdk(
            assets: _FakeAssetManager(asset),
            auth: auth,
            pubkeys: pubkeys,
          ),
          asset.id.id,
          _NoopAnalyticsBloc(),
          gaslessReceiveGate: _DisabledReceiveGate(),
        );
        addTearDown(bloc.close);
        bloc.seedReady(
          CoinAddressesState(
            addresses: [original],
            gaslessReceiveStatus: GaslessReceiveStatus.ready,
            gaslessReceiveConfigExpiresAt: DateTime.now().toUtc().add(
              const Duration(minutes: 1),
            ),
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
        expect(checking.addresses, testCase.$2);
        expect(checking.gaslessReceiveStatus, GaslessReceiveStatus.checking);
        expect(checking.verifiedGasfreeAddress, isNull);
        expect(checking.gaslessReceiveWalletPubkeyHash, isNull);

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
}

void main() {
  testCoinAddressesBlocGaslessRevalidation();
}

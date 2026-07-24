import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_sdk/src/assets/asset_manager.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_sdk/src/withdrawals/withdrawal_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_bloc.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_event.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_state.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/gasless_consolidation_wizard.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/withdraw_form.dart';

const _walletHash = 'wallet-a-pubkey-hash';
const _custodyAddress = 'TGasFreeCustodyAddress000000000001';
const _standardAddress = 'TStandardSourceAddress00000000001';
const _providerAddress = 'TLntW9Z59LYY5KEi9cmwk3PKjQga828ird';

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
  'coin': 'USDT-TRC20',
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

(Asset, Asset) _assets() {
  final parent = Asset.fromJson(_trxConfig(), knownIds: const {});
  final token = Asset.fromJson(_trc20Config(), knownIds: {parent.id});
  return (parent, token);
}

PubkeyInfo _pubkey({
  required String coin,
  required Decimal balance,
  String? gasfreeAddress,
}) => PubkeyInfo(
  address: _standardAddress,
  derivationPath: "m/44'/195'/0'/0/0",
  chain: 'external',
  balance: BalanceInfo(
    total: balance,
    spendable: balance,
    unspendable: Decimal.zero,
  ),
  coinTicker: coin,
  gasfreeAddress: gasfreeAddress,
);

AssetPubkeys _assetPubkeys(Asset asset, PubkeyInfo key) => AssetPubkeys(
  assetId: asset.id,
  keys: [key],
  availableAddressesCount: 1,
  syncStatus: SyncStatusEnum.success,
);

KdfUser _user() => KdfUser(
  walletId: WalletId.withPubkeyHash(
    'wallet-a',
    const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
    _walletHash,
  ),
  isBip39Seed: true,
);

GaslessAccountStatusResponse _accountStatus({
  required GaslessAccountAvailability availability,
}) => GaslessAccountStatusResponse.parse({
  'mmrpc': '2.0',
  'result': {
    'gasfree_address': _custodyAddress,
    'on_chain_balance': '5',
    'availability': switch (availability) {
      GaslessAccountAvailability.available => 'available',
      GaslessAccountAvailability.pendingTransfer => 'pending_transfer',
      GaslessAccountAvailability.tokenUnsupported => 'token_unsupported',
      GaslessAccountAvailability.providerUnreachable => 'provider_unreachable',
    },
    if (availability != GaslessAccountAvailability.providerUnreachable)
      'service_provider': _providerAddress,
    if (availability == GaslessAccountAvailability.available ||
        availability == GaslessAccountAvailability.pendingTransfer) ...{
      'active': true,
      'frozen_balance': '0',
      'spendable_balance': '5',
      'transfer_fee': '1',
    },
    if (availability == GaslessAccountAvailability.available)
      'max_withdrawable': '4',
  },
});

CoinAddressesState _readyState({
  required DateTime observedAt,
  GaslessAccountAvailability availability =
      GaslessAccountAvailability.available,
}) => CoinAddressesState(
  addresses: [
    _pubkey(
      coin: 'USDT-TRC20',
      balance: Decimal.fromInt(5),
      gasfreeAddress: _custodyAddress,
    ),
  ],
  gaslessReceiveStatus: availability == GaslessAccountAvailability.available
      ? GaslessReceiveStatus.ready
      : GaslessReceiveStatus.temporarilyUnavailable,
  gaslessReceiveConfigExpiresAt: DateTime.now().toUtc().add(
    const Duration(hours: 1),
  ),
  verifiedGasfreeAddress: _custodyAddress,
  gaslessReceiveWalletPubkeyHash: _walletHash,
  gaslessAccountStatus: _accountStatus(availability: availability),
  gaslessAccountStatusObservedAt: observedAt,
);

String? _testAddressVerifier(
  KomodoDefiSdk sdk,
  Asset asset,
  CoinAddressesState state, {
  required WalletType? walletType,
  required String? currentWalletPubkeyHash,
}) {
  final status = state.gaslessAccountStatus;
  if (walletType != WalletType.hdwallet ||
      currentWalletPubkeyHash != _walletHash ||
      state.gaslessReceiveWalletPubkeyHash != currentWalletPubkeyHash ||
      state.gaslessReceiveStatus != GaslessReceiveStatus.ready ||
      state.verifiedGasfreeAddress != _custodyAddress ||
      status?.availability != GaslessAccountAvailability.available ||
      status?.gasfreeAddress != _custodyAddress ||
      status?.serviceProvider != _providerAddress) {
    return null;
  }
  return _custodyAddress;
}

class _FakeCoinAddressesBloc extends Cubit<CoinAddressesState>
    implements CoinAddressesBloc {
  _FakeCoinAddressesBloc(super.initialState);

  final List<CoinAddressesEvent> events = [];

  void update(CoinAddressesState state) => emit(state);

  @override
  void add(CoinAddressesEvent event) {
    events.add(event);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthBloc extends Cubit<AuthBlocState> implements AuthBloc {
  _FakeAuthBloc() : super(AuthBlocState.loggedIn(_user()));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAssetManager implements AssetManager {
  _FakeAssetManager(Iterable<Asset> assets)
    : _assets = {for (final asset in assets) asset.id: asset};

  final Map<AssetId, Asset> _assets;

  @override
  Asset? fromId(AssetId id) => _assets[id];

  @override
  Set<Asset> findAssetsByConfigId(String ticker) =>
      _assets.values.where((asset) => asset.id.id == ticker).toSet();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePubkeyManager implements PubkeyManager {
  _FakePubkeyManager(this._pubkeys);

  final Map<AssetId, AssetPubkeys> _pubkeys;

  @override
  AssetPubkeys? lastKnown(AssetId assetId) => _pubkeys[assetId];

  @override
  Future<AssetPubkeys> getPubkeys(Asset asset) async => _pubkeys[asset.id]!;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAddressOperations implements AddressOperations {
  @override
  Future<AddressValidation> validateAddress({
    required Asset asset,
    required String address,
  }) async => AddressValidation(isValid: true, address: address, asset: asset);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWithdrawalManager implements WithdrawalManager {
  int previewCalls = 0;

  @override
  Future<WithdrawalPreview> previewWithdrawal(
    WithdrawParameters parameters,
  ) async {
    previewCalls += 1;
    return WithdrawResult(
      txHex: 'signed-consolidation-preview-$previewCalls',
      txHash: 'consolidation-preview-$previewCalls',
      from: const [_standardAddress],
      to: [parameters.toAddress],
      balanceChanges: BalanceChanges(
        netChange: Decimal.fromInt(-5),
        receivedByMe: Decimal.zero,
        spentByMe: Decimal.fromInt(5),
        totalAmount: Decimal.fromInt(5),
      ),
      blockHeight: 1,
      timestamp:
          DateTime.now().millisecondsSinceEpoch ~/
          Duration.millisecondsPerSecond,
      fee: FeeInfo.tron(
        coin: 'TRX',
        bandwidthUsed: 1,
        energyUsed: 1,
        bandwidthFee: Decimal.zero,
        energyFee: Decimal.parse('0.1'),
        totalFeeAmount: Decimal.parse('0.1'),
      ),
      coin: parameters.asset,
    );
  }

  @override
  Future<WithdrawalFeeOptions?> getFeeOptions(String assetId) async => null;

  @override
  Future<List<PendingGaslessTransfer>> listPendingGaslessTransfers() async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSdk implements KomodoDefiSdk {
  _FakeSdk({
    required this.assets,
    required this.pubkeys,
    required this.withdrawals,
  });

  @override
  final AssetManager assets;

  @override
  final PubkeyManager pubkeys;

  @override
  final WithdrawalManager withdrawals;

  @override
  final AddressOperations addresses = _FakeAddressOperations();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMm2Api implements Mm2Api {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void testGaslessConsolidationWizardLifecycle() {
  testWidgets(
    'resume disposes the active form and waits for a fresh typed status',
    (tester) async {
      final (parent, token) = _assets();
      final withdrawals = _FakeWithdrawalManager();
      final sdk = _FakeSdk(
        assets: _FakeAssetManager([parent, token]),
        pubkeys: _FakePubkeyManager({
          token.id: _assetPubkeys(
            token,
            _pubkey(
              coin: token.id.id,
              balance: Decimal.fromInt(5),
              gasfreeAddress: _custodyAddress,
            ),
          ),
          parent.id: _assetPubkeys(
            parent,
            _pubkey(coin: parent.id.id, balance: Decimal.one),
          ),
        }),
        withdrawals: withdrawals,
      );
      final addressesBloc = _FakeCoinAddressesBloc(
        _readyState(observedAt: DateTime.now().toUtc()),
      );
      final authBloc = _FakeAuthBloc();
      addTearDown(addressesBloc.close);
      addTearDown(authBloc.close);

      await tester.pumpWidget(
        MultiRepositoryProvider(
          providers: [
            RepositoryProvider<KomodoDefiSdk>.value(value: sdk),
            RepositoryProvider<Mm2Api>.value(value: _FakeMm2Api()),
          ],
          child: MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: authBloc),
              BlocProvider<CoinAddressesBloc>.value(value: addressesBloc),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: GaslessConsolidationWizard(
                  asset: token,
                  custodyAddress: _custodyAddress,
                  addressVerifier: _testAddressVerifier,
                  onDone: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final moveSource = find.byKey(
        const Key('gasless-consolidation-move-$_standardAddress'),
      );
      expect(moveSource, findsOneWidget);
      expect(withdrawals.previewCalls, 1);

      await tester.tap(moveSource);
      await tester.pump();
      expect(find.byType(WithdrawForm), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();

      expect(find.byType(WithdrawForm), findsNothing);
      expect(
        find.byKey(const Key('gasless-consolidation-gate')),
        findsOneWidget,
      );
      expect(
        addressesBloc.events
            .whereType<CoinAddressesGaslessReceiveVisibilityChanged>()
            .last
            .isForeground,
        isFalse,
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      // The pre-background status is still present in the BLoC, but its
      // observation timestamp predates this resume. No source action or
      // preflight is restored from that stale snapshot.
      expect(moveSource, findsNothing);
      expect(withdrawals.previewCalls, 1);
      expect(
        addressesBloc.events
            .whereType<CoinAddressesGaslessReceiveVisibilityChanged>()
            .last
            .isForeground,
        isTrue,
      );

      // A fresh typed provider failure is also fail-closed.
      addressesBloc.update(
        _readyState(
          observedAt: DateTime.now().toUtc(),
          availability: GaslessAccountAvailability.providerUnreachable,
        ),
      );
      await tester.pump();
      expect(moveSource, findsNothing);
      expect(withdrawals.previewCalls, 1);

      // Only a fresh post-resume `available` status may restart enumeration.
      addressesBloc.update(_readyState(observedAt: DateTime.now().toUtc()));
      await tester.pumpAndSettle();
      expect(moveSource, findsOneWidget);
      expect(withdrawals.previewCalls, 2);
    },
  );
}

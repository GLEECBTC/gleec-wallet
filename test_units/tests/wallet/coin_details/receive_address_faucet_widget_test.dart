import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_cex_market_data/komodo_cex_market_data.dart'
    show QuoteCurrency, Stablecoin;
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart'
    show
        AssetIdFaucetExtension,
        BalanceManager,
        KomodoDefiSdk,
        MarketDataManager;
import 'package:komodo_defi_sdk/src/assets/asset_manager.dart'
    show AssetManager;
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart'
    show PubkeyManager;
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_bloc.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_event.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_state.dart';
import 'package:web_dex/bloc/faucet_button/faucet_button_bloc.dart';
import 'package:web_dex/bloc/faucet_button/faucet_button_event.dart';
import 'package:web_dex/bloc/faucet_button/faucet_button_state.dart';
import 'package:web_dex/bloc/coins_bloc/asset_coin_extension.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/bloc/settings/settings_state.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/model/stored_settings.dart';
import 'package:web_dex/shared/constants.dart'
    show
        isTronGaslessConfigured,
        isTronGaslessReceiveConfigured,
        tronGaslessServiceProvider;
import 'package:web_dex/shared/gasless/tron_gasless_receive_reason.dart';
import 'package:web_dex/shared/utils/extensions/legacy_coin_migration_extensions.dart';
import 'package:web_dex/shared/widgets/copyable_address_dialog.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/coin_addresses.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/coin_details_common_buttons.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/gasless_standard_balance_notice.dart';
import 'package:web_dex/views/wallet/coin_details/faucet/faucet_button.dart';
import 'package:web_dex/views/wallet/common/address_copy_button.dart';

import 'coin_addresses_bloc_gasless_revalidation_test.dart';

class _FakeCoinAddressesBloc extends Cubit<CoinAddressesState>
    implements CoinAddressesBloc {
  _FakeCoinAddressesBloc(
    super.initialState, {
    this.actionRevalidationAllowed = true,
  });

  bool actionRevalidationAllowed;
  int actionRevalidationCalls = 0;
  CoinAddressesEvent? lastEvent;

  void update(CoinAddressesState state) => emit(state);

  @override
  void add(CoinAddressesEvent event) {
    lastEvent = event;
  }

  @override
  bool revalidateGaslessReceiveForAction({
    required String custodyAddress,
    required String walletEpoch,
  }) {
    actionRevalidationCalls++;
    return actionRevalidationAllowed;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthBloc extends Cubit<AuthBlocState> implements AuthBloc {
  _FakeAuthBloc(super.initialState);

  void update(AuthBlocState state) => emit(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBalanceManager implements BalanceManager {
  _FakeBalanceManager(this._balances);

  final Map<AssetId, BalanceInfo> _balances;

  @override
  BalanceInfo? lastKnown(AssetId assetId) => _balances[assetId];

  @override
  Stream<BalanceInfo> watchBalance(
    AssetId assetId, {
    bool activateIfNeeded = true,
  }) async* {
    final balance = _balances[assetId];
    if (balance != null) {
      yield balance;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMarketDataManager implements MarketDataManager {
  @override
  Decimal? priceIfKnown(
    AssetId assetId, {
    DateTime? priceDate,
    QuoteCurrency quoteCurrency = Stablecoin.usdt,
  }) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSdk implements KomodoDefiSdk {
  _FakeSdk({
    required this.balances,
    MarketDataManager? marketData,
    Iterable<Asset> assetValues = const <Asset>[],
    this.boundGaslessReceive = false,
  }) : marketData = marketData ?? _FakeMarketDataManager(),
       assets = _FakeAssetManager(assetValues);

  @override
  final BalanceManager balances;

  @override
  final MarketDataManager marketData;

  @override
  final AssetManager assets;

  final bool boundGaslessReceive;

  @override
  bool canReceiveGasless(Asset asset) => boundGaslessReceive;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAssetManager implements AssetManager {
  _FakeAssetManager(Iterable<Asset> assets) : _assets = assets.toList();

  final List<Asset> _assets;

  @override
  Set<Asset> findAssetsByConfigId(String ticker) =>
      _assets.where((asset) => asset.id.id == ticker).toSet();

  @override
  Asset? fromId(AssetId id) {
    for (final asset in _assets) {
      if (asset.id == id) return asset;
    }
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CachedPubkeyManager implements PubkeyManager {
  const _CachedPubkeyManager({required this.walletId, required this.pubkeys});

  final WalletId walletId;
  final AssetPubkeys pubkeys;

  @override
  AssetPubkeys? lastKnownForWallet(AssetId assetId, WalletId walletId) =>
      assetId == pubkeys.assetId && walletId == this.walletId ? pubkeys : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReceiveSelectorSdk extends _FakeSdk {
  _ReceiveSelectorSdk({
    required super.balances,
    required super.assetValues,
    required super.boundGaslessReceive,
    required this.pubkeys,
  });

  @override
  final PubkeyManager pubkeys;
}

class _FakeSettingsBloc extends Cubit<SettingsState> implements SettingsBloc {
  _FakeSettingsBloc()
    : super(SettingsState.fromStored(StoredSettings.initial()));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFaucetBloc extends Cubit<FaucetState> implements FaucetBloc {
  _FakeFaucetBloc(super.initialState);

  FaucetEvent? lastEvent;

  @override
  void add(FaucetEvent event) {
    lastEvent = event;
    if (event is FaucetRequested) {
      emit(FaucetRequestInProgress(address: event.address));
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PubkeyInfo _address(String value, {BalanceInfo? balance}) {
  return PubkeyInfo(
    address: value,
    derivationPath: "m/44'/141'/0'/0/0",
    chain: 'external',
    balance:
        balance ??
        BalanceInfo(
          total: Decimal.one,
          spendable: Decimal.one,
          unspendable: Decimal.zero,
        ),
    coinTicker: 'KMD',
  );
}

Map<String, dynamic> _utxoConfig() => {
  'coin': 'DOC',
  'type': 'Smart Chain',
  'name': 'Doc',
  'fname': 'Doc',
  'wallet_only': false,
  'mm2': 1,
  'chain_id': 141,
  'decimals': 8,
  'is_testnet': true,
  'required_confirmations': 1,
  'derivation_path': "m/44'/141'/0'",
  'protocol': {'type': 'UTXO'},
};

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

PubkeyInfo _trc20Address({
  required String address,
  required String gasfreeAddress,
  BalanceInfo? balance,
  String? derivationPath = "m/44'/195'/0'/0/0",
  String? chain = 'external',
}) {
  return PubkeyInfo(
    address: address,
    derivationPath: derivationPath,
    chain: chain,
    balance:
        balance ??
        BalanceInfo(
          total: Decimal.zero,
          spendable: Decimal.zero,
          unspendable: Decimal.zero,
        ),
    coinTicker: 'USDT-TRC20',
    gasfreeAddress: gasfreeAddress,
  );
}

BalanceInfo _balanceOf(String amount) => BalanceInfo(
  total: Decimal.parse(amount),
  spendable: Decimal.parse(amount),
  unspendable: Decimal.zero,
);

const _walletAHash = 'wallet-a-pubkey-hash';
const _walletBHash = 'wallet-b-pubkey-hash';

KdfUser _softwareUser(String walletName, String pubkeyHash) => KdfUser(
  walletId: WalletId.withPubkeyHash(
    walletName,
    const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
    pubkeyHash,
  ),
  isBip39Seed: true,
);

GaslessAccountStatusResponse _gaslessAccountStatus(
  String custodyAddress, {
  String availability = 'available',
  String onChainBalance = '120.5',
}) => GaslessAccountStatusResponse.parse({
  'mmrpc': '2.0',
  'result': {
    'gasfree_address': custodyAddress,
    'on_chain_balance': onChainBalance,
    'availability': availability,
    'service_provider': availability == 'provider_unreachable'
        ? null
        : tronGaslessServiceProvider.isEmpty
        ? 'TLntW9Z59LYY5KEi9cmwk3PKjQga828ird'
        : tronGaslessServiceProvider,
    'active': availability == 'available' || availability == 'pending_transfer'
        ? true
        : null,
    'frozen_balance':
        availability == 'available' || availability == 'pending_transfer'
        ? '0'
        : null,
    'spendable_balance':
        availability == 'available' || availability == 'pending_transfer'
        ? onChainBalance
        : null,
    'transfer_fee':
        availability == 'available' || availability == 'pending_transfer'
        ? '1'
        : null,
    'activation_fee': null,
    'max_withdrawable': availability == 'available'
        ? (Decimal.parse(onChainBalance) - Decimal.one).toString()
        : null,
  },
});

Widget _liveGaslessReceiveDialog({
  required Asset asset,
  required PubkeyInfo address,
  CoinAddressesBloc? addressesBloc,
  _FakeAuthBloc? authBloc,
  AddressDisplayVariant? variant,
  TextScaler textScaler = const TextScaler.linear(1),
}) {
  final activeAuthBloc =
      authBloc ??
      _FakeAuthBloc(
        AuthBlocState.loggedIn(_softwareUser('wallet-a', _walletAHash)),
      );
  if (authBloc == null) addTearDown(activeAuthBloc.close);
  final bloc =
      addressesBloc ??
      _FakeCoinAddressesBloc(
        CoinAddressesState(
          addresses: [address],
          gaslessReceiveStatus: GaslessReceiveStatus.ready,
          verifiedGasfreeAddress: address.gasfreeAddress,
          gaslessReceiveWalletPubkeyHash: _walletAHash,
          gaslessAccountStatus: _gaslessAccountStatus(address.gasfreeAddress!),
          gaslessAccountStatusObservedAt: DateTime.now().toUtc(),
        ),
      );
  if (addressesBloc == null) addTearDown(bloc.close);
  final sdk = _FakeSdk(
    balances: _FakeBalanceManager(const {}),
    assetValues: [asset],
    boundGaslessReceive: true,
  );

  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: child!,
    ),
    home: RepositoryProvider<KomodoDefiSdk>.value(
      value: sdk,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>.value(value: activeAuthBloc),
          BlocProvider<CoinAddressesBloc>.value(value: bloc),
        ],
        child: Scaffold(
          body: PubkeyReceiveDialog(
            coin: asset.toCoin(),
            address: address,
            variant: variant,
            gaslessReceiveEnabled: true,
          ),
        ),
      ),
    ),
  );
}

void testReceiveAddressFaucetWidgets() {
  testCoinAddressesBlocGaslessRevalidation();

  group('Receive/address/faucet widgets', () {
    testWidgets('faucet button dispatches request for selected address', (
      tester,
    ) async {
      final bloc = _FakeFaucetBloc(const FaucetInitial());
      addTearDown(bloc.close);
      final address = _address('R-test-address');

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<FaucetBloc>.value(
            value: bloc,
            child: Scaffold(
              body: FaucetButton(coinAbbr: 'KMD', address: address),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(UiPrimaryButton));
      await tester.pump();

      expect(bloc.lastEvent, isA<FaucetRequested>());
      final event = bloc.lastEvent! as FaucetRequested;
      expect(event.coinAbbr, 'KMD');
      expect(event.address, address.address);
    });

    testWidgets('faucet button disabled while request pending', (tester) async {
      final address = _address('R-test-address');
      final bloc = _FakeFaucetBloc(
        FaucetRequestInProgress(address: address.address),
      );
      addTearDown(bloc.close);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<FaucetBloc>.value(
            value: bloc,
            child: Scaffold(
              body: FaucetButton(coinAbbr: 'KMD', address: address),
            ),
          ),
        ),
      );

      final button = tester.widget<UiPrimaryButton>(
        find.byType(UiPrimaryButton),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('legacy TRC20 selector remains Standard-only', (tester) async {
      final parent = Asset.fromJson(_trxConfig(), knownIds: const {});
      final asset = Asset.fromJson(_trc20Config(), knownIds: {parent.id});
      final address = _trc20Address(
        address: 'TRegularReceiveAddress000000000001',
        gasfreeAddress: 'TGasFreeReceiveAddress000000000001',
      );
      final pubkeys = AssetPubkeys(
        assetId: asset.id,
        keys: [address],
        availableAddressesCount: 1,
        syncStatus: SyncStatusEnum.success,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 420,
              child: CopyableAddressDialog(
                address: address,
                asset: asset,
                pubkeys: pubkeys,
                onAddressChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('coin-details-address-field')));
      await tester.pumpAndSettle();

      expect(find.text('TRegul...000001'), findsOneWidget);
      expect(find.text('TGasFr...000001'), findsNothing);
    });

    testWidgets(
      'receive dialog reveals the standard address behind the hatch',
      (tester) async {
        tester.view.physicalSize = const Size(900, 1800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final parent = Asset.fromJson(_trxConfig(), knownIds: const {});
        final asset = Asset.fromJson(_trc20Config(), knownIds: {parent.id});
        final address = PubkeyInfo(
          address: 'TRegularReceiveAddress000000000001',
          derivationPath: "m/44'/195'/0'/0/0",
          chain: 'external',
          // Funded EOA → the stranded-balance line must appear in the hatch.
          balance: BalanceInfo(
            total: Decimal.parse('7'),
            spendable: Decimal.parse('7'),
            unspendable: Decimal.zero,
          ),
          coinTicker: 'USDT-TRC20',
          gasfreeAddress: 'TGasFreeReceiveAddress000000000001',
        );

        await tester.pumpWidget(
          _liveGaslessReceiveDialog(asset: asset, address: address),
        );

        // Custody is the headline address; the EOA is hidden by default.
        expect(find.text('receiveGaslessOnlySendToAddress'), findsOneWidget);
        expect(
          find.byKey(const Key('receive-standard-address-toggle')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('receive-standard-address-row')),
          findsNothing,
        );

        await tester.ensureVisible(
          find.byKey(const Key('receive-standard-address-toggle')),
        );
        await tester.tap(
          find.byKey(const Key('receive-standard-address-toggle')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('receive-standard-address-row')),
          findsOneWidget,
        );
        expect(find.text('receiveStandardAddressCaveat'), findsOneWidget);
        expect(
          find.byKey(const Key('receive-standard-balance-notice')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'in-flight candidate replacement or duplication revokes QR and copy',
      (tester) async {
        final parent = Asset.fromJson(_trxConfig(), knownIds: const {});
        final asset = Asset.fromJson(_trc20Config(), knownIds: {parent.id});
        final address = _trc20Address(
          address: 'TRegularReceiveAddress000000000001',
          gasfreeAddress: 'TGasFreeReceiveAddress000000000001',
        );
        final addressesBloc = _FakeCoinAddressesBloc(
          CoinAddressesState(
            addresses: [address],
            gaslessReceiveStatus: GaslessReceiveStatus.ready,
            verifiedGasfreeAddress: address.gasfreeAddress,
            gaslessReceiveWalletPubkeyHash: _walletAHash,
            gaslessAccountStatus: _gaslessAccountStatus(
              address.gasfreeAddress!,
            ),
            gaslessAccountStatusObservedAt: DateTime.now().toUtc(),
          ),
        );
        addTearDown(addressesBloc.close);

        await tester.pumpWidget(
          _liveGaslessReceiveDialog(
            asset: asset,
            address: address,
            addressesBloc: addressesBloc,
          ),
        );
        expect(find.byType(QrCode), findsOneWidget);
        expect(find.byIcon(Icons.copy_rounded), findsOneWidget);

        final replacement = _trc20Address(
          address: 'TRegularReceiveAddress000000000002',
          gasfreeAddress: 'TGasFreeReceiveAddress000000000002',
        );
        addressesBloc.update(
          CoinAddressesState(
            addresses: [replacement],
            gaslessReceiveStatus: GaslessReceiveStatus.checking,
          ),
        );
        await tester.pump();

        expect(
          find.byKey(const Key('gasless-receive-paused-dialog')),
          findsOneWidget,
        );
        expect(find.byType(QrCode), findsNothing);
        expect(find.byIcon(Icons.copy_rounded), findsNothing);

        final duplicateCandidate = _trc20Address(
          address: 'TRegularReceiveAddress000000000003',
          gasfreeAddress: 'TGasFreeReceiveAddress000000000003',
        );
        addressesBloc.update(
          CoinAddressesState(
            addresses: [replacement, duplicateCandidate],
            gaslessReceiveStatus: GaslessReceiveStatus.checking,
          ),
        );
        await tester.pump();
        expect(find.byType(QrCode), findsNothing);
        expect(find.byIcon(Icons.copy_rounded), findsNothing);

        addressesBloc.update(
          CoinAddressesState(
            addresses: [replacement, duplicateCandidate],
            gaslessReceiveStatus: GaslessReceiveStatus.disabled,
          ),
        );
        await tester.pump();
        expect(
          find.byKey(const Key('gasless-official-recovery-action')),
          findsNothing,
        );
        expect(find.text('gaslessRecoveryBody'), findsNothing);

        addressesBloc.update(
          CoinAddressesState(
            addresses: [replacement, duplicateCandidate],
            gaslessReceiveStatus: GaslessReceiveStatus.unsupported,
            gaslessReceiveReason: GaslessReceiveReasonCode.tokenUnsupported,
            gaslessAccountStatus: _gaslessAccountStatus(
              replacement.gasfreeAddress!,
              availability: 'token_unsupported',
            ),
          ),
        );
        await tester.pump();
        expect(
          find.byKey(const Key('gasless-official-recovery-action')),
          findsOneWidget,
        );
        expect(find.text('gaslessRecoveryBody'), findsOneWidget);

        addressesBloc.update(
          CoinAddressesState(
            addresses: [replacement, duplicateCandidate],
            gaslessReceiveStatus: GaslessReceiveStatus.temporarilyUnavailable,
            gaslessReceiveReason:
                GaslessReceiveReasonCode.providerTemporarilyUnavailable,
          ),
        );
        await tester.pump();
        expect(
          find.byKey(const Key('gasless-official-recovery-action')),
          findsNothing,
        );
        expect(find.text('gaslessRecoveryBody'), findsNothing);

        addressesBloc.update(
          CoinAddressesState(
            addresses: [replacement, duplicateCandidate],
            gaslessReceiveStatus: GaslessReceiveStatus.securityMismatch,
            gaslessReceiveReason:
                GaslessReceiveReasonCode.providerIdentityMismatch,
          ),
        );
        await tester.pump();
        expect(
          find.byKey(const Key('gasless-official-recovery-action')),
          findsNothing,
        );
        expect(find.text('gaslessRecoveryBody'), findsNothing);

        addressesBloc.update(
          CoinAddressesState(
            addresses: [address],
            gaslessReceiveStatus: GaslessReceiveStatus.ready,
            verifiedGasfreeAddress: 'TDifferentCustodyAddress',
            gaslessReceiveWalletPubkeyHash: _walletAHash,
            gaslessAccountStatus: _gaslessAccountStatus(
              address.gasfreeAddress!,
            ),
            gaslessAccountStatusObservedAt: DateTime.now().toUtc(),
          ),
        );
        await tester.pump();
        expect(find.byType(QrCode), findsNothing);
      },
    );

    testWidgets(
      'open GasFree dialog immediately pauses on a same-type wallet switch',
      (tester) async {
        final parent = Asset.fromJson(_trxConfig(), knownIds: const {});
        final asset = Asset.fromJson(_trc20Config(), knownIds: {parent.id});
        final address = _trc20Address(
          address: 'TRegularReceiveAddress000000000001',
          gasfreeAddress: 'TGasFreeReceiveAddress000000000001',
        );
        final authBloc = _FakeAuthBloc(
          AuthBlocState.loggedIn(_softwareUser('wallet-a', _walletAHash)),
        );
        final addressesBloc = _FakeCoinAddressesBloc(
          CoinAddressesState(
            addresses: [address],
            gaslessReceiveStatus: GaslessReceiveStatus.ready,
            verifiedGasfreeAddress: address.gasfreeAddress,
            gaslessReceiveWalletPubkeyHash: _walletAHash,
            gaslessAccountStatus: _gaslessAccountStatus(
              address.gasfreeAddress!,
            ),
            gaslessAccountStatusObservedAt: DateTime.now().toUtc(),
          ),
        );
        addTearDown(authBloc.close);
        addTearDown(addressesBloc.close);

        await tester.pumpWidget(
          _liveGaslessReceiveDialog(
            asset: asset,
            address: address,
            addressesBloc: addressesBloc,
            authBloc: authBloc,
          ),
        );
        expect(find.byType(QrCode), findsOneWidget);

        authBloc.update(
          AuthBlocState.loggedIn(_softwareUser('wallet-b', _walletBHash)),
        );
        await tester.pump();

        expect(
          find.byKey(const Key('gasless-receive-paused-dialog')),
          findsOneWidget,
        );
        expect(find.byType(QrCode), findsNothing);
        expect(find.byIcon(Icons.copy_rounded), findsNothing);
      },
    );

    testWidgets(
      'GasFree dialog copy revalidates at action time and fails closed',
      (tester) async {
        final parent = Asset.fromJson(_trxConfig(), knownIds: const {});
        final asset = Asset.fromJson(_trc20Config(), knownIds: {parent.id});
        final address = _trc20Address(
          address: 'TRegularReceiveAddress000000000001',
          gasfreeAddress: 'TGasFreeReceiveAddress000000000001',
        );
        final addressesBloc = _FakeCoinAddressesBloc(
          CoinAddressesState(
            addresses: [address],
            gaslessReceiveStatus: GaslessReceiveStatus.ready,
            verifiedGasfreeAddress: address.gasfreeAddress,
            gaslessReceiveWalletPubkeyHash: _walletAHash,
            gaslessAccountStatus: _gaslessAccountStatus(
              address.gasfreeAddress!,
            ),
            gaslessAccountStatusObservedAt: DateTime.now().toUtc(),
          ),
          actionRevalidationAllowed: false,
        );
        addTearDown(addressesBloc.close);

        await tester.pumpWidget(
          _liveGaslessReceiveDialog(
            asset: asset,
            address: address,
            addressesBloc: addressesBloc,
          ),
        );

        expect(find.byType(QrCode), findsOneWidget);
        expect(addressesBloc.actionRevalidationCalls, isZero);

        await tester.tap(find.byIcon(Icons.copy_rounded));
        await tester.pump();

        expect(addressesBloc.actionRevalidationCalls, 1);
        expect(
          addressesBloc.lastEvent,
          isA<CoinAddressesGaslessReceiveRefreshRequested>(),
        );
        expect(find.text('receiveGaslessPausedNotice'), findsOneWidget);
      },
    );

    testWidgets('non-gasless receive dialog has no standard-address hatch', (
      tester,
    ) async {
      final parent = Asset.fromJson(_trxConfig(), knownIds: const {});
      final asset = Asset.fromJson(_trc20Config(), knownIds: {parent.id});
      final address = PubkeyInfo(
        address: 'TRegularReceiveAddress000000000001',
        derivationPath: "m/44'/195'/0'/0/0",
        chain: 'external',
        balance: BalanceInfo(
          total: Decimal.zero,
          spendable: Decimal.zero,
          unspendable: Decimal.zero,
        ),
        coinTicker: 'USDT-TRC20',
        // No custody address → plain receive, no hatch.
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PubkeyReceiveDialog(
              coin: asset.toCoin(),
              address: address,
              gaslessReceiveEnabled: true,
            ),
          ),
        ),
      );

      expect(
        find.byKey(const Key('receive-standard-address-toggle')),
        findsNothing,
      );
    });

    testWidgets('create-address is gated off for gasless assets', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CreateButton(
              status: FormStatus.initial,
              createAddressStatus: FormStatus.initial,
              cantCreateNewAddressReasons: null,
              gaslessSingleAddress: true,
            ),
          ),
        ),
      );

      final button = tester.widget<UiPrimaryButton>(
        find.byType(UiPrimaryButton),
      );
      expect(button.onPressed, isNull);
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, 'gaslessSingleAddressTooltip');
    });

    testWidgets('create-address stays enabled for non-gasless assets', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CreateButton(
              status: FormStatus.initial,
              createAddressStatus: FormStatus.initial,
              cantCreateNewAddressReasons: null,
            ),
          ),
        ),
      );

      final button = tester.widget<UiPrimaryButton>(
        find.byType(UiPrimaryButton),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets(
      'GasFree Receive selector keeps the page-scoped address state',
      (tester) async {
        tester.view.physicalSize = const Size(900, 1800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final parent = Asset.fromJson(_trxConfig(), knownIds: const {});
        final asset = Asset.fromJson(_trc20Config(), knownIds: {parent.id});
        final address = _trc20Address(
          address: 'TRegularReceiveAddress000000000001',
          gasfreeAddress: 'TGasFreeReceiveAddress000000000001',
          balance: _balanceOf('7'),
        );
        final user = _softwareUser('wallet-a', _walletAHash);
        final addressesBloc = _FakeCoinAddressesBloc(
          CoinAddressesState(
            addresses: [address],
            gaslessReceiveStatus: GaslessReceiveStatus.ready,
            verifiedGasfreeAddress: address.gasfreeAddress,
            gaslessReceiveWalletPubkeyHash: _walletAHash,
            gaslessAccountStatus: _gaslessAccountStatus(
              address.gasfreeAddress!,
            ),
            gaslessAccountStatusObservedAt: DateTime.now().toUtc(),
          ),
        );
        final authBloc = _FakeAuthBloc(AuthBlocState.loggedIn(user));
        final sdk = _ReceiveSelectorSdk(
          balances: _FakeBalanceManager(const {}),
          assetValues: [parent, asset],
          boundGaslessReceive: true,
          pubkeys: _CachedPubkeyManager(
            walletId: user.walletId,
            pubkeys: AssetPubkeys(
              assetId: asset.id,
              keys: [address],
              availableAddressesCount: 1,
              syncStatus: SyncStatusEnum.success,
            ),
          ),
        );
        addTearDown(addressesBloc.close);
        addTearDown(authBloc.close);

        // Auth and the SDK live above the app Navigator, while the address
        // BLoC intentionally mirrors CoinDetailsInfo's page-local scope.
        await tester.pumpWidget(
          RepositoryProvider<KomodoDefiSdk>.value(
            value: sdk,
            child: BlocProvider<AuthBloc>.value(
              value: authBloc,
              child: MaterialApp(
                home: BlocProvider<CoinAddressesBloc>.value(
                  value: addressesBloc,
                  child: Scaffold(
                    body: ListView(
                      children: [
                        GaslessStandardBalanceNotice(
                          coin: asset.toCoin(),
                          setPageType: (_) {},
                        ),
                        Builder(
                          builder: (context) => CoinDetailsReceiveButton(
                            isMobile: true,
                            coin: asset.toCoin(),
                            selectWidget: (_) {},
                            context: context,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        expect(
          find.byKey(const Key('gasless-consolidate-button')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('coin-details-receive-button')));
        await tester.pumpAndSettle();

        expect(find.byType(SimpleDialog), findsOneWidget);
        expect(
          find.byKey(ValueKey('receive-rail-gasfree-${address.address}')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('receive-rail-standard-${address.address}')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
      skip: !isTronGaslessReceiveConfigured,
    );

    group('stranded-balance recovery notice', () {
      Widget buildNotice({required BalanceInfo? parentTrxBalance}) {
        final parent = Asset.fromJson(_trxConfig(), knownIds: const {});
        final asset = Asset.fromJson(_trc20Config(), knownIds: {parent.id});
        final strandedAddress = PubkeyInfo(
          address: 'TRegularReceiveAddress000000000001',
          derivationPath: "m/44'/195'/0'/0/0",
          chain: 'external',
          balance: BalanceInfo(
            total: Decimal.parse('7'),
            spendable: Decimal.parse('7'),
            unspendable: Decimal.zero,
          ),
          coinTicker: 'USDT-TRC20',
          gasfreeAddress: 'TGasFreeReceiveAddress000000000001',
        );
        final sdk = _FakeSdk(
          balances: _FakeBalanceManager({
            if (parentTrxBalance != null) parent.id: parentTrxBalance,
          }),
          assetValues: [parent, asset],
        );
        final addressesBloc = _FakeCoinAddressesBloc(
          CoinAddressesState(addresses: [strandedAddress]),
        );
        final authBloc = _FakeAuthBloc(
          AuthBlocState.loggedIn(_softwareUser('wallet-a', _walletAHash)),
        );
        addTearDown(addressesBloc.close);
        addTearDown(authBloc.close);

        return MaterialApp(
          home: RepositoryProvider<KomodoDefiSdk>.value(
            value: sdk,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<CoinAddressesBloc>.value(value: addressesBloc),
                BlocProvider<AuthBloc>.value(value: authBloc),
              ],
              child: Scaffold(
                body: GaslessStandardBalanceNotice(
                  coin: asset.toCoin(),
                  setPageType: (_) {},
                ),
              ),
            ),
          ),
        );
      }

      testWidgets('does not infer exact-source TRX from aggregate balance', (
        tester,
      ) async {
        await tester.pumpWidget(
          buildNotice(parentTrxBalance: BalanceInfo.zero()),
        );

        expect(
          find.byKey(const Key('gasless-standard-balance-notice')),
          findsOneWidget,
        );
        // The per-source wizard validates TRX on the exact EOA. An aggregate
        // parent balance cannot prove whether this particular source can pay.
        expect(find.text('gaslessStandardBalanceNoTrxWarning'), findsNothing);
      });

      testWidgets('no warning when TRX is available', (tester) async {
        await tester.pumpWidget(
          buildNotice(
            parentTrxBalance: BalanceInfo(
              total: Decimal.parse('20'),
              spendable: Decimal.parse('20'),
              unspendable: Decimal.zero,
            ),
          ),
        );

        expect(
          find.byKey(const Key('gasless-standard-balance-notice')),
          findsOneWidget,
        );
        expect(find.text('gaslessStandardBalanceNoTrxWarning'), findsNothing);
      });

      testWidgets('no warning when the TRX balance is unknown', (tester) async {
        await tester.pumpWidget(buildNotice(parentTrxBalance: null));

        expect(
          find.byKey(const Key('gasless-standard-balance-notice')),
          findsOneWidget,
        );
        expect(find.text('gaslessStandardBalanceNoTrxWarning'), findsNothing);
      });
    });

    test(
      'single-address gate is fail-closed when the build feature is disabled',
      () {
        final sdk = _FakeSdk(balances: _FakeBalanceManager(const {}));
        final trx = Asset.fromJson(_trxConfig(), knownIds: const {});
        final usdt = Asset.fromJson(_trc20Config(), knownIds: {trx.id});

        // Asserted against the compiled switch rather than a hardcoded
        // `isFalse`: CI now supplies the same GasFree --dart-defines as the
        // release builds, so the rail is legitimately active there and
        // inactive in an unconfigured build. The invariant that matters is
        // that the single-address scope tracks `isTronGaslessConfigured`
        // exactly - never open while the feature is unconfigured. Note it is
        // deliberately NOT gated on the *receive* flag: pulling the receive
        // kill switch must not re-open secondary TRON address creation.
        expect(
          trx.toCoin().isGaslessSingleAddressScope(sdk),
          isTronGaslessConfigured,
        );
        expect(
          usdt.toCoin().isGaslessSingleAddressScope(sdk),
          isTronGaslessConfigured,
        );
        // Recovery identity is deliberately config-independent.
        expect(usdt.toCoin().isGaslessRecoveryAsset, isTrue);

        final utxo = Asset.fromJson({
          'coin': 'DOC',
          'type': 'Smart Chain',
          'name': 'Doc',
          'fname': 'Doc',
          'wallet_only': false,
          'mm2': 1,
          'chain_id': 141,
          'decimals': 8,
          'is_testnet': true,
          'required_confirmations': 1,
          'derivation_path': "m/44'/141'/0'",
          'protocol': {'type': 'UTXO'},
        }, knownIds: const {});
        expect(utxo.toCoin().isGaslessSingleAddressScope(sdk), isFalse);
      },
    );

    test('faucet is hidden for gasless custody receive addresses', () {
      // A hypothetical faucet-enabled TRC-20 (faucet tickers are hardcoded in
      // the SDK): the faucet drips to the EOA, so it belongs on the standard
      // row — dripping while the custody address is displayed would land
      // funds stranded outside the shown account.
      final parent = Asset.fromJson(_trxConfig(), knownIds: const {});
      final faucetTrc20 = Asset.fromJson(
        {..._trc20Config(), 'coin': 'DOC', 'name': 'Doc', 'fname': 'Doc'},
        knownIds: {parent.id},
      );
      expect(faucetTrc20.id.hasFaucet, isTrue);
      expect(
        showFaucetForAddress(
          faucetTrc20.toCoin(),
          AddressDisplayVariant.gasfree,
        ),
        isFalse,
      );
      expect(
        showFaucetForAddress(
          faucetTrc20.toCoin(),
          AddressDisplayVariant.standard,
        ),
        isTrue,
      );

      // A plain faucet coin with a normal address keeps its faucet.
      final utxoFaucet = Asset.fromJson(_utxoConfig(), knownIds: const {});
      expect(utxoFaucet.id.hasFaucet, isTrue);
      expect(
        showFaucetForAddress(
          utxoFaucet.toCoin(),
          AddressDisplayVariant.standard,
        ),
        isTrue,
      );
    });

    group('blended gasless address rows', () {
      Asset trc20Asset() {
        final parent = Asset.fromJson(_trxConfig(), knownIds: const {});
        return Asset.fromJson(_trc20Config(), knownIds: {parent.id});
      }

      test('canonical custody key requires the exact primary derivation', () {
        PubkeyInfo key(String? path, {String? chain = 'external'}) =>
            _trc20Address(
              address: 'TRegularReceiveAddress000000000001',
              gasfreeAddress: 'TGasFreeReceiveAddress000000000001',
              derivationPath: path,
              chain: chain,
            );

        expect(
          isCanonicalTronGaslessPubkey(
            key("m/44'/195'/0'/0/0"),
            isHdWallet: true,
          ),
          isTrue,
        );
        for (final path in [
          "m/44'/195'/1'/0/0",
          "m/44'/195'/0'/1/0",
          "m/44'/195'/0'/0/1",
          "m/44'/60'/0'/0/0",
          null,
        ]) {
          expect(
            isCanonicalTronGaslessPubkey(key(path), isHdWallet: true),
            isFalse,
            reason: 'HD path $path must not enter GasFree custody',
          );
        }
        expect(
          isCanonicalTronGaslessPubkey(
            key("m/44'/195'/0'/0/0", chain: 'internal'),
            isHdWallet: true,
          ),
          isFalse,
        );
        expect(
          isCanonicalTronGaslessPubkey(
            key(null, chain: null),
            isHdWallet: false,
          ),
          isTrue,
        );
      });

      test('visibleAddressRows expands a gasless pubkey custody-first', () {
        final usdt = trc20Asset();
        final pubkey = _trc20Address(
          address: 'TRegularReceiveAddress000000000001',
          gasfreeAddress: 'TGasFreeReceiveAddress000000000001',
        );

        final rows = visibleAddressRows(
          usdt.toCoin(),
          [pubkey],
          hideZeroBalance: false,
          gaslessReceiveEnabled: true,
          isHdWallet: true,
        );

        expect(rows, hasLength(2));
        expect(rows.first.variant, AddressDisplayVariant.gasfree);
        expect(rows.last.variant, AddressDisplayVariant.standard);
        expect(rows.first.pubkey, same(pubkey));
        expect(rows.last.pubkey, same(pubkey));
      });

      test('visibleAddressRows keeps plain pubkeys as one standard row', () {
        final utxo = Asset.fromJson(_utxoConfig(), knownIds: const {});

        final rows = visibleAddressRows(
          utxo.toCoin(),
          [_address('R-test-address')],
          hideZeroBalance: false,
          gaslessReceiveEnabled: false,
          isHdWallet: false,
        );

        expect(rows, hasLength(1));
        expect(rows.single.variant, AddressDisplayVariant.standard);
      });

      test('only the canonical primary key gets a GasFree row', () {
        final usdt = trc20Asset();
        final primary = _trc20Address(
          address: 'TRegularReceiveAddress000000000001',
          gasfreeAddress: 'TGasFreeReceiveAddress000000000001',
        );
        final secondary = _trc20Address(
          address: 'TRegularReceiveAddress000000000002',
          gasfreeAddress: 'TGasFreeReceiveAddress000000000002',
          derivationPath: "m/44'/195'/0'/0/1",
        );

        final rows = visibleAddressRows(
          usdt.toCoin(),
          [primary, secondary],
          hideZeroBalance: false,
          gaslessReceiveEnabled: true,
          isHdWallet: true,
        );

        expect(rows, hasLength(3));
        expect(
          rows.where((row) => row.variant == AddressDisplayVariant.gasfree),
          hasLength(1),
        );
        expect(rows.last.pubkey, same(secondary));
        expect(rows.last.variant, AddressDisplayVariant.standard);
      });

      test('receive kill switch leaves every key on the standard rail', () {
        final usdt = trc20Asset();
        final primary = _trc20Address(
          address: 'TRegularReceiveAddress000000000001',
          gasfreeAddress: 'TGasFreeReceiveAddress000000000001',
        );

        final rows = visibleAddressRows(
          usdt.toCoin(),
          [primary],
          hideZeroBalance: false,
          gaslessReceiveEnabled: false,
          isHdWallet: true,
        );

        expect(rows, hasLength(1));
        expect(rows.single.variant, AddressDisplayVariant.standard);
      });

      test('receive pause preserves a read-only custody account row', () {
        final usdt = trc20Asset();
        final primary = _trc20Address(
          address: 'TRegularReceiveAddress000000000001',
          gasfreeAddress: 'TGasFreeReceiveAddress000000000001',
        );

        final rows = visibleAddressRows(
          usdt.toCoin(),
          [primary],
          hideZeroBalance: false,
          gaslessReceiveEnabled: false,
          isHdWallet: true,
          gaslessCustodyVisible: true,
        );

        expect(rows, hasLength(2));
        expect(rows.first.variant, AddressDisplayVariant.gasfree);
        expect(rows.last.variant, AddressDisplayVariant.standard);
      });

      test('zero-balance toggle hides the empty standard sibling, never the '
          'gas-free row', () {
        final usdt = trc20Asset();
        final emptyEoa = _trc20Address(
          address: 'TRegularReceiveAddress000000000001',
          gasfreeAddress: 'TGasFreeReceiveAddress000000000001',
        );
        final fundedEoa = _trc20Address(
          address: 'TRegularReceiveAddress000000000002',
          gasfreeAddress: 'TGasFreeReceiveAddress000000000002',
          balance: _balanceOf('7.25'),
        );

        final hidden = visibleAddressRows(
          usdt.toCoin(),
          [emptyEoa],
          hideZeroBalance: true,
          gaslessReceiveEnabled: true,
          isHdWallet: true,
        );
        expect(hidden, hasLength(1));
        expect(hidden.single.variant, AddressDisplayVariant.gasfree);

        final shown = visibleAddressRows(
          usdt.toCoin(),
          [fundedEoa],
          hideZeroBalance: true,
          gaslessReceiveEnabled: true,
          isHdWallet: true,
        );
        expect(shown, hasLength(2));

        // A plain zero-balance pubkey has no custody row to keep it around.
        final utxo = Asset.fromJson(_utxoConfig(), knownIds: const {});
        final utxoRows = visibleAddressRows(
          utxo.toCoin(),
          [_address('R-test-address', balance: _balanceOf('0'))],
          hideZeroBalance: true,
          gaslessReceiveEnabled: false,
          isHdWallet: false,
        );
        expect(utxoRows, isEmpty);
      });

      Widget buildAddressCard({
        required Asset asset,
        required PubkeyInfo address,
        required AddressDisplayVariant variant,
        Map<AssetId, BalanceInfo> balances = const {},
        GaslessAccountStatusResponse? gaslessAccountStatus,
        bool gaslessReceiveEnabled = true,
        GaslessReceiveStatus gaslessReceiveStatus =
            GaslessReceiveStatus.initial,
        GaslessReceiveReasonCode? gaslessReceiveReason,
        TextScaler textScaler = const TextScaler.linear(1),
        ThemeMode themeMode = ThemeMode.light,
      }) {
        final sdk = _FakeSdk(balances: _FakeBalanceManager(balances));
        return MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: themeMode,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
          home: RepositoryProvider<KomodoDefiSdk>.value(
            value: sdk,
            child: BlocProvider<SettingsBloc>.value(
              value: _FakeSettingsBloc(),
              child: Scaffold(
                body: AddressCard(
                  address: address,
                  coin: asset.toCoin(),
                  variant: variant,
                  setPageType: (_) {},
                  isSoleGaslessRow: true,
                  gaslessReceiveEnabled: gaslessReceiveEnabled,
                  gaslessReceiveStatus: gaslessReceiveStatus,
                  gaslessReceiveReason: gaslessReceiveReason,
                  gaslessAccountStatus: gaslessAccountStatus,
                ),
              ),
            ),
          ),
        );
      }

      Widget buildCoinAddressesComposition({
        required Asset asset,
        required PubkeyInfo address,
        required CoinAddressesState state,
        bool disableAnimations = false,
      }) {
        final addressesBloc = _FakeCoinAddressesBloc(state);
        final authBloc = _FakeAuthBloc(
          AuthBlocState.loggedIn(_softwareUser('wallet-a', _walletAHash)),
        );
        final settingsBloc = _FakeSettingsBloc();
        addTearDown(addressesBloc.close);
        addTearDown(authBloc.close);
        addTearDown(settingsBloc.close);

        final sdk = _FakeSdk(
          balances: _FakeBalanceManager(const {}),
          assetValues: [asset],
        );

        return MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: disableAnimations),
            child: child!,
          ),
          home: RepositoryProvider<KomodoDefiSdk>.value(
            value: sdk,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<AuthBloc>.value(value: authBloc),
                BlocProvider<CoinAddressesBloc>.value(value: addressesBloc),
                BlocProvider<SettingsBloc>.value(value: settingsBloc),
              ],
              child: Scaffold(
                body: CustomScrollView(
                  slivers: [
                    CoinAddresses(coin: asset.toCoin(), setPageType: (_) {}),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      testWidgets(
        'gas-free row shows the custody address, tag and custody balance',
        (tester) async {
          final usdt = trc20Asset();
          final pubkey = _trc20Address(
            address: 'TRegularReceiveAddress000000000001',
            gasfreeAddress: 'TGasFreeReceiveAddress000000000001',
            // Funded EOA whose balance must NOT be attributed to this row.
            balance: _balanceOf('7.25'),
          );

          await tester.pumpWidget(
            buildAddressCard(
              asset: usdt,
              address: pubkey,
              variant: AddressDisplayVariant.gasfree,
              // The normal balance is aggregate wallet ownership and must not
              // be rendered beside the custody address.
              balances: {usdt.id: _balanceOf('127.75')},
              gaslessAccountStatus: _gaslessAccountStatus(
                pubkey.gasfreeAddress!,
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            find.byKey(const Key('address-row-gasfree-tag')),
            findsOneWidget,
          );
          expect(find.byIcon(Icons.copy), findsOneWidget);
          expect(find.byType(FaucetButton), findsNothing);
          expect(find.byType(SwapAddressTag), findsNothing);
          expect(find.textContaining('120.5'), findsOneWidget);
          expect(find.textContaining('7.25'), findsNothing);
        },
      );

      testWidgets(
        'custody row never substitutes aggregate balance without a snapshot',
        (tester) async {
          final usdt = trc20Asset();
          final pubkey = _trc20Address(
            address: 'TRegularReceiveAddress000000000001',
            gasfreeAddress: 'TGasFreeReceiveAddress000000000001',
            balance: _balanceOf('7.25'),
          );

          await tester.pumpWidget(
            buildAddressCard(
              asset: usdt,
              address: pubkey,
              variant: AddressDisplayVariant.gasfree,
              balances: {usdt.id: _balanceOf('127.75')},
            ),
          );
          await tester.pumpAndSettle();

          expect(find.textContaining('127.75'), findsNothing);
          expect(find.textContaining('7.25'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'paused custody row keeps balance visible without copy or QR actions',
        (tester) async {
          final usdt = trc20Asset();
          final pubkey = _trc20Address(
            address: 'TRegularReceiveAddress000000000001',
            gasfreeAddress: 'TGasFreeReceiveAddress000000000001',
          );

          await tester.pumpWidget(
            buildAddressCard(
              asset: usdt,
              address: pubkey,
              variant: AddressDisplayVariant.gasfree,
              balances: {usdt.id: _balanceOf('127.75')},
              gaslessAccountStatus: _gaslessAccountStatus(
                pubkey.gasfreeAddress!,
                availability: 'provider_unreachable',
              ),
              gaslessReceiveEnabled: false,
              gaslessReceiveStatus: GaslessReceiveStatus.temporarilyUnavailable,
              gaslessReceiveReason:
                  GaslessReceiveReasonCode.providerTemporarilyUnavailable,
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('addressRowGasfreePausedTag'), findsOneWidget);
          expect(find.textContaining('120.5'), findsOneWidget);
          expect(find.byType(AddressCopyButton), findsNothing);
          expect(find.byType(QrButton), findsNothing);
          expect(find.text('gaslessRecoveryBody'), findsNothing);
          expect(
            find.byKey(const Key('gasless-custody-recovery-action')),
            findsNothing,
          );
        },
      );

      testWidgets('build-time Receive disable retains the custody snapshot', (
        tester,
      ) async {
        final usdt = trc20Asset();
        final pubkey = _trc20Address(
          address: 'TRegularReceiveAddress000000000001',
          gasfreeAddress: 'TGasFreeReceiveAddress000000000001',
        );

        await tester.pumpWidget(
          buildAddressCard(
            asset: usdt,
            address: pubkey,
            variant: AddressDisplayVariant.gasfree,
            gaslessAccountStatus: _gaslessAccountStatus(pubkey.gasfreeAddress!),
            gaslessReceiveEnabled: false,
            gaslessReceiveStatus: GaslessReceiveStatus.disabled,
            gaslessReceiveReason: GaslessReceiveReasonCode.receiveBuildDisabled,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('120.5'), findsOneWidget);
        expect(find.byType(AddressCopyButton), findsNothing);
        expect(find.byType(QrButton), findsNothing);
        expect(find.text('gaslessRecoveryBody'), findsNothing);
        expect(
          find.byKey(const Key('gasless-custody-recovery-action')),
          findsNothing,
        );
      });

      testWidgets(
        'checking custody row is stable and never shows paused recovery copy',
        (tester) async {
          final usdt = trc20Asset();
          final pubkey = _trc20Address(
            address: 'TRegularReceiveAddress000000000001',
            gasfreeAddress: 'TGasFreeReceiveAddress000000000001',
          );

          await tester.pumpWidget(
            buildAddressCard(
              asset: usdt,
              address: pubkey,
              variant: AddressDisplayVariant.gasfree,
              gaslessReceiveEnabled: false,
              gaslessReceiveStatus: GaslessReceiveStatus.checking,
            ),
          );

          expect(
            find.byKey(const Key('address-row-gasfree-checking-tag')),
            findsOneWidget,
          );
          expect(find.text('gaslessRecoveryBody'), findsNothing);
          expect(
            find.byKey(const Key('address-row-gasfree-tag')),
            findsNothing,
          );
        },
      );

      testWidgets(
        'checking composition keeps Standard actions usable with reduced '
        'motion',
        (tester) async {
          final usdt = trc20Asset();
          final pubkey = _trc20Address(
            address: 'TRegularReceiveAddress000000000001',
            gasfreeAddress: 'TGasFreeReceiveAddress000000000001',
            balance: _balanceOf('7.25'),
          );

          await tester.pumpWidget(
            buildCoinAddressesComposition(
              asset: usdt,
              address: pubkey,
              state: CoinAddressesState(
                status: FormStatus.success,
                addresses: [pubkey],
                gaslessReceiveStatus: GaslessReceiveStatus.checking,
              ),
              disableAnimations: true,
            ),
          );
          await tester.pump();

          expect(
            MediaQuery.disableAnimationsOf(
              tester.element(find.byType(CoinAddresses)),
            ),
            isTrue,
          );
          expect(
            find.byKey(const Key('address-row-gasfree-checking-tag')),
            findsOneWidget,
          );
          expect(find.text('gaslessRecoveryBody'), findsNothing);

          final standardRow = find.byKey(
            ValueKey('address-card-standard-${pubkey.address}'),
          );
          expect(standardRow, findsOneWidget);
          expect(
            find.descendant(
              of: standardRow,
              matching: find.byType(AddressCopyButton),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(of: standardRow, matching: find.byType(QrButton)),
            findsOneWidget,
          );
          final standardReceiveAction = find.descendant(
            of: standardRow,
            matching: find.byKey(const Key('address-row-receive-action')),
          );
          expect(
            tester.widget<Semantics>(standardReceiveAction).properties.enabled,
            isTrue,
          );

          // The checking banner exists only in builds where the receive rail
          // is compiled in. The named feature-enabled run below exercises its
          // reduced-motion fallback; the unconfigured suite still verifies
          // the complete row composition and Standard escape hatch.
          expect(
            find.byKey(const Key('gasless-receive-checking-banner')),
            isTronGaslessReceiveConfigured ? findsOneWidget : findsNothing,
          );
          expect(find.byType(LinearProgressIndicator), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets('paused reasons render distinct closed-state guidance', (
        tester,
      ) async {
        final usdt = trc20Asset();
        final pubkey = _trc20Address(
          address: 'TRegularReceiveAddress000000000001',
          gasfreeAddress: 'TGasFreeReceiveAddress000000000001',
        );

        Future<void> expectReason(
          GaslessReceiveReasonCode reason,
          String expectedKey, {
          bool offersOfficialRecovery = false,
        }) async {
          await tester.pumpWidget(
            buildAddressCard(
              asset: usdt,
              address: pubkey,
              variant: AddressDisplayVariant.gasfree,
              gaslessReceiveEnabled: false,
              gaslessReceiveStatus: offersOfficialRecovery
                  ? GaslessReceiveStatus.unsupported
                  : GaslessReceiveStatus.disabled,
              gaslessReceiveReason: reason,
              gaslessAccountStatus: offersOfficialRecovery
                  ? _gaslessAccountStatus(
                      pubkey.gasfreeAddress!,
                      availability: 'token_unsupported',
                    )
                  : null,
            ),
          );
          expect(find.text(expectedKey), findsOneWidget);
          expect(
            find.text('gaslessRecoveryBody'),
            offersOfficialRecovery ? findsOneWidget : findsNothing,
          );
          expect(
            find.byKey(const Key('gasless-custody-recovery-action')),
            offersOfficialRecovery ? findsOneWidget : findsNothing,
          );
        }

        await expectReason(
          GaslessReceiveReasonCode.receiveBuildDisabled,
          'receiveGaslessBuildDisabledNotice',
        );
        await expectReason(
          GaslessReceiveReasonCode.malformedAccountStatus,
          'receiveGaslessSecurityBlockedNotice',
        );
        await expectReason(
          GaslessReceiveReasonCode.providerIdentityMismatch,
          'receiveGaslessProviderMismatchNotice',
        );
        await expectReason(
          GaslessReceiveReasonCode.reactivationRequired,
          'receiveGaslessReactivationRequiredNotice',
        );
        await expectReason(
          GaslessReceiveReasonCode.pendingTransfer,
          'receiveGaslessPendingTransferNotice',
        );
        await expectReason(
          GaslessReceiveReasonCode.tokenUnsupported,
          'receiveGaslessTokenUnsupportedNotice',
        );
        await expectReason(
          GaslessReceiveReasonCode.tokenUnsupported,
          'receiveGaslessTokenUnsupportedNotice',
          offersOfficialRecovery: true,
        );
      });

      testWidgets('standard sibling row shows the EOA with its own balance', (
        tester,
      ) async {
        final usdt = trc20Asset();
        final pubkey = _trc20Address(
          address: 'TRegularReceiveAddress000000000001',
          gasfreeAddress: 'TGasFreeReceiveAddress000000000001',
          balance: _balanceOf('7.25'),
        );

        await tester.pumpWidget(
          buildAddressCard(
            asset: usdt,
            address: pubkey,
            variant: AddressDisplayVariant.standard,
            // Custody balance present in the cache but not this row's.
            balances: {usdt.id: _balanceOf('120.5')},
          ),
        );

        expect(
          find.byKey(const Key('address-row-standard-tag')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('address-row-gasfree-tag')), findsNothing);
        final copy = tester.widget<AddressCopyButton>(
          find.byType(AddressCopyButton),
        );
        expect(copy.address, 'TRegularReceiveAddress000000000001');
        expect(find.byType(SwapAddressTag), findsOneWidget);
        expect(find.byType(FaucetButton), findsNothing);
        expect(find.textContaining('7.25'), findsOneWidget);
        expect(find.textContaining('120.5'), findsNothing);
      });

      testWidgets(
        'receive dialog pinned to the standard variant shows the EOA QR '
        'with the caveat',
        (tester) async {
          tester.view.physicalSize = const Size(900, 1800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          final usdt = trc20Asset();
          final pubkey = _trc20Address(
            address: 'TRegularReceiveAddress000000000001',
            gasfreeAddress: 'TGasFreeReceiveAddress000000000001',
            // Funded EOA → the stranded-balance line must appear.
            balance: _balanceOf('7'),
          );

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: PubkeyReceiveDialog(
                  coin: usdt.toCoin(),
                  address: pubkey,
                  variant: AddressDisplayVariant.standard,
                  gaslessReceiveEnabled: true,
                ),
              ),
            ),
          );

          final qr = tester.widget<QrCode>(find.byType(QrCode));
          expect(qr.address, 'TRegularReceiveAddress000000000001');
          expect(
            find.byKey(const Key('receive-standard-variant-caveat')),
            findsOneWidget,
          );
          expect(find.text('receiveStandardVariantCaveat'), findsOneWidget);
          expect(
            find.byKey(const Key('receive-standard-balance-notice')),
            findsOneWidget,
          );
          // No gasless badge and no disclosure — this IS the standard address.
          expect(find.text('receiveGaslessBadgeTitle'), findsNothing);
          expect(
            find.byKey(const Key('receive-standard-address-toggle')),
            findsNothing,
          );
        },
      );

      testWidgets(
        'GasFree receive dialog fits 320px at 200% text and announces '
        'disclosure state',
        (tester) async {
          tester.view.physicalSize = const Size(320, 568);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final semantics = tester.ensureSemantics();

          final usdt = trc20Asset();
          final pubkey = _trc20Address(
            address: 'TRegularReceiveAddress000000000001',
            gasfreeAddress: 'TGasFreeReceiveAddress000000000001',
          );

          await tester.pumpWidget(
            _liveGaslessReceiveDialog(
              asset: usdt,
              address: pubkey,
              textScaler: const TextScaler.linear(2),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(
            tester.getSize(find.byType(QrCode)).width,
            lessThanOrEqualTo(200),
          );
          await tester.ensureVisible(find.byType(QrCode));
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            tester.getSemantics(find.byType(QrCode)).label,
            contains('scanTheQrCode: USDT'),
          );

          Semantics disclosure() => tester.widget<Semantics>(
            find.byKey(
              const Key('receive-standard-address-disclosure-semantics'),
            ),
          );
          expect(disclosure().properties.expanded, isFalse);

          await tester.ensureVisible(
            find.byKey(const Key('receive-standard-address-toggle')),
          );
          await tester.tap(
            find.byKey(const Key('receive-standard-address-toggle')),
          );
          await tester.pumpAndSettle();
          expect(disclosure().properties.expanded, isTrue);
          expect(tester.takeException(), isNull);
          semantics.dispose();
        },
      );

      testWidgets(
        'paused custody address exposes a disabled 48dp receive target',
        (tester) async {
          tester.view.physicalSize = const Size(320, 568);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          final usdt = trc20Asset();
          final pubkey = _trc20Address(
            address: 'TRegularReceiveAddress000000000001',
            gasfreeAddress: 'TGasFreeReceiveAddress000000000001',
          );
          await tester.pumpWidget(
            buildAddressCard(
              asset: usdt,
              address: pubkey,
              variant: AddressDisplayVariant.gasfree,
              gaslessReceiveEnabled: false,
              textScaler: const TextScaler.linear(2),
              gaslessAccountStatus: _gaslessAccountStatus(
                pubkey.gasfreeAddress!,
                availability: 'provider_unreachable',
              ),
            ),
          );

          final receiveAction = find.byKey(
            const Key('address-row-receive-action'),
          );
          expect(
            tester.getRect(receiveAction).height,
            greaterThanOrEqualTo(48),
          );
          expect(
            tester.widget<Semantics>(receiveAction).properties.enabled,
            isFalse,
          );
          expect(tester.takeException(), isNull);
        },
      );

      // screen.dart's global screen type only changes via
      // updateScreenType(context); sync it to the current test view by
      // pumping a trivial widget (pumping AddressCard itself would render
      // the stale branch at the new size and overflow).
      Future<void> syncScreenTypeToView(WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                updateScreenType(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
      }

      Future<void> expectReadyAndPausedAtViewport(
        WidgetTester tester, {
        required Size size,
        required ThemeMode themeMode,
        required Brightness brightness,
      }) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await syncScreenTypeToView(tester);
        addTearDown(() async {
          tester.view.physicalSize = const Size(400, 800);
          tester.view.devicePixelRatio = 1;
          await syncScreenTypeToView(tester);
        });

        final usdt = trc20Asset();
        final pubkey = _trc20Address(
          address: 'TRegularReceiveAddress000000000001',
          gasfreeAddress: 'TGasFreeReceiveAddress000000000001',
        );
        final availableStatus = _gaslessAccountStatus(pubkey.gasfreeAddress!);
        final unreachableStatus = _gaslessAccountStatus(
          pubkey.gasfreeAddress!,
          availability: 'provider_unreachable',
        );

        await tester.pumpWidget(
          buildAddressCard(
            asset: usdt,
            address: pubkey,
            variant: AddressDisplayVariant.gasfree,
            gaslessAccountStatus: availableStatus,
            gaslessReceiveStatus: GaslessReceiveStatus.ready,
            themeMode: themeMode,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          Theme.of(tester.element(find.byType(AddressCard))).brightness,
          brightness,
        );
        expect(
          find.byKey(const Key('address-row-gasfree-tag')),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.copy), findsOneWidget);
        expect(find.byType(QrButton), findsOneWidget);
        expect(find.textContaining('120.5'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          buildAddressCard(
            asset: usdt,
            address: pubkey,
            variant: AddressDisplayVariant.gasfree,
            gaslessAccountStatus: unreachableStatus,
            gaslessReceiveEnabled: false,
            gaslessReceiveStatus: GaslessReceiveStatus.temporarilyUnavailable,
            gaslessReceiveReason:
                GaslessReceiveReasonCode.providerTemporarilyUnavailable,
            themeMode: themeMode,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          Theme.of(tester.element(find.byType(AddressCard))).brightness,
          brightness,
        );
        expect(find.text('addressRowGasfreePausedTag'), findsOneWidget);
        expect(find.textContaining('120.5'), findsOneWidget);
        expect(find.byIcon(Icons.copy), findsNothing);
        expect(find.byType(QrButton), findsNothing);
        expect(
          find.text('receiveGaslessProviderUnavailableNotice'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }

      testWidgets(
        'ready and paused custody rows render at 375px in light theme',
        (tester) => expectReadyAndPausedAtViewport(
          tester,
          size: const Size(375, 812),
          themeMode: ThemeMode.light,
          brightness: Brightness.light,
        ),
      );

      testWidgets(
        'ready and paused custody rows render at 768px in dark theme',
        (tester) => expectReadyAndPausedAtViewport(
          tester,
          size: const Size(768, 1024),
          themeMode: ThemeMode.dark,
          brightness: Brightness.dark,
        ),
      );

      testWidgets('desktop rows lay out the variant tag without overflow', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await syncScreenTypeToView(tester);
        // Restore the mobile screen type afterwards — the global persists
        // across the whole test binary otherwise.
        addTearDown(() async {
          tester.view.physicalSize = const Size(400, 800);
          await syncScreenTypeToView(tester);
        });

        final usdt = trc20Asset();
        final pubkey = _trc20Address(
          address: 'TRegularReceiveAddress000000000001',
          gasfreeAddress: 'TGasFreeReceiveAddress000000000001',
          balance: _balanceOf('7.25'),
        );

        // The desktop branch places the tag beside the fixed-width actions
        // box; any overflow fails the test via the rendering exception.
        await tester.pumpWidget(
          buildAddressCard(
            asset: usdt,
            address: pubkey,
            variant: AddressDisplayVariant.gasfree,
            balances: {usdt.id: _balanceOf('127.75')},
            gaslessAccountStatus: _gaslessAccountStatus(pubkey.gasfreeAddress!),
          ),
        );
        expect(
          find.byKey(const Key('address-row-gasfree-tag')),
          findsOneWidget,
        );
        final desktopReceiveAction = find.byKey(
          const Key('address-row-desktop-receive-action'),
        );
        expect(
          tester.getRect(desktopReceiveAction).height,
          greaterThanOrEqualTo(48),
        );
        expect(
          tester.widget<Semantics>(desktopReceiveAction).properties.button,
          isTrue,
        );
        expect(find.textContaining('120.5'), findsOneWidget);

        await tester.pumpWidget(
          buildAddressCard(
            asset: usdt,
            address: pubkey,
            variant: AddressDisplayVariant.standard,
          ),
        );
        expect(
          find.byKey(const Key('address-row-standard-tag')),
          findsOneWidget,
        );
        expect(find.textContaining('7.25'), findsOneWidget);
      });

      testWidgets('QrButton opens the dialog pinned to its variant', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(900, 1800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final usdt = trc20Asset();
        final pubkey = _trc20Address(
          address: 'TRegularReceiveAddress000000000001',
          gasfreeAddress: 'TGasFreeReceiveAddress000000000001',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: QrButton(
                coin: usdt.toCoin(),
                address: pubkey,
                variant: AddressDisplayVariant.standard,
              ),
            ),
          ),
        );

        await tester.tap(find.byType(IconButton));
        await tester.pumpAndSettle();

        final qr = tester.widget<QrCode>(find.byType(QrCode));
        expect(qr.address, 'TRegularReceiveAddress000000000001');
        expect(find.text('receiveGaslessBadgeTitle'), findsNothing);
      });

      testWidgets('GasFree QrButton revalidates at tap time and fails closed', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(900, 1800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final parent = Asset.fromJson(_trxConfig(), knownIds: const {});
        final asset = Asset.fromJson(_trc20Config(), knownIds: {parent.id});
        final pubkey = _trc20Address(
          address: 'TRegularReceiveAddress000000000001',
          gasfreeAddress: 'TGasFreeReceiveAddress000000000001',
        );
        final addressesBloc = _FakeCoinAddressesBloc(
          CoinAddressesState(
            addresses: [pubkey],
            gaslessReceiveStatus: GaslessReceiveStatus.ready,
            verifiedGasfreeAddress: pubkey.gasfreeAddress,
            gaslessReceiveWalletPubkeyHash: _walletAHash,
            gaslessAccountStatus: _gaslessAccountStatus(pubkey.gasfreeAddress!),
            gaslessAccountStatusObservedAt: DateTime.now().toUtc(),
          ),
        );
        final authBloc = _FakeAuthBloc(
          AuthBlocState.loggedIn(_softwareUser('wallet-a', _walletAHash)),
        );
        final sdk = _FakeSdk(
          balances: _FakeBalanceManager(const {}),
          assetValues: [asset],
          boundGaslessReceive: true,
        );
        addTearDown(addressesBloc.close);
        addTearDown(authBloc.close);

        await tester.pumpWidget(
          MaterialApp(
            home: RepositoryProvider<KomodoDefiSdk>.value(
              value: sdk,
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<AuthBloc>.value(value: authBloc),
                  BlocProvider<CoinAddressesBloc>.value(value: addressesBloc),
                ],
                child: Scaffold(
                  body: QrButton(
                    coin: asset.toCoin(),
                    address: pubkey,
                    variant: AddressDisplayVariant.gasfree,
                    gaslessReceiveEnabled: true,
                  ),
                ),
              ),
            ),
          ),
        );

        // Simulate authority being revoked after the button was rendered but
        // before the user acts.
        addressesBloc.actionRevalidationAllowed = false;
        await tester.tap(find.byType(IconButton));
        await tester.pump();

        expect(addressesBloc.actionRevalidationCalls, 1);
        expect(
          addressesBloc.lastEvent,
          isA<CoinAddressesGaslessReceiveRefreshRequested>(),
        );
        expect(find.byType(QrCode), findsNothing);
        expect(find.byType(PubkeyReceiveDialog), findsNothing);
        expect(find.text('receiveGaslessPausedNotice'), findsOneWidget);
      });
    });
  });
}

void main() {
  testReceiveAddressFaucetWidgets();
}

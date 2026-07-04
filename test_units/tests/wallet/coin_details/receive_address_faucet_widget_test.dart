import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_cex_market_data/komodo_cex_market_data.dart'
    show QuoteCurrency, Stablecoin;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart'
    show
        AssetIdFaucetExtension,
        BalanceManager,
        KomodoDefiSdk,
        MarketDataManager;
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_bloc.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_state.dart';
import 'package:web_dex/bloc/faucet_button/faucet_button_bloc.dart';
import 'package:web_dex/bloc/faucet_button/faucet_button_event.dart';
import 'package:web_dex/bloc/faucet_button/faucet_button_state.dart';
import 'package:web_dex/bloc/coins_bloc/asset_coin_extension.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/bloc/settings/settings_state.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/model/stored_settings.dart';
import 'package:web_dex/shared/utils/extensions/legacy_coin_migration_extensions.dart';
import 'package:web_dex/shared/widgets/copyable_address_dialog.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/coin_addresses.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/gasless_standard_balance_notice.dart';
import 'package:web_dex/views/wallet/coin_details/faucet/faucet_button.dart';
import 'package:web_dex/views/wallet/common/address_copy_button.dart';

class _FakeCoinAddressesBloc extends Cubit<CoinAddressesState>
    implements CoinAddressesBloc {
  _FakeCoinAddressesBloc(super.initialState);

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
  _FakeSdk({required this.balances, MarketDataManager? marketData})
    : marketData = marketData ?? _FakeMarketDataManager();

  @override
  final BalanceManager balances;

  @override
  final MarketDataManager marketData;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
}) {
  return PubkeyInfo(
    address: address,
    derivationPath: "m/44'/195'/0'/0/0",
    chain: 'external',
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

void testReceiveAddressFaucetWidgets() {
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

    testWidgets('TRC20 receive selector shows GasFree address', (tester) async {
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

      expect(find.text('TGasFr...000001'), findsOneWidget);
      expect(find.text('TRegul...000001'), findsNothing);
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
          MaterialApp(
            home: Scaffold(
              body: PubkeyReceiveDialog(coin: asset.toCoin(), address: address),
            ),
          ),
        );

        // Custody is the headline address; the EOA is hidden by default.
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
            body: PubkeyReceiveDialog(coin: asset.toCoin(), address: address),
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

    group('stranded-balance notice zero-TRX pre-warning', () {
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
        );
        final addressesBloc = _FakeCoinAddressesBloc(
          CoinAddressesState(addresses: [strandedAddress]),
        );

        return MaterialApp(
          home: RepositoryProvider<KomodoDefiSdk>.value(
            value: sdk,
            child: BlocProvider<CoinAddressesBloc>.value(
              value: addressesBloc,
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

      testWidgets('warns when the TRX balance is known to be zero', (
        tester,
      ) async {
        await tester.pumpWidget(
          buildNotice(parentTrxBalance: BalanceInfo.zero()),
        );

        expect(
          find.byKey(const Key('gasless-standard-balance-notice')),
          findsOneWidget,
        );
        expect(find.text('gaslessStandardBalanceNoTrxWarning'), findsOneWidget);
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
      'single-address gate scope covers TRX and TRC-20, not other chains',
      () {
        final sdk = _FakeSdk(balances: _FakeBalanceManager(const {}));
        final trx = Asset.fromJson(_trxConfig(), knownIds: const {});
        final usdt = Asset.fromJson(_trc20Config(), knownIds: {trx.id});

        // TRX shares the TRON HD address list, so it must be gated too — a
        // TRX-created address would be hidden by the SDK's phantom filter.
        expect(trx.toCoin().isGaslessSingleAddressScope(sdk), isTrue);
        expect(usdt.toCoin().isGaslessSingleAddressScope(sdk), isTrue);

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

      test('visibleAddressRows expands a gasless pubkey custody-first', () {
        final usdt = trc20Asset();
        final pubkey = _trc20Address(
          address: 'TRegularReceiveAddress000000000001',
          gasfreeAddress: 'TGasFreeReceiveAddress000000000001',
        );

        final rows = visibleAddressRows(usdt.toCoin(), [
          pubkey,
        ], hideZeroBalance: false);

        expect(rows, hasLength(2));
        expect(rows.first.variant, AddressDisplayVariant.gasfree);
        expect(rows.last.variant, AddressDisplayVariant.standard);
        expect(rows.first.pubkey, same(pubkey));
        expect(rows.last.pubkey, same(pubkey));
      });

      test('visibleAddressRows keeps plain pubkeys as one standard row', () {
        final utxo = Asset.fromJson(_utxoConfig(), knownIds: const {});

        final rows = visibleAddressRows(utxo.toCoin(), [
          _address('R-test-address'),
        ], hideZeroBalance: false);

        expect(rows, hasLength(1));
        expect(rows.single.variant, AddressDisplayVariant.standard);
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

        final hidden = visibleAddressRows(usdt.toCoin(), [
          emptyEoa,
        ], hideZeroBalance: true);
        expect(hidden, hasLength(1));
        expect(hidden.single.variant, AddressDisplayVariant.gasfree);

        final shown = visibleAddressRows(usdt.toCoin(), [
          fundedEoa,
        ], hideZeroBalance: true);
        expect(shown, hasLength(2));

        // A plain zero-balance pubkey has no custody row to keep it around.
        final utxo = Asset.fromJson(_utxoConfig(), knownIds: const {});
        final utxoRows = visibleAddressRows(utxo.toCoin(), [
          _address('R-test-address', balance: _balanceOf('0')),
        ], hideZeroBalance: true);
        expect(utxoRows, isEmpty);
      });

      Widget buildAddressCard({
        required Asset asset,
        required PubkeyInfo address,
        required AddressDisplayVariant variant,
        Map<AssetId, BalanceInfo> balances = const {},
      }) {
        final sdk = _FakeSdk(balances: _FakeBalanceManager(balances));
        return MaterialApp(
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
              balances: {usdt.id: _balanceOf('120.5')},
            ),
          );

          expect(
            find.byKey(const Key('address-row-gasfree-tag')),
            findsOneWidget,
          );
          final copy = tester.widget<AddressCopyButton>(
            find.byType(AddressCopyButton),
          );
          expect(copy.address, 'TGasFreeReceiveAddress000000000001');
          expect(find.byType(FaucetButton), findsNothing);
          expect(find.byType(SwapAddressTag), findsNothing);
          expect(find.textContaining('120.5'), findsOneWidget);
          expect(find.textContaining('7.25'), findsNothing);
        },
      );

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
            balances: {usdt.id: _balanceOf('120.5')},
          ),
        );
        expect(
          find.byKey(const Key('address-row-gasfree-tag')),
          findsOneWidget,
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
    });
  });
}

void main() {
  testReceiveAddressFaucetWidgets();
}

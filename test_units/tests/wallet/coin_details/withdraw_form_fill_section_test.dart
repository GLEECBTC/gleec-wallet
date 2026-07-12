import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:decimal/decimal.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart'
    show BalanceManager, GaslessAccountStatusResponse, KomodoDefiSdk;
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui/komodo_ui.dart' show AddressSelectInput;
import 'package:komodo_ui_kit/komodo_ui_kit.dart' show UiPrimaryButton;
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/bloc/withdraw_form/withdraw_form_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/withdraw_form.dart';

Map<String, dynamic> _utxoConfig() => {
  'coin': 'KMD',
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

BalanceInfo _balance(String amount) {
  final value = Decimal.parse(amount);
  return BalanceInfo(total: value, spendable: value, unspendable: Decimal.zero);
}

GaslessAccountStatusResponse _gaslessStatus({
  bool providerAvailable = true,
  bool? active = true,
  String? activationFee,
  String? transferFee = '1',
}) {
  return GaslessAccountStatusResponse.parse({
    'mmrpc': '2.0',
    'result': {
      'gasfree_address': 'TGasFreeSourceAddress',
      'on_chain_balance': '100',
      'provider_available': providerAvailable,
      if (active != null) 'active': active,
      if (transferFee != null) 'transfer_fee': transferFee,
      if (activationFee != null) 'activation_fee': activationFee,
    },
  });
}

WithdrawFormState _trc20FillState({
  bool isGaslessEnabled = true,
  GaslessAccountStatusResponse? gaslessAccountStatus,
  WalletType? walletType = WalletType.hdwallet,
  bool isGaslessStatusLoading = false,
  String sourceBalance = '100',
}) {
  final parent = Asset.fromJson(_trxConfig(), knownIds: const {});
  final asset = Asset.fromJson(_trc20Config(), knownIds: {parent.id});
  final source = PubkeyInfo(
    address: 'TRegularSourceAddress',
    derivationPath: "m/44'/195'/0'/0/0",
    chain: 'external',
    balance: _balance(sourceBalance),
    coinTicker: asset.id.id,
    gasfreeAddress: 'TGasFreeSourceAddress',
  );
  return WithdrawFormState(
    isGaslessFeatureConfigured: true,
    asset: asset,
    pubkeys: AssetPubkeys(
      assetId: asset.id,
      keys: [source],
      availableAddressesCount: 1,
      syncStatus: SyncStatusEnum.success,
    ),
    selectedSourceAddress: source,
    step: WithdrawFormStep.fill,
    recipientAddress: 'recipient',
    amount: '1',
    isGaslessEnabled: isGaslessEnabled,
    gaslessAccountStatus: gaslessAccountStatus,
    walletType: walletType,
    isGaslessStatusLoading: isGaslessStatusLoading,
  );
}

class _FakeBalanceManager implements BalanceManager {
  @override
  BalanceInfo? lastKnown(AssetId assetId) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSdk implements KomodoDefiSdk {
  @override
  final BalanceManager balances = _FakeBalanceManager();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWithdrawFormBloc extends Cubit<WithdrawFormState>
    implements WithdrawFormBloc {
  _FakeWithdrawFormBloc(super.initialState);

  final List<WithdrawFormEvent> events = <WithdrawFormEvent>[];

  @override
  void add(WithdrawFormEvent event) {
    events.add(event);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _buildTestWidget(WithdrawFormBloc bloc) {
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(size: Size(1280, 1200)),
      child: Builder(
        builder: (context) {
          updateScreenType(context);
          return RepositoryProvider<KomodoDefiSdk>.value(
            value: _FakeSdk(),
            child: BlocProvider<WithdrawFormBloc>.value(
              value: bloc,
              child: const Scaffold(
                body: SingleChildScrollView(
                  child: WithdrawFormFillSection(suppressPreviewError: false),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

void testWithdrawFormFillSection() {
  group('WithdrawFormFillSection', () {
    testWidgets('locks editable controls while preview is sending', (
      tester,
    ) async {
      final asset = Asset.fromJson(_utxoConfig(), knownIds: const {});
      final bloc = _FakeWithdrawFormBloc(
        WithdrawFormState(
          isGaslessFeatureConfigured: true,
          asset: asset,
          step: WithdrawFormStep.fill,
          recipientAddress: 'recipient',
          amount: '1',
          isSending: true,
        ),
      );
      addTearDown(bloc.close);

      await tester.pumpWidget(_buildTestWidget(bloc));

      final lockWidget = tester.widget<IgnorePointer>(
        find.byKey(const Key('withdraw-form-fill-input-lock')),
      );

      expect(lockWidget.ignoring, isTrue);
    });

    testWidgets('keeps editable controls enabled when not sending', (
      tester,
    ) async {
      final asset = Asset.fromJson(_utxoConfig(), knownIds: const {});
      final bloc = _FakeWithdrawFormBloc(
        WithdrawFormState(
          isGaslessFeatureConfigured: true,
          asset: asset,
          step: WithdrawFormStep.fill,
          recipientAddress: 'recipient',
          amount: '1',
          isSending: false,
        ),
      );
      addTearDown(bloc.close);

      await tester.pumpWidget(_buildTestWidget(bloc));

      final lockWidget = tester.widget<IgnorePointer>(
        find.byKey(const Key('withdraw-form-fill-input-lock')),
      );

      expect(lockWidget.ignoring, isFalse);
    });

    testWidgets('gas-free rail selects the custody entry in the source '
        'selector', (tester) async {
      final bloc = _FakeWithdrawFormBloc(_trc20FillState());
      addTearDown(bloc.close);

      await tester.pumpWidget(_buildTestWidget(bloc));

      // The selector's closed state shows the address the send actually
      // settles from — the GasFree custody address — not the signing
      // address (which previously rendered, locked, while the transfer
      // left the custody address).
      expect(
        find.byKey(const Key('withdraw-gasless-source-selector')),
        findsOneWidget,
      );
      expect(find.text('withdrawSendFrom'), findsOneWidget);
      expect(find.text('TGasFr...ddress'), findsOneWidget);
      expect(find.text('TRegul...ddress'), findsNothing);
      expect(find.textContaining('Maximum sendable amount'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('native rail selects the standard entry in the source '
        'selector', (tester) async {
      final bloc = _FakeWithdrawFormBloc(
        _trc20FillState(isGaslessEnabled: false),
      );
      addTearDown(bloc.close);

      await tester.pumpWidget(_buildTestWidget(bloc));

      expect(
        find.byKey(const Key('withdraw-gasless-source-selector')),
        findsOneWidget,
      );
      expect(find.text('TRegul...ddress'), findsOneWidget);
      expect(find.text('TGasFr...ddress'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('picking the standard entry switches to the native rail', (
      tester,
    ) async {
      final bloc = _FakeWithdrawFormBloc(_trc20FillState());
      addTearDown(bloc.close);

      await tester.pumpWidget(_buildTestWidget(bloc));

      final selector = tester.widget<AddressSelectInput>(
        find.byType(AddressSelectInput),
      );
      expect(selector.addresses, hasLength(2));
      final standard = selector.addresses.singleWhere(
        (entry) => entry.address == 'TRegularSourceAddress',
      );

      // Exercise the production selector callback directly. The generic
      // dropdown owns a process-wide overlay and is independently tested by
      // komodo_ui; direct selection keeps this rail-wiring test deterministic.
      selector.onAddressSelected!(standard);

      final toggle = bloc.events.whereType<WithdrawFormGaslessToggled>().single;
      expect(toggle.isEnabled, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('gasless rail shows a status chip, not a checkbox', (
      tester,
    ) async {
      final bloc = _FakeWithdrawFormBloc(_trc20FillState());
      addTearDown(bloc.close);

      await tester.pumpWidget(_buildTestWidget(bloc));

      expect(find.byKey(const Key('withdraw-gasless-chip')), findsOneWidget);
      // The amount field still has its legitimate "send maximum" checkbox;
      // ensure there is no checkbox inside the rail-specific Advanced card.
      expect(
        find.descendant(
          of: find.byKey(const Key('withdraw-advanced-section')),
          matching: find.byType(CheckboxListTile),
        ),
        findsNothing,
      );
      expect(
        find.byKey(const Key('withdraw-advanced-section')),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('chip shows a checking state while the first status fetch is '
        'in flight', (tester) async {
      final bloc = _FakeWithdrawFormBloc(
        _trc20FillState(isGaslessStatusLoading: true),
      );
      addTearDown(bloc.close);

      await tester.pumpWidget(_buildTestWidget(bloc));

      expect(find.text('withdrawGaslessCheckingAvailability'), findsOneWidget);
      // Preview is held until availability is known, so it cannot hard-fail
      // against an unreachable provider the user was never told about.
      final button = tester.widget<UiPrimaryButton>(
        find.byType(UiPrimaryButton),
      );
      expect(button.onPressed, isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'source selector still offers both pots when the standard address is '
      'empty',
      (tester) async {
        final bloc = _FakeWithdrawFormBloc(_trc20FillState(sourceBalance: '0'));
        addTearDown(bloc.close);

        await tester.pumpWidget(_buildTestWidget(bloc));

        expect(
          find.byKey(const Key('withdraw-gasless-source-selector')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('withdraw-gasless-chip')), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('advanced native switch dispatches the gasless toggle', (
      tester,
    ) async {
      final bloc = _FakeWithdrawFormBloc(_trc20FillState());
      addTearDown(bloc.close);

      await tester.pumpWidget(_buildTestWidget(bloc));

      // Collapsed by default while gasless is active — expand it first.
      await tester.ensureVisible(
        find.byKey(const Key('withdraw-advanced-section')),
      );
      await tester.tap(find.byKey(const Key('withdraw-advanced-section')));
      await tester.pump(const Duration(milliseconds: 300));

      final nativeSwitch = tester.widget<SwitchListTile>(
        find.byKey(const Key('withdraw-native-send-switch')),
      );
      nativeSwitch.onChanged!(true);
      expect(
        bloc.events.whereType<WithdrawFormGaslessToggled>().single.isEnabled,
        isFalse,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('native rail expands Advanced with the active note', (
      tester,
    ) async {
      final bloc = _FakeWithdrawFormBloc(
        _trc20FillState(isGaslessEnabled: false),
      );
      addTearDown(bloc.close);

      await tester.pumpWidget(_buildTestWidget(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('withdraw-gasless-chip')), findsNothing);
      expect(
        find.byKey(const Key('withdraw-native-send-active-note')),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('activation banner appears only for an inactive account', (
      tester,
    ) async {
      final inactiveBloc = _FakeWithdrawFormBloc(
        _trc20FillState(
          gaslessAccountStatus: _gaslessStatus(
            active: false,
            activationFee: '1',
          ),
        ),
      );
      addTearDown(inactiveBloc.close);

      await tester.pumpWidget(_buildTestWidget(inactiveBloc));
      expect(
        find.byKey(const Key('withdraw-gasless-activation-banner')),
        findsOneWidget,
      );

      final activeBloc = _FakeWithdrawFormBloc(
        _trc20FillState(gaslessAccountStatus: _gaslessStatus()),
      );
      addTearDown(activeBloc.close);

      await tester.pumpWidget(_buildTestWidget(activeBloc));
      expect(
        find.byKey(const Key('withdraw-gasless-activation-banner')),
        findsNothing,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('provider-unavailable notice blocks preview and can retry', (
      tester,
    ) async {
      final bloc = _FakeWithdrawFormBloc(
        _trc20FillState(
          gaslessAccountStatus: _gaslessStatus(
            providerAvailable: false,
            active: null,
            transferFee: null,
          ),
        ),
      );
      addTearDown(bloc.close);

      await tester.pumpWidget(_buildTestWidget(bloc));

      expect(
        find.byKey(const Key('gasless-provider-unavailable-notice')),
        findsOneWidget,
      );
      final previewButton = tester.widget<PreviewWithdrawButton>(
        find.byType(PreviewWithdrawButton),
      );
      expect(previewButton.onPressed, isNull);

      await tester.ensureVisible(
        find.byKey(const Key('gasless-provider-unavailable-retry')),
      );
      await tester.tap(
        find.byKey(const Key('gasless-provider-unavailable-retry')),
      );
      final retry = bloc.events
          .whereType<WithdrawFormGaslessStatusRequested>()
          .single;
      expect(retry.force, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Trezor sees the honest hardware notice instead of gasless', (
      tester,
    ) async {
      final bloc = _FakeWithdrawFormBloc(
        _trc20FillState(walletType: WalletType.trezor),
      );
      addTearDown(bloc.close);

      await tester.pumpWidget(_buildTestWidget(bloc));

      expect(
        find.byKey(const Key('withdraw-gasless-trezor-notice')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('withdraw-gasless-chip')), findsNothing);
      expect(find.byKey(const Key('withdraw-advanced-section')), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

void main() {
  testWithdrawFormFillSection();
}

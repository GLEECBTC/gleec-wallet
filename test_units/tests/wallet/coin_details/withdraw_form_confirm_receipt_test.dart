import 'package:app_theme/app_theme.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/withdraw_form/withdraw_form_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/model/wallet.dart' show WalletType;
import 'package:web_dex/views/wallet/coin_details/withdraw_form/withdraw_form.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/widgets/gasless_balance_breakdown.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/widgets/gasless_pending_transfer_panel.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/widgets/send_complete_form/send_complete_form_buttons.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/widgets/send_confirm_form/send_confirm_buttons.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/widgets/send_confirm_form/send_confirm_item.dart';

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

Asset _trc20Asset() {
  final parent = Asset.fromJson(_trxConfig(), knownIds: const {});
  return Asset.fromJson(_trc20Config(), knownIds: {parent.id});
}

Asset _utxoAsset() => Asset.fromJson(_utxoConfig(), knownIds: const {});

BalanceChanges _balanceChanges({required String spent, String received = '0'}) {
  final spentByMe = Decimal.parse(spent);
  final receivedByMe = Decimal.parse(received);
  return BalanceChanges(
    netChange: receivedByMe - spentByMe,
    receivedByMe: receivedByMe,
    spentByMe: spentByMe,
    totalAmount: spentByMe,
  );
}

FeeInfoTronGasless _gaslessFee({
  String totalTokenFee = '1.5',
  String signedMaxFee = '2',
  String? activationFee,
}) {
  final fee = Decimal.parse(totalTokenFee);
  return FeeInfoTronGasless(
    coin: 'USDT-TRC20',
    feeMethod: 'gasless',
    providerName: 'gasfree',
    gasfreeAddress: 'TGasFreeSourceAddress',
    transferFee: fee,
    totalTokenFee: fee,
    signedMaxFee: Decimal.parse(signedMaxFee),
    activationFee: activationFee == null ? null : Decimal.parse(activationFee),
  );
}

WithdrawResult _result({
  required BalanceChanges balanceChanges,
  required FeeInfo fee,
  String coin = 'USDT-TRC20',
  int blockHeight = 0,
  int timestamp = 0,
}) {
  return WithdrawResult(
    txHex: 'deadbeef',
    txHash: 'test-tx-hash',
    from: const ['TRegularSourceAddress'],
    to: const ['TRecipientAddress'],
    balanceChanges: balanceChanges,
    blockHeight: blockHeight,
    timestamp: timestamp,
    fee: fee,
    coin: coin,
  );
}

class _FakeMarketData implements MarketDataManager {
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
  _FakeSdk();

  @override
  final MarketDataManager marketData = _FakeMarketData();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWithdrawFormBloc extends Cubit<WithdrawFormState>
    implements WithdrawFormBloc {
  _FakeWithdrawFormBloc(super.initialState);

  void update(WithdrawFormState state) => emit(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _wrap(Widget child) {
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(size: Size(1280, 1200)),
      child: Builder(
        builder: (context) {
          updateScreenType(context);
          return RepositoryProvider<KomodoDefiSdk>.value(
            value: _FakeSdk(),
            child: Scaffold(body: SingleChildScrollView(child: child)),
          );
        },
      ),
    ),
  );
}

Future<void> _pumpNarrowLargeText(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    ),
  );
  await tester.pump();
}

Widget _responsiveLifecycleSurface({
  required Widget child,
  required WithdrawFormBloc bloc,
  required ThemeMode themeMode,
  bool disableAnimations = false,
}) {
  final selectedTheme = themeMode == ThemeMode.dark
      ? newThemeDark
      : newThemeLight;
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: disableAnimations),
      child: child!,
    ),
    theme: selectedTheme,
    darkTheme: selectedTheme,
    themeMode: themeMode,
    themeAnimationDuration: Duration.zero,
    home: Builder(
      builder: (context) {
        updateScreenType(context);
        return RepositoryProvider<KomodoDefiSdk>.value(
          value: _FakeSdk(),
          child: BlocProvider<WithdrawFormBloc>.value(
            value: bloc,
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: child,
              ),
            ),
          ),
        );
      },
    ),
  );
}

Future<void> _syncScreenTypeToTestView(WidgetTester tester) async {
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

WithdrawFormState _gaslessConfirmState() => WithdrawFormState(
  asset: _trc20Asset(),
  step: WithdrawFormStep.confirm,
  walletType: WalletType.hdwallet,
  recipientAddress: 'TRecipientAddress',
  amount: '10',
  isGaslessFeatureConfigured: true,
  isGaslessEnabled: true,
  gaslessAvailability: GaslessAvailability.ready,
  authorizedRecipientAmount: Decimal.parse('10'),
  previewSecondsRemaining: 45,
  preview: _result(
    balanceChanges: _balanceChanges(spent: '11.5'),
    fee: _gaslessFee(signedMaxFee: '2'),
  ),
);

WithdrawalResult _confirmedGaslessResult({
  String traceId = 'trace-responsive-1',
  String? finalFee = '1.25',
}) {
  final preview = _result(
    balanceChanges: _balanceChanges(spent: '11.5'),
    fee: _gaslessFee(signedMaxFee: '2', activationFee: '0.5'),
    blockHeight: 76543210,
    timestamp: 1720000000,
  );
  return WithdrawalResult(
    txHash: preview.txHash,
    balanceChanges: preview.balanceChanges,
    coin: preview.coin,
    toAddress: preview.to.first,
    fee: preview.fee,
    confirmationBlockHeight: preview.blockHeight,
    confirmedAt: DateTime.fromMillisecondsSinceEpoch(
      preview.timestamp * Duration.millisecondsPerSecond,
      isUtc: true,
    ),
    gaslessFinalFee: finalFee == null ? null : Decimal.parse(finalFee),
    gaslessTraceId: traceId,
  );
}

WithdrawFormState _gaslessConfirmedState() => WithdrawFormState(
  asset: _trc20Asset(),
  step: WithdrawFormStep.success,
  walletType: WalletType.hdwallet,
  recipientAddress: 'TRecipientAddress',
  amount: '10',
  isGaslessFeatureConfigured: true,
  isGaslessEnabled: true,
  gaslessAvailability: GaslessAvailability.ready,
  authorizedRecipientAmount: Decimal.parse('10'),
  gaslessTransferState: GaslessTransferState.confirmed,
  gaslessTraceId: 'trace-responsive-1',
  result: _confirmedGaslessResult(),
);

WithdrawFormState _gaslessUnresolvedState({required bool submittedUnknown}) =>
    WithdrawFormState(
      asset: _trc20Asset(),
      step: WithdrawFormStep.pending,
      walletType: WalletType.hdwallet,
      recipientAddress: 'TRecipientAddress',
      amount: '10',
      isGaslessFeatureConfigured: true,
      isGaslessEnabled: true,
      gaslessAvailability: GaslessAvailability.pendingTransfer,
      gaslessTransferState: submittedUnknown
          ? GaslessTransferState.submittedUnknown
          : GaslessTransferState.submittedPending,
      gaslessTraceId: submittedUnknown ? null : 'trace-responsive-pending',
      gaslessJournalId: 'journal-responsive-pending',
      gaslessSubmittedAt: DateTime.utc(2026, 7, 16, 12),
    );

void testWithdrawFormConfirmReceipt() {
  group('WithdrawPreviewDetails (confirm summary)', () {
    testWidgets(
      'gas-free preview headlines the recipient amount, not amount+fee',
      (tester) async {
        // User typed 10; KDF reports spent_by_me = amount + token fee = 11.5.
        final state = WithdrawFormState(
          asset: _trc20Asset(),
          step: WithdrawFormStep.confirm,
          recipientAddress: 'TRecipientAddress',
          amount: '10',
          isGaslessEnabled: true,
          isGaslessFeatureConfigured: true,
          authorizedRecipientAmount: Decimal.parse('10'),
          preview: _result(
            balanceChanges: _balanceChanges(spent: '11.5'),
            fee: _gaslessFee(),
          ),
        );

        await tester.pumpWidget(_wrap(WithdrawPreviewDetails(state: state)));

        expect(find.text('withdrawRecipientGets'), findsOneWidget);
        expect(find.text('youSend'), findsNothing);
        expect(find.textContaining('10 USDT'), findsWidgets);
        expect(find.textContaining('11.5 USDT'), findsNothing);
        expect(
          find.byKey(const Key('withdraw-gasless-total-deducted')),
          findsOneWidget,
        );
        // Fee box shows the token fee with a clean ticker.
        expect(find.textContaining('1.5 USDT'), findsWidgets);
        // GasFree fee presentation does not apply a local threshold.
        expect(find.text('withdrawHighFee'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));
      },
    );

    testWidgets('does not invent a local GasFree fee warning', (tester) async {
      final state = WithdrawFormState(
        asset: _trc20Asset(),
        step: WithdrawFormStep.confirm,
        recipientAddress: 'TRecipientAddress',
        amount: '2',
        isGaslessEnabled: true,
        isGaslessFeatureConfigured: true,
        authorizedRecipientAmount: Decimal.parse('2'),
        preview: _result(
          balanceChanges: _balanceChanges(spent: '3.5'),
          fee: _gaslessFee(),
        ),
      );

      await tester.pumpWidget(_wrap(WithdrawPreviewDetails(state: state)));

      expect(find.text('withdrawHighFee'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('non-gasless preview keeps the existing summary', (
      tester,
    ) async {
      final state = WithdrawFormState(
        asset: _utxoAsset(),
        step: WithdrawFormStep.confirm,
        recipientAddress: 'recipient',
        amount: '1',
        isGaslessFeatureConfigured: false,
        preview: _result(
          balanceChanges: _balanceChanges(spent: '1'),
          fee: FeeInfoUtxoFixed(coin: 'KMD', amount: Decimal.parse('0.0001')),
          coin: 'KMD',
        ),
      );

      await tester.pumpWidget(_wrap(WithdrawPreviewDetails(state: state)));

      expect(find.text('youSend'), findsOneWidget);
      expect(find.text('withdrawRecipientGets'), findsNothing);
      expect(
        find.byKey(const Key('withdraw-gasless-total-deducted')),
        findsNothing,
      );
      expect(find.textContaining('1 KMD'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('WithdrawSuccessReceipt', () {
    testWidgets(
      'gas-free receipt shows recipient amount, total deducted and on-chain '
      'finality',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            WithdrawSuccessReceipt(
              asset: _trc20Asset(),
              result: _confirmedGaslessResult(traceId: 'trace-receipt-1'),
              recipientAmount: Decimal.parse('10'),
              onClose: () {},
            ),
          ),
        );

        expect(find.textContaining('10 USDT'), findsWidgets);
        expect(
          find.byKey(const Key('withdraw-receipt-total-deducted')),
          findsOneWidget,
        );
        // The relay only completes after on-chain confirmation, so the
        // receipt must not claim we are still awaiting confirmations.
        expect(
          find.byKey(const Key('withdraw-gasless-confirmed-chip')),
          findsOneWidget,
        );
        expect(find.text('withdrawGaslessConfirmedOnChain'), findsOneWidget);
        expect(find.text('withdrawAwaitingConfirmations'), findsNothing);

        await tester.tap(find.text('technicalDetails'));
        await tester.pumpAndSettle();
        expect(find.text('withdrawGaslessFinalFee'), findsOneWidget);
        expect(find.text('withdrawGaslessMaxFee'), findsOneWidget);
        expect(find.text('withdrawGaslessActivationFee'), findsOneWidget);
        expect(find.text('withdrawGaslessConfirmationTime'), findsOneWidget);
        expect(find.text('withdrawGaslessConfirmationBlock'), findsOneWidget);
        expect(find.text('76543210'), findsOneWidget);
        expect(find.text('withdrawGaslessTraceId'), findsOneWidget);
        expect(find.textContaining('1.25 USDT'), findsWidgets);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));
      },
    );

    testWidgets('gas-free receipt does not label a preview fee as final', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          WithdrawSuccessReceipt(
            asset: _trc20Asset(),
            result: _confirmedGaslessResult(
              traceId: 'trace-without-final-fee',
              finalFee: null,
            ),
            recipientAmount: Decimal.parse('10'),
            onClose: () {},
          ),
        ),
      );

      await tester.tap(find.text('technicalDetails'));
      await tester.pumpAndSettle();

      expect(find.text('withdrawGaslessFinalFee'), findsNothing);
      expect(find.text('withdrawGaslessMaxFee'), findsOneWidget);
      expect(find.text('withdrawGaslessTransferFee'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('standard receipt keeps the awaiting-confirmations chip', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          WithdrawSuccessReceipt(
            asset: _utxoAsset(),
            result: WithdrawalResult.fromWithdrawResult(
              _result(
                balanceChanges: _balanceChanges(spent: '1'),
                fee: FeeInfoUtxoFixed(
                  coin: 'KMD',
                  amount: Decimal.parse('0.0001'),
                ),
                coin: 'KMD',
              ),
            ),
            onClose: () {},
          ),
        ),
      );

      expect(find.text('withdrawAwaitingConfirmations'), findsOneWidget);
      expect(
        find.byKey(const Key('withdraw-gasless-confirmed-chip')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('withdraw-receipt-total-deducted')),
        findsNothing,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('zero-net wallet-internal move shows the moved amount, not 0', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          WithdrawSuccessReceipt(
            asset: _utxoAsset(),
            result: WithdrawalResult.fromWithdrawResult(
              _result(
                balanceChanges: _balanceChanges(spent: '10', received: '10'),
                fee: FeeInfoUtxoFixed(
                  coin: 'KMD',
                  amount: Decimal.parse('0.0001'),
                ),
                coin: 'KMD',
              ),
            ),
            onClose: () {},
          ),
        ),
      );

      expect(find.textContaining('10 KMD'), findsWidgets);
      expect(find.text('0 KMD'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('GasFree responsive lifecycle surfaces', () {
    Future<void> expectLifecycleAtViewport(
      WidgetTester tester, {
      required Size size,
      required ThemeMode themeMode,
      required Brightness brightness,
      required IconData destinationDirection,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _syncScreenTypeToTestView(tester);
      addTearDown(() async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1;
        await _syncScreenTypeToTestView(tester);
      });

      final bloc = _FakeWithdrawFormBloc(_gaslessConfirmState());
      addTearDown(bloc.close);

      Future<void> pumpSurface(Widget child) async {
        await tester.pumpWidget(
          _responsiveLifecycleSurface(
            child: child,
            bloc: bloc,
            themeMode: themeMode,
          ),
        );
        await tester.pump();
      }

      await pumpSurface(const WithdrawFormConfirmSection());
      expect(
        Theme.of(
          tester.element(find.byType(WithdrawFormConfirmSection)),
        ).brightness,
        brightness,
      );
      expect(find.text('withdrawRecipientGets'), findsOneWidget);
      expect(
        find.byKey(const Key('withdraw-gasless-total-deducted')),
        findsOneWidget,
      );
      expect(find.text('withdrawPreviewExpiresIn'), findsOneWidget);
      expect(find.byIcon(destinationDirection), findsOneWidget);
      expect(tester.takeException(), isNull);

      bloc.update(_gaslessConfirmedState());
      await pumpSurface(WithdrawFormSuccessSection(onDone: _noop));
      expect(
        Theme.of(
          tester.element(find.byType(WithdrawFormSuccessSection)),
        ).brightness,
        brightness,
      );
      expect(
        find.byKey(const Key('withdraw-gasless-confirmed-chip')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('withdraw-receipt-total-deducted')),
        findsOneWidget,
      );
      expect(find.text('withdrawAwaitingConfirmations'), findsNothing);
      await tester.ensureVisible(find.text('technicalDetails'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('technicalDetails'));
      await tester.pumpAndSettle();
      expect(find.text('withdrawGaslessConfirmationBlock'), findsOneWidget);
      expect(tester.takeException(), isNull);

      bloc.update(_gaslessUnresolvedState(submittedUnknown: true));
      await pumpSurface(WithdrawFormPendingSection(onViewActivity: _noop));
      expect(
        Theme.of(
          tester.element(find.byType(WithdrawFormPendingSection)),
        ).brightness,
        brightness,
      );
      expect(
        find.text('withdrawGaslessAcceptanceUnknownTitle'),
        findsOneWidget,
      );
      expect(
        find.text('withdrawGaslessAcceptanceUnknownDescription'),
        findsOneWidget,
      );
      expect(find.text('withdrawGaslessPendingTitle'), findsNothing);
      expect(find.text('withdrawGaslessContinueChecking'), findsNothing);
      expect(find.textContaining('trace-responsive-pending'), findsNothing);
      expect(find.textContaining('journal-responsive-pending'), findsNothing);
      expect(tester.takeException(), isNull);

      bloc.update(_gaslessUnresolvedState(submittedUnknown: false));
      await pumpSurface(WithdrawFormPendingSection(onViewActivity: _noop));
      expect(find.text('withdrawGaslessPendingTitle'), findsOneWidget);
      expect(find.text('withdrawGaslessPendingDescription'), findsOneWidget);
      expect(find.text('withdrawGaslessAcceptanceUnknownTitle'), findsNothing);
      expect(find.textContaining('trace-responsive-pending'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // AssetAmountWithFiat internally owns a delayed auto-scroll check even
      // when scrolling is disabled. Dispose every surface and advance past
      // that delay so the test leaves no framework timers behind.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    }

    testWidgets(
      'confirm, confirmed receipt and submitted-unknown/pending fit 375px '
      'light',
      (tester) => expectLifecycleAtViewport(
        tester,
        size: const Size(375, 812),
        themeMode: ThemeMode.light,
        brightness: Brightness.light,
        destinationDirection: Icons.south_rounded,
      ),
    );

    testWidgets(
      'confirm, confirmed receipt and submitted-unknown/pending fit 768px '
      'dark',
      (tester) => expectLifecycleAtViewport(
        tester,
        size: const Size(768, 1024),
        themeMode: ThemeMode.dark,
        brightness: Brightness.dark,
        destinationDirection: Icons.arrow_forward_rounded,
      ),
    );

    testWidgets('relay and pending states honor reduced motion', (
      tester,
    ) async {
      final relayingState = _gaslessConfirmState().copyWith(
        isSending: true,
        gaslessStatusMessage: () => 'accepted',
        gaslessTraceState: () => GaslessTraceState.submitted,
        gaslessTransferState: () => GaslessTransferState.submittedPending,
        gaslessTraceId: () => 'trace-reduced-motion',
      );
      final bloc = _FakeWithdrawFormBloc(relayingState);
      addTearDown(bloc.close);

      Future<void> pumpSurface(Widget child) async {
        await tester.pumpWidget(
          _responsiveLifecycleSurface(
            child: child,
            bloc: bloc,
            themeMode: ThemeMode.light,
            disableAnimations: true,
          ),
        );
        await tester.pump();
      }

      await pumpSurface(const WithdrawFormConfirmSection());
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
      expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);

      bloc.update(
        _gaslessUnresolvedState(
          submittedUnknown: false,
        ).copyWith(isSending: true),
      );
      await pumpSurface(WithdrawFormPendingSection(onViewActivity: _noop));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.byKey(const Key('gasless-pending-static-progress')),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('GasFree accessibility and narrow layout', () {
    testWidgets(
      'pending trace remains scroll-safe with 320px width and 200% text',
      (tester) async {
        final semantics = tester.ensureSemantics();

        await _pumpNarrowLargeText(
          tester,
          GaslessPendingTransferPanel(
            title: 'Transfer still processing',
            description:
                'The relay accepted this transfer and it may still confirm.',
            continueLabel: 'Continue checking transfer status',
            activityLabel: 'View pending transfer activity',
            supportLabel: 'Contact support',
            traceLabel: 'Trace ID',
            traceId: '4f8f4bea-f0d6-49ad-a02f-e871408b6b22',
            isChecking: false,
            onContinueChecking: () {},
            onViewActivity: () {},
            onSupport: () {},
          ),
        );

        expect(tester.takeException(), isNull);
        expect(
          find.bySemanticsLabel(
            'Transfer still processing. '
            'The relay accepted this transfer and it may still confirm.',
          ),
          findsOneWidget,
        );
        for (final button in [
          find.ancestor(
            of: find.text('Continue checking transfer status'),
            matching: find.byType(FilledButton),
          ),
          find.ancestor(
            of: find.text('View pending transfer activity'),
            matching: find.byType(OutlinedButton),
          ),
          find.ancestor(
            of: find.text('Contact support'),
            matching: find.byType(TextButton),
          ),
        ]) {
          expect(tester.getRect(button).height, greaterThanOrEqualTo(48));
        }
        semantics.dispose();
      },
    );

    testWidgets('journal-only pending state cannot start trace reconciliation', (
      tester,
    ) async {
      var continueChecks = 0;
      var activityViews = 0;

      await _pumpNarrowLargeText(
        tester,
        GaslessPendingTransferPanel(
          title: 'Transfer still processing',
          description:
              'Relay acceptance is unknown and no provider trace is available.',
          continueLabel: 'Continue checking',
          activityLabel: 'View activity',
          supportLabel: 'Contact support',
          traceLabel: 'Trace ID',
          isChecking: false,
          onContinueChecking: () => continueChecks++,
          onViewActivity: () => activityViews++,
          onSupport: () {},
        ),
      );

      expect(find.text('Continue checking'), findsNothing);
      expect(find.text('View activity'), findsOneWidget);
      expect(find.text('Contact support'), findsOneWidget);
      final activityAction = find.text('View activity');
      await tester.ensureVisible(activityAction);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(activityAction);
      expect(activityViews, 1);
      expect(continueChecks, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('balance values and labels use their theme foreground roles', (
      tester,
    ) async {
      const balanceBreakdown = GaslessBalanceBreakdown(
        total: '10',
        spendable: '8',
        pending: '2',
        symbol: 'USDT',
        totalLabel: 'Gas-free total',
        spendableLabel: 'Spendable',
        pendingLabel: 'Pending / locked',
      );
      const amountTexts = <String>['10 USDT', '8 USDT', '2 USDT'];
      const labelTexts = <String>[
        'Gas-free total',
        'Spendable',
        'Pending / locked',
      ];

      for (final theme in <ThemeData>[newThemeLight, newThemeDark]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            darkTheme: theme,
            themeMode: theme.brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            themeAnimationDuration: Duration.zero,
            home: const Material(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: balanceBreakdown,
              ),
            ),
          ),
        );

        for (final amountText in amountTexts) {
          final text = tester.widget<Text>(find.text(amountText));
          expect(text.style?.color, theme.textTheme.bodyMedium?.color);
          expect(text.style?.color, isNot(theme.colorScheme.onSurface));
        }
        for (final labelText in labelTexts) {
          final text = tester.widget<Text>(find.text(labelText));
          expect(text.style?.color, theme.colorScheme.onSurfaceVariant);
        }
      }
    });

    testWidgets('balance values and confirmation items wrap at 200% text', (
      tester,
    ) async {
      const longAmount = '12345678901234567890.123456789';
      await _pumpNarrowLargeText(
        tester,
        const Column(
          children: [
            GaslessBalanceBreakdown(
              total: longAmount,
              spendable: '12345678901234567889.123456789',
              pending: '1.000000000',
              symbol: 'USDT-TRC20',
              totalLabel: 'Gas-free custody total',
              spendableLabel: 'Sendable after provider fees',
              pendingLabel: 'Pending and locked funds',
            ),
            SizedBox(height: 16),
            SendConfirmItem(
              title: 'Recipient amount authorized',
              value: '$longAmount USDT-TRC20',
              usdPrice: 1234567890.12,
            ),
            SizedBox(height: 16),
            SendConfirmButtons(hasSendError: false, onBackTap: _noop),
          ],
        ),
      );

      expect(find.text('$longAmount USDT-TRC20'), findsWidgets);
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.byKey(const Key('confirm-back-button'))).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getRect(find.byKey(const Key('confirm-agree-button'))).height,
        greaterThanOrEqualTo(48),
      );
    });

    testWidgets(
      'desktop confirmation and completion targets are at least 48dp',
      (tester) async {
        final asset = _utxoAsset();
        final bloc = _FakeWithdrawFormBloc(
          WithdrawFormState(
            asset: asset,
            step: WithdrawFormStep.success,
            recipientAddress: 'recipient',
            amount: '1',
            isGaslessFeatureConfigured: false,
            result: WithdrawalResult.fromWithdrawResult(
              _result(
                balanceChanges: _balanceChanges(spent: '1'),
                fee: FeeInfo.utxoFixed(
                  coin: asset.id.id,
                  amount: Decimal.parse('0.0001'),
                ),
                coin: asset.id.id,
              ),
            ),
          ),
        );
        addTearDown(bloc.close);

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(size: Size(1280, 900)),
              child: Builder(
                builder: (context) {
                  updateScreenType(context);
                  return BlocProvider<WithdrawFormBloc>.value(
                    value: bloc,
                    child: const Scaffold(
                      body: Column(
                        children: [
                          SendConfirmButtons(
                            hasSendError: false,
                            onBackTap: _noop,
                          ),
                          SendCompleteFormButtons(),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );

        for (final key in [
          const Key('confirm-back-button'),
          const Key('confirm-agree-button'),
          const Key('send-complete-done'),
        ]) {
          expect(
            tester.getRect(find.byKey(key)).height,
            greaterThanOrEqualTo(48),
          );
        }
      },
    );
  });
}

void _noop() {}

void main() {
  testWithdrawFormConfirmReceipt();
}

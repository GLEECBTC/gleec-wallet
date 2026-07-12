import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/withdraw_form/withdraw_form_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/withdraw_form.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/widgets/gasless_balance_breakdown.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/widgets/gasless_pending_transfer_panel.dart';
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
  String? finalFee,
  String? signedMaxFee,
  String? activationFee,
  String? traceId,
}) {
  final fee = Decimal.parse(totalTokenFee);
  return FeeInfoTronGasless(
    coin: 'USDT-TRC20',
    feeMethod: 'gasless',
    providerName: 'gasfree',
    gasfreeAddress: 'TGasFreeSourceAddress',
    transferFee: fee,
    totalTokenFee: fee,
    finalFee: finalFee == null ? null : Decimal.parse(finalFee),
    signedMaxFee: signedMaxFee == null ? null : Decimal.parse(signedMaxFee),
    activationFee: activationFee == null ? null : Decimal.parse(activationFee),
    traceId: traceId,
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
        // 1.5 fee on a 10 send is below the 20% dominance threshold.
        expect(find.text('withdrawHighFee'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));
      },
    );

    testWidgets('warns when the flat gas-free fee dominates a small send', (
      tester,
    ) async {
      // Recipient gets 2; fee 1.5 is 75% of that.
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

      expect(find.text('withdrawHighFee'), findsOneWidget);

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
              result: WithdrawalResult.fromWithdrawResult(
                _result(
                  balanceChanges: _balanceChanges(spent: '11.5'),
                  fee: _gaslessFee(
                    finalFee: '1.25',
                    signedMaxFee: '2',
                    activationFee: '0.5',
                    traceId: 'trace-receipt-1',
                  ),
                  blockHeight: 76543210,
                  timestamp: 1720000000,
                ),
              ),
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

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));
      },
    );

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

    testWidgets('request-only pending state cannot start a trace poll', (
      tester,
    ) async {
      var continueChecks = 0;
      var activityViews = 0;

      await _pumpNarrowLargeText(
        tester,
        GaslessPendingTransferPanel(
          title: 'Transfer still processing',
          description: 'Relay acceptance is being reconciled.',
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
  });
}

void _noop() {}

void main() {
  testWithdrawFormConfirmReceipt();
}

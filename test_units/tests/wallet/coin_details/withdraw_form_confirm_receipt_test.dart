import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
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

FeeInfoTronGasless _gaslessFee({String totalTokenFee = '1.5'}) {
  final fee = Decimal.parse(totalTokenFee);
  return FeeInfoTronGasless(
    coin: 'USDT-TRC20',
    feeMethod: 'gasless',
    providerName: 'gasfree',
    gasfreeAddress: 'TGasFreeSourceAddress',
    transferFee: fee,
    totalTokenFee: fee,
  );
}

WithdrawResult _result({
  required BalanceChanges balanceChanges,
  required FeeInfo fee,
  String coin = 'USDT-TRC20',
}) {
  return WithdrawResult(
    txHex: 'deadbeef',
    txHash: 'test-tx-hash',
    from: const ['TRegularSourceAddress'],
    to: const ['TRecipientAddress'],
    balanceChanges: balanceChanges,
    blockHeight: 0,
    timestamp: 0,
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
                  fee: _gaslessFee(),
                ),
              ),
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
}

void main() {
  testWithdrawFormConfirmReceipt();
}

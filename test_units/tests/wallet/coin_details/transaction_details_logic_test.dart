import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/views/wallet/coin_details/transactions/transaction_details.dart';

import 'coin_details_test_harness.dart';

Future<void> _disposeAnimatedWidgets(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 3));
}

void testTransactionDetailsLogic() {
  group('TransactionDetails logic', () {
    testWidgets('confirmations label returns count when confirmed', (
      tester,
    ) async {
      final coin = buildTestCoin();
      final tx = buildTestTransaction(
        assetId: coin.id,
        confirmations: 3,
        blockHeight: 100,
      );

      await tester.pumpWidget(
        wrapWithMaterial(
          TransactionDetails(
            coin: coin,
            transaction: tx,
            onClose: () {},
            usdPriceResolver: (_, __) => 0,
          ),
        ),
      );

      expect(find.text('3'), findsOneWidget);
      await _disposeAnimatedWidgets(tester);
    });

    testWidgets(
      'confirmations label returns zero when block height present without confirmations',
      (tester) async {
        final coin = buildTestCoin();
        final tx = buildTestTransaction(
          assetId: coin.id,
          confirmations: 0,
          blockHeight: 10,
        );

        await tester.pumpWidget(
          wrapWithMaterial(
            TransactionDetails(
              coin: coin,
              transaction: tx,
              onClose: () {},
              usdPriceResolver: (_, __) => 0,
            ),
          ),
        );

        expect(find.text('0'), findsOneWidget);
        await _disposeAnimatedWidgets(tester);
      },
    );

    testWidgets('confirmations label returns in-progress when pending', (
      tester,
    ) async {
      final coin = buildTestCoin();
      final tx = buildTestTransaction(
        assetId: coin.id,
        confirmations: 0,
        blockHeight: 0,
      );

      await tester.pumpWidget(
        wrapWithMaterial(
          TransactionDetails(
            coin: coin,
            transaction: tx,
            onClose: () {},
            usdPriceResolver: (_, __) => 0,
          ),
        ),
      );

      expect(find.text(LocaleKeys.inProgress), findsOneWidget);
      await _disposeAnimatedWidgets(tester);
    });

    testWidgets('block height label returns unknown when block is zero', (
      tester,
    ) async {
      final coin = buildTestCoin();
      final tx = buildTestTransaction(assetId: coin.id, blockHeight: 0);

      await tester.pumpWidget(
        wrapWithMaterial(
          TransactionDetails(
            coin: coin,
            transaction: tx,
            onClose: () {},
            usdPriceResolver: (_, __) => 0,
          ),
        ),
      );

      expect(find.text(LocaleKeys.unknown), findsOneWidget);
      await _disposeAnimatedWidgets(tester);
    });

    testWidgets('balance change formats plus sign for incoming', (
      tester,
    ) async {
      final coin = buildTestCoin();
      final tx = buildTestTransaction(
        assetId: coin.id,
        netChange: Decimal.parse('1.25'),
      );

      await tester.pumpWidget(
        wrapWithMaterial(
          TransactionDetails(
            coin: coin,
            transaction: tx,
            onClose: () {},
            usdPriceResolver: (_, __) => 0,
          ),
        ),
      );

      expect(find.textContaining('+'), findsOneWidget);
      await _disposeAnimatedWidgets(tester);
    });

    testWidgets('balance change formats minus sign for outgoing', (
      tester,
    ) async {
      final coin = buildTestCoin();
      final tx = buildTestTransaction(
        assetId: coin.id,
        netChange: Decimal.parse('-1.25'),
      );

      await tester.pumpWidget(
        wrapWithMaterial(
          TransactionDetails(
            coin: coin,
            transaction: tx,
            onClose: () {},
            usdPriceResolver: (_, __) => 0,
          ),
        ),
      );

      expect(find.textContaining('-'), findsWidgets);
      await _disposeAnimatedWidgets(tester);
    });

    testWidgets('balance change renders fiat amount from resolver', (
      tester,
    ) async {
      final coin = buildTestCoin();
      final tx = buildTestTransaction(assetId: coin.id);

      await tester.pumpWidget(
        wrapWithMaterial(
          TransactionDetails(
            coin: coin,
            transaction: tx,
            onClose: () {},
            usdPriceResolver: (_, __) => 0,
          ),
        ),
      );

      expect(find.textContaining(r'($0'), findsWidgets);
      await _disposeAnimatedWidgets(tester);
    });

    testWidgets('fee section renders em dash when fee is absent', (
      tester,
    ) async {
      final coin = buildTestCoin();
      final tx = buildTestTransaction(assetId: coin.id, fee: null);

      await tester.pumpWidget(
        wrapWithMaterial(
          TransactionDetails(
            coin: coin,
            transaction: tx,
            onClose: () {},
            usdPriceResolver: (_, __) => 0,
          ),
        ),
      );

      expect(find.text('—'), findsOneWidget);
      await _disposeAnimatedWidgets(tester);
    });

    testWidgets('memo section hides when empty', (tester) async {
      final coin = buildTestCoin();
      final tx = buildTestTransaction(assetId: coin.id, memo: '');

      await tester.pumpWidget(
        wrapWithMaterial(
          TransactionDetails(
            coin: coin,
            transaction: tx,
            onClose: () {},
            usdPriceResolver: (_, __) => 0,
          ),
        ),
      );

      expect(find.text('${LocaleKeys.memo}: '), findsNothing);
      await _disposeAnimatedWidgets(tester);
    });
  });
}

void main() {
  testTransactionDetailsLogic();
}

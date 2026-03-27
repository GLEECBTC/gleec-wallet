import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/transaction_history/transaction_history_bloc.dart';
import 'package:web_dex/bloc/transaction_history/transaction_history_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin_type.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/views/wallet/coin_details/transactions/transaction_details.dart';
import 'package:web_dex/views/wallet/coin_details/transactions/transaction_table.dart';

import 'coin_details_test_harness.dart';

class _FakeTransactionHistoryBloc extends Cubit<TransactionHistoryState>
    implements TransactionHistoryBloc {
  _FakeTransactionHistoryBloc(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _disposeAnimatedWidgets(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 3));
}

void testTransactionViewsWidgets() {
  group('Transaction views widgets', () {
    testWidgets('transaction table shows loading spinner while fetching', (
      tester,
    ) async {
      final coin = buildTestCoin(type: CoinType.smartChain);
      final bloc = _FakeTransactionHistoryBloc(
        const TransactionHistoryState(
          transactions: [],
          loading: true,
          error: null,
        ),
      );
      addTearDown(bloc.close);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<TransactionHistoryBloc>.value(
            value: bloc,
            child: CustomScrollView(
              slivers: [
                TransactionTable(
                  coin: coin,
                  selectedTransaction: null,
                  setTransaction: (_) {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(UiSpinnerList), findsOneWidget);
    });

    testWidgets('transaction table shows empty state without items', (
      tester,
    ) async {
      final coin = buildTestCoin(type: CoinType.smartChain);
      final bloc = _FakeTransactionHistoryBloc(
        const TransactionHistoryState.initial(),
      );
      addTearDown(bloc.close);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<TransactionHistoryBloc>.value(
            value: bloc,
            child: CustomScrollView(
              slivers: [
                TransactionTable(
                  coin: coin,
                  selectedTransaction: null,
                  setTransaction: (_) {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text(LocaleKeys.noTransactionsTitle), findsOneWidget);
    });

    testWidgets('transaction table shows error state on failure', (
      tester,
    ) async {
      final coin = buildTestCoin(type: CoinType.smartChain);
      final bloc = _FakeTransactionHistoryBloc(
        TransactionHistoryState(
          transactions: const [],
          loading: false,
          error: TextError(error: 'network failed'),
        ),
      );
      addTearDown(bloc.close);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<TransactionHistoryBloc>.value(
            value: bloc,
            child: CustomScrollView(
              slivers: [
                TransactionTable(
                  coin: coin,
                  selectedTransaction: null,
                  setTransaction: (_) {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        find.textContaining(LocaleKeys.connectionToServersFailing),
        findsOneWidget,
      );
    });

    testWidgets('transaction details done button calls onClose', (
      tester,
    ) async {
      final coin = buildTestCoin();
      final tx = buildTestTransaction(assetId: coin.id);
      var didClose = false;

      await tester.pumpWidget(
        wrapWithMaterial(
          TransactionDetails(
            coin: coin,
            transaction: tx,
            onClose: () => didClose = true,
            usdPriceResolver: (_, __) => 0,
          ),
        ),
      );

      await tester.tap(find.text(LocaleKeys.done).first);
      await tester.pump();

      expect(didClose, isTrue);
      await _disposeAnimatedWidgets(tester);
    });

    testWidgets('transaction details view on explorer uses tx hash', (
      tester,
    ) async {
      final coin = buildTestCoin();
      final tx = buildTestTransaction(assetId: coin.id, txHash: 'abc-hash');
      String? launched;

      await tester.pumpWidget(
        wrapWithMaterial(
          TransactionDetails(
            coin: coin,
            transaction: tx,
            onClose: () {},
            usdPriceResolver: (_, __) => 0,
            onLaunchExplorer: (url) => launched = url,
          ),
        ),
      );

      await tester.tap(find.text(LocaleKeys.viewOnExplorer).first);
      await tester.pump();

      expect(launched, isNotNull);
      expect(launched, contains('abc-hash'));
      await _disposeAnimatedWidgets(tester);
    });
  });
}

void main() {
  testTransactionViewsWidgets();
}

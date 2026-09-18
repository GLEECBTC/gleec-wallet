import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/transaction_history/transaction_history_bloc.dart';
import 'package:web_dex/bloc/transaction_history/transaction_history_event.dart';
import 'package:web_dex/bloc/transaction_history/transaction_history_state.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin_type.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/views/wallet/coin_details/transactions/transaction_details.dart';
import 'package:web_dex/views/wallet/coin_details/transactions/transaction_list_item.dart';
import 'package:web_dex/views/wallet/coin_details/transactions/transaction_table.dart';

import 'coin_details_test_harness.dart';

class _FakeTransactionHistoryBloc extends Cubit<TransactionHistoryState>
    implements TransactionHistoryBloc {
  _FakeTransactionHistoryBloc(super.initialState);

  final events = <TransactionHistoryEvent>[];

  @override
  void add(TransactionHistoryEvent event) => events.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCoinsBloc extends Cubit<CoinsState> implements CoinsBloc {
  _FakeCoinsBloc() : super(CoinsState.initial());

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
      expect(
        find.byKey(const Key('transaction-history-retry')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('transaction-history-retry')));
      expect(bloc.events, hasLength(1));
      expect(bloc.events.single, isA<TransactionHistorySubscribe>());
    });

    testWidgets('transaction row labels net-zero transfer as internal move', (
      tester,
    ) async {
      final coin = buildTestCoin(type: CoinType.smartChain);
      final tx = buildTestTransaction(
        assetId: coin.id,
        netChange: Decimal.zero,
        spentByMe: Decimal.parse('12.5'),
        receivedByMe: Decimal.parse('12.5'),
        from: const ['eoa-address'],
        to: const ['custody-address'],
      );
      final coinsBloc = _FakeCoinsBloc();
      addTearDown(coinsBloc.close);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider<CoinsBloc>.value(
              value: coinsBloc,
              child: TransactionListRow(
                transaction: tx,
                coinAbbr: coin.abbr,
                setTransaction: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.text(LocaleKeys.txInternalTransfer), findsOneWidget);
      expect(find.text(LocaleKeys.receive), findsNothing);
      expect(find.text(LocaleKeys.send), findsNothing);
      expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
      // Unsigned amounts: magnitude without a +/- prefix (a directional row
      // would render '+ $...' or '- $...' in the USD column).
      expect(find.textContaining('12.5'), findsWidgets);
      expect(find.text(r'$0.00'), findsOneWidget);
      expect(find.textContaining('+'), findsNothing);
      expect(find.textContaining(r'- $'), findsNothing);
      // The destination (custody) address is shown, not the sender.
      expect(find.textContaining('custody-address'), findsWidgets);
      expect(find.textContaining('eoa-address'), findsNothing);
      await _disposeAnimatedWidgets(tester);
    });

    testWidgets('internal-transfer label fits a phone-width mobile row', (
      tester,
    ) async {
      // Regression: the (long) internal-transfer label used to overflow the
      // mobile row by ~84px at 375px width (RenderFlex overflow).
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final coin = buildTestCoin(type: CoinType.smartChain);
      final tx = buildTestTransaction(
        assetId: coin.id,
        netChange: Decimal.zero,
        spentByMe: Decimal.parse('12.5'),
        receivedByMe: Decimal.parse('12.5'),
        from: const ['eoa-address'],
        to: const ['custody-address'],
      );
      final coinsBloc = _FakeCoinsBloc();
      addTearDown(coinsBloc.close);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(375, 812)),
            child: Builder(
              builder: (context) {
                // Pin the screen-type global to this phone-sized viewport —
                // earlier suites in the aggregated run leave it desktop,
                // which would render the desktop row here instead of the
                // mobile layout under test.
                updateScreenType(context);
                return Scaffold(
                  body: BlocProvider<CoinsBloc>.value(
                    value: coinsBloc,
                    child: TransactionListRow(
                      transaction: tx,
                      coinAbbr: coin.abbr,
                      setTransaction: (_) {},
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text(LocaleKeys.txInternalTransfer), findsOneWidget);
      await _disposeAnimatedWidgets(tester);
    });

    testWidgets('transaction row still labels positive-net tx as receive', (
      tester,
    ) async {
      final coin = buildTestCoin(type: CoinType.smartChain);
      final tx = buildTestTransaction(
        assetId: coin.id,
        netChange: Decimal.parse('2.0'),
        spentByMe: Decimal.zero,
        receivedByMe: Decimal.parse('2.0'),
      );
      final coinsBloc = _FakeCoinsBloc();
      addTearDown(coinsBloc.close);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider<CoinsBloc>.value(
              value: coinsBloc,
              child: TransactionListRow(
                transaction: tx,
                coinAbbr: coin.abbr,
                setTransaction: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.text(LocaleKeys.receive), findsOneWidget);
      expect(find.text(LocaleKeys.txInternalTransfer), findsNothing);
      expect(find.byIcon(Icons.arrow_circle_down), findsOneWidget);
      await _disposeAnimatedWidgets(tester);
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

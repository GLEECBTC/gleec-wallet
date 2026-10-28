import 'package:decimal/decimal.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/model/cex_price.dart';
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
  _FakeCoinsBloc([CoinsState? state]) : super(state ?? CoinsState.initial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void testTransactionViewsWidgets() {
  group('Transaction views widgets', () {
    for (final (name, net, spent, received, label) in [
      ('outgoing net-only proxy row', '-1', '0', '0', LocaleKeys.send),
      ('incoming component-only row', '0', '0', '2', LocaleKeys.receive),
      ('unknown gross movement', '0', '0', '0', LocaleKeys.unknown),
      (
        'native self-transfer plus fee',
        '-0.01',
        '1.01',
        '1',
        LocaleKeys.txInternalTransfer,
      ),
    ]) {
      testWidgets('$name preserves direction without inventing fiat', (
        tester,
      ) async {
        final coin = buildTestCoin();
        final tx = buildTestTransaction(
          assetId: coin.id,
          netChange: Decimal.parse(net),
          spentByMe: Decimal.parse(spent),
          receivedByMe: Decimal.parse(received),
          fee: FeeInfo.utxoFixed(
            coin: coin.abbr,
            amount: Decimal.parse('0.01'),
          ),
        );
        final coins = _FakeCoinsBloc();
        addTearDown(coins.close);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BlocProvider<CoinsBloc>.value(
                value: coins,
                child: TransactionListRow(
                  transaction: tx,
                  setTransaction: (_) {},
                  coinAbbr: coin.abbr,
                ),
              ),
            ),
          ),
        );
        expect(find.text(label), findsOneWidget);
        if (label != LocaleKeys.receive) {
          expect(find.text(LocaleKeys.receive), findsNothing);
        } else {
          expect(find.textContaining('to-address'), findsWidgets);
          expect(find.textContaining('from-address'), findsNothing);
        }
        expect(find.text('—'), findsOneWidget);
        expect(find.textContaining(r'$0.00'), findsNothing);
      });
    }

    for (final price in ['1', '0']) {
      testWidgets(
        'token history resolves normalized price $price and preserves real zero',
        (tester) async {
          final coin = buildTestCoin(abbr: 'USDC-PLG20');
          final tx = buildTestTransaction(
            assetId: coin.id,
            netChange: Decimal.parse('-2'),
          );
          final coins = _FakeCoinsBloc(
            CoinsState.initial().copyWith(
              prices: {
                'USDC': CexPrice(
                  assetId: coin.id,
                  price: Decimal.parse(price),
                  change24h: null,
                  lastUpdated: DateTime.utc(2026, 10, 28),
                ),
              },
            ),
          );
          addTearDown(coins.close);
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: BlocProvider<CoinsBloc>.value(
                  value: coins,
                  child: TransactionListRow(
                    transaction: tx,
                    setTransaction: (_) {},
                    coinAbbr: coin.abbr,
                  ),
                ),
              ),
            ),
          );
          expect(
            find.text(price == '0' ? r'- $0.00' : r'- $2.00'),
            findsOneWidget,
          );
          expect(find.text('—'), findsNothing);
        },
      );
    }

    testWidgets(
      'unknown detail valuations stay unavailable for principal and fee',
      (tester) async {
        final coin = buildTestCoin();
        final tx = buildTestTransaction(
          assetId: coin.id,
          fee: FeeInfo.utxoFixed(
            coin: coin.abbr,
            amount: Decimal.parse('0.01'),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TransactionDetails(
                transaction: tx,
                coin: coin,
                onClose: () {},
                usdPriceResolver: (_, __) => null,
              ),
            ),
          ),
        );
        expect(find.textContaining('(—)'), findsNWidgets(2));
        expect(find.textContaining(r'$0.00'), findsNothing);
      },
    );

    testWidgets('details use credit components when the net field is absent', (
      tester,
    ) async {
      final coin = buildTestCoin();
      final tx = buildTestTransaction(
        assetId: coin.id,
        netChange: Decimal.zero,
        receivedByMe: Decimal.fromInt(2),
        spentByMe: Decimal.zero,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransactionDetails(
              transaction: tx,
              coin: coin,
              onClose: () {},
              usdPriceResolver: (_, __) => null,
            ),
          ),
        ),
      );
      expect(find.textContaining('+ 2 KMD'), findsOneWidget);
      expect(find.textContaining('- 2 KMD'), findsNothing);
    });

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
      expect(find.text('—'), findsOneWidget);
      expect(find.textContaining('+'), findsNothing);
      expect(find.textContaining(r'- $'), findsNothing);
      // The destination (custody) address is shown, not the sender.
      expect(find.textContaining('custody-address'), findsWidgets);
      expect(find.textContaining('eoa-address'), findsNothing);
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
    });
  });
}

void main() {
  testTransactionViewsWidgets();
}

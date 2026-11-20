import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/blocs/trading_entities_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/my_orders/my_order.dart';
import 'package:web_dex/model/swap.dart';
import 'package:web_dex/views/dex/entities_list/common/dex_empty_list.dart';
import 'package:web_dex/views/dex/entities_list/history/history_item.dart';
import 'package:web_dex/views/dex/entities_list/history/history_list.dart';

class _TradingEntities extends Fake implements TradingEntitiesBloc {
  final updates = StreamController<List<Swap>>.broadcast();

  @override
  List<Swap> swaps = [];

  @override
  Stream<List<Swap>> get outSwaps => updates.stream;

  @override
  Stream<Map<String, RecoverySubmissionStatus>> get outRecoveryStatuses =>
      const Stream.empty();

  @override
  RecoverySubmissionStatus recoveryStatusFor(String uuid) =>
      RecoverySubmissionStatus.idle;

  @override
  bool canRecoverSwap(String uuid) => false;

  @override
  double getPriceFromAmount(Rational sellAmount, Rational buyAmount) => 1;

  @override
  String getTypeString(bool isTaker) => 'Taker';

  void publish(List<Swap> value) {
    swaps = value;
    updates.add(value);
  }
}

class _Coins extends Fake implements CoinsRepo {
  @override
  Coin? getCoin(String abbr) => null;
}

Swap _swap(String uuid, {bool completed = true}) => Swap(
  type: TradeSide.taker,
  uuid: uuid,
  myOrderUuid: uuid,
  events: completed
      ? const [
          SwapEventItem(
            timestamp: 1,
            event: SwapEvent(type: 'Finished', data: null),
          ),
        ]
      : const [],
  makerAmount: Rational.one,
  makerCoin: 'DOC',
  takerAmount: Rational.one,
  takerCoin: 'MARTY',
  gui: 'test',
  mmVersion: '1',
  successEvents: const ['Started', 'Finished'],
  errorEvents: const ['Failed'],
  recoverable: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _TradingEntities trading;

  setUpAll(() async {
    final font = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope-Regular.ttf'));
    await font.load();
  });
  setUp(() => trading = _TradingEntities());
  tearDown(() {
    if (!trading.updates.isClosed) return trading.updates.close();
  });
  // The analyzer does not recognize the test_units directory as tests.
  // ignore: invalid_use_of_visible_for_testing_member
  tearDown(resetScreenType);

  Future<void> pumpHistory(
    WidgetTester tester, {
    bool Function(Swap)? filter,
  }) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Manrope'),
        home: MultiRepositoryProvider(
          providers: [
            RepositoryProvider<TradingEntitiesBloc>.value(value: trading),
            RepositoryProvider<CoinsRepo>.value(value: _Coins()),
          ],
          child: Builder(
            builder: (context) {
              updateScreenType(context);
              return Scaffold(
                body: HistoryList(onItemClick: (_) {}, filter: filter),
              );
            },
          ),
        ),
      ),
    );
  }

  List<String> displayedSwaps(WidgetTester tester) => tester
      .widgetList<HistoryItem>(find.byType(HistoryItem))
      .map((item) => item.swap.uuid)
      .toList();

  testWidgets('shows cached completed swaps without another broadcast', (
    tester,
  ) async {
    trading.publish([_swap('settled'), _swap('pending', completed: false)]);
    // The poll completed before the history tab mounted. A broadcast stream
    // does not replay this event to the new subscriber.
    await tester.pump();

    await pumpHistory(tester);

    expect(displayedSwaps(tester), ['settled']);
  });

  testWidgets('filters and refilters the initial snapshot', (tester) async {
    trading.swaps = [_swap('first'), _swap('second')];
    await pumpHistory(tester, filter: (swap) => swap.uuid == 'second');
    expect(displayedSwaps(tester), ['second']);

    await pumpHistory(tester);
    expect(displayedSwaps(tester), ['first', 'second']);
  });

  testWidgets('clears the previous wallet and accepts replacement updates', (
    tester,
  ) async {
    trading.swaps = [_swap('wallet-a')];
    await pumpHistory(tester);
    expect(displayedSwaps(tester), ['wallet-a']);

    // TradingEntitiesBloc clears its scoped cache on an auth observation.
    trading.publish([]);
    await tester.pumpAndSettle();
    expect(displayedSwaps(tester), isEmpty);
    expect(find.byType(DexEmptyList), findsOneWidget);

    trading.publish([_swap('wallet-b')]);
    await tester.pumpAndSettle();
    expect(displayedSwaps(tester), ['wallet-b']);
  });

  testWidgets('removes cached history when its source closes', (tester) async {
    trading.swaps = [_swap('settled')];
    await pumpHistory(tester);
    expect(displayedSwaps(tester), ['settled']);

    unawaited(trading.updates.close());
    await tester.pumpAndSettle();
    expect(displayedSwaps(tester), isEmpty);
  });

  testWidgets('cancels the subscription when leaving history', (tester) async {
    trading.swaps = [_swap('settled')];
    await pumpHistory(tester);
    expect(trading.updates.hasListener, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(trading.updates.hasListener, isFalse);
    trading.publish([_swap('later')]);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

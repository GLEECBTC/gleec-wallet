import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/swap.dart';
import 'package:web_dex/views/dex/entity_details/swap/swap_details_page.dart';
import 'package:web_dex/views/dex/entity_details/trading_details_header.dart';
import 'package:web_dex/views/dex/entity_details/trading_details_total_time.dart';
import 'package:web_dex/views/dex/entity_details/trading_progress_status.dart';

const _successKey = Key('swap-status-success');
const _failedKey = Key('swap-status-failed');
const _startedAt = 1700000000;

// KDF's taker sequence includes Finished as its eleventh and terminal event.
const _takerSuccessEvents = [
  'Started',
  'Negotiated',
  'TakerFeeSent',
  'TakerPaymentInstructionsReceived',
  'MakerPaymentReceived',
  'MakerPaymentWaitConfirmStarted',
  'MakerPaymentValidatedAndConfirmed',
  'TakerPaymentSent',
  'TakerPaymentSpent',
  'MakerPaymentSpent',
  'Finished',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Swap terminal status', () {
    testWidgets('100 percent without terminal success stays in progress', (
      tester,
    ) async {
      await _pump(tester, const SwapProgressStatus(progress: 100));

      expect(find.byKey(_successKey), findsNothing);
      expect(find.byKey(_failedKey), findsNothing);
      expect(find.text('99 %'), findsOneWidget);
    });

    testWidgets('failure wins over progress and a conflicting success flag', (
      tester,
    ) async {
      await _pump(
        tester,
        const SwapProgressStatus(
          progress: 100,
          isFailed: true,
          isSuccessful: true,
        ),
      );

      expect(find.byKey(_failedKey), findsOneWidget);
      expect(find.byKey(_successKey), findsNothing);
    });

    testWidgets('terminal success is independent of the progress estimate', (
      tester,
    ) async {
      await _pump(
        tester,
        const SwapProgressStatus(progress: 75, isSuccessful: true),
      );

      expect(find.byKey(_successKey), findsOneWidget);
      expect(find.byKey(_failedKey), findsNothing);
    });

    testWidgets('ten taker events do not complete an eleven-event swap', (
      tester,
    ) async {
      final swap = _swap(_takerSuccessEvents.take(10).toList());
      expect(swap.isSuccessful, isFalse);
      await _pump(tester, SwapDetailsPage(swap));

      final status = tester.widget<SwapProgressStatus>(
        find.byType(SwapProgressStatus),
      );
      expect(status.isSuccessful, isFalse);
      expect(status.progress, inInclusiveRange(0, 99));
      expect(find.byKey(_successKey), findsNothing);
      expect(
        tester
            .widget<TradingDetailsHeader>(find.byType(TradingDetailsHeader))
            .title,
        LocaleKeys.tradingDetailsTitleInProgress.tr(),
      );
    });

    testWidgets('late failure at the old completion threshold stays failed', (
      tester,
    ) async {
      final swap = _swap([
        ..._takerSuccessEvents.take(9),
        'MakerPaymentSpendFailed',
      ]);
      expect(swap.isFailed, isTrue);
      await _pump(tester, SwapDetailsPage(swap));

      expect(find.byKey(_failedKey), findsOneWidget);
      expect(find.byKey(_successKey), findsNothing);
      expect(
        tester
            .widget<TradingDetailsHeader>(find.byType(TradingDetailsHeader))
            .title,
        LocaleKeys.tradingDetailsTitleFailed.tr(),
      );
      expect(
        tester
            .widget<TradingDetailsTotalTime>(
              find.byType(TradingDetailsTotalTime),
            )
            .finishedTime,
        (_startedAt + 9) * 1000,
      );
    });

    testWidgets('Finished remains authoritative after an additional event', (
      tester,
    ) async {
      final swap = _swap([..._takerSuccessEvents, 'WatcherMessageSent']);
      expect(swap.isSuccessful, isTrue);
      await _pump(tester, SwapDetailsPage(swap));

      expect(find.byKey(_successKey), findsOneWidget);
      expect(find.byKey(_failedKey), findsNothing);
      expect(
        tester
            .widget<SwapProgressStatus>(find.byType(SwapProgressStatus))
            .progress,
        100,
      );
      expect(
        tester
            .widget<TradingDetailsHeader>(find.byType(TradingDetailsHeader))
            .title,
        LocaleKeys.tradingDetailsTitleCompleted.tr(),
      );
      expect(
        tester
            .widget<TradingDetailsTotalTime>(
              find.byType(TradingDetailsTotalTime),
            )
            .finishedTime,
        (_startedAt + 10) * 1000,
        reason: 'A later nonterminal event must not restart the elapsed timer',
      );
    });

    for (final events in [
      <String>[],
      ['Started'],
    ]) {
      testWidgets('empty success catalog stays bounded with $events', (
        tester,
      ) async {
        await _pump(
          tester,
          SwapDetailsPage(_swap(events, successEvents: const [])),
        );

        final status = tester.widget<SwapProgressStatus>(
          find.byType(SwapProgressStatus),
        );
        expect(status.progress, 0);
        expect(status.isSuccessful, isFalse);
        expect(find.byKey(_successKey), findsNothing);
        expect(
          tester
              .widget<TradingDetailsTotalTime>(
                find.byType(TradingDetailsTotalTime),
              )
              .finishedTime,
          isNull,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('one-event catalog is pending until its terminal event', (
      tester,
    ) async {
      await _pump(
        tester,
        SwapDetailsPage(_swap([], successEvents: const ['Finished'])),
      );
      expect(
        tester
            .widget<SwapProgressStatus>(find.byType(SwapProgressStatus))
            .progress,
        0,
      );
      expect(find.byKey(_successKey), findsNothing);

      await tester.pumpWidget(
        _host(
          SwapDetailsPage(
            _swap(['Finished'], successEvents: const ['Finished']),
          ),
        ),
      );
      expect(find.byKey(_successKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  // The analyzer does not recognize this repository's test_units directory.
  // ignore: invalid_use_of_visible_for_testing_member
  addTearDown(resetScreenType);
  await tester.pumpWidget(_host(child));
}

Widget _host(Widget child) => RepositoryProvider<CoinsRepo>.value(
  value: _EmptyCoinsRepo(),
  child: MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) {
          updateScreenType(context);
          return SingleChildScrollView(child: child);
        },
      ),
    ),
  ),
);

class _EmptyCoinsRepo implements CoinsRepo {
  @override
  Coin? getCoin(String coinId) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Swap _swap(
  List<String> events, {
  List<String> successEvents = _takerSuccessEvents,
}) => Swap.fromJson({
  'type': 'Taker',
  'uuid': 'terminal-status-swap',
  'maker_coin': 'MARTY',
  'maker_amount': '0.025',
  'taker_coin': 'DOC',
  'taker_amount': '0.01',
  'events': [
    for (final (index, type) in events.indexed)
      {
        'timestamp': (_startedAt + index) * 1000,
        'event': {'type': type},
      },
  ],
  'success_events': successEvents,
  'error_events': ['MakerPaymentSpendFailed'],
  'my_info': {
    'my_coin': 'DOC',
    'other_coin': 'MARTY',
    'my_amount': '0.01',
    'other_amount': '0.025',
    'started_at': _startedAt,
  },
});

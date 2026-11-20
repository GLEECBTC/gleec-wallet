import 'package:app_theme/app_theme.dart';
// Loads the new strings without the asset bundle, and resets the
// package-global translations so other tests can assert raw keys.
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/assets_overview/bloc/asset_overview_bloc.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/models/fiat_value.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/profit_loss_bloc.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/charts/portfolio_profit_loss_chart.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_main/wallet_overview.dart';

import '../../tests/utils/test_util.dart';

const _excludesOne = 'Excludes 1 asset without price history';
const _excludesThree = 'Excludes 3 assets without price history';
const _unavailable = 'Not available right now';
const _chartUnavailable = 'Profit and loss is not available right now';

void _loadCopy() => Localization.load(
  const Locale('en'),
  translations: Translations({
    'portfolioStatUnavailable': _unavailable,
    'portfolioProfitLossUnavailable': _chartUnavailable,
    'portfolioExcludesUnpricedAssets': {
      'one': 'Excludes {} asset without price history',
      'other': 'Excludes {} assets without price history',
    },
  }),
);

PortfolioAssetsOverviewLoadSuccess _totals({int excluded = 0}) =>
    PortfolioAssetsOverviewLoadSuccess(
      selectedAssetIds: const ['BTCZ', 'KMD'],
      excludedAssetIds: [for (var i = 0; i < excluded; i++) 'UNPRICED-$i'],
      assetPortionPercentages: const {},
      totalInvestment: FiatValue.usd(23),
      totalValue: FiatValue.usd(4),
      profitAmount: FiatValue.usd(4),
      profitIncreasePercentage: 17.39,
    );

const _noTotals = PortfolioAssetsOverviewUnavailable(
  reason: AssetOverviewUnavailableReason.noAssetValued,
);

class _ProfitLossBloc extends Cubit<ProfitLossState> implements ProfitLossBloc {
  _ProfitLossBloc(super.initialState);

  final events = <ProfitLossEvent>[];

  @override
  void add(ProfitLossEvent event) => events.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(_loadCopy);
  tearDown(() => Localization.load(const Locale('en')));

  group('AllTimeStatisticCard', () {
    PortfolioAssetsOverviewLoadSuccess? trendTotals;

    Future<void> pumpCard(
      WidgetTester tester,
      AssetOverviewState overview, {
      bool hideBalances = false,
    }) async {
      trendTotals = null;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: AllTimeStatisticCard(
                  title: 'All-time Investment',
                  overview: overview,
                  amount: (totals) => totals.totalInvestment.value,
                  hideBalances: hideBalances,
                  trendBuilder: (totals) {
                    trendTotals = totals;
                    return null;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    /// The amount line, or null while the card draws its loading placeholder.
    String? shownValue(WidgetTester tester) {
      final value = find.byType(AutoScrollText);
      return value.evaluate().isEmpty
          ? null
          : tester.widget<AutoScrollText>(value).text;
    }

    testWidgets('shows a complete total without a note', (tester) async {
      await pumpCard(tester, _totals());
      expect(shownValue(tester), r'$23.00');
      expect(find.byKey(AllTimeStatisticCard.noteKey), findsNothing);
      expect(trendTotals, isNotNull);
    });

    testWidgets('keeps the total and says how many assets it leaves out', (
      tester,
    ) async {
      await pumpCard(tester, _totals(excluded: 1));
      expect(shownValue(tester), r'$23.00');
      expect(find.text(_excludesOne), findsOneWidget);

      await pumpCard(tester, _totals(excluded: 3));
      expect(shownValue(tester), r'$23.00');
      expect(find.text(_excludesThree), findsOneWidget);
    });

    testWidgets('shows a dash and says so when there is no total', (
      tester,
    ) async {
      await pumpCard(tester, _noTotals);
      expect(shownValue(tester), AllTimeStatisticCard.unavailableValue);
      expect(find.text(_unavailable), findsOneWidget);
      expect(find.textContaining(r'$'), findsNothing);
      expect(trendTotals, isNull);
    });

    testWidgets('an identity that cannot be read is not shown as loading', (
      tester,
    ) async {
      await pumpCard(
        tester,
        const PortfolioAssetsOverviewUnavailable(
          reason: AssetOverviewUnavailableReason.walletIdentity,
        ),
      );
      expect(shownValue(tester), AllTimeStatisticCard.unavailableValue);
      expect(find.text(_unavailable), findsOneWidget);
    });

    testWidgets('draws the loading placeholder until a load has an answer', (
      tester,
    ) async {
      await pumpCard(tester, const AssetOverviewInitial());
      expect(shownValue(tester), isNull);
      expect(find.byKey(AllTimeStatisticCard.noteKey), findsNothing);
    });

    testWidgets('hidden balances mask the amount but not its absence', (
      tester,
    ) async {
      await pumpCard(tester, _totals(excluded: 1), hideBalances: true);
      expect(shownValue(tester), '\$$maskedBalanceText');
      expect(find.text(_excludesOne), findsOneWidget);

      await pumpCard(tester, _noTotals, hideBalances: true);
      expect(shownValue(tester), AllTimeStatisticCard.unavailableValue);
    });
  });

  testWidgets('the phone carousel can make room for a note', (tester) async {
    Future<double> pageHeight(double extraHeight) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatisticsCarousel(
              cards: const [SizedBox.expand()],
              extraHeight: extraHeight,
            ),
          ),
        ),
      );
      return tester.getSize(find.byType(PageView)).height;
    }

    expect(await pageHeight(0), 160);
    expect(await pageHeight(80), 240);
  });

  group('PortfolioProfitLossChart', () {
    final coins = [setCoin(coinAbbr: 'BTCZ'), setCoin(coinAbbr: 'KMD')];

    Future<_ProfitLossBloc> pumpChart(
      WidgetTester tester,
      ProfitLossState state,
    ) async {
      final bloc = _ProfitLossBloc(state);
      addTearDown(bloc.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme.global.light,
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 340,
              child: BlocProvider<ProfitLossBloc>.value(
                value: bloc,
                child: PortfolioProfitLossChart(initialCoins: coins),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return bloc;
    }

    PortfolioProfitLossChartLoadSuccess chart({int excluded = 0}) =>
        PortfolioProfitLossChartLoadSuccess(
          profitLossChart: const [],
          totalValue: 3,
          percentageIncrease: 150,
          coins: coins,
          excludedAssetIds: [for (var i = 0; i < excluded; i++) 'UNPRICED-$i'],
          fiatCurrency: 'USDT',
          walletId: 'wallet-a',
          selectedPeriod: const Duration(hours: 1),
        );

    for (final reason in ProfitLossUnavailableReason.values) {
      testWidgets('${reason.name} keeps the controls and explains itself', (
        tester,
      ) async {
        final bloc = await pumpChart(
          tester,
          ProfitLossLoadFailure(
            reason: reason,
            selectedPeriod: const Duration(hours: 1),
          ),
        );

        expect(find.byType(MarketChartHeaderControls), findsOneWidget);
        expect(find.text(_chartUnavailable), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.textContaining('Exception'), findsNothing);
        expect(find.textContaining('unavailable for'), findsNothing);
        expect(find.textContaining(r'$0.00'), findsNothing);

        await tester.tap(find.text('1D'));
        expect(bloc.events, [
          const ProfitLossPortfolioPeriodChanged(
            selectedPeriod: Duration(days: 1),
          ),
        ]);
      });
    }

    testWidgets('a loading chart shows progress, not the unavailable message', (
      tester,
    ) async {
      await pumpChart(tester, const ProfitLossInitial());
      expect(find.byType(MarketChartHeaderControls), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text(_chartUnavailable), findsNothing);
    });

    testWidgets('a chart that leaves assets out says how many', (tester) async {
      await pumpChart(tester, chart(excluded: 3));
      expect(find.text(_excludesThree), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      await pumpChart(tester, chart());
      expect(
        find.byKey(const Key('portfolio-profit-loss-excluded-assets')),
        findsNothing,
      );
    });
  });
}

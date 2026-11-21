import 'package:dragon_charts_flutter/dragon_charts_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/profit_loss_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/wallet/wallet_page/charts/coin_prices_chart.dart';

class PortfolioProfitLossChart extends StatefulWidget {
  const PortfolioProfitLossChart({super.key, required this.initialCoins});

  final List<Coin> initialCoins;

  @override
  State<PortfolioProfitLossChart> createState() =>
      PortfolioProfitLossChartState();
}

class PortfolioProfitLossChartState extends State<PortfolioProfitLossChart> {
  late List<Coin> _selectedCoins = widget.initialCoins;

  Coin? get _singleCoinOrNull => _selectedCoins.singleOrNull;

  bool get _isSingleCoinSelected => _selectedCoins.length == 1;

  // Determines if the chart is shown in the wallet overview or on a
  // coin's page. Consider changing this to a widget parameter if needed.
  bool get _isCoinPage => widget.initialCoins.length == 1;

  @override
  void didUpdateWidget(PortfolioProfitLossChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // TODO: Handle this. And for other charts. This
  }

  String? get walletId =>
      RepositoryProvider.of<AuthBloc>(context).state.currentUser?.walletId.name;

  List<ChartData> _buildChartDataForSelectedPeriod({
    required List<ChartData> sourceData,
    required double minChartExtent,
    required double maxChartExtent,
  }) {
    if (sourceData.isEmpty) {
      return List.empty();
    }

    ChartData? boundaryPoint;
    final filteredChartData = <ChartData>[];

    for (final point in sourceData) {
      if (point.x < minChartExtent) {
        boundaryPoint = point;
        continue;
      }

      if (point.x > maxChartExtent) {
        break;
      }

      filteredChartData.add(point);
    }

    if (boundaryPoint != null) {
      filteredChartData.insert(0, boundaryPoint);
    }

    if (filteredChartData.isNotEmpty) {
      filteredChartData.add(
        ChartData(x: maxChartExtent, y: filteredChartData.last.y),
      );
    }

    return filteredChartData;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfitLossBloc, ProfitLossState>(
      builder: (BuildContext context, ProfitLossState state) {
        if (state is ProfitLossLoadFailure) {
          return Center(child: Text(state.error.message));
        }

        final (dateAxisLabelCount, dateAxisLabelFormat) =
            PriceChartPage.dateAxisLabelCountFormat(state.selectedPeriod);
        final minChartExtent = DateTime.now()
            .subtract(state.selectedPeriod)
            .millisecondsSinceEpoch
            .toDouble();
        final maxChartExtent = DateTime.now().millisecondsSinceEpoch.toDouble();

        final isSuccess = state is PortfolioProfitLossChartLoadSuccess;
        final isUpdating =
            state is PortfolioProfitLossChartLoadSuccess && state.isUpdating;
        final List<ChartData> sourceData = isSuccess
            ? state.profitLossChart
                  .map((point) => ChartData(x: point.x.toDouble(), y: point.y))
                  .toList()
            : List.empty();
        final List<ChartData> chartData = _buildChartDataForSelectedPeriod(
          sourceData: sourceData,
          minChartExtent: minChartExtent,
          maxChartExtent: maxChartExtent,
        );

        final double rawTotalValue = isSuccess ? state.totalValue : 0.0;
        final double totalValue = rawTotalValue.isFinite ? rawTotalValue : 0.0;
        final double rawPercentageIncrease = isSuccess
            ? state.percentageIncrease
            : 0.0;
        final double percentageIncrease = rawPercentageIncrease.isFinite
            ? rawPercentageIncrease
            : 0.0;
        final bool hasValidTotal = isSuccess && rawTotalValue.isFinite;
        final formattedValue = hasValidTotal
            ? '${totalValue >= 0 ? '+' : '-'}${NumberFormat.currency(symbol: '\$', decimalDigits: 2).format(totalValue)}'
            : '--';

        return Card(
          clipBehavior: Clip.antiAlias,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                MarketChartHeaderControls(
                  title: Text(
                    _singleCoinOrNull?.name == null
                        ? LocaleKeys.portfolioPerformance.tr()
                        : LocaleKeys.performance.tr(),
                  ),
                  leadingIcon: _singleCoinOrNull == null
                      ? null
                      : AssetLogo.ofId(_singleCoinOrNull!.id, size: 24),
                  leadingText: Text(formattedValue),
                  emptySelectAllowed: !_isCoinPage,
                  availableCoins: widget.initialCoins
                      .map((coin) => coin.id)
                      .toList(),
                  selectedCoinId: _singleCoinOrNull?.abbr,
                  onCoinSelected: _isCoinPage ? null : _showSpecificCoin,
                  centreAmount: totalValue,
                  percentageIncrease: percentageIncrease,
                  selectedPeriod: state.selectedPeriod,
                  onPeriodChanged: (selected) {
                    if (selected != null) {
                      context.read<ProfitLossBloc>().add(
                        ProfitLossPortfolioPeriodChanged(
                          selectedPeriod: selected,
                        ),
                      );
                    }
                  },
                ),
                const Gap(16),
                Expanded(
                  child: LineChart(
                    key: ValueKey<String>(
                      'portfolio_profit_loss_chart_${state.selectedPeriod.inMilliseconds}',
                    ),
                    rangeExtent: const ChartExtent.tight(),
                    elements: [
                      ChartDataSeries(
                        data: chartData,
                        color:
                            (_isSingleCoinSelected
                                ? getCoinColor(_singleCoinOrNull!.abbr)
                                : null) ??
                            Theme.of(context).colorScheme.primary,
                      ),
                      ChartGridLines(isVertical: false, count: 5),
                      ChartAxisLabels(
                        isVertical: true,
                        count: 5,
                        labelBuilder: (value) =>
                            NumberFormat.compactSimpleCurrency(
                              locale: 'en_US',
                            ).format(value),
                      ),
                      ChartAxisLabels(
                        isVertical: false,
                        count: dateAxisLabelCount,
                        labelBuilder: (value) {
                          return dateAxisLabelFormat.format(
                            DateTime.fromMillisecondsSinceEpoch(value.toInt()),
                          );
                        },
                      ),
                    ],
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    markerSelectionStrategy: CartesianSelectionStrategy(
                      snapToClosest: true,
                    ),
                    tooltipBuilder: (context, dataPoints, dataColors) {
                      return _PortfolioProfitLossTooltip(
                        date: DateTime.fromMillisecondsSinceEpoch(
                          dataPoints.first.x.toInt(),
                        ),
                        portfolioValue: dataPoints.first.y,
                        selectedChartCoin: _singleCoinOrNull,
                      );
                    },
                    domainExtent: ChartExtent.withBounds(
                      min: minChartExtent,
                      max: maxChartExtent,
                    ),
                  ),
                ),
                if (!isSuccess || isUpdating)
                  Container(
                    clipBehavior: Clip.none,
                    child: const LinearProgressIndicator(
                      semanticsLabel: 'Linear progress indicator',
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSpecificCoin(String? coinId) {
    final coin = coinId == null
        ? null
        : widget.initialCoins.firstWhere((coin) => coin.abbr == coinId);

    final newCoins = coin == null ? widget.initialCoins : [coin];

    context.read<ProfitLossBloc>().add(
      ProfitLossPortfolioChartLoadRequested(
        coins: newCoins,
        fiatCoinId: 'USDT',
        selectedPeriod: context.read<ProfitLossBloc>().state.selectedPeriod,
        walletId: walletId!,
      ),
    );

    setState(() => _selectedCoins = newCoins);
  }
}

class _PortfolioProfitLossTooltip extends StatelessWidget {
  const _PortfolioProfitLossTooltip({
    required this.date,
    required this.portfolioValue,
    required this.selectedChartCoin,
  });

  final DateTime date;
  final double portfolioValue;

  final Coin? selectedChartCoin;

  @override
  Widget build(BuildContext context) {
    final adjective = portfolioValue > 0 ? '+' : '-';
    return ChartTooltipContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            DateFormat('MMMM d, y').format(date),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            '$adjective${NumberFormat.currency(symbol: '\$', decimalDigits: 2).format(portfolioValue.abs())}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: portfolioValue > 0
                  ? Colors.green
                  : Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:dragon_charts_flutter/dragon_charts_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_ui/komodo_ui.dart' show AssetIcon;
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/cex_market_data/portfolio_growth/portfolio_growth_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/asset_coin_extension.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/wallet/wallet_page/charts/coin_prices_chart.dart';

class PortfolioGrowthChart extends StatefulWidget {
  const PortfolioGrowthChart({super.key, required this.initialCoins});

  final List<Coin> initialCoins;

  @override
  State<PortfolioGrowthChart> createState() => _PortfolioGrowthChartState();
}

class _PortfolioGrowthChartState extends State<PortfolioGrowthChart> {
  late List<Coin> _selectedCoins = widget.initialCoins;

  Coin? get _singleCoinOrNull => _selectedCoins.singleOrNull;
  bool get _isSingleCoinSelected => _selectedCoins.length == 1;

  // Determines if the chart is shown in the wallet overview or on a
  // coin's page. Consider changing this to a widget parameter if needed.
  bool get _isCoinPage => widget.initialCoins.length == 1;

  double _calculateTotalValue(List<ChartData> chartData) {
    if (chartData.isEmpty) return 0.0;
    final value = chartData.last.y;
    return value.isFinite ? value : 0.0;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PortfolioGrowthBloc, PortfolioGrowthState>(
      builder: (BuildContext context, PortfolioGrowthState state) {
        final List<ChartData> chartData =
            (state is PortfolioGrowthChartLoadSuccess)
            ? state.portfolioGrowth
                  .map((point) => ChartData(x: point.x, y: point.y))
                  .toList()
            : [];

        final totalValue = _calculateTotalValue(chartData);

        final double rawPercentageIncrease =
            state is PortfolioGrowthChartLoadSuccess
            ? state.percentageIncrease
            : 0.0;
        final double percentageIncrease = rawPercentageIncrease.isFinite
            ? rawPercentageIncrease
            : 0.0;

        final (dateAxisLabelCount, dateAxisLabelFormat) =
            PriceChartPage.dateAxisLabelCountFormat(state.selectedPeriod);

        final isChartLoading =
            (state is! PortfolioGrowthChartLoadSuccess &&
                state is! PortfolioGrowthChartUnsupported) ||
            (state is PortfolioGrowthChartLoadSuccess && state.isUpdating);

        return Card(
          clipBehavior: Clip.antiAlias,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surface,
            child: Column(
              children: [
                MarketChartHeaderControls(
                  emptySelectAllowed: widget.initialCoins.length > 1,
                  title: Text(
                    _singleCoinOrNull?.abbr == null
                        ? LocaleKeys.portfolioGrowth.tr()
                        : LocaleKeys.growth.tr(),
                  ),
                  leadingIcon: _singleCoinOrNull == null
                      ? null
                      : AssetIcon.ofTicker(_singleCoinOrNull!.abbr, size: 24),
                  leadingText: Text(
                    NumberFormat.currency(
                      symbol: '\$',
                      decimalDigits: 2,
                    ).format(totalValue),
                  ),
                  availableCoins: widget.initialCoins
                      .map(
                        (coin) => getSdkAsset(
                          context.read<KomodoDefiSdk>(),
                          coin.abbr,
                        ).id,
                      )
                      .toList(),
                  selectedCoinId: _singleCoinOrNull?.abbr,
                  onCoinSelected: _isCoinPage ? null : _showSpecificCoin,
                  centreAmount: totalValue,
                  percentageIncrease: percentageIncrease,
                  selectedPeriod: state.selectedPeriod,
                  onPeriodChanged: (selected) {
                    if (selected == null) {
                      return;
                    }

                    final user = context.read<AuthBloc>().state.currentUser;
                    final walletId = user!.wallet.id;
                    context.read<PortfolioGrowthBloc>().add(
                      PortfolioGrowthPeriodChanged(
                        selectedPeriod: selected,
                        coins: _selectedCoins,
                        walletId: walletId,
                      ),
                    );
                  },
                ),
                const Gap(16),
                Expanded(
                  child: LineChart(
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
                              // symbol: '\$',
                              // USD Locale
                              locale: 'en_US',
                              // )..maximumFractionDigits = 2
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
                      return _PortfolioGrowthChartTooltip(
                        dataPoints: dataPoints,
                        coins: _selectedCoins,
                      );
                    },
                    // Use the domain of the beginning of the period
                    domainExtent: ChartExtent.withBounds(
                      min: DateTime.now()
                          .subtract(state.selectedPeriod)
                          .millisecondsSinceEpoch
                          .toDouble(),
                      max: DateTime.now().millisecondsSinceEpoch.toDouble(),
                    ),
                  ),
                ),
                if (isChartLoading)
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
    final currentWallet = context.read<AuthBloc>().state.currentUser?.wallet;
    final coin = coinId == null
        ? null
        : widget.initialCoins.firstWhere((coin) => coin.abbr == coinId);
    final newCoins = coin == null ? widget.initialCoins : [coin];

    final walletId = currentWallet!.id;
    context.read<PortfolioGrowthBloc>().add(
      PortfolioGrowthPeriodChanged(
        selectedPeriod: context
            .read<PortfolioGrowthBloc>()
            .state
            .selectedPeriod,
        coins: newCoins,
        walletId: walletId,
      ),
    );

    setState(() => _selectedCoins = newCoins);
  }
}

class _PortfolioGrowthChartTooltip extends StatelessWidget {
  final List<ChartData> dataPoints;
  final List<Coin> coins;
  // final Color backgroundColor;

  const _PortfolioGrowthChartTooltip({
    required this.dataPoints,
    required this.coins,
    // required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final date = DateTime.fromMillisecondsSinceEpoch(
      dataPoints.first.x.toInt(),
    );
    final isSingleCoinSelected = coins.length == 1;

    return ChartTooltipContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            DateFormat('MMMM d, y').format(date),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          if (dataPoints.length > 1 || isSingleCoinSelected)
            ...dataPoints.asMap().entries.map((entry) {
              int index = entry.key;
              ChartData data = entry.value;
              Coin coin = coins[index];
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AssetIcon.ofTicker(coin.abbr, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        abbr2Ticker(coin.abbr),
                        style: Theme.of(context).textTheme.bodyMedium!,
                      ),
                      const SizedBox(width: 16),
                    ],
                  ),
                  Text(
                    formatAmt(data.y),
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              );
            })
          else
            Text(
              NumberFormat.currency(
                symbol: '\$',
                decimalDigits: 2,
              ).format(dataPoints.first.y),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
        ],
      ),
    );
  }
}

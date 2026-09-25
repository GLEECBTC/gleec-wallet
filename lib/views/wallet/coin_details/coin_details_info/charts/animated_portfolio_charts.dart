import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/cex_market_data/portfolio_growth/portfolio_growth_bloc.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/profit_loss_bloc.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/analytics/events/portfolio_events.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/charts/portfolio_growth_chart.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/charts/portfolio_profit_loss_chart.dart';

class AnimatedPortfolioCharts extends StatefulWidget {
  const AnimatedPortfolioCharts({
    required this.tabController,
    required this.walletCoinsFiltered,
    super.key,
  });

  final TabController tabController;
  final List<Coin> walletCoinsFiltered;

  @override
  State<AnimatedPortfolioCharts> createState() =>
      _AnimatedPortfolioChartsState();
}

class _AnimatedPortfolioChartsState extends State<AnimatedPortfolioCharts> {
  bool _userHasInteracted = false;

  @override
  void initState() {
    super.initState();
    widget.tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    widget.tabController.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() {
    if (!_userHasInteracted) {
      setState(() {
        _userHasInteracted = true;
      });
    }

    if (!widget.tabController.indexIsChanging) {
      if (widget.tabController.index == 0) {
        final growthState = context.read<PortfolioGrowthBloc>().state;
        if (growthState is PortfolioGrowthChartLoadSuccess) {
          final period = _formatDuration(growthState.selectedPeriod);
          context.read<AnalyticsBloc>().logEvent(
            PortfolioGrowthViewedEventData(
              period: period,
              growthPct: growthState.percentageIncrease,
            ),
          );
        }
      } else if (widget.tabController.index == 1) {
        final profitLossState = context.read<ProfitLossBloc>().state;
        if (profitLossState is PortfolioProfitLossChartLoadSuccess) {
          final timeframe = _formatDuration(profitLossState.selectedPeriod);
          context.read<AnalyticsBloc>().logEvent(
            PortfolioPnlViewedEventData(
              timeframe: timeframe,
              realizedPnl: profitLossState.totalValue,
              unrealizedPnl: 0,
            ),
          );
        }
      }
    }
  }

  String _formatDuration(Duration duration) {
    if (duration.inDays >= 365) return '${duration.inDays ~/ 365}y';
    if (duration.inDays >= 30) return '${duration.inDays ~/ 30}M';
    if (duration.inDays >= 1) return '${duration.inDays}d';
    if (duration.inHours >= 1) return '${duration.inHours}h';
    if (duration.inMinutes >= 1) return '${duration.inMinutes}m';
    return '${duration.inSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PortfolioGrowthBloc, PortfolioGrowthState>(
      builder: (context, state) {
        final bool shouldExpand =
            state is PortfolioGrowthChartLoadSuccess || _userHasInteracted;

        return Column(
          children: [
            Card(
              child: TabBar(
                controller: widget.tabController,
                tabs: [
                  Tab(text: LocaleKeys.portfolioGrowth.tr()),
                  Tab(text: LocaleKeys.profitAndLoss.tr()),
                ],
              ),
            ),
            AnimatedContainer(
              key: const Key('animated_portfolio_charts_container'),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
              height: shouldExpand ? 340 : 0,
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(),
              child: Stack(
                children: [
                  TabBarView(
                    controller: widget.tabController,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: PortfolioGrowthChart(
                          initialCoins: widget.walletCoinsFiltered,
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: PortfolioProfitLossChart(
                          initialCoins: widget.walletCoinsFiltered,
                        ),
                      ),
                    ],
                  ),
                  if (state is! PortfolioGrowthChartLoadSuccess &&
                      _userHasInteracted)
                    const Center(child: CircularProgressIndicator()),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

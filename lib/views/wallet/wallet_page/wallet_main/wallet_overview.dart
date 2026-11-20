import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/analytics/events.dart';
import 'package:web_dex/analytics/events/portfolio_events.dart';
import 'package:web_dex/analytics/wallet_load_timeline.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/assets_overview/bloc/asset_overview_bloc.dart';
import 'package:web_dex/bloc/cex_market_data/portfolio_growth/portfolio_growth_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/bloc/settings/settings_event.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/utils/balance_utils.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_main/balance_summary_widget.dart';

// TODO(@takenagain): Please clean up the widget structure and bloc usage for
// the wallet overview. It may be better to split this into a separate bloc
// instead of the changes we've made to the existing PortfolioGrowthBloc since
// that bloc is primarily focused on chart data.
//
// IMPLEMENTATION NOTES:
// - Current Balance: Uses calculated total balance from the SDK
// - 24h Change: Uses PortfolioGrowthBloc.percentageChange24h and totalChange24h
// - All-time Investment: Uses AssetOverviewBloc.totalInvestment
// - All-time Profit: Uses AssetOverviewBloc.profitAmount and profitIncreasePercentage

class WalletOverview extends StatefulWidget {
  const WalletOverview({
    super.key,
    this.onPortfolioGrowthPressed,
    this.onPortfolioProfitLossPressed,
    this.onAssetsPressed,
  });

  final VoidCallback? onPortfolioGrowthPressed;
  final VoidCallback? onPortfolioProfitLossPressed;
  final VoidCallback? onAssetsPressed;

  @override
  State<WalletOverview> createState() => _WalletOverviewState();
}

class _WalletOverviewState extends State<WalletOverview> {
  bool _logged = false;
  static const double _desktopCaptionHeight = 20;

  @override
  Widget build(BuildContext context) {
    final themeCustom = Theme.of(context).brightness == Brightness.dark
        ? Theme.of(context).extension<ThemeCustomDark>()!
        : Theme.of(context).extension<ThemeCustomLight>()!;
    final hideBalances = context.select(
      (SettingsBloc bloc) => bloc.state.hideBalances,
    );

    return BlocBuilder<CoinsBloc, CoinsState>(
      builder: (context, state) {
        if (state.coins.isEmpty) return _buildSpinner();
        final portfolioAssetsOverviewBloc = context.watch<AssetOverviewBloc>();
        final int assetCount = state.walletCoins.length;

        // Get asset overview state data
        final overviewState = portfolioAssetsOverviewBloc.state;
        final stateWithData =
            overviewState is PortfolioAssetsOverviewLoadSuccess
            ? overviewState
            : null;

        // Calculate the total balance from the SDK balances and market data
        // interfaces rather than the PortfolioGrowthBloc - limited coin
        // coverage and dependent on OHLC API request limits.
        final walletTotal = computeWalletTotalUsdDetailed(
          coins: state.walletCoins.values,
          coinsState: state,
          sdk: context.sdk,
        );
        final double? totalBalance = walletTotal.totalUsd;

        // The first frame in which the user can actually see their money.
        // `takeElapsedMs` returns non-null exactly once per session, so this
        // needs no latch of its own and cannot double-report across rebuilds.
        if (totalBalance != null) {
          final elapsedMs = WalletLoadTimeline.instance.takeElapsedMs();
          if (elapsedMs != null) {
            context.read<AnalyticsBloc>().logEvent(
              TimeToFirstBalanceEventData(
                timeToFirstBalanceMs: elapsedMs,
                assetCount: walletTotal.assetCount,
                pricedAssetCount: walletTotal.pricedAssetCount,
                walletType:
                    context.read<AuthBloc>().state.currentUser?.isHd ?? false
                    ? 'hd'
                    : 'iguana',
              ),
            );
          }
        }

        if (!_logged && stateWithData != null && totalBalance != null) {
          context.read<AnalyticsBloc>().logEvent(
            PortfolioViewedEventData(
              totalCoins: assetCount,
              totalValueUsd: stateWithData.totalValue.value,
            ),
          );
          _logged = true;
        }

        // The all-time cards wait for the wallet balance, so that the row of
        // statistics fills in together.
        final allTimeOverview = totalBalance == null
            ? const AssetOverviewInitial()
            : overviewState;

        // Create the statistic cards - replace first card with BalanceSummaryWidget for mobile
        final List<Widget> statisticCards = [
          // For mobile, use BalanceSummaryWidget; for desktop, use StatisticCard
          if (isMobile) ...[
            // Get 24h change data from the PortfolioGrowthBloc
            BlocBuilder<PortfolioGrowthBloc, PortfolioGrowthState>(
              builder: (context, state) {
                final double totalChange24h =
                    state is PortfolioGrowthChartLoadSuccess
                    ? state.totalChange24h
                    : 0.0;
                final double percentageChange24h =
                    state is PortfolioGrowthChartLoadSuccess
                    ? state.percentageChange24h
                    : 0.0;

                return BalanceSummaryWidget(
                  totalBalance: totalBalance,
                  changeAmount: totalChange24h,
                  changePercentage: percentageChange24h,
                  onTap: widget.onAssetsPressed,
                  onLongPress: totalBalance != null && !hideBalances
                      ? () {
                          final formattedValue = NumberFormat.currency(
                            symbol: '\$',
                          ).format(totalBalance);
                          copyToClipBoard(context, formattedValue);
                        }
                      : null,
                  hideBalances: hideBalances,
                  onToggleHideBalances: () {
                    context.read<SettingsBloc>().add(
                      HideBalancesChanged(hideBalances: !hideBalances),
                    );
                  },
                );
              },
            ),
          ] else ...[
            StatisticCard(
              key: const Key('overview-current-value'),
              caption: SizedBox(
                height: _desktopCaptionHeight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(LocaleKeys.yourBalance.tr()),
                    const SizedBox(width: 4),
                    _BalancePrivacyToggleButton(hideBalances: hideBalances),
                  ],
                ),
              ),
              value: totalBalance,
              valueText: hideBalances && totalBalance != null
                  ? '\$$maskedBalanceText'
                  : null,
              onTap: widget.onAssetsPressed,
              onLongPress: totalBalance != null && !hideBalances
                  ? () {
                      final formattedValue = NumberFormat.currency(symbol: '\$')
                          .format(totalBalance);
                      copyToClipBoard(context, formattedValue);
                    }
                  : null,
              trendWidget: totalBalance != null && !hideBalances
                  ? BlocBuilder<PortfolioGrowthBloc, PortfolioGrowthState>(
                      builder: (context, state) {
                        final double totalChange =
                            state is PortfolioGrowthChartLoadSuccess
                            ? state.percentageChange24h
                            : 0.0;
                        final double totalChange24h =
                            state is PortfolioGrowthChartLoadSuccess
                            ? state.totalChange24h
                            : 0.0;

                        return TrendPercentageText(
                          percentage: totalChange,
                          upColor: themeCustom.increaseColor,
                          downColor: themeCustom.decreaseColor,
                          value: totalChange24h,
                          valueFormatter: NumberFormat.currency(symbol: '\$')
                              .format,
                        );
                      },
                    )
                  : null,
            ),
          ],
          AllTimeStatisticCard(
            key: const Key('overview-all-time-investment'),
            title: LocaleKeys.allTimeInvestment.tr(),
            overview: allTimeOverview,
            amount: (totals) => totals.totalInvestment.value,
            hideBalances: hideBalances,
            onTap: widget.onPortfolioGrowthPressed,
            trendBuilder: (_) => ActionChip(
              avatar: Icon(Icons.pie_chart, size: 16),
              onPressed: widget.onAssetsPressed,
              visualDensity: const VisualDensity(vertical: -4),
              label: Text(
                LocaleKeys.assetNumber.plural(assetCount),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          AllTimeStatisticCard(
            key: const Key('overview-all-time-profit'),
            title: LocaleKeys.allTimeProfit.tr(),
            overview: allTimeOverview,
            amount: (totals) => totals.profitAmount.value,
            hideBalances: hideBalances,
            onTap: widget.onPortfolioProfitLossPressed,
            trendBuilder: (totals) => totals == null || hideBalances
                ? null
                : TrendPercentageText(
                    percentage: totals.profitIncreasePercentage,
                    upColor: themeCustom.increaseColor,
                    downColor: themeCustom.decreaseColor,
                    // Show the total profit amount as the value
                    value: totals.profitAmount.value,
                    valueFormatter: NumberFormat.currency(symbol: '\$').format,
                  ),
          ),
        ];

        if (isMobile) {
          final hasNote = AllTimeStatisticCard.noteFor(allTimeOverview) != null;
          final textScaler = MediaQuery.textScalerOf(context);
          return StatisticsCarousel(
            cards: statisticCards,
            // The page height is fixed. It holds the note under an all-time
            // total at ordinary text sizes; larger text needs the room for
            // its two lines added.
            extraHeight: hasNote && textScaler.scale(1) > 1.4
                ? textScaler.scale(40)
                : 0,
          );
        }

        return Row(
          spacing: 24,
          // A note under an all-time total makes its card taller; the amounts
          // stay on one line across the row.
          crossAxisAlignment: CrossAxisAlignment.start,
          children: statisticCards.map((card) {
            return Expanded(child: card);
          }).toList(),
        );
      },
    );
  }

  Widget _buildSpinner() {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [Padding(padding: EdgeInsets.all(20.0), child: UiSpinner())],
    );
  }
}

/// An all-time total from the portfolio overview.
///
/// Shows the amount once it is known, a placeholder while it loads, and an em
/// dash when the overview has no total to give. A note under the title says
/// when assets were left out of the amount.
class AllTimeStatisticCard extends StatelessWidget {
  const AllTimeStatisticCard({
    required this.title,
    required this.overview,
    required this.amount,
    required this.hideBalances,
    this.onTap,
    this.trendBuilder,
    super.key,
  });

  final String title;
  final AssetOverviewState overview;
  final double Function(PortfolioAssetsOverviewLoadSuccess totals) amount;
  final bool hideBalances;
  final VoidCallback? onTap;

  /// Builds the trailing widget; `totals` is null until they are shown.
  final Widget? Function(PortfolioAssetsOverviewLoadSuccess? totals)?
  trendBuilder;

  static const noteKey = Key('overview-all-time-note');

  /// Stands in for an amount that is not known; it is not a zero.
  static const unavailableValue = '—';

  /// What a card says under its title for [overview], if anything.
  static String? noteFor(AssetOverviewState overview) {
    if (overview is PortfolioAssetsOverviewUnavailable) {
      return 'portfolioStatUnavailable'.tr();
    }
    final excludedAssets = overview is PortfolioAssetsOverviewLoadSuccess
        ? overview.excludedAssetIds.length
        : 0;
    return excludedAssets > 0
        ? 'portfolioExcludesUnpricedAssets'.plural(excludedAssets)
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final state = overview;
    final totals = state is PortfolioAssetsOverviewLoadSuccess ? state : null;
    final isUnavailable = state is PortfolioAssetsOverviewUnavailable;
    final value = totals == null ? null : amount(totals);
    final note = noteFor(overview);

    final String? valueText;
    if (isUnavailable) {
      valueText = unavailableValue;
    } else if (hideBalances && value != null) {
      valueText = '\$$maskedBalanceText';
    } else {
      valueText = null;
    }

    return StatisticCard(
      caption: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: _WalletOverviewState._desktopCaptionHeight,
            child: Align(alignment: Alignment.centerLeft, child: Text(title)),
          ),
          if (note != null)
            Text(
              note,
              key: noteKey,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      // A null value is what makes StatisticCard draw its loading placeholder,
      // so a total that is known to be unavailable needs one to show its dash.
      value: isUnavailable ? 0 : value,
      valueText: valueText,
      onTap: onTap,
      onLongPress: value != null && !hideBalances
          ? () => copyToClipBoard(
              context,
              NumberFormat.currency(symbol: '\$').format(value),
            )
          : null,
      trendWidget: trendBuilder?.call(totals),
    );
  }
}

class _BalancePrivacyToggleButton extends StatelessWidget {
  const _BalancePrivacyToggleButton({required this.hideBalances});

  final bool hideBalances;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: LocaleKeys.hideBalancesTitle.tr(),
      child: InkResponse(
        key: const Key('wallet-overview-privacy-toggle'),
        radius: 16,
        onTap: () {
          context.read<SettingsBloc>().add(
            HideBalancesChanged(hideBalances: !hideBalances),
          );
        },
        child: Icon(
          hideBalances
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          size: 20,
        ),
      ),
    );
  }
}

/// A carousel widget that displays statistics cards with page indicators
class StatisticsCarousel extends StatefulWidget {
  final List<Widget> cards;

  /// Added to the fixed height of a page.
  final double extraHeight;

  const StatisticsCarousel({
    super.key,
    required this.cards,
    this.extraHeight = 0,
  });

  @override
  State<StatisticsCarousel> createState() => _StatisticsCarouselState();
}

// TODO: Refactor into a generic card carousel widget and move to `komodo_ui`
class _StatisticsCarouselState extends State<StatisticsCarousel> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController.addListener(() {
      int next = _pageController.page?.round() ?? 0;
      if (_currentPage != next) {
        setState(() {
          _currentPage = next;
        });
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 160 + widget.extraHeight,
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.cards.length,
            physics: const ClampingScrollPhysics(),
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: widget.cards[index],
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        // Page indicators
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            widget.cards.length,
            (index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 8,
                width: _currentPage == index ? 24 : 8,
                decoration: BoxDecoration(
                  color: _currentPage == index
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

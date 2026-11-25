import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/analytics/events.dart';
import 'package:web_dex/analytics/events/portfolio_events.dart';
import 'package:web_dex/analytics/wallet_load_timeline.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/assets_overview/bloc/asset_overview_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';

/// The wallet total's load metrics, for whichever view shows the total: the
/// first frame with a balance, and the first view of the portfolio totals.
class WalletOverviewAnalytics {
  bool _portfolioViewed = false;

  void report(
    BuildContext context, {
    required ({double? totalUsd, int pricedAssetCount, int assetCount})
    walletTotal,
    required AssetOverviewState overview,
    required int walletCoinCount,
  }) {
    final totalBalance = walletTotal.totalUsd;
    if (totalBalance == null) return;

    // `takeElapsedMs` returns non-null exactly once per session, so this needs
    // no latch of its own and cannot double-report across rebuilds.
    final elapsedMs = WalletLoadTimeline.instance.takeElapsedMs();
    if (elapsedMs != null) {
      context.read<AnalyticsBloc>().logEvent(
        TimeToFirstBalanceEventData(
          timeToFirstBalanceMs: elapsedMs,
          assetCount: walletTotal.assetCount,
          pricedAssetCount: walletTotal.pricedAssetCount,
          walletType: context.read<AuthBloc>().state.currentUser?.isHd ?? false
              ? 'hd'
              : 'iguana',
        ),
      );
    }

    if (!_portfolioViewed && overview is PortfolioAssetsOverviewLoadSuccess) {
      context.read<AnalyticsBloc>().logEvent(
        PortfolioViewedEventData(
          totalCoins: walletCoinCount,
          totalValueUsd: overview.totalValue.value,
        ),
      );
      _portfolioViewed = true;
    }
  }
}

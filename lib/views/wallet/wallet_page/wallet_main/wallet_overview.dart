import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/assets_overview/bloc/asset_overview_bloc.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/utils/fiat_format.dart';
import 'package:web_dex/shared/utils/utils.dart';

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

  static const _captionHeight = 20.0;

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
            height: _captionHeight,
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
          ? () => copyToClipBoard(context, FiatFormat.amount(value))
          : null,
      trendWidget: trendBuilder?.call(totals),
    );
  }
}

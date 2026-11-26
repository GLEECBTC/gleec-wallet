import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/assets_overview/bloc/asset_overview_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/utils/fiat_format.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/charts/portfolio_growth_chart.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/charts/portfolio_profit_loss_chart.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_home_style.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_main/wallet_overview.dart';

/// Growth or Profit & Loss: the all-time totals over the portfolio chart.
class WalletHomeInsights extends StatelessWidget {
  const WalletHomeInsights({required this.profitLoss, super.key});

  /// Shows the profit and loss chart rather than growth.
  final bool profitLoss;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _AllTimeTotals(),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: walletHomeGroupDecoration(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SizedBox(
                height: 340,
                child: BlocSelector<CoinsBloc, CoinsState, List<Coin>>(
                  selector: (state) => state.walletCoins.values.toList(),
                  builder: (context, coins) => profitLoss
                      ? PortfolioProfitLossChart(initialCoins: coins)
                      : PortfolioGrowthChart(initialCoins: coins),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AllTimeTotals extends StatelessWidget {
  const _AllTimeTotals();

  @override
  Widget build(BuildContext context) {
    final overview = context.watch<AssetOverviewBloc>().state;
    final hidden = context.select(
      (SettingsBloc bloc) => bloc.state.hideBalances,
    );
    final totals = overview is PortfolioAssetsOverviewLoadSuccess
        ? overview
        : null;
    final note = AllTimeStatisticCard.noteFor(overview);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              Expanded(
                child: _Stat(
                  key: const Key('overview-all-time-investment'),
                  title: LocaleKeys.allTimeInvestment.tr(),
                  overview: overview,
                  hidden: hidden,
                  value: totals?.totalInvestment.value,
                ),
              ),
              Expanded(
                child: _Stat(
                  key: const Key('overview-all-time-profit'),
                  title: LocaleKeys.allTimeProfit.tr(),
                  overview: overview,
                  hidden: hidden,
                  value: totals?.profitAmount.value,
                  percent: totals?.profitIncreasePercentage,
                  signed: true,
                ),
              ),
            ],
          ),
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              note,
              key: AllTimeStatisticCard.noteKey,
              style: WalletHomeText.caption(context),
            ),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.title,
    required this.overview,
    required this.hidden,
    required this.value,
    this.percent,
    this.signed = false,
    super.key,
  });

  final String title;
  final AssetOverviewState overview;
  final bool hidden;
  final double? value;
  final double? percent;
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final value = this.value;
    final percent = this.percent;
    final unavailable = overview is PortfolioAssetsOverviewUnavailable;
    final String text;
    if (unavailable) {
      text = AllTimeStatisticCard.unavailableValue;
    } else if (value == null) {
      text = '';
    } else if (hidden) {
      text = '\$$maskedBalanceText';
    } else {
      text = signed ? FiatFormat.signedAmount(value) : FiatFormat.amount(value);
    }
    return DecoratedBox(
      decoration: walletHomeGroupDecoration(context),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: WalletHomeText.caption(context)),
            const SizedBox(height: 6),
            if (text.isEmpty)
              Container(
                width: 88,
                height: 18,
                decoration: BoxDecoration(
                  color: palette.surfaceHigh,
                  borderRadius: BorderRadius.circular(9),
                ),
              )
            else
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  text,
                  maxLines: 1,
                  style: WalletHomeText.value(context).copyWith(
                    fontSize: 18,
                    color: signed && value != null && !hidden
                        ? trendColor(context, value)
                        : palette.text,
                  ),
                ),
              ),
            if (percent != null && !hidden && !unavailable) ...[
              const SizedBox(height: 2),
              Text(
                FiatFormat.percent(percent),
                style: WalletHomeText.figure(context)
                    .copyWith(color: trendColor(context, percent)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

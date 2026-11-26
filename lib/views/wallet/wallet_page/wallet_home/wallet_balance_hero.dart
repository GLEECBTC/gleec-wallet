import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/assets_overview/bloc/asset_overview_bloc.dart';
import 'package:web_dex/bloc/cex_market_data/portfolio_growth/portfolio_growth_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/bloc/settings/settings_event.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/utils/balance_utils.dart';
import 'package:web_dex/shared/utils/fiat_format.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/motion/swap_motion_tokens.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_home_style.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_main/wallet_overview_analytics.dart';

/// The wallet's total at the top of the home screen: its change over 24
/// hours, a privacy toggle, and a prompt to add funds while it is empty.
class WalletBalanceHero extends StatefulWidget {
  const WalletBalanceHero({super.key});

  @override
  State<WalletBalanceHero> createState() => _WalletBalanceHeroState();
}

class _WalletBalanceHeroState extends State<WalletBalanceHero> {
  final _analytics = WalletOverviewAnalytics();

  @override
  Widget build(BuildContext context) {
    final hidden = context.select(
      (SettingsBloc bloc) => bloc.state.hideBalances,
    );
    return BlocBuilder<CoinsBloc, CoinsState>(
      builder: (context, coins) {
        final walletTotal = computeWalletTotalUsdDetailed(
          coins: coins.walletCoins.values,
          coinsState: coins,
          sdk: context.sdk,
        );
        _analytics.report(
          context,
          walletTotal: walletTotal,
          overview: context.watch<AssetOverviewBloc>().state,
          walletCoinCount: coins.walletCoins.length,
        );
        final total = coins.coins.isEmpty ? null : walletTotal.totalUsd;
        return BlocBuilder<PortfolioGrowthBloc, PortfolioGrowthState>(
          builder: (context, growth) => BalanceHeroContent(
            total: total,
            change: growth is PortfolioGrowthChartLoadSuccess
                ? (
                    amount: growth.totalChange24h,
                    percent: growth.percentageChange24h,
                  )
                : null,
            hidden: hidden,
            onToggleHidden: () {
              SwapHaptics.selection();
              context.read<SettingsBloc>().add(
                HideBalancesChanged(hideBalances: !hidden),
              );
            },
            onCopy: total == null || hidden
                ? null
                : () {
                    SwapHaptics.light();
                    copyToClipBoard(context, FiatFormat.amount(total));
                  },
          ),
        );
      },
    );
  }
}

/// What [WalletBalanceHero] draws, from plain values.
class BalanceHeroContent extends StatelessWidget {
  const BalanceHeroContent({
    required this.total,
    required this.change,
    required this.hidden,
    required this.onToggleHidden,
    this.onCopy,
    super.key,
  });

  /// The wallet's value in dollars; null while it is still being worked out.
  final double? total;

  /// The change over 24 hours; null until the portfolio history has loaded.
  final ({double amount, double percent})? change;
  final bool hidden;
  final VoidCallback onToggleHidden;
  final VoidCallback? onCopy;

  static const emptyHintKey = Key('wallet-home-empty-hint');
  static const changeKey = Key('wallet-home-change');

  /// The total, under the key the desktop overview gave it, which the
  /// integration tests find the wallet page by.
  static const totalKey = Key('overview-current-value');

  @override
  Widget build(BuildContext context) {
    final total = this.total;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: _glow(context)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Caption(hidden: hidden, onToggleHidden: onToggleHidden),
            GestureDetector(
              key: totalKey,
              onLongPress: onCopy,
              child: AnimatedSwitcher(
                duration: SwapMotion.of(context, SwapMotion.reveal),
                child: total == null
                    ? const _Skeleton(width: 190, height: 48)
                    : _AnimatedBalance(value: total, hidden: hidden),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 30,
              child: AnimatedSwitcher(
                duration: SwapMotion.of(context, SwapMotion.reveal),
                child: _subline(context, total),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _subline(BuildContext context, double? total) {
    final change = this.change;
    if (total == null) return const _Skeleton(width: 150, height: 28);
    if (hidden) return const SizedBox.shrink();
    if (total == 0) {
      return Center(
        key: emptyHintKey,
        child: Text(
          LocaleKeys.walletHomeEmptyHint.tr(),
          style: WalletHomeText.caption(context),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (change == null) return const SizedBox.shrink();
    return _ChangePill(
      key: changeKey,
      amount: change.amount,
      percent: change.percent,
    );
  }

  /// A soft brand glow behind the total. It is an ellipse that fades out
  /// exactly at the box's edges, so the box never shows as a band.
  Gradient _glow(BuildContext context) {
    final brand = SwapPalette.of(context).brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return RadialGradient(
      radius: 0.5,
      transform: const _Widen(),
      colors: [
        brand.withValues(alpha: isDark ? 0.24 : 0.1),
        brand.withValues(alpha: isDark ? 0.08 : 0.03),
        brand.withValues(alpha: 0),
      ],
      stops: const [0, 0.55, 1],
    );
  }
}

/// Stretches a circular gradient to the box's width.
class _Widen extends GradientTransform {
  const _Widen();

  @override
  Matrix4 transform(Rect bounds, {ui.TextDirection? textDirection}) {
    final center = bounds.center;
    return Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(bounds.width / bounds.height, 1, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);
  }
}

class _Caption extends StatelessWidget {
  const _Caption({required this.hidden, required this.onToggleHidden});

  final bool hidden;
  final VoidCallback onToggleHidden;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The icon button pads its glyph by 15 on each side; matching that
        // here keeps the label and glyph centred as a pair.
        const SizedBox(width: 15),
        Text(
          LocaleKeys.walletHomeTotalBalance.tr(),
          style: WalletHomeText.caption(context),
        ),
        IconButton(
          key: const Key('balance-summary-privacy-toggle'),
          tooltip: hidden
              ? LocaleKeys.walletHomeShowBalances.tr()
              : LocaleKeys.hideBalancesTitle.tr(),
          onPressed: onToggleHidden,
          iconSize: 18,
          color: palette.textTertiary,
          icon: Icon(
            hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          ),
        ),
      ],
    );
  }
}

/// The total, rolling to each new value; dollars large, cents a step down.
class _AnimatedBalance extends StatelessWidget {
  const _AnimatedBalance({required this.value, required this.hidden});

  final double value;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final whole = WalletHomeText.balance(context);
    if (hidden) {
      return Text(
        '\$$maskedBalanceText',
        key: const ValueKey('hidden'),
        style: whole,
      );
    }
    return Semantics(
      label: FiatFormat.amount(value),
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        key: const ValueKey('balance'),
        // A changed end animates from wherever the last change had got to.
        tween: Tween(begin: value, end: value),
        duration: SwapMotion.of(context, const Duration(milliseconds: 700)),
        curve: Curves.easeOutCubic,
        builder: (context, shown, _) {
          final parts = FiatFormat.amountParts(shown);
          return FittedBox(
            fit: BoxFit.scaleDown,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: parts.whole, style: whole),
                  TextSpan(
                    text: parts.fraction,
                    style: WalletHomeText.balanceFraction(context),
                  ),
                ],
              ),
              key: const Key('wallet-home-balance'),
              maxLines: 1,
            ),
          );
        },
      ),
    );
  }
}

class _ChangePill extends StatelessWidget {
  const _ChangePill({required this.amount, required this.percent, super.key});

  final double amount;
  final double percent;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final direction = amount != 0 ? amount : percent;
    final color = trendColor(context, direction);
    final background = direction > 0
        ? palette.successBg
        : direction < 0
        ? palette.dangerBg
        : palette.surfaceHigh;
    final icon = direction > 0
        ? Icons.arrow_upward_rounded
        : direction < 0
        ? Icons.arrow_downward_rounded
        : Icons.remove_rounded;
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Text(
                  '${FiatFormat.signedAmount(amount)} '
                  '(${FiatFormat.percent(percent)})',
                  style: WalletHomeText.figure(context).copyWith(color: color),
                ),
                const SizedBox(width: 6),
                Text('24h', style: WalletHomeText.caption(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: SwapPalette.of(context).surfaceHigh,
          borderRadius: BorderRadius.circular(height / 2.5),
        ),
      ),
    );
  }
}

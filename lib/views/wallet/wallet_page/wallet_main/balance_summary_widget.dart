import 'package:app_theme/src/dark/theme_custom_dark.dart';
import 'package:app_theme/src/light/theme_custom_light.dart';
import 'package:flutter/material.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/shared/constants.dart';

/// Balance Summary Widget for mobile view
class BalanceSummaryWidget extends StatelessWidget {
  final double? totalBalance;
  final double? changeAmount;
  final double? changePercentage;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool hideBalances;

  const BalanceSummaryWidget({
    super.key,
    this.totalBalance,
    required this.changeAmount,
    required this.changePercentage,
    this.onTap,
    this.onLongPress,
    this.hideBalances = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeCustom = Theme.of(context).brightness == Brightness.dark
        ? Theme.of(context).extension<ThemeCustomDark>()!
        : Theme.of(context).extension<ThemeCustomLight>()!;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          gradient: StatisticCard.containerGradient(theme),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Total balance or placeholder
            totalBalance != null
                ? Text(
                    hideBalances
                        ? '\$${maskedBalanceText}'
                        : '\$${NumberFormat("#,##0.00").format(totalBalance!)}',
                    style: theme.textTheme.headlineSmall,
                  )
                : _BalancePlaceholder(),
            const SizedBox(height: 12),
            // Change indicator using TrendPercentageText or placeholder
            totalBalance != null && !hideBalances
                ? TrendPercentageText(
                    percentage: changePercentage,
                    upColor: themeCustom.increaseColor,
                    downColor: themeCustom.decreaseColor,
                    value: changeAmount,
                    valueFormatter: (value) =>
                        NumberFormat.currency(symbol: '\$').format(value),
                  )
                : _ChangePlaceholder(),
          ],
        ),
      ),
    );
  }
}

class _BalancePlaceholder extends StatelessWidget {
  const _BalancePlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 32,
      width: 160,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

class _ChangePlaceholder extends StatelessWidget {
  const _ChangePlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 20,
      width: 100,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

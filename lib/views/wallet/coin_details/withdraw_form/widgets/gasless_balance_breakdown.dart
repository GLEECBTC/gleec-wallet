import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

/// Custody balance breakdown for GasFree sends.
///
/// Keeping total, spendable, and pending/locked funds visible prevents a
/// provider lookup or in-flight transfer from making wallet-owned funds appear
/// to disappear.
class GaslessBalanceBreakdown extends StatelessWidget {
  const GaslessBalanceBreakdown({
    required this.total,
    required this.spendable,
    required this.pending,
    required this.symbol,
    required this.totalLabel,
    required this.spendableLabel,
    required this.pendingLabel,
    super.key,
  });

  final String total;
  final String spendable;
  final String pending;
  final String symbol;
  final String totalLabel;
  final String spendableLabel;
  final String pendingLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = <Widget>[
      _BalanceMetric(label: totalLabel, amount: total, symbol: symbol),
      _BalanceMetric(label: spendableLabel, amount: spendable, symbol: symbol),
      _BalanceMetric(label: pendingLabel, amount: pending, symbol: symbol),
    ];

    return Semantics(
      container: true,
      label:
          '$totalLabel $total $symbol, '
          '$spendableLabel $spendable $symbol, '
          '$pendingLabel $pending $symbol',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.45,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            if (constraints.maxWidth < 520 || textScale > 1.3) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < metrics.length; index++) ...[
                    metrics[index],
                    if (index != metrics.length - 1) const SizedBox(height: 10),
                  ],
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < metrics.length; index++) ...[
                  Expanded(child: metrics[index]),
                  if (index != metrics.length - 1) const SizedBox(width: 16),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BalanceMetric extends StatelessWidget {
  const _BalanceMetric({
    required this.label,
    required this.amount,
    required this.symbol,
  });

  final String label;
  final String amount;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$amount $symbol',
            softWrap: true,
            // The legacy app theme uses ColorScheme.onSurface as the scaffold
            // background. Inherit the text foreground until the semantic
            // migration in docs/THEME_SEMANTIC_COLOR_MIGRATION_PLAN.md.
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

@Preview(
  name: 'GasFree balances - phone light',
  group: 'GasFree withdrawal',
  size: Size(375, 220),
)
Widget gaslessBalanceBreakdownLightPreview() => MaterialApp(
  theme: newThemeLight,
  home: const Material(
    child: Padding(
      padding: EdgeInsets.all(16),
      child: GaslessBalanceBreakdown(
        total: '1234.567890',
        spendable: '1200.567890',
        pending: '34',
        symbol: 'USDT',
        totalLabel: 'Gas-free total',
        spendableLabel: 'Sendable',
        pendingLabel: 'Pending / locked',
      ),
    ),
  ),
);

@Preview(
  name: 'GasFree balances - tablet dark',
  group: 'GasFree withdrawal',
  size: Size(760, 180),
)
Widget gaslessBalanceBreakdownDarkPreview() => MaterialApp(
  theme: newThemeDark,
  home: const Material(
    child: Padding(
      padding: EdgeInsets.all(16),
      child: GaslessBalanceBreakdown(
        total: '1234.567890',
        spendable: '1200.567890',
        pending: '34',
        symbol: 'USDT',
        totalLabel: 'Gas-free total',
        spendableLabel: 'Sendable',
        pendingLabel: 'Pending / locked',
      ),
    ),
  ),
);

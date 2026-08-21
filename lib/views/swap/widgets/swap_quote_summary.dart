import 'package:flutter/material.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

/// The headline figure for a priced swap.
///
/// Leads with the guaranteed amount, never the expected one. Both sources can
/// deliver less than their estimate — a routed swap through slippage, an
/// atomic fill by not filling — so the estimate is the number that gets people
/// into arguments and the guarantee is the one worth committing to.
class SwapQuoteSummary extends StatelessWidget {
  const SwapQuoteSummary({required this.quote, super.key});

  /// The offer being summarised.
  final SwapQuote quote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showsRange = quote.expectedReceive > quote.guaranteedReceive;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('You receive at least', style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          '${quote.guaranteedReceive} ${quote.to.id}',
          style: theme.textTheme.headlineSmall,
          key: const Key('swap-guaranteed-receive'),
        ),
        if (showsRange) ...[
          const SizedBox(height: 2),
          Text(
            'Typically around ${quote.expectedReceive} ${quote.to.id}',
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 12),
        _SourceChip(source: quote.source, provider: quote.providerLabel),
        if (quote.estimatedDuration != null) ...[
          const SizedBox(height: 8),
          Text(
            'Usually takes about ${_readableDuration(quote.estimatedDuration!)}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  static String _readableDuration(Duration duration) {
    if (duration.inMinutes < 1) return '${duration.inSeconds} seconds';
    if (duration.inMinutes == 1) return 'a minute';
    return '${duration.inMinutes} minutes';
  }
}

/// Says where the liquidity comes from.
///
/// Not decoration: one route keeps funds peer-to-peer, the other sends them
/// through third-party contracts. That is a material difference and hiding it
/// behind a single price would be the wrong kind of simplification.
class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.source, this.provider});

  final SwapLiquiditySource source;
  final String? provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, icon) = switch (source) {
      SwapLiquiditySource.atomic => ('Peer-to-peer', Icons.swap_horiz),
      SwapLiquiditySource.routed => (
        provider == null ? 'Routed' : 'Routed via $provider',
        Icons.alt_route,
      ),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.labelMedium),
      ],
    );
  }
}

/// The cost breakdown, with an explicit warning when it is incomplete.
class SwapCostBreakdown extends StatelessWidget {
  const SwapCostBreakdown({required this.quote, super.key});

  /// The offer whose costs are shown.
  final SwapQuote quote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final cost in quote.costs)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  cost.isDeductedFromReceive
                      ? '${cost.label} (already deducted)'
                      : cost.label,
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  '${cost.amount} ${cost.tokenLabel}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        if (quote.hasUndisclosedCosts) ...[
          const SizedBox(height: 8),
          Text(
            // The quote omits approval gas entirely, so any total here is a
            // floor. Presenting it as exact would be a number we cannot stand
            // behind at the moment the user commits.
            'A one-off approval transaction may also be needed. Its network '
            'fee is not included above.',
            key: const Key('swap-undisclosed-costs'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

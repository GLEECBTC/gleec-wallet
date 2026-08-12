import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/views/swap/widgets/swap_quote_summary.dart';

/// The last screen before money moves.
class SwapReviewSheet extends StatelessWidget {
  const SwapReviewSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<UnifiedSwapBloc>();

    return BlocBuilder<UnifiedSwapBloc, UnifiedSwapState>(
      builder: (context, state) {
        final quote = state.selectedQuote;
        if (quote == null) return const SizedBox.shrink();

        // A price that moved against the user during the pre-start re-price.
        // Nothing has been sent and nothing will be until they accept it.
        final reprice = state.repricedQuote;
        if (reprice != null) {
          return _RepriceConsent(
            previousGuaranteed: '${quote.guaranteedReceive} ${quote.to.id}',
            updatedGuaranteed: '${reprice.guaranteedReceive} ${reprice.to.id}',
            onAccept: () => bloc.add(const UnifiedSwapRepriceAccepted()),
            onReject: () => bloc.add(const UnifiedSwapRepriceRejected()),
          );
        }

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'You pay ${quote.sellAmount} ${quote.from.id}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              SwapQuoteSummary(quote: quote),
              const SizedBox(height: 20),
              SwapCostBreakdown(quote: quote),
              if (quote.isCrossChain) ...[
                const SizedBox(height: 16),
                Text(
                  'This swap moves funds between networks and can take '
                  'several minutes.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (state.startError != null) ...[
                const SizedBox(height: 16),
                Text(
                  state.startError!,
                  key: const Key('swap-start-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('swap-start'),
                onPressed: state.canStart
                    ? () => bloc.add(const UnifiedSwapStartRequested())
                    : null,
                child: Text(state.isRepricing ? 'Checking price…' : 'Swap now'),
              ),
              TextButton(
                onPressed: () => bloc.add(const UnifiedSwapReviewDismissed()),
                child: const Text('Back'),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Asks the user to accept a price that moved before anything was sent.
class _RepriceConsent extends StatelessWidget {
  const _RepriceConsent({
    required this.previousGuaranteed,
    required this.updatedGuaranteed,
    required this.onAccept,
    required this.onReject,
  });

  final String previousGuaranteed;
  final String updatedGuaranteed;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      key: const Key('swap-reprice-consent'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('The price changed', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Nothing has been sent. Review the new amount before continuing.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        // Old and new side by side. Showing only the new figure would let a
        // worse price slip past someone who is skimming.
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Was', style: theme.textTheme.bodySmall),
            Text(
              previousGuaranteed,
              style: theme.textTheme.bodySmall?.copyWith(
                decoration: TextDecoration.lineThrough,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Now', style: theme.textTheme.bodyMedium),
            Text(updatedGuaranteed, style: theme.textTheme.titleSmall),
          ],
        ),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('swap-reprice-accept'),
          onPressed: onAccept,
          child: const Text('Accept and swap'),
        ),
        TextButton(
          key: const Key('swap-reprice-reject'),
          onPressed: onReject,
          child: const Text('Go back'),
        ),
      ],
    );
  }
}

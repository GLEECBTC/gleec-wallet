import 'package:flutter/material.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';

/// Shows a running or finished swap.
///
/// Two rules from the design review are enforced here rather than left to
/// copy: a finished swap is not automatically a successful one, and no state
/// claims to know where the funds are when it does not.
class SwapProgressView extends StatelessWidget {
  const SwapProgressView({
    required this.progress,
    required this.onCancel,
    required this.onDone,
    super.key,
  });

  /// The latest snapshot.
  final RoutedSwapProgress progress;

  /// Called when the user asks to stop the swap.
  final VoidCallback onCancel;

  /// Called when the user dismisses a finished swap.
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_headline, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(_detail, style: theme.textTheme.bodyMedium),
        if (progress.providerStatusDetail != null) ...[
          const SizedBox(height: 8),
          // Provider passthrough: in the provider's own language, subject to
          // change without notice, and not translatable. It belongs in a
          // details line, never as the primary message.
          Text(
            progress.providerStatusDetail!,
            key: const Key('swap-provider-detail'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (!progress.isTerminal) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text(
            'You can leave this screen. The swap keeps running.',
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            if (progress.canCancel)
              TextButton(
                key: const Key('swap-cancel'),
                onPressed: onCancel,
                child: const Text('Cancel swap'),
              ),
            if (progress.isTerminal)
              FilledButton(
                key: const Key('swap-done'),
                onPressed: onDone,
                child: const Text('Done'),
              ),
          ],
        ),
      ],
    );
  }

  String get _headline {
    final receipt = progress.receipt;
    if (receipt != null) {
      return switch (receipt.outcome.wire) {
        'completed' => 'You received ${receipt.amount} ${receipt.tokenLabel}',
        // A partial fill and a refund are terminal, and neither is the swap
        // the user asked for. Calling either "complete" would misrepresent
        // where their money went.
        'partial' => 'Partly filled',
        'refunded' => 'Swap refunded',
        _ => 'Swap finished',
      };
    }
    if (progress.failure != null) return 'Swap failed';

    return switch (progress.phase) {
      RoutedSwapPhase.preparing => 'Getting the best price…',
      RoutedSwapPhase.approving => 'Approving token…',
      RoutedSwapPhase.signing => 'Signing…',
      RoutedSwapPhase.sending => 'Sending…',
      RoutedSwapPhase.confirming => 'Confirming…',
      RoutedSwapPhase.bridging => 'Moving funds across…',
      _ => 'Working…',
    };
  }

  String get _detail {
    final receipt = progress.receipt;
    if (receipt != null) {
      return switch (receipt.outcome.wire) {
        'partial' =>
          'You received ${receipt.amount} ${receipt.tokenLabel}, which is not '
              'the full amount you asked for.',
        'refunded' =>
          'The swap did not happen. ${receipt.amount} ${receipt.tokenLabel} '
              'was returned to you.',
        _ => 'The swap is complete.',
      };
    }

    final failure = progress.failure;
    if (failure != null) {
      // Only claim the funds are untouched when the contract says so. Telling
      // someone their money is safe when it may not be is the one mistake
      // worth avoiding absolutely.
      final safety = failure.fundsUntouched
          ? 'Nothing was sent, so your balance is unchanged.'
          : 'Check the transaction details before trying again.';
      return '${failure.message}\n$safety';
    }

    return switch (progress.phase) {
      RoutedSwapPhase.bridging =>
        'This can take a while. We keep tracking it in the background.',
      RoutedSwapPhase.sending =>
        'This step cannot be cancelled once it has started.',
      _ => 'Nothing has left your wallet yet.',
    };
  }
}

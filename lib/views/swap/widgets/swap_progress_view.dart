import 'package:flutter/material.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';

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
  final UnifiedSwapProgress progress;

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
        if (progress.providerDetail != null) ...[
          const SizedBox(height: 8),
          // Provider passthrough: in the provider's own language, subject to
          // change without notice, and not translatable. It belongs in a
          // details line, never as the primary message.
          Text(
            progress.providerDetail!,
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

  /// The headline the source supplied, or a phase label while it runs.
  ///
  /// Terminal wording comes from the execution layer because only it knows
  /// whether a finished swap actually delivered — a refund and a partial fill
  /// are both finished and neither may be called complete.
  String get _headline {
    final headline = progress.headline;
    if (headline != null) return headline;
    if (progress.phase == SwapPhase.failed) return 'Swap failed';

    return switch (progress.phase) {
      SwapPhase.preparing => 'Getting the best price…',
      SwapPhase.approving => 'Approving token…',
      SwapPhase.signing => 'Signing…',
      SwapPhase.sending => 'Sending…',
      SwapPhase.confirming => 'Confirming…',
      SwapPhase.settling => 'Completing the swap…',
      _ => 'Working…',
    };
  }

  String get _detail {
    if (progress.phase == SwapPhase.failed) {
      // Only claim the funds are untouched where the source can prove it.
      // Telling someone their money is safe when it may not be is the one
      // mistake worth avoiding absolutely.
      final safety = progress.fundsUntouched
          ? 'Nothing was sent, so your balance is unchanged.'
          : 'Check the transaction details before trying again.';
      final detail = progress.detail;
      return detail == null ? safety : '$detail\n$safety';
    }

    final detail = progress.detail;
    if (detail != null) return detail;
    if (progress.isTerminal) return 'The swap is complete.';

    return switch (progress.phase) {
      SwapPhase.settling =>
        'This can take a while. We keep tracking it in the background.',
      SwapPhase.sending => 'This step cannot be cancelled once it has started.',
      _ => 'Nothing has left your wallet yet.',
    };
  }
}

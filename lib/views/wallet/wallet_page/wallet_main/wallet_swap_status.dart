import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/shared/swap/swap_execution_presentation.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/views/swap/common/swap_buttons.dart';
import 'package:web_dex/views/swap/common/swap_copy.dart';
import 'package:web_dex/views/swap/execution/swap_execution_display.dart';

/// Where a swap the wallet row stands for has got to. Each has its own
/// glyph, so the three are told apart without relying on colour.
enum _SwapRowStatus {
  inProgress(Icons.sync_rounded),
  needsAttention(Icons.priority_high_rounded),
  received(Icons.check_rounded);

  const _SwapRowStatus(this.icon);

  final IconData icon;

  static _SwapRowStatus of(SwapExecutionSnapshot snapshot) =>
      snapshot.needsAttention
      ? needsAttention
      : snapshot.isSuccess
      ? received
      : inProgress;
}

/// A view of the existing execution registry, with no independent polling.
class WalletSwapStatus extends StatelessWidget {
  const WalletSwapStatus({super.key});

  @override
  Widget build(BuildContext context) {
    final services = context.read<SwapServices?>();
    if (services == null) return const SizedBox.shrink();
    final session = services.presentation;
    return StreamBuilder<List<SwapExecutionSnapshot>>(
      stream: services.registry.executions,
      builder: (context, _) => StreamBuilder<int>(
        stream: session.changes,
        builder: (context, _) {
          final entries = session.walletEntries;
          if (entries.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: entries.length > 1
                ? _several(context, services, entries)
                : _one(context, services, entries.first),
          );
        },
      ),
    );
  }

  Widget _one(
    BuildContext context,
    SwapServices services,
    SwapExecutionSnapshot snapshot,
  ) {
    final display = SwapExecutionDisplay(snapshot, services.networks());
    final balanceUpdating =
        snapshot.isSuccess &&
        services.presentation.balanceStatus(snapshot.id) ==
            SwapReceiptBalanceStatus.updating;
    final status = _SwapRowStatus.of(snapshot);
    return _SwapStatusRow(
      icon: status.icon,
      accent: _accent(context, status),
      title: display.statusLine,
      detail: balanceUpdating
          ? '${display.pairLine} · ${'swapUpdatingBalance'.tr()}'
          : display.pairLine,
      onTap: () {
        services.requestOpen((id: snapshot.id, source: snapshot.source));
        routingState.selectedMenu = MainMenuValue.dex;
      },
    );
  }

  /// Several swaps are counted, not followed: some may be done or stuck, and
  /// the line under the count says how many of each.
  Widget _several(
    BuildContext context,
    SwapServices services,
    List<SwapExecutionSnapshot> entries,
  ) {
    int count(_SwapRowStatus status) =>
        entries.where((entry) => _SwapRowStatus.of(entry) == status).length;
    final inProgress = count(_SwapRowStatus.inProgress);
    final needAttention = count(_SwapRowStatus.needsAttention);
    final received = count(_SwapRowStatus.received);
    return _SwapStatusRow(
      icon: Icons.swap_horiz_rounded,
      accent: Theme.of(context).colorScheme.primary,
      title: 'swapWalletSwaps'.tr(args: ['${entries.length}']),
      detail: [
        if (inProgress > 0)
          'swapWalletSummaryInProgress'.tr(args: ['$inProgress']),
        if (needAttention > 0)
          'swapWalletSummaryAttention'.tr(args: ['$needAttention']),
        if (received > 0) 'swapWalletSummaryReceived'.tr(args: ['$received']),
      ].join(' · '),
      onTap: () {
        services.requestActivity();
        routingState.selectedMenu = MainMenuValue.dex;
      },
    );
  }

  Color _accent(BuildContext context, _SwapRowStatus status) {
    final scheme = Theme.of(context).colorScheme;
    return switch (status) {
      _SwapRowStatus.inProgress => scheme.primary,
      _SwapRowStatus.needsAttention => scheme.error,
      _SwapRowStatus.received => theme.custom.successColor,
    };
  }
}

/// One compact row in the wallet page's own colours: a status glyph, what
/// is happening, and the swap it is happening to.
class _SwapStatusRow extends StatelessWidget {
  const _SwapStatusRow({
    required this.icon,
    required this.accent,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: scheme.outline),
    );
    return SwapButtonSemantics(
      label: '$title. $detail',
      onTap: onTap,
      child: Material(
        color: scheme.surface,
        shape: shape,
        child: InkWell(
          key: const Key('wallet-swap-status'),
          customBorder: shape,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 20, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        // Amounts wrap rather than lose their end.
                        Text(
                          detail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

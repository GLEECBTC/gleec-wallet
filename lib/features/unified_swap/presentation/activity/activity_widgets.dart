import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:intl/intl.dart';
import 'package:web_dex/features/unified_swap/domain/route_activity_models.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';
import 'package:web_dex/features/unified_swap/presentation/unified_swap_design.dart';

typedef ActivityClipboardWriter = Future<void> Function(String value);
typedef ActivityAnnouncement =
    Future<void> Function(BuildContext context, String message);

Future<void> defaultActivityClipboardWriter(String value) =>
    Clipboard.setData(ClipboardData(text: value));

Future<void> defaultActivityAnnouncement(
  BuildContext context,
  String message,
) => SemanticsService.sendAnnouncement(
  View.of(context),
  message,
  Directionality.of(context),
);

class RouteActivityExecutionId extends StatefulWidget {
  const RouteActivityExecutionId({
    required this.routeExecutionId,
    required this.clipboardWriter,
    required this.announcement,
    this.compact = false,
    super.key,
  });

  final String routeExecutionId;
  final ActivityClipboardWriter clipboardWriter;
  final ActivityAnnouncement announcement;
  final bool compact;

  @override
  State<RouteActivityExecutionId> createState() =>
      _RouteActivityExecutionIdState();
}

class _RouteActivityExecutionIdState extends State<RouteActivityExecutionId> {
  bool _copying = false;

  Future<void> _copy() async {
    if (_copying) return;
    setState(() => _copying = true);
    try {
      await widget.clipboardWriter(widget.routeExecutionId);
    } on Object {
      if (!mounted) return;
      _showMessage(
        unifiedSwapText(
          context,
          'activity.copyExecutionIdFailed',
          'The execution ID could not be copied.',
        ),
        isError: true,
      );
      return;
    } finally {
      if (mounted) setState(() => _copying = false);
    }

    if (!mounted) return;
    final message = unifiedSwapText(
      context,
      'activity.executionIdCopied',
      'Full execution ID copied.',
    );
    _showMessage(message);
    try {
      await widget.announcement(context, message);
    } on Object {
      // Clipboard success remains authoritative even if the platform does not
      // support an explicit accessibility announcement.
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    final colors = Theme.of(context).colorScheme;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Semantics(liveRegion: true, child: Text(message)),
        backgroundColor: isError ? colors.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: unifiedSwapText(
        context,
        'activity.executionIdSemantics',
        'Execution ID {id}',
        namedArgs: {'id': widget.routeExecutionId},
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: ExcludeSemantics(
              child: Text(
                widget.routeExecutionId,
                key: Key('activity-execution-id-${widget.routeExecutionId}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: widget.compact
                    ? textTheme.bodySmall
                    : textTheme.bodyMedium,
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            key: Key('activity-copy-${widget.routeExecutionId}'),
            onPressed: _copying ? null : _copy,
            tooltip: unifiedSwapText(
              context,
              'activity.copyExecutionId',
              'Copy full execution ID',
            ),
            icon: _copying
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.copy_rounded),
            visualDensity: widget.compact
                ? VisualDensity.compact
                : VisualDensity.standard,
          ),
        ],
      ),
    );
  }
}

class RouteActivityStatusChip extends StatelessWidget {
  const RouteActivityStatusChip({required this.status, super.key});

  final RouteActivityStatus status;

  @override
  Widget build(BuildContext context) {
    final presentation = switch (status) {
      RouteActivityStatus.active => (
        label: unifiedSwapText(context, 'activity.status.active', 'Active'),
        icon: Icons.sync_rounded,
        tone: UnifiedSwapNoticeTone.brand,
      ),
      RouteActivityStatus.attentionRequired => (
        label: unifiedSwapText(
          context,
          'activity.status.attentionRequired',
          'Needs attention',
        ),
        icon: Icons.priority_high_rounded,
        tone: UnifiedSwapNoticeTone.warning,
      ),
      RouteActivityStatus.completed => (
        label: unifiedSwapText(
          context,
          'activity.status.completed',
          'Completed',
        ),
        icon: Icons.check_circle_outline_rounded,
        tone: UnifiedSwapNoticeTone.success,
      ),
      RouteActivityStatus.cancelled => (
        label: unifiedSwapText(
          context,
          'activity.status.cancelled',
          'Cancelled',
        ),
        icon: Icons.block_rounded,
        tone: UnifiedSwapNoticeTone.neutral,
      ),
      RouteActivityStatus.failed => (
        label: unifiedSwapText(context, 'activity.status.failed', 'Failed'),
        icon: Icons.error_outline_rounded,
        tone: UnifiedSwapNoticeTone.danger,
      ),
      RouteActivityStatus.unknown => (
        label: unifiedSwapText(
          context,
          'activity.status.unknown',
          'Status unavailable',
        ),
        icon: Icons.help_outline_rounded,
        tone: UnifiedSwapNoticeTone.neutral,
      ),
    };
    return Semantics(
      label: unifiedSwapText(
        context,
        'activity.routeStatusSemantics',
        'Route status: {status}',
        namedArgs: {'status': presentation.label},
      ),
      child: ExcludeSemantics(
        child: UnifiedSwapBadge(
          label: presentation.label,
          icon: presentation.icon,
          tone: presentation.tone,
        ),
      ),
    );
  }
}

class RouteActivitySectionCard extends StatelessWidget {
  const RouteActivitySectionCard({
    required this.title,
    required this.child,
    this.icon,
    this.semanticLabel,
    super.key,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    return Semantics(
      container: true,
      label: semanticLabel ?? title,
      child: UnifiedSwapSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: colors.brandHover),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: UnifiedSwapDesign.typography(context).cardTitle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class RouteActivityPlaceholder extends StatelessWidget {
  const RouteActivityPlaceholder({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.liveRegion = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    return ColoredBox(
      color: colors.canvas,
      child: Center(
        child: SingleChildScrollView(
          padding: UnifiedSwapDesign.pagePadding(context),
          child: Semantics(
            container: true,
            liveRegion: liveRegion,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.selected,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: SizedBox.square(
                      dimension: 64,
                      child: Icon(icon, size: 32, color: colors.brandHover),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: UnifiedSwapDesign.typography(context).sectionTitle,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: UnifiedSwapDesign.typography(context).bodyMedium,
                  ),
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(height: 20),
                    FilledButton.tonal(
                      style: UnifiedSwapDesign.primaryButtonStyle(context),
                      onPressed: onAction,
                      child: Text(actionLabel!),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RouteActivityFailureNotice extends StatelessWidget {
  const RouteActivityFailureNotice({required this.onRetry, super.key});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      liveRegion: true,
      label: unifiedSwapText(
        context,
        'activity.refreshFailedSemantics',
        'Activity could not be refreshed.',
      ),
      child: Material(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Icon(Icons.cloud_off_outlined, color: colors.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  unifiedSwapText(
                    context,
                    'activity.outOfDate',
                    'Some activity may be out of date.',
                  ),
                  style: TextStyle(color: colors.onErrorContainer),
                ),
              ),
              TextButton(
                onPressed: onRetry,
                child: Text(unifiedSwapText(context, 'common.retry', 'Retry')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String routeActivityDate(BuildContext context, DateTime value) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  return DateFormat.yMMMd(locale).add_Hm().format(value.toLocal());
}

String routeActivityAssetLabel(
  BuildContext context,
  UnifiedSwapAssetIdentity asset,
) {
  if (asset.chainFamily == UnifiedSwapChainFamily.unknown ||
      asset.kind == UnifiedSwapAssetKind.unknown) {
    return unifiedSwapText(
      context,
      'activity.assetIdentityUnavailable',
      '{ticker} (identity unavailable)',
      namedArgs: {'ticker': asset.ticker},
    );
  }
  return '${asset.ticker} · ${asset.chainId}';
}

String routeActivityAmount(
  String smallestUnits,
  UnifiedSwapAssetIdentity asset,
) {
  final decimals = asset.decimals;
  if (decimals == 0) return '$smallestUnits ${asset.ticker}';
  final padded = smallestUnits.padLeft(decimals + 1, '0');
  final split = padded.length - decimals;
  final whole = padded.substring(0, split);
  final fraction = padded.substring(split).replaceFirst(RegExp(r'0+$'), '');
  return '${fraction.isEmpty ? whole : '$whole.$fraction'} ${asset.ticker}';
}

String routeActivityPhaseLabel(BuildContext context, RouteStagePhase phase) {
  final fallback = switch (phase) {
    RouteStagePhase.preparing => 'Preparing',
    RouteStagePhase.approval => 'Approval',
    RouteStagePhase.sending => 'Sending',
    RouteStagePhase.receiving => 'Receiving',
    RouteStagePhase.reconciliation => 'Reconciliation',
    RouteStagePhase.recovery => 'Recovery',
    RouteStagePhase.completed => 'Completed',
    RouteStagePhase.cancelled => 'Cancelled',
    RouteStagePhase.failed => 'Failed',
    RouteStagePhase.unknown => 'Status unavailable',
  };
  return unifiedSwapText(context, 'activity.phase.${phase.name}', fallback);
}

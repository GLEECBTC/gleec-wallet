import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/features/unified_swap/application/route_activity_bloc.dart';
import 'package:web_dex/features/unified_swap/domain/route_activity_models.dart';
import 'package:web_dex/features/unified_swap/presentation/activity/activity_widgets.dart';
import 'package:web_dex/features/unified_swap/presentation/unified_swap_design.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

class RouteActivityListView extends StatefulWidget {
  const RouteActivityListView({
    required this.state,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onExecutionSelected,
    required this.clipboardWriter,
    required this.announcement,
    super.key,
  });

  final RouteActivityState state;
  final Future<void> Function() onRefresh;
  final VoidCallback onLoadMore;
  final ValueChanged<String> onExecutionSelected;
  final ActivityClipboardWriter clipboardWriter;
  final ActivityAnnouncement announcement;

  @override
  State<RouteActivityListView> createState() => _RouteActivityListViewState();
}

class _RouteActivityListViewState extends State<RouteActivityListView> {
  RouteActivityGroup _selected = RouteActivityGroup.active;

  @override
  void didUpdateWidget(RouteActivityListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final grouped = widget.state.grouped;
    if (grouped[_selected]!.isEmpty) {
      _selected = RouteActivityGroup.values.firstWhere(
        (group) => grouped[group]!.isNotEmpty,
        orElse: () => RouteActivityGroup.active,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final colors = UnifiedSwapDesign.colors(context);
    if (state.status == RouteActivityLoadStatus.loading &&
        state.executions.isEmpty) {
      return ColoredBox(
        color: colors.canvas,
        child: Center(
          child: Semantics(
            liveRegion: true,
            label: unifiedSwapText(
              context,
              'activity.loadingSemantics',
              'Loading Unified Swap activity',
            ),
            child: const SizedBox(
              width: 240,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  UnifiedSwapSkeleton(height: 72),
                  SizedBox(height: 10),
                  UnifiedSwapSkeleton(height: 112),
                  SizedBox(height: 10),
                  UnifiedSwapSkeleton(height: 112),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (state.status == RouteActivityLoadStatus.unavailable &&
        state.executions.isEmpty) {
      return RouteActivityPlaceholder(
        icon: Icons.cloud_off_outlined,
        title: unifiedSwapText(
          context,
          'activity.unavailableTitle',
          'Activity is temporarily unavailable',
        ),
        message: unifiedSwapText(
          context,
          'activity.unavailableBody',
          'The wallet could not safely load authoritative route activity.',
        ),
        actionLabel: unifiedSwapText(context, 'common.retry', 'Retry'),
        onAction: widget.onRefresh,
        liveRegion: true,
      );
    }
    if (state.executions.isEmpty && !state.hasMore) {
      return RouteActivityPlaceholder(
        icon: Icons.history_rounded,
        title: LocaleKeys.unifiedSwap_activityEmptyTitle.tr(),
        message: LocaleKeys.unifiedSwap_activityEmptyBody.tr(),
        actionLabel: unifiedSwapText(context, 'common.refresh', 'Refresh'),
        onAction: widget.onRefresh,
      );
    }

    final grouped = state.grouped;
    final executions = grouped[_selected]!;
    return ColoredBox(
      color: colors.canvas,
      child: RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(
              key: const Key('route-activity-list'),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: UnifiedSwapDesign.pagePadding(context),
              children: [
                _ActivityListHeader(
                  refreshing:
                      state.status == RouteActivityLoadStatus.refreshing,
                  onRefresh: widget.onRefresh,
                ),
                const SizedBox(height: 18),
                _ActivityFilters(
                  selected: _selected,
                  counts: {
                    for (final group in RouteActivityGroup.values)
                      group: grouped[group]!.length,
                  },
                  onSelected: (group) => setState(() => _selected = group),
                ),
                if (state.status == RouteActivityLoadStatus.refreshing) ...[
                  const SizedBox(height: 12),
                  const UnifiedSwapSkeleton(
                    key: Key('activity-refresh-progress'),
                    height: 6,
                  ),
                ],
                if (state.failure != null) ...[
                  const SizedBox(height: 12),
                  RouteActivityFailureNotice(onRetry: widget.onRefresh),
                ],
                const SizedBox(height: 14),
                if (executions.isEmpty)
                  UnifiedSwapNotice(
                    title: _emptyTitle(context, _selected),
                    message: unifiedSwapText(
                      context,
                      'activity.bucketEmptyBody',
                      'Routes in this state will appear here.',
                    ),
                    tone: UnifiedSwapNoticeTone.neutral,
                    icon: Icons.inbox_outlined,
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 760 ? 2 : 1;
                      const spacing = 10.0;
                      final cardWidth =
                          (constraints.maxWidth - spacing * (columns - 1)) /
                          columns;
                      return Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        children: [
                          for (final execution in executions)
                            SizedBox(
                              width: cardWidth,
                              child: _ActivitySummaryCard(
                                execution: execution,
                                onSelected: widget.onExecutionSelected,
                                clipboardWriter: widget.clipboardWriter,
                                announcement: widget.announcement,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                if (state.hasMore) ...[
                  const SizedBox(height: 16),
                  Center(
                    child: FilledButton.tonalIcon(
                      key: const Key('activity-load-more'),
                      style: UnifiedSwapDesign.secondaryButtonStyle(context),
                      onPressed:
                          state.status == RouteActivityLoadStatus.loadingMore
                          ? null
                          : widget.onLoadMore,
                      icon: state.status == RouteActivityLoadStatus.loadingMore
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.expand_more_rounded),
                      label: Text(
                        state.status == RouteActivityLoadStatus.loadingMore
                            ? unifiedSwapText(
                                context,
                                'activity.loadingMore',
                                'Loading more activity',
                              )
                            : unifiedSwapText(
                                context,
                                'activity.loadMore',
                                'Load more activity',
                              ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityListHeader extends StatelessWidget {
  const _ActivityListHeader({
    required this.refreshing,
    required this.onRefresh,
  });

  final bool refreshing;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return UnifiedSwapPageTitle(
      title: unifiedSwapText(context, 'activity.title', 'Activity'),
      trailing: IconButton(
        key: const Key('activity-refresh'),
        onPressed: refreshing ? null : onRefresh,
        tooltip: unifiedSwapText(
          context,
          'activity.refreshTooltip',
          'Refresh activity',
        ),
        icon: const Icon(Icons.refresh_rounded),
      ),
    );
  }
}

class _ActivityFilters extends StatelessWidget {
  const _ActivityFilters({
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  final RouteActivityGroup selected;
  final Map<RouteActivityGroup, int> counts;
  final ValueChanged<RouteActivityGroup> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (
            var index = 0;
            index < RouteActivityGroup.values.length;
            index++
          ) ...[
            _ActivityFilterButton(
              key: Key(
                'activity-group-${RouteActivityGroup.values[index].name}',
              ),
              group: RouteActivityGroup.values[index],
              count: counts[RouteActivityGroup.values[index]] ?? 0,
              selected: selected == RouteActivityGroup.values[index],
              onPressed: () => onSelected(RouteActivityGroup.values[index]),
            ),
            if (index < RouteActivityGroup.values.length - 1)
              const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _ActivityFilterButton extends StatelessWidget {
  const _ActivityFilterButton({
    required this.group,
    required this.count,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final RouteActivityGroup group;
  final int count;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    return Semantics(
      selected: selected,
      button: true,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: colors.textPrimary,
          backgroundColor: selected ? colors.selected : Colors.transparent,
          side: BorderSide(
            color: selected ? colors.brand : colors.controlBorder,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          '${_groupLabel(context, group)}${count > 0 ? ' $count' : ''}',
        ),
      ),
    );
  }
}

class _ActivitySummaryCard extends StatelessWidget {
  const _ActivitySummaryCard({
    required this.execution,
    required this.onSelected,
    required this.clipboardWriter,
    required this.announcement,
  });

  final RouteActivitySummary execution;
  final ValueChanged<String> onSelected;
  final ActivityClipboardWriter clipboardWriter;
  final ActivityAnnouncement announcement;

  @override
  Widget build(BuildContext context) {
    final isInert = execution.status == RouteActivityStatus.unknown;
    final colors = UnifiedSwapDesign.colors(context);
    final semanticsLabel = StringBuffer()
      ..write(
        unifiedSwapText(
          context,
          'activity.summarySemantics',
          '{source} to {destination}, updated {date}',
          namedArgs: {
            'source': routeActivityAssetLabel(context, execution.source),
            'destination': routeActivityAssetLabel(
              context,
              execution.destination,
            ),
            'date': routeActivityDate(context, execution.updatedAt),
          },
        ),
      );
    return Semantics(
      key: Key('activity-card-semantics-${execution.routeExecutionId}'),
      container: true,
      button: !isInert,
      enabled: !isInert,
      label: semanticsLabel.toString(),
      child: Material(
        key: Key('activity-card-${execution.routeExecutionId}'),
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: isInert ? null : () => onSelected(execution.routeExecutionId),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 132),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: colors.controlBorder),
              borderRadius: BorderRadius.circular(14),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact =
                    constraints.maxWidth < 420 ||
                    MediaQuery.textScalerOf(context).scale(16) >= 24;
                final identity = _ActivityIdentity(
                  execution: execution,
                  clipboardWriter: clipboardWriter,
                  announcement: announcement,
                );
                final meta = _ActivityMeta(execution: execution);
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          UnifiedSwapAssetAvatar(
                            asset: execution.destination,
                            size: 42,
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: identity),
                        ],
                      ),
                      const SizedBox(height: 8),
                      meta,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    UnifiedSwapAssetAvatar(
                      asset: execution.destination,
                      size: 42,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: identity),
                    const SizedBox(width: 8),
                    meta,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityIdentity extends StatelessWidget {
  const _ActivityIdentity({
    required this.execution,
    required this.clipboardWriter,
    required this.announcement,
  });

  final RouteActivitySummary execution;
  final ActivityClipboardWriter clipboardWriter;
  final ActivityAnnouncement announcement;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${unifiedSwapText(context, 'common.assetOnNetwork', '{asset} on {network}', namedArgs: {'asset': execution.source.ticker, 'network': unifiedSwapNetworkLabel(context, execution.source)})} → '
          '${unifiedSwapText(context, 'common.assetOnNetwork', '{asset} on {network}', namedArgs: {'asset': execution.destination.ticker, 'network': unifiedSwapNetworkLabel(context, execution.destination)})}',
          style: UnifiedSwapDesign.typography(context).labelLarge,
        ),
        const SizedBox(height: 4),
        Text(
          _statusDescription(context, execution.status),
          style: UnifiedSwapDesign.typography(context).bodyMedium,
        ),
        const SizedBox(height: 4),
        RouteActivityExecutionId(
          routeExecutionId: execution.routeExecutionId,
          clipboardWriter: clipboardWriter,
          announcement: announcement,
          compact: true,
        ),
      ],
    );
  }
}

class _ActivityMeta extends StatelessWidget {
  const _ActivityMeta({required this.execution});

  final RouteActivitySummary execution;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        RouteActivityStatusChip(status: execution.status),
        const SizedBox(height: 4),
        Text(
          routeActivityDate(context, execution.updatedAt),
          textAlign: TextAlign.end,
          style: UnifiedSwapDesign.typography(context).bodySmall,
        ),
      ],
    );
  }
}

String _groupLabel(BuildContext context, RouteActivityGroup group) =>
    switch (group) {
      RouteActivityGroup.active => unifiedSwapText(
        context,
        'activity.active',
        'Active',
      ),
      RouteActivityGroup.attentionRequired => unifiedSwapText(
        context,
        'activity.needsAttention',
        'Needs attention',
      ),
      RouteActivityGroup.completed => unifiedSwapText(
        context,
        'activity.completed',
        'Completed',
      ),
    };

String _emptyTitle(BuildContext context, RouteActivityGroup group) =>
    switch (group) {
      RouteActivityGroup.active => unifiedSwapText(
        context,
        'activity.noActive',
        'No active swaps',
      ),
      RouteActivityGroup.attentionRequired => unifiedSwapText(
        context,
        'activity.noAttention',
        'Nothing needs attention',
      ),
      RouteActivityGroup.completed => unifiedSwapText(
        context,
        'activity.noCompleted',
        'No completed swaps yet',
      ),
    };

String _statusDescription(BuildContext context, RouteActivityStatus status) =>
    switch (status) {
      RouteActivityStatus.active => unifiedSwapText(
        context,
        'activity.progressing',
        'Swap in progress',
      ),
      RouteActivityStatus.attentionRequired => unifiedSwapText(
        context,
        'activity.actionRequired',
        'Action required',
      ),
      RouteActivityStatus.completed => unifiedSwapText(
        context,
        'activity.received',
        'Funds received',
      ),
      RouteActivityStatus.cancelled => unifiedSwapText(
        context,
        'activity.cancelled',
        'Swap cancelled',
      ),
      RouteActivityStatus.failed => unifiedSwapText(
        context,
        'activity.failed',
        'Recovery may be available',
      ),
      RouteActivityStatus.unknown => unifiedSwapText(
        context,
        'activity.unknown',
        'Status unavailable',
      ),
    };

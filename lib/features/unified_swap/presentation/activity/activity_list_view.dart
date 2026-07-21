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
    this.onStartSwap,
    super.key,
  });

  final RouteActivityState state;
  final Future<void> Function() onRefresh;
  final VoidCallback onLoadMore;
  final ValueChanged<String> onExecutionSelected;
  final ActivityClipboardWriter clipboardWriter;
  final ActivityAnnouncement announcement;
  final VoidCallback? onStartSwap;

  @override
  State<RouteActivityListView> createState() => _RouteActivityListViewState();
}

class _RouteActivityListViewState extends State<RouteActivityListView> {
  RouteActivityGroup _selected = RouteActivityGroup.attentionRequired;
  bool _selectionRestored = false;
  bool _selectionPinned = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _restoreSelection();
  }

  void _restoreSelection() {
    if (_selectionRestored) return;
    _selectionRestored = true;
    final stored = PageStorage.maybeOf(
      context,
    )?.readState(context, identifier: _selectionStorageId);
    final restored = _groupNamed(stored);
    if (restored != null) {
      _selected = restored;
      _selectionPinned = true;
      return;
    }
    _selectFirstAvailableGroup();
  }

  @override
  void didUpdateWidget(RouteActivityListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.walletId != widget.state.walletId) {
      _selected = RouteActivityGroup.attentionRequired;
      _selectionPinned = false;
      _selectionRestored = false;
      _restoreSelection();
    }
    if (!_selectionPinned) _selectFirstAvailableGroup();
  }

  void _selectFirstAvailableGroup() {
    final grouped = widget.state.grouped;
    const priority = [
      RouteActivityGroup.attentionRequired,
      RouteActivityGroup.active,
      RouteActivityGroup.completed,
    ];
    final next = priority.firstWhere(
      (group) => grouped[group]!.isNotEmpty,
      orElse: () => RouteActivityGroup.attentionRequired,
    );
    if (next == _selected) return;
    _selected = next;
  }

  void _selectGroup(RouteActivityGroup group) {
    if (group == _selected) {
      if (!_selectionPinned) {
        _selectionPinned = true;
        _persistSelection();
      }
      return;
    }
    setState(() {
      _selected = group;
      _selectionPinned = true;
    });
    _persistSelection();
  }

  void _persistSelection() {
    PageStorage.maybeOf(
      context,
    )?.writeState(context, _selected.name, identifier: _selectionStorageId);
  }

  String get _selectionStorageId =>
      'route-activity-selected-group-${widget.state.walletId.hashCode}';

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
        icon: Icons.swap_horiz_rounded,
        title: LocaleKeys.unifiedSwap_activityEmptyTitle.tr(),
        message: LocaleKeys.unifiedSwap_activityEmptyBody.tr(),
        actionLabel: widget.onStartSwap == null
            ? unifiedSwapText(context, 'common.refresh', 'Refresh')
            : unifiedSwapText(context, 'activity.startSwap', 'Start a swap'),
        onAction: widget.onStartSwap ?? widget.onRefresh,
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
            constraints: const BoxConstraints(
              maxWidth: UnifiedSwapDesign.contentWidth,
            ),
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
                  hasMore: state.hasMore,
                  counts: {
                    for (final group in RouteActivityGroup.values)
                      group: grouped[group]!.length,
                  },
                  onSelected: _selectGroup,
                ),
                if (state.hasMore) ...[
                  const SizedBox(height: 12),
                  UnifiedSwapNotice(
                    key: const Key('activity-results-partial'),
                    title: unifiedSwapText(
                      context,
                      'activity.loadedResultsTitle',
                      'Showing loaded activity',
                    ),
                    message: unifiedSwapText(
                      context,
                      'activity.loadedResultsBody',
                      'Bucket counts cover the journal pages loaded so far. '
                          'Load more before treating a category as empty.',
                    ),
                    tone: UnifiedSwapNoticeTone.info,
                    icon: Icons.info_outline_rounded,
                  ),
                ],
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
                    title: state.hasMore
                        ? unifiedSwapText(
                            context,
                            'activity.noLoadedBucketResults',
                            'No loaded swaps in this category yet',
                          )
                        : _emptyTitle(context, _selected),
                    message: state.hasMore
                        ? unifiedSwapText(
                            context,
                            'activity.bucketPartialBody',
                            'More authoritative journal pages remain. Load '
                                'more to continue checking this category.',
                          )
                        : unifiedSwapText(
                            context,
                            'activity.bucketEmptyBody',
                            'Routes in this state will appear here.',
                          ),
                    tone: UnifiedSwapNoticeTone.neutral,
                    icon: Icons.inbox_outlined,
                  )
                else
                  Column(
                    children: [
                      for (
                        var index = 0;
                        index < executions.length;
                        index++
                      ) ...[
                        _ActivitySummaryCard(
                          execution: executions[index],
                          onSelected: widget.onExecutionSelected,
                        ),
                        if (index < executions.length - 1)
                          const SizedBox(height: 10),
                      ],
                    ],
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

RouteActivityGroup? _groupNamed(Object? value) {
  if (value is! String) return null;
  for (final group in RouteActivityGroup.values) {
    if (group.name == value) return group;
  }
  return null;
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
    required this.hasMore,
    required this.counts,
    required this.onSelected,
  });

  final RouteActivityGroup selected;
  final bool hasMore;
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
              hasMore: hasMore,
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
    required this.hasMore,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final RouteActivityGroup group;
  final int count;
  final bool hasMore;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    return Semantics(
      selected: selected,
      button: true,
      label: unifiedSwapText(
        context,
        'activity.filterSemantics',
        hasMore
            ? '{label}, {count} loaded swaps; more activity is available'
            : '{label}, {count} swaps',
        namedArgs: {'label': _groupLabel(context, group), 'count': '$count'},
      ),
      excludeSemantics: true,
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_groupLabel(context, group)),
            const SizedBox(width: 6),
            DecoratedBox(
              decoration: BoxDecoration(
                color: selected ? colors.brand : colors.surfaceHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                child: Text(
                  '$count',
                  style: UnifiedSwapDesign.typography(context).bodySmall
                      .copyWith(
                        color: selected ? Colors.white : colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivitySummaryCard extends StatelessWidget {
  const _ActivitySummaryCard({
    required this.execution,
    required this.onSelected,
  });

  final RouteActivitySummary execution;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
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
    semanticsLabel
      ..write(', ')
      ..write(_statusDescription(context, execution));
    if (_showsActionRequired(execution)) {
      semanticsLabel
        ..write(', ')
        ..write(
          unifiedSwapText(
            context,
            'activity.row.actionRequiredBadge',
            'Action required',
          ),
        );
    }
    return Semantics(
      key: ValueKey<int>(
        Object.hash('activity-card-semantics', execution.routeExecutionId),
      ),
      container: true,
      button: true,
      enabled: true,
      label: semanticsLabel.toString(),
      excludeSemantics: true,
      child: Material(
        key: ValueKey<int>(
          Object.hash('activity-card', execution.routeExecutionId),
        ),
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => onSelected(execution.routeExecutionId),
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
                    constraints.maxWidth < 320 ||
                    MediaQuery.textScalerOf(context).scale(16) >= 30;
                final identity = _ActivityIdentity(execution: execution);
                final meta = _ActivityMeta(execution: execution);
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ActivityAssetPair(execution: execution),
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
                    _ActivityAssetPair(execution: execution),
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
  const _ActivityIdentity({required this.execution});

  final RouteActivitySummary execution;

  @override
  Widget build(BuildContext context) {
    final source = execution.sourceAmount == null
        ? execution.source.ticker
        : routeActivityAmount(execution.sourceAmount!, execution.source);
    final destination = execution.expectedReceive == null
        ? execution.destination.ticker
        : routeActivityAmount(
            execution.expectedReceive!,
            execution.destination,
          );
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$source · ${unifiedSwapNetworkLabel(context, execution.source)}',
          style: UnifiedSwapDesign.typography(context).labelLarge,
        ),
        Text(
          '→ $destination · '
          '${unifiedSwapNetworkLabel(context, execution.destination)}',
          style: UnifiedSwapDesign.typography(context).bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          _statusDescription(context, execution),
          style: UnifiedSwapDesign.typography(context).bodyMedium,
        ),
      ],
    );
  }
}

class _ActivityAssetPair extends StatelessWidget {
  const _ActivityAssetPair({required this.execution});

  final RouteActivitySummary execution;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 48,
    height: 44,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        PositionedDirectional(
          start: 0,
          top: 0,
          child: UnifiedSwapAssetAvatar(asset: execution.source, size: 34),
        ),
        PositionedDirectional(
          end: 0,
          bottom: 0,
          child: UnifiedSwapAssetAvatar(asset: execution.destination, size: 34),
        ),
      ],
    ),
  );
}

class _ActivityMeta extends StatelessWidget {
  const _ActivityMeta({required this.execution});

  final RouteActivitySummary execution;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_showsActionRequired(execution)) ...[
          UnifiedSwapBadge(
            key: ValueKey<int>(
              Object.hash(
                'activity-action-required',
                execution.routeExecutionId,
              ),
            ),
            label: unifiedSwapText(
              context,
              'activity.row.actionRequiredBadge',
              'Action required',
            ),
            icon: Icons.priority_high_rounded,
            tone: UnifiedSwapNoticeTone.warning,
          ),
          const SizedBox(height: 4),
        ],
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

String _statusDescription(
  BuildContext context,
  RouteActivitySummary execution,
) => switch (execution.status) {
  RouteActivityStatus.active => unifiedSwapText(
    context,
    'activity.row.active',
    'Swap in progress',
  ),
  RouteActivityStatus.attentionRequired =>
    execution.requiresUserAction
        ? unifiedSwapText(
            context,
            'activity.row.actionRequired',
            'Action required',
          )
        : unifiedSwapText(
            context,
            'activity.row.attentionRequired',
            'Needs attention',
          ),
  RouteActivityStatus.completed => unifiedSwapText(
    context,
    'activity.row.completed',
    'Received',
  ),
  RouteActivityStatus.cancelled => unifiedSwapText(
    context,
    'activity.row.cancelled',
    'Cancelled before funds moved',
  ),
  RouteActivityStatus.failed =>
    (execution.requiresUserAttention || execution.requiresUserAction)
        ? unifiedSwapText(
            context,
            'activity.row.failedAttention',
            'Recovery may be available',
          )
        : unifiedSwapText(context, 'activity.row.failed', 'Swap failed'),
  RouteActivityStatus.unknown => unifiedSwapText(
    context,
    'activity.row.unknown',
    'Status unavailable',
  ),
};

bool _showsActionRequired(RouteActivitySummary execution) =>
    execution.status != RouteActivityStatus.unknown &&
    execution.requiresUserAction;

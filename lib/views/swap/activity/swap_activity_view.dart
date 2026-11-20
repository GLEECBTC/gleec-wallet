import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/swap_activity/swap_activity_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_history_repository.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/views/swap/common/swap_copy.dart';
import 'package:web_dex/views/swap/common/swap_format.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/execution/swap_execution_view.dart';
import 'package:web_dex/views/swap/execution/swap_execution_display.dart';
import 'package:web_dex/views/swap/execution/swap_loading_status.dart';
import 'package:web_dex/views/swap/motion/swap_motion.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

/// Every swap, from both sources: running, needing attention, or done.
class SwapActivityView extends StatelessWidget {
  const SwapActivityView({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = SwapShellScope.of(context);
    return ListenableBuilder(
      listenable: shell,
      builder: (context, _) {
        final detail = shell.detail;
        final Widget screen;
        if (detail != null) {
          final known = context
              .read<SwapActivityBloc>()
              .state
              .entries
              .where((entry) => entry.id == detail.id)
              .firstOrNull;
          screen = SwapExecutionView(
            key: ValueKey('activity-${detail.id}'),
            id: detail.id,
            source: detail.source,
            initial: known,
            context: SwapExecutionContext.activity,
          );
        } else {
          screen = const _ActivityList();
        }
        return SwapReveal.screen(
          revealKey: detail?.id,
          forward: detail != null,
          child: screen,
        );
      },
    );
  }
}

class _ActivityList extends StatelessWidget {
  const _ActivityList();

  @override
  Widget build(BuildContext context) {
    final services = context.read<SwapServices>();
    final registry = services.registry;
    return BlocBuilder<SwapActivityBloc, SwapActivityState>(
      builder: (context, state) {
        final bloc = context.read<SwapActivityBloc>();
        final list = RefreshIndicator(
          onRefresh: () async => bloc.add(const SwapActivityRefreshed()),
          child: SingleChildScrollView(
            // Back from a swap returns to where the list was.
            key: const PageStorageKey('swap-activity-list'),
            physics: const AlwaysScrollableScrollPhysics(),
            child: SwapColumn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwapPageHeading(title: LocaleKeys.swapNavActivity.tr()),
                  StreamBuilder<List<SwapExecutionSnapshot>>(
                    stream: registry.executions,
                    builder: (context, _) => SwapFilterBar<SwapActivityFilter>(
                      values: SwapActivityFilter.values,
                      selected: state.filter,
                      semanticLabel: LocaleKeys.swapNavActivity.tr(),
                      labelOf: (filter) => switch (filter) {
                        SwapActivityFilter.active =>
                          LocaleKeys.swapActivityFilterActive.tr(),
                        SwapActivityFilter.attention =>
                          LocaleKeys.swapActivityFilterAttention.tr(),
                        SwapActivityFilter.completed =>
                          LocaleKeys.swapActivityFilterCompleted.tr(),
                      },
                      countOf: (filter) => switch (filter) {
                        SwapActivityFilter.active => registry.activeCount,
                        SwapActivityFilter.attention =>
                          registry.unacknowledgedAttentionCount,
                        SwapActivityFilter.completed => 0,
                      },
                      onChanged: (filter) =>
                          bloc.add(SwapActivityFilterChanged(filter)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (state.isPartial &&
                      state.status == SwapActivityStatus.ready) ...[
                    SwapCallout(
                      tone: SwapTone.warning,
                      message: LocaleKeys.swapActivityPartial.tr(),
                      action: SwapLinkButton(
                        label: LocaleKeys.tryAgain.tr(),
                        onPressed: () =>
                            bloc.add(const SwapActivityRefreshed()),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  ..._content(context, state, services),
                ],
              ),
            ),
          ),
        );
        return SwapScreen(child: list);
      },
    );
  }

  List<Widget> _content(
    BuildContext context,
    SwapActivityState state,
    SwapServices services,
  ) {
    final bloc = context.read<SwapActivityBloc>();
    final shell = SwapShellScope.of(context);
    switch (state.status) {
      case SwapActivityStatus.loading:
        return [
          SwapLoadingStatus(
            label: 'swapActivityLoading'.tr(),
            skeletons: const [
              SwapSkeleton(height: 76),
              SizedBox(height: 12),
              SwapSkeleton(height: 76),
              SizedBox(height: 12),
              SwapSkeleton(height: 76),
            ],
          ),
        ];
      case SwapActivityStatus.error:
        return [
          SwapStatusHero(
            icon: Icons.error_outline_rounded,
            tone: SwapTone.danger,
            title: LocaleKeys.swapActivityErrorTitle.tr(),
            body: LocaleKeys.swapActivityErrorBody.tr(),
            action: SwapButton(
              label: LocaleKeys.tryAgain.tr(),
              onPressed: () => bloc.add(const SwapActivityRefreshed()),
            ),
          ),
        ];
      case SwapActivityStatus.ready:
        final entries = state.entries;
        if (entries.isEmpty) return [_empty(context, state.filter)];
        final networks = services.networks();
        return [
          for (final entry in entries) ...[
            _ActivityRow(
              snapshot: entry,
              copy: SwapExecutionDisplay(entry, networks),
              returning: entry.id == shell.lastDetail?.id,
              onTap: () => shell.showActivity(
                swap: (id: entry.id, source: entry.source),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (state.hasMore)
            SwapButton(
              label: LocaleKeys.swapActivityLoadMore.tr(),
              variant: SwapButtonVariant.secondary,
              busy: state.loadingMore,
              onPressed: () => bloc.add(const SwapActivityMoreRequested()),
            ),
        ];
    }
  }

  Widget _empty(BuildContext context, SwapActivityFilter filter) {
    final (title, body) = switch (filter) {
      SwapActivityFilter.active => (
        LocaleKeys.swapActivityEmptyActiveTitle.tr(),
        LocaleKeys.swapActivityEmptyActiveBody.tr(),
      ),
      SwapActivityFilter.attention => (
        LocaleKeys.swapActivityEmptyAttentionTitle.tr(),
        LocaleKeys.swapActivityEmptyAttentionBody.tr(),
      ),
      SwapActivityFilter.completed => (
        LocaleKeys.swapActivityEmptyCompletedTitle.tr(),
        LocaleKeys.swapActivityEmptyCompletedBody.tr(),
      ),
    };
    return SwapStatusHero(
      icon: filter == SwapActivityFilter.attention
          ? Icons.task_alt_rounded
          : Icons.schedule_rounded,
      tone: SwapTone.brand,
      title: title,
      body: body,
      liveRegion: false,
      action: filter == SwapActivityFilter.attention
          ? null
          : SwapButton(
              label: LocaleKeys.swapActivityStartSwap.tr(),
              onPressed: () =>
                  SwapShellScope.of(context).show(SwapDestination.swap),
            ),
    );
  }
}

class _ActivityRow extends StatefulWidget {
  const _ActivityRow({
    required this.snapshot,
    required this.copy,
    required this.returning,
    required this.onTap,
  });

  final SwapExecutionSnapshot snapshot;
  final SwapExecutionCopy copy;

  /// Whether this swap's detail was the last one open, so that coming back
  /// from it puts the keyboard back on this row.
  final bool returning;
  final VoidCallback onTap;

  @override
  State<_ActivityRow> createState() => _ActivityRowState();
}

class _ActivityRowState extends State<_ActivityRow> {
  static const _iconSize = 42.0;
  static const _gap = 12.0;

  final FocusNode _focus = FocusNode(debugLabel: 'Activity row');

  @override
  void initState() {
    super.initState();
    if (!widget.returning) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && swapFocusLost()) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final copy = widget.copy;
    final palette = SwapPalette.of(context);
    final time =
        snapshot.updatedAt ?? snapshot.finishedAt ?? snapshot.createdAt;
    final actionRequired = snapshot.stage == SwapProgressStage.actionRequired;
    final attention = snapshot.isTerminal && snapshot.needsAttention;
    final refunded = snapshot.outcome?.kind == SwapOutcomeKind.refunded;
    // A swap waiting on the user already says so as its status; a badge
    // would only say it again.
    final badge = attention ? LocaleKeys.swapNavNeedsAttention.tr() : null;
    final when = time == null ? null : SwapFormat.time(time);
    final timeStyle = SwapText.small(context);
    return Semantics(
      button: true,
      child: Material(
        color: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: palette.controlBorder),
        ),
        child: InkWell(
          focusNode: _focus,
          borderRadius: BorderRadius.circular(14),
          onTap: widget.onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 76),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Beside the swap while that leaves it most of the row.
                  // A dated time, a badge or large text takes more than
                  // that, and would squeeze the amounts into a column of
                  // single characters; then they go under it.
                  final trailing = math.max(
                    when == null
                        ? 0.0
                        : SwapText.widthOf(context, when, timeStyle),
                    badge == null ? 0.0 : SwapBadge.widthOf(context, badge),
                  );
                  final room = constraints.maxWidth - _iconSize - 2 * _gap;
                  final beside = trailing <= room * 0.35;
                  final marks = [
                    if (badge != null)
                      SwapBadge(label: badge, tone: SwapTone.warning),
                    if (when != null) Text(when, style: timeStyle),
                  ];
                  return Row(
                    children: [
                      SwapTokenIcon(
                        asset: snapshot.from,
                        ticker: snapshot.fromTicker,
                        size: _iconSize,
                      ),
                      const SizedBox(width: _gap),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              copy.pairLine,
                              style: SwapText.strong(context),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              copy.statusLine,
                              style: SwapText.small(context).copyWith(
                                color: attention || actionRequired || refunded
                                    ? palette.warning
                                    : palette.textTertiary,
                              ),
                            ),
                            if (!beside && marks.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: marks,
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (beside && marks.isNotEmpty) ...[
                        const SizedBox(width: _gap),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final (index, mark) in marks.indexed) ...[
                              if (index > 0) const SizedBox(height: 4),
                              mark,
                            ],
                          ],
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

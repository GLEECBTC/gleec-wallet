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
        if (detail != null) {
          final known = context
              .read<SwapActivityBloc>()
              .state
              .entries
              .where((entry) => entry.id == detail.id)
              .firstOrNull;
          return SwapExecutionView(
            key: ValueKey('activity-${detail.id}'),
            id: detail.id,
            source: detail.source,
            initial: known,
            context: SwapExecutionContext.activity,
          );
        }
        return const _ActivityList();
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
        return RefreshIndicator(
          onRefresh: () async => bloc.add(const SwapActivityRefreshed()),
          child: SingleChildScrollView(
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
      },
    );
  }

  List<Widget> _content(
    BuildContext context,
    SwapActivityState state,
    SwapServices services,
  ) {
    final bloc = context.read<SwapActivityBloc>();
    switch (state.status) {
      case SwapActivityStatus.loading:
        return [
          Semantics(
            label: LocaleKeys.swapNavActivity.tr(),
            child: const Column(
              children: [
                SwapSkeleton(height: 76),
                SizedBox(height: 12),
                SwapSkeleton(height: 76),
                SizedBox(height: 12),
                SwapSkeleton(height: 76),
              ],
            ),
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
              copy: SwapExecutionCopy(entry, networks),
              onTap: () => SwapShellScope.of(
                context,
              ).showActivity(swap: (id: entry.id, source: entry.source)),
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

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.snapshot,
    required this.copy,
    required this.onTap,
  });

  final SwapExecutionSnapshot snapshot;
  final SwapExecutionCopy copy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final time =
        snapshot.updatedAt ?? snapshot.finishedAt ?? snapshot.createdAt;
    final actionRequired = snapshot.stage == SwapProgressStage.actionRequired;
    final attention = snapshot.isTerminal && snapshot.needsAttention;
    return Semantics(
      button: true,
      child: Material(
        color: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: palette.controlBorder),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 76),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  SwapTokenIcon(
                    asset: snapshot.from,
                    ticker: snapshot.fromTicker,
                    size: 42,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(copy.pairLine, style: SwapText.strong(context)),
                        const SizedBox(height: 3),
                        Text(
                          copy.statusLine,
                          style: SwapText.small(context).copyWith(
                            color: attention || actionRequired
                                ? palette.warning
                                : palette.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (actionRequired || attention) ...[
                        SwapBadge(
                          label: actionRequired
                              ? LocaleKeys.swapActivityActionRequired.tr()
                              : LocaleKeys.swapNavNeedsAttention.tr(),
                          tone: SwapTone.warning,
                        ),
                        const SizedBox(height: 4),
                      ],
                      if (time != null)
                        Text(
                          SwapFormat.time(time),
                          style: SwapText.small(context),
                        ),
                    ],
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

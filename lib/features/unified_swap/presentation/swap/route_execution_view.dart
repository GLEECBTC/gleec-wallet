import 'dart:async';

import 'package:flutter/material.dart';
import 'package:web_dex/features/unified_swap/application/route_execution_bloc.dart';
import 'package:web_dex/features/unified_swap/domain/route_activity_models.dart';
import 'package:web_dex/features/unified_swap/domain/route_execution_models.dart';
import 'package:web_dex/features/unified_swap/presentation/swap/swap_widgets.dart';
import 'package:web_dex/features/unified_swap/presentation/unified_swap_design.dart';
import 'package:web_dex/features/unified_swap/presentation/unified_swap_sensitive_dialog.dart';

class RouteExecutionView extends StatelessWidget {
  const RouteExecutionView({
    required this.state,
    required this.onReattach,
    required this.onCancel,
    required this.onStopAfterCurrent,
    required this.onDecision,
    required this.canSelectRecoveryRoute,
    required this.clipboardWriter,
    required this.announcement,
    this.onClose,
    this.onViewActivity,
    super.key,
  });

  final RouteExecutionState state;
  final VoidCallback onReattach;
  final VoidCallback onCancel;
  final VoidCallback onStopAfterCurrent;
  final ValueChanged<RouteExecutionActionKind> onDecision;
  final bool canSelectRecoveryRoute;
  final SwapClipboardWriter clipboardWriter;
  final SwapAnnouncement announcement;
  final VoidCallback? onClose;
  final VoidCallback? onViewActivity;

  @override
  Widget build(BuildContext context) {
    final progress = state.progress;
    final routeExecutionId = state.routeExecutionId;
    final unknown =
        state.status == RouteExecutionLoadStatus.unknown ||
        (progress != null && !progress.isExecutable);
    final colors = UnifiedSwapDesign.colors(context);
    final recoveryLike =
        state.status == RouteExecutionLoadStatus.recovery ||
        state.status == RouteExecutionLoadStatus.attentionRequired ||
        state.status == RouteExecutionLoadStatus.failed ||
        unknown;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onClose?.call();
      },
      child: ColoredBox(
        color: colors.canvas,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: UnifiedSwapDesign.contentWidth,
            ),
            child: ListView(
              key: const Key('unified-swap-execution'),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: UnifiedSwapDesign.pagePadding(context),
              children: [
                UnifiedSwapPageTitle(
                  title: recoveryLike
                      ? unifiedSwapText(
                          context,
                          'execution.recoveryTitle',
                          'Recovery',
                        )
                      : unifiedSwapText(
                          context,
                          'execution.progressTitle',
                          'Swap progress',
                        ),
                  leading: onClose == null
                      ? null
                      : IconButton(
                          key: const Key('swap-execution-close'),
                          onPressed: onClose,
                          tooltip: unifiedSwapText(
                            context,
                            'execution.close',
                            'Close',
                          ),
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
                const SizedBox(height: 12),
                UnifiedSwapStatusHero(
                  title: _heroTitle(context, state.status, progress),
                  message: _heroDescription(context, state.status, progress),
                  icon: _statusIcon(state.status, progress?.phase),
                  tone: _statusTone(state.status, unknown),
                  key: const Key('swap-execution-status'),
                ),
                if (state.status == RouteExecutionLoadStatus.starting ||
                    state.status == RouteExecutionLoadStatus.reattaching) ...[
                  const SizedBox(height: 12),
                  const UnifiedSwapSkeleton(
                    key: Key('swap-execution-loading'),
                    height: 8,
                  ),
                ],
                if (state.failure case final failure?) ...[
                  const SizedBox(height: 12),
                  _ExecutionNotice(
                    key: const Key('swap-execution-failure'),
                    title: unifiedSwapText(
                      context,
                      'execution.statusAttentionTitle',
                      'Status needs attention',
                    ),
                    message: _failure(context, failure),
                    error: true,
                  ),
                ],
                if (unknown) ...[
                  const SizedBox(height: 12),
                  _ExecutionNotice(
                    key: const Key('swap-execution-unknown'),
                    title: unifiedSwapText(
                      context,
                      'execution.statusUnavailableTitle',
                      'Status unavailable',
                    ),
                    message: unifiedSwapText(
                      context,
                      'execution.statusUnavailableBody',
                      'The wallet received an unknown route status. Movement '
                          'controls are disabled while Activity and recovery '
                          'remain available.',
                    ),
                    error: true,
                  ),
                ],
                if (recoveryLike && progress != null) ...[
                  const SizedBox(height: 12),
                  _RecoveryQuestions(progress: progress, unknown: unknown),
                ],
                if (routeExecutionId != null) ...[
                  const SizedBox(height: 12),
                  SwapSectionCard(
                    title: unifiedSwapText(
                      context,
                      'common.executionId',
                      'Execution ID',
                    ),
                    icon: Icons.fingerprint_rounded,
                    child: SwapCopyableValue(
                      label: unifiedSwapText(
                        context,
                        'common.executionId',
                        'Execution ID',
                      ),
                      value: routeExecutionId,
                      valueKey: 'swap-progress-execution-id',
                      clipboardWriter: clipboardWriter,
                      announcement: announcement,
                    ),
                  ),
                ],
                if (progress != null) ...[
                  const SizedBox(height: 12),
                  _ProgressCard(progress: progress),
                  if (progress.holding != null) ...[
                    const SizedBox(height: 12),
                    _HoldingCard(
                      holding: progress.holding!,
                      clipboardWriter: clipboardWriter,
                      announcement: announcement,
                    ),
                  ],
                  if (progress.approvalRecovery != null) ...[
                    const SizedBox(height: 12),
                    _ApprovalRecoveryCard(
                      recovery: progress.approvalRecovery!,
                      clipboardWriter: clipboardWriter,
                      announcement: announcement,
                    ),
                  ],
                  if (progress.transactionHashes.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _TransactionCard(
                      hashes: progress.transactionHashes,
                      clipboardWriter: clipboardWriter,
                      announcement: announcement,
                    ),
                  ],
                  if (progress.pendingAction != null) ...[
                    const SizedBox(height: 12),
                    _PendingActionCard(
                      progress: progress,
                      controlInFlight: state.controlInFlight,
                      canSelectRecoveryRoute: canSelectRecoveryRoute,
                      onDecision: onDecision,
                    ),
                  ],
                  const SizedBox(height: 12),
                  _ServerControls(
                    progress: progress,
                    controlInFlight: state.controlInFlight,
                    onCancel: onCancel,
                    onStopAfterCurrent: onStopAfterCurrent,
                  ),
                ],
                if (routeExecutionId != null &&
                    (state.status == RouteExecutionLoadStatus.unknown ||
                        state.status == RouteExecutionLoadStatus.failed)) ...[
                  const SizedBox(height: 16),
                  FilledButton.tonalIcon(
                    key: const Key('swap-execution-reattach'),
                    onPressed: state.controlInFlight ? null : onReattach,
                    icon: const Icon(Icons.sync_rounded),
                    label: Text(
                      unifiedSwapText(
                        context,
                        'execution.reattach',
                        'Reattach and reconcile',
                      ),
                    ),
                  ),
                ],
                if (onViewActivity != null) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    key: const Key('swap-view-activity'),
                    style: UnifiedSwapDesign.secondaryButtonStyle(context),
                    onPressed: onViewActivity,
                    icon: const Icon(Icons.history_rounded),
                    label: Text(
                      unifiedSwapText(
                        context,
                        'execution.viewInActivity',
                        'View in Activity',
                      ),
                    ),
                  ),
                ],
                if (onClose != null && _isTerminal(state.status)) ...[
                  const SizedBox(height: 8),
                  FilledButton(
                    key: const Key('swap-execution-done'),
                    style: UnifiedSwapDesign.primaryButtonStyle(context),
                    onPressed: onClose,
                    child: Text(
                      unifiedSwapText(context, 'execution.done', 'Done'),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  unifiedSwapText(
                    context,
                    'execution.leavingNotice',
                    'Leaving this screen only stops local observation. It never '
                        'cancels backend execution.',
                  ),
                  textAlign: TextAlign.center,
                  style: UnifiedSwapDesign.typography(context).bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ApprovalRecoveryCard extends StatelessWidget {
  const _ApprovalRecoveryCard({
    required this.recovery,
    required this.clipboardWriter,
    required this.announcement,
  });

  final RouteApprovalRecovery recovery;
  final SwapClipboardWriter clipboardWriter;
  final SwapAnnouncement announcement;

  @override
  Widget build(BuildContext context) {
    final allowance = swapAmount(recovery.remainingAllowance, recovery.token);
    final instruction = recovery.instruction;
    final revoke =
        instruction ==
        RouteApprovalRecoveryInstruction.revokeAllowanceBeforeRetry;
    final known = instruction != RouteApprovalRecoveryInstruction.unknown;
    return SwapSectionCard(
      title: unifiedSwapText(
        context,
        'execution.approvalRecovery.title',
        'Token permission after this attempt',
      ),
      icon: Icons.admin_panel_settings_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(switch (instruction) {
            RouteApprovalRecoveryInstruction.revokeAllowanceBeforeRetry =>
              unifiedSwapText(
                context,
                'execution.approvalRecovery.revokeBeforeRetry',
                'An allowance of {amount} remains. Revoke it in your '
                    'wallet before retrying this swap.',
                namedArgs: {'amount': allowance},
              ),
            RouteApprovalRecoveryInstruction.noAllowanceRemains =>
              unifiedSwapText(
                context,
                'execution.approvalRecovery.noAllowanceRemains',
                'No token allowance remains, so no revoke is required '
                    'before retrying.',
              ),
            RouteApprovalRecoveryInstruction.unknown => unifiedSwapText(
              context,
              'execution.approvalRecovery.unknown',
              'The remaining token permission could not be verified. '
                  'Reconcile the swap before retrying.',
            ),
          }),
          if (known) ...[
            const SizedBox(height: 12),
            SwapCopyableValue(
              label: unifiedSwapText(
                context,
                'execution.approvalRecovery.validatedSpender',
                'Validated permission address',
              ),
              value: recovery.validatedSpender,
              valueKey: 'swap-approval-recovery-spender',
              clipboardWriter: clipboardWriter,
              announcement: announcement,
            ),
          ],
          if (revoke) ...[
            const SizedBox(height: 10),
            Text(
              unifiedSwapText(
                context,
                'execution.approvalRecovery.walletOnly',
                'For safety, revoke through your wallet’s token permissions. '
                    'This status does not authorize a revoke action.',
              ),
              style: UnifiedSwapDesign.typography(context).bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _RecoveryQuestions extends StatelessWidget {
  const _RecoveryQuestions({required this.progress, required this.unknown});

  final RouteExecutionProgress progress;
  final bool unknown;

  @override
  Widget build(BuildContext context) {
    final holding = progress.holding;
    final lastConfirmed = _lastConfirmedProgressEvidence(progress);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UnifiedSwapQuestion(
          first: true,
          question: unifiedSwapText(
            context,
            'recovery.whatHappened',
            'What happened?',
          ),
          answer: _recoveryHeadline(context, progress),
          details: _recoveryDetails(context, progress),
        ),
        UnifiedSwapQuestion(
          question: unifiedSwapText(
            context,
            'recovery.whereFunds',
            'Where are the funds?',
          ),
          answer: holding == null
              ? lastConfirmed?.holding != null
                    ? unifiedSwapText(
                        context,
                        'recovery.lastConfirmedCurrentUnknown',
                        'Last confirmed location · current location unknown',
                      )
                    : lastConfirmed != null
                    ? unifiedSwapText(
                        context,
                        'recovery.lastConfirmedEvidenceCurrentUnknown',
                        'Last confirmed evidence · current location unknown',
                      )
                    : unifiedSwapText(
                        context,
                        'recovery.locationUnverified',
                        'Current location is not yet verified',
                      )
              : unifiedSwapText(
                  context,
                  'recovery.verifiedHolding',
                  'Verified current holding',
                ),
          details: holding == null
              ? _lastConfirmedProgressDetails(context, lastConfirmed)
              : unifiedSwapText(
                  context,
                  'recovery.holdingLocation',
                  '{amount} at {address} on {network}.',
                  namedArgs: {
                    'amount': swapAmount(holding.amount, holding.asset),
                    'address': unifiedSwapShortIdentity(holding.address),
                    'network': unifiedSwapNetworkLabel(context, holding.asset),
                  },
                ),
        ),
        UnifiedSwapQuestion(
          question: unifiedSwapText(
            context,
            'recovery.whatCanDo',
            'What can I do now?',
          ),
          answer: unknown
              ? unifiedSwapText(
                  context,
                  'recovery.waitOrReattach',
                  'Wait for verified status or reattach',
                )
              : unifiedSwapText(
                  context,
                  'recovery.authorizedActionsOnly',
                  'Only the actions authorized below are available',
                ),
          details: unifiedSwapText(
            context,
            'recovery.freshConsent',
            'Fresh consent is always required before starting a new swap.',
          ),
        ),
      ],
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.progress});

  final RouteExecutionProgress progress;

  @override
  Widget build(BuildContext context) {
    final hasStages = progress.stageCount > 0;
    final visibleStage = hasStages
        ? (progress.stageIndex + 1).clamp(1, progress.stageCount)
        : 0;
    final ratio = hasStages ? visibleStage / progress.stageCount : null;
    return SwapSectionCard(
      title: unifiedSwapText(
        context,
        'execution.authoritativeProgress',
        'Authoritative progress',
      ),
      icon: Icons.route_rounded,
      semanticLabel:
          '${unifiedSwapText(context, 'execution.authoritativeProgressSemantics', 'Authoritative route progress')}: '
          '${_phase(context, progress.phase)}, '
          '${_outcome(context, progress.outcome)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text(_phase(context, progress.phase))),
              Chip(label: Text(_outcome(context, progress.outcome))),
              if (progress.controls.reconciliationOnly)
                Chip(
                  label: Text(
                    unifiedSwapText(
                      context,
                      'execution.reconciliationOnly',
                      'Reconciliation only',
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (hasStages) ...[
            Text(
              unifiedSwapText(
                context,
                'common.stepOf',
                'Step {current} of {total}',
                namedArgs: {
                  'current': '$visibleStage',
                  'total': '${progress.stageCount}',
                },
              ),
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              key: const Key('swap-stage-progress'),
              value: ratio,
              semanticsLabel: unifiedSwapText(
                context,
                'execution.routeStepOf',
                'Route step {current} of {total}',
                namedArgs: {
                  'current': '$visibleStage',
                  'total': '${progress.stageCount}',
                },
              ),
            ),
          ] else
            Text(
              unifiedSwapText(
                context,
                'execution.stageCountUnavailable',
                'Route step count is not yet available.',
              ),
            ),
          if (hasStages) ...[
            const SizedBox(height: 16),
            _HumanTimeline(progress: progress),
          ],
          const SizedBox(height: 12),
          Text(
            unifiedSwapText(
              context,
              'common.updated',
              'Updated {date}',
              namedArgs: {'date': _executionDate(context, progress.updatedAt)},
            ),
          ),
        ],
      ),
    );
  }
}

class _HumanTimeline extends StatefulWidget {
  const _HumanTimeline({required this.progress});

  final RouteExecutionProgress progress;

  @override
  State<_HumanTimeline> createState() => _HumanTimelineState();
}

class _HumanTimelineState extends State<_HumanTimeline> {
  bool _expanded = false;

  @override
  void didUpdateWidget(_HumanTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress.routeExecutionId !=
            widget.progress.routeExecutionId ||
        oldWidget.progress.stageCount != widget.progress.stageCount) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress;
    final count = progress.stageCount;
    final current = progress.stageIndex.clamp(0, count - 1);
    final ordered = _visibleTimelineIndices(
      count: count,
      current: current,
      expanded: _expanded,
    );
    final collapsedCompletedCount = ordered.isEmpty ? 0 : ordered.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (collapsedCompletedCount > 0)
          _CollapsedStages(count: collapsedCompletedCount),
        for (
          var visibleIndex = 0;
          visibleIndex < ordered.length;
          visibleIndex++
        ) ...[
          _TimelineStage(
            index: ordered[visibleIndex],
            current: current,
            plan: _stagePlan(progress, ordered[visibleIndex]),
            result: _stageResult(progress, ordered[visibleIndex]),
            outcome: progress.outcome,
            last: visibleIndex == ordered.length - 1,
          ),
        ],
        if (count > 12 && current > 0) ...[
          const SizedBox(height: 4),
          TextButton.icon(
            key: const Key('swap-timeline-expand'),
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: Icon(
              _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            ),
            label: Text(
              _expanded
                  ? unifiedSwapText(
                      context,
                      'execution.showFewerSteps',
                      'Show fewer steps',
                    )
                  : unifiedSwapText(
                      context,
                      'execution.showAllSteps',
                      'Show all {count} steps',
                      namedArgs: {'count': '$count'},
                    ),
            ),
          ),
        ],
      ],
    );
  }
}

List<int> _visibleTimelineIndices({
  required int count,
  required int current,
  required bool expanded,
}) {
  if (expanded || count <= 12) {
    return List.generate(count, (index) => index);
  }
  // Long routes keep the current and every remaining semantic stage visible.
  // Only the completed prefix is collapsed, so the 17-stage stress route at
  // stage 13 presents "12 completed" plus the five stages still relevant.
  return List.generate(count - current, (offset) => current + offset);
}

class _CollapsedStages extends StatelessWidget {
  const _CollapsedStages({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(15, 2, 0, 8),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: UnifiedSwapBadge(
          label: unifiedSwapText(
            context,
            'execution.completedStagesCollapsed',
            '{count} completed stages · evidence preserved',
            namedArgs: {'count': '$count'},
          ),
          tone: UnifiedSwapNoticeTone.neutral,
        ),
      ),
    );
  }
}

class _TimelineStage extends StatelessWidget {
  const _TimelineStage({
    required this.index,
    required this.current,
    required this.plan,
    required this.result,
    required this.outcome,
    required this.last,
  });

  final int index;
  final int current;
  final RouteReviewStep? plan;
  final RouteStageHistoryEntry? result;
  final RouteExecutionOutcome outcome;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    final failed =
        result?.phase == RouteStagePhase.failed ||
        (index == current && outcome == RouteExecutionOutcome.failed);
    final cancelled =
        result?.phase == RouteStagePhase.cancelled ||
        (index == current && outcome == RouteExecutionOutcome.cancelled);
    final needsAttention =
        index == current &&
        (outcome == RouteExecutionOutcome.attentionRequired ||
            outcome == RouteExecutionOutcome.recovery);
    final done =
        outcome == RouteExecutionOutcome.completed ||
        result?.phase == RouteStagePhase.completed ||
        result?.completedAt != null ||
        index < current;
    final active =
        index == current && !failed && !cancelled && !needsAttention && !done;
    final toneColor = failed
        ? colors.danger
        : cancelled
        ? colors.textSecondary
        : needsAttention
        ? colors.warning
        : done
        ? colors.success
        : active
        ? colors.brandHover
        : colors.controlBorder;
    final background = failed
        ? colors.dangerContainer
        : cancelled
        ? colors.surfaceHighest
        : needsAttention
        ? colors.warningContainer
        : done
        ? colors.successContainer
        : active
        ? colors.selected
        : colors.surfaceHigh;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: background,
                    border: Border.all(color: toneColor, width: 2),
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox.square(
                    dimension: 32,
                    child: Icon(
                      failed
                          ? Icons.error_outline_rounded
                          : cancelled
                          ? Icons.block_rounded
                          : needsAttention
                          ? Icons.priority_high_rounded
                          : done
                          ? Icons.check_rounded
                          : active
                          ? Icons.more_horiz_rounded
                          : Icons.circle_outlined,
                      size: 17,
                      color: toneColor,
                    ),
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: done ? colors.success : colors.border,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      _timelineStageTitle(context, index, plan),
                      style: UnifiedSwapDesign.typography(context).labelLarge,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    failed
                        ? unifiedSwapText(
                            context,
                            'execution.timeline.failed',
                            'Failed',
                          )
                        : cancelled
                        ? unifiedSwapText(
                            context,
                            'execution.timeline.cancelled',
                            'Cancelled',
                          )
                        : needsAttention
                        ? outcome == RouteExecutionOutcome.recovery
                              ? unifiedSwapText(
                                  context,
                                  'execution.timeline.recovery',
                                  'Recovery',
                                )
                              : unifiedSwapText(
                                  context,
                                  'execution.timeline.needsAttention',
                                  'Needs attention',
                                )
                        : done
                        ? unifiedSwapText(
                            context,
                            'execution.timeline.completed',
                            'Completed',
                          )
                        : active
                        ? unifiedSwapText(
                            context,
                            'execution.timeline.inProgress',
                            'In progress',
                          )
                        : unifiedSwapText(
                            context,
                            'execution.timeline.waiting',
                            'Waiting',
                          ),
                    style: UnifiedSwapDesign.typography(context).bodySmall,
                  ),
                  if (plan != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      plan!.kind == RouteReviewStepKind.atomic
                          ? unifiedSwapText(
                              context,
                              'execution.timeline.directExchange',
                              'Direct exchange',
                            )
                          : unifiedSwapText(
                              context,
                              'execution.timeline.unifiedTransfer',
                              'Unified transfer',
                            ),
                      style: UnifiedSwapDesign.typography(context).bodySmall,
                    ),
                  ],
                  if (result != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      _stagePhaseLabel(context, result!.phase),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (result!.holding case final holding?)
                      Text(
                        unifiedSwapText(
                          context,
                          'execution.timeline.verifiedHolding',
                          'Verified holding: {amount} on {network}',
                          namedArgs: {
                            'amount': swapAmount(holding.amount, holding.asset),
                            'network': unifiedSwapNetworkLabel(
                              context,
                              holding.asset,
                            ),
                          },
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    for (final evidence in result!.evidence)
                      Text(
                        _timelineEvidence(context, evidence),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HoldingCard extends StatelessWidget {
  const _HoldingCard({
    required this.holding,
    required this.clipboardWriter,
    required this.announcement,
  });

  final RouteHolding holding;
  final SwapClipboardWriter clipboardWriter;
  final SwapAnnouncement announcement;

  @override
  Widget build(BuildContext context) {
    return SwapSectionCard(
      title: unifiedSwapText(
        context,
        'execution.verifiedFundLocation',
        'Verified fund location',
      ),
      icon: Icons.location_on_outlined,
      semanticLabel: unifiedSwapText(
        context,
        'execution.verifiedHoldingSemantics',
        'Verified holding {amount} at {address}',
        namedArgs: {
          'amount': swapAmount(holding.amount, holding.asset),
          'address': holding.address,
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            swapAmount(holding.amount, holding.asset),
            key: const Key('swap-verified-holding'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(swapAssetLabel(context, holding.asset)),
          const SizedBox(height: 8),
          Text(
            unifiedSwapText(
              context,
              'execution.verifiedAddress',
              'Verified address',
            ),
          ),
          SwapCopyableValue(
            label: unifiedSwapText(
              context,
              'execution.verifiedAddress',
              'Verified address',
            ),
            value: holding.address,
            valueKey: 'swap-verified-holding-address',
            clipboardWriter: clipboardWriter,
            announcement: announcement,
          ),
          const SizedBox(height: 8),
          Text(
            unifiedSwapText(
              context,
              'execution.recoverySupportNotice',
              'Keep this execution ID and fund location available when asking '
                  'for recovery support.',
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  const _TransactionCard({
    required this.hashes,
    required this.clipboardWriter,
    required this.announcement,
  });

  final List<String> hashes;
  final SwapClipboardWriter clipboardWriter;
  final SwapAnnouncement announcement;

  @override
  Widget build(BuildContext context) {
    return SwapSectionCard(
      title: unifiedSwapText(context, 'execution.transactions', 'Transactions'),
      icon: Icons.link_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < hashes.length; index++) ...[
            Text(
              unifiedSwapText(
                context,
                'execution.transactionNumber',
                'Transaction {number}',
                namedArgs: {'number': '${index + 1}'},
              ),
            ),
            SwapCopyableValue(
              label: unifiedSwapText(
                context,
                'execution.transactionHash',
                'Transaction hash',
              ),
              value: hashes[index],
              valueKey: 'swap-transaction-$index',
              clipboardWriter: clipboardWriter,
              announcement: announcement,
              compact: true,
            ),
            if (index != hashes.length - 1) const Divider(height: 16),
          ],
        ],
      ),
    );
  }
}

class _PendingActionCard extends StatefulWidget {
  const _PendingActionCard({
    required this.progress,
    required this.controlInFlight,
    required this.canSelectRecoveryRoute,
    required this.onDecision,
  });

  final RouteExecutionProgress progress;
  final bool controlInFlight;
  final bool canSelectRecoveryRoute;
  final ValueChanged<RouteExecutionActionKind> onDecision;

  @override
  State<_PendingActionCard> createState() => _PendingActionCardState();
}

class _PendingActionCardState extends State<_PendingActionCard> {
  Timer? _replacementExpiryTimer;

  RouteExecutionProgress get progress => widget.progress;
  bool get controlInFlight => widget.controlInFlight;
  bool get canSelectRecoveryRoute => widget.canSelectRecoveryRoute;
  ValueChanged<RouteExecutionActionKind> get onDecision => widget.onDecision;

  @override
  void initState() {
    super.initState();
    _scheduleReplacementExpiry();
  }

  @override
  void didUpdateWidget(_PendingActionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldExpiry =
        oldWidget.progress.pendingAction?.replacementProposal?.expiresAt;
    final expiry = progress.pendingAction?.replacementProposal?.expiresAt;
    if (oldExpiry != expiry) _scheduleReplacementExpiry();
  }

  void _scheduleReplacementExpiry() {
    _replacementExpiryTimer?.cancel();
    final expiry = progress.pendingAction?.replacementProposal?.expiresAt;
    if (expiry == null) return;
    final remaining = expiry.difference(DateTime.now().toUtc());
    if (remaining <= Duration.zero) return;
    _replacementExpiryTimer = Timer(
      remaining + const Duration(milliseconds: 1),
      () {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _replacementExpiryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pending = progress.pendingAction!;
    if (!progress.isExecutable || !pending.isExecutable) {
      return _ExecutionNotice(
        key: const Key('swap-pending-action-inert'),
        title: unifiedSwapText(
          context,
          'execution.actionUnavailableTitle',
          'Action unavailable',
        ),
        message: unifiedSwapText(
          context,
          'execution.actionUnavailableBody',
          'The requested action type is unknown. No action was submitted.',
        ),
        error: true,
      );
    }
    final allowed = pending.allowedActions;
    final replacement = pending.replacementProposal;
    final replacementStage = replacement == null
        ? null
        : _stagePlanById(progress, replacement.stageId);
    final canAcceptReplacement =
        allowed.contains(RouteExecutionActionKind.acceptReplacement) &&
        replacement != null &&
        replacementStage != null &&
        !replacement.isExpiredAt(DateTime.now().toUtc());
    return SwapSectionCard(
      title: _pendingTitle(context, pending.reason),
      icon: Icons.priority_high_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_pendingMessage(context, pending.reason)),
          if (canAcceptReplacement) ...[
            const SizedBox(height: 8),
            _ReplacementProposalReview(
              proposal: replacement,
              stage: replacementStage,
            ),
          ] else if (allowed.contains(
            RouteExecutionActionKind.acceptReplacement,
          )) ...[
            const SizedBox(height: 8),
            _ExecutionNotice(
              key: const Key('swap-replacement-review-required'),
              title: unifiedSwapText(
                context,
                'execution.updatedConsentTitle',
                'Updated terms unavailable',
              ),
              message: unifiedSwapText(
                context,
                'execution.updatedConsentBody',
                'The wallet cannot safely display the complete typed update. '
                    'Accepting it remains disabled.',
              ),
              error: true,
            ),
          ],
          if (allowed.contains(RouteExecutionActionKind.selectRecoveryRoute) &&
              !canSelectRecoveryRoute) ...[
            const SizedBox(height: 8),
            _ExecutionNotice(
              key: const Key('swap-recovery-selection-unavailable'),
              title: unifiedSwapText(
                context,
                'execution.recoveryReviewTitle',
                'Recovery review required',
              ),
              message: unifiedSwapText(
                context,
                'execution.recoveryReviewBody',
                'Verified holding information is shown above. Selecting a '
                    'new recovery route requires an exact registered Review.',
              ),
              error: false,
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              if (allowed.contains(RouteExecutionActionKind.rejectChange))
                OutlinedButton(
                  key: const Key('swap-decision-reject-change'),
                  onPressed: controlInFlight
                      ? null
                      : () => onDecision(RouteExecutionActionKind.rejectChange),
                  child: Text(
                    unifiedSwapText(
                      context,
                      'execution.rejectChangedRoute',
                      'Reject changed route',
                    ),
                  ),
                ),
              if (canAcceptReplacement)
                FilledButton(
                  key: const Key('swap-decision-accept-replacement'),
                  onPressed: controlInFlight
                      ? null
                      : () => onDecision(
                          RouteExecutionActionKind.acceptReplacement,
                        ),
                  child: Text(
                    unifiedSwapText(
                      context,
                      'execution.acceptUpdatedRoute',
                      'Accept updated route',
                    ),
                  ),
                ),
              if (allowed.contains(RouteExecutionActionKind.stopAfterCurrent))
                OutlinedButton(
                  key: const Key('swap-decision-stop'),
                  onPressed: controlInFlight
                      ? null
                      : () => _confirmStopAfterCurrent(
                          context,
                          progress.routeExecutionId,
                          () => onDecision(
                            RouteExecutionActionKind.stopAfterCurrent,
                          ),
                        ),
                  child: Text(
                    unifiedSwapText(
                      context,
                      'execution.stopAfterCurrentStep',
                      'Stop after current step',
                    ),
                  ),
                ),
              if (allowed.contains(
                    RouteExecutionActionKind.selectRecoveryRoute,
                  ) &&
                  canSelectRecoveryRoute)
                FilledButton.tonal(
                  key: const Key('swap-decision-recovery'),
                  onPressed: controlInFlight
                      ? null
                      : () => onDecision(
                          RouteExecutionActionKind.selectRecoveryRoute,
                        ),
                  child: Text(
                    unifiedSwapText(
                      context,
                      'execution.reviewRecoveryRoute',
                      'Review recovery route',
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReplacementProposalReview extends StatelessWidget {
  const _ReplacementProposalReview({
    required this.proposal,
    required this.stage,
  });

  final RouteReplacementProposal proposal;
  final RouteReviewStep stage;

  @override
  Widget build(BuildContext context) {
    return SwapSectionCard(
      title: unifiedSwapText(
        context,
        'execution.updatedRouteTerms',
        'Updated route terms',
      ),
      icon: Icons.compare_arrows_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ReplacementLine(
            label: unifiedSwapText(
              context,
              'review.expectedReceive',
              'Expected receive',
            ),
            previous: swapAmount(stage.expectedReceive, stage.destination),
            updated: swapAmount(proposal.expectedReceive, stage.destination),
          ),
          _ReplacementLine(
            label: unifiedSwapText(
              context,
              'review.minimumReceive',
              'Minimum receive',
            ),
            previous: swapAmount(stage.minimumReceive, stage.destination),
            updated: swapAmount(proposal.minimumReceive, stage.destination),
          ),
          if (proposal.fees.isNotEmpty) ...[
            const Divider(height: 20),
            Text(
              unifiedSwapText(
                context,
                'execution.updatedFees',
                'Updated costs',
              ),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            for (final fee in proposal.fees)
              Text(
                '${swapFeeKind(context, fee.kind)} · '
                '${swapAmount(fee.amount, fee.asset)}',
              ),
          ],
          if (proposal.requiredTotalNetworkFee case final networkFee?) ...[
            const SizedBox(height: 8),
            Text(
              unifiedSwapText(
                context,
                'execution.updatedMaximumNetworkCost',
                'Updated maximum network cost: {amount}',
                namedArgs: {
                  'amount': swapAmount(networkFee.amount, networkFee.asset),
                },
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            unifiedSwapText(
              context,
              'execution.updatedTermsConsent',
              'Accepting applies only these typed changes to the current '
                  'route. No broader permission is granted.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ReplacementLine extends StatelessWidget {
  const _ReplacementLine({
    required this.label,
    required this.previous,
    required this.updated,
  });

  final String label;
  final String previous;
  final String updated;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: previous,
                    style: const TextStyle(
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                  TextSpan(text: ' → $updated'),
                ],
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerControls extends StatelessWidget {
  const _ServerControls({
    required this.progress,
    required this.controlInFlight,
    required this.onCancel,
    required this.onStopAfterCurrent,
  });

  final RouteExecutionProgress progress;
  final bool controlInFlight;
  final VoidCallback onCancel;
  final VoidCallback onStopAfterCurrent;

  @override
  Widget build(BuildContext context) {
    final controls = progress.controls;
    final safe = progress.isExecutable && !controls.reconciliationOnly;
    final canCancel = safe && controls.canCancel;
    final canStop = safe && controls.canStopAfterCurrent;
    if (!canCancel && !canStop) {
      return _ExecutionNotice(
        key: const Key('swap-controls-unavailable'),
        title: controls.reconciliationOnly
            ? unifiedSwapText(
                context,
                'execution.reconciliationOnly',
                'Reconciliation only',
              )
            : unifiedSwapText(
                context,
                'execution.noControlsTitle',
                'No movement controls available',
              ),
        message: controls.reconciliationOnly
            ? unifiedSwapText(
                context,
                'execution.reconciliationOnlyBody',
                'The wallet will continue status and recovery reconciliation.',
              )
            : unifiedSwapText(
                context,
                'execution.noControlsBody',
                'Cancellation availability is determined by the current route '
                    'status, not by the screen.',
              ),
        error: false,
      );
    }
    return SwapSectionCard(
      title: unifiedSwapText(
        context,
        'execution.availableControls',
        'Available controls',
      ),
      icon: Icons.tune_rounded,
      semanticLabel: unifiedSwapText(
        context,
        'execution.controlsSemantics',
        'Controls authorized by the current route status',
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          if (canStop)
            OutlinedButton(
              key: const Key('swap-control-stop'),
              onPressed: controlInFlight
                  ? null
                  : () => _confirmStopAfterCurrent(
                      context,
                      progress.routeExecutionId,
                      onStopAfterCurrent,
                    ),
              child: Text(
                unifiedSwapText(
                  context,
                  'execution.stopAfterCurrentStep',
                  'Stop after current step',
                ),
              ),
            ),
          if (canCancel)
            FilledButton.tonal(
              key: const Key('swap-control-cancel'),
              onPressed: controlInFlight
                  ? null
                  : () => _confirmCancellation(
                      context,
                      progress.routeExecutionId,
                      onCancel,
                    ),
              child: Text(
                unifiedSwapText(
                  context,
                  'execution.cancelRoute',
                  'Cancel route',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ExecutionNotice extends StatelessWidget {
  const _ExecutionNotice({
    required this.title,
    required this.message,
    required this.error,
    super.key,
  });

  final String title;
  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: error,
      container: true,
      child: Material(
        color: error ? colors.errorContainer : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(message),
            ],
          ),
        ),
      ),
    );
  }
}

String _heroTitle(
  BuildContext context,
  RouteExecutionLoadStatus status,
  RouteExecutionProgress? progress,
) {
  if (status == RouteExecutionLoadStatus.observing && progress != null) {
    return switch (progress.phase) {
      RouteExecutionPhase.validating => unifiedSwapText(
        context,
        'execution.hero.preparing',
        'Preparing swap',
      ),
      RouteExecutionPhase.awaitingApproval => unifiedSwapText(
        context,
        'execution.hero.approvalRequired',
        'Approval required',
      ),
      RouteExecutionPhase.approvalPending => unifiedSwapText(
        context,
        'execution.hero.approving',
        'Approving exact amount',
      ),
      RouteExecutionPhase.awaitingSignature => unifiedSwapText(
        context,
        'execution.hero.signatureRequired',
        'Signature required',
      ),
      RouteExecutionPhase.signed => unifiedSwapText(
        context,
        'execution.hero.signatureReceived',
        'Signature received',
      ),
      RouteExecutionPhase.broadcasting => unifiedSwapText(
        context,
        'execution.hero.broadcasting',
        'Sending transaction',
      ),
      RouteExecutionPhase.sourcePending => unifiedSwapText(
        context,
        'execution.hero.sourcePending',
        'Waiting for source confirmation',
      ),
      RouteExecutionPhase.sourceConfirmed => unifiedSwapText(
        context,
        'execution.hero.sourceConfirmed',
        'Source confirmed',
      ),
      RouteExecutionPhase.bridgePending => unifiedSwapText(
        context,
        'execution.hero.transferPending',
        'Transfer in progress',
      ),
      RouteExecutionPhase.destinationConfirmed => unifiedSwapText(
        context,
        'execution.hero.destinationConfirmed',
        'Destination confirmed',
      ),
      RouteExecutionPhase.atomicFill => unifiedSwapText(
        context,
        'execution.hero.exchanging',
        'Completing exchange',
      ),
      RouteExecutionPhase.awaitingUserAction => unifiedSwapText(
        context,
        'execution.status.attentionTitle',
        'Action required',
      ),
      RouteExecutionPhase.stopAfterCurrent => unifiedSwapText(
        context,
        'execution.hero.stopping',
        'Stopping after current step',
      ),
      RouteExecutionPhase.partial ||
      RouteExecutionPhase.refundPending ||
      RouteExecutionPhase.refunded ||
      RouteExecutionPhase.manualIntervention => _recoveryHeadline(
        context,
        progress,
      ),
      RouteExecutionPhase.completed => unifiedSwapText(
        context,
        'execution.status.completedTitle',
        'Unified Swap completed',
      ),
      RouteExecutionPhase.cancelled => unifiedSwapText(
        context,
        'execution.status.cancelledTitle',
        'Unified Swap cancelled',
      ),
      RouteExecutionPhase.failed => unifiedSwapText(
        context,
        'execution.status.failedTitle',
        'Unified Swap failed',
      ),
      RouteExecutionPhase.unknown => unifiedSwapText(
        context,
        'execution.status.unknownTitle',
        'Execution status unavailable',
      ),
    };
  }
  if ((status == RouteExecutionLoadStatus.attentionRequired ||
          status == RouteExecutionLoadStatus.recovery) &&
      progress != null) {
    return _recoveryHeadline(context, progress);
  }
  return switch (status) {
    RouteExecutionLoadStatus.starting => unifiedSwapText(
      context,
      'execution.status.startingTitle',
      'Starting Unified Swap',
    ),
    RouteExecutionLoadStatus.reattaching => unifiedSwapText(
      context,
      'execution.status.reattachingTitle',
      'Reattaching to execution',
    ),
    RouteExecutionLoadStatus.observing => unifiedSwapText(
      context,
      'execution.status.observingTitle',
      'Unified Swap in progress',
    ),
    RouteExecutionLoadStatus.attentionRequired => unifiedSwapText(
      context,
      'execution.status.attentionTitle',
      'Action required',
    ),
    RouteExecutionLoadStatus.recovery => unifiedSwapText(
      context,
      'execution.status.recoveryTitle',
      'Recovery information available',
    ),
    RouteExecutionLoadStatus.completed => unifiedSwapText(
      context,
      'execution.status.completedTitle',
      'Unified Swap completed',
    ),
    RouteExecutionLoadStatus.cancelled => unifiedSwapText(
      context,
      'execution.status.cancelledTitle',
      'Unified Swap cancelled',
    ),
    RouteExecutionLoadStatus.failed => unifiedSwapText(
      context,
      'execution.status.failedTitle',
      'Unified Swap failed',
    ),
    RouteExecutionLoadStatus.unknown => unifiedSwapText(
      context,
      'execution.status.unknownTitle',
      'Execution status unavailable',
    ),
    RouteExecutionLoadStatus.idle || RouteExecutionLoadStatus.reviewRequired =>
      unifiedSwapText(context, 'execution.status.idleTitle', 'Unified Swap'),
  };
}

String _heroDescription(
  BuildContext context,
  RouteExecutionLoadStatus status,
  RouteExecutionProgress? progress,
) {
  if (status == RouteExecutionLoadStatus.observing && progress != null) {
    return switch (progress.phase) {
      RouteExecutionPhase.validating => unifiedSwapText(
        context,
        'execution.hero.preparingBody',
        'The wallet is validating the exact route before anything moves.',
      ),
      RouteExecutionPhase.awaitingApproval => unifiedSwapText(
        context,
        'execution.hero.approvalRequiredBody',
        'Review and sign only the exact token permission shown for this swap.',
      ),
      RouteExecutionPhase.approvalPending => unifiedSwapText(
        context,
        'execution.hero.approvingBody',
        'The exact token approval is waiting for network confirmation.',
      ),
      RouteExecutionPhase.awaitingSignature => unifiedSwapText(
        context,
        'execution.hero.signatureRequiredBody',
        'Nothing moves until you review and sign the current transaction.',
      ),
      RouteExecutionPhase.signed => unifiedSwapText(
        context,
        'execution.hero.signatureReceivedBody',
        'The wallet is checking whether the signed transaction was broadcast.',
      ),
      RouteExecutionPhase.broadcasting ||
      RouteExecutionPhase.sourcePending => unifiedSwapText(
        context,
        'execution.hero.sourcePendingBody',
        'The source transaction is being reconciled on its network.',
      ),
      RouteExecutionPhase.sourceConfirmed ||
      RouteExecutionPhase.bridgePending => unifiedSwapText(
        context,
        'execution.hero.transferPendingBody',
        'The source is confirmed and the next route boundary is being checked.',
      ),
      RouteExecutionPhase.destinationConfirmed ||
      RouteExecutionPhase.atomicFill => unifiedSwapText(
        context,
        'execution.hero.finishingBody',
        'The destination result is confirmed and final route work is finishing.',
      ),
      RouteExecutionPhase.awaitingUserAction ||
      RouteExecutionPhase.stopAfterCurrent ||
      RouteExecutionPhase.partial ||
      RouteExecutionPhase.refundPending ||
      RouteExecutionPhase.refunded ||
      RouteExecutionPhase.manualIntervention => _recoveryDetails(
        context,
        progress,
      ),
      RouteExecutionPhase.completed => unifiedSwapText(
        context,
        'execution.status.completedBody',
        'The route reached its authoritative completed state.',
      ),
      RouteExecutionPhase.cancelled => unifiedSwapText(
        context,
        'execution.status.cancelledBody',
        'The route reached its authoritative cancelled state.',
      ),
      RouteExecutionPhase.failed => unifiedSwapText(
        context,
        'execution.status.failedBody',
        'The route failed. Review the verified evidence before taking action.',
      ),
      RouteExecutionPhase.unknown => unifiedSwapText(
        context,
        'execution.status.unknownBody',
        'No movement action is available until the status is understood.',
      ),
    };
  }
  if ((status == RouteExecutionLoadStatus.attentionRequired ||
          status == RouteExecutionLoadStatus.recovery) &&
      progress != null) {
    return _recoveryDetails(context, progress);
  }
  return switch (status) {
    RouteExecutionLoadStatus.starting => unifiedSwapText(
      context,
      'execution.status.startingBody',
      'The exact reviewed route is being registered with the wallet engine.',
    ),
    RouteExecutionLoadStatus.reattaching => unifiedSwapText(
      context,
      'execution.status.reattachingBody',
      'The wallet is rebuilding live observation from durable route activity.',
    ),
    RouteExecutionLoadStatus.observing => unifiedSwapText(
      context,
      'execution.status.observingBody',
      'Status is authoritative. You may leave this screen safely.',
    ),
    RouteExecutionLoadStatus.attentionRequired => unifiedSwapText(
      context,
      'execution.status.attentionBody',
      'Review the verified fund location and only the actions shown below.',
    ),
    RouteExecutionLoadStatus.recovery => unifiedSwapText(
      context,
      'execution.status.recoveryBody',
      'Funds have a verified location. Keep reconciliation available.',
    ),
    RouteExecutionLoadStatus.completed => unifiedSwapText(
      context,
      'execution.status.completedBody',
      'The route reached its authoritative completed state.',
    ),
    RouteExecutionLoadStatus.cancelled => unifiedSwapText(
      context,
      'execution.status.cancelledBody',
      'The route reached its authoritative cancelled state.',
    ),
    RouteExecutionLoadStatus.failed => unifiedSwapText(
      context,
      'execution.status.failedBody',
      'The route failed. Review the verified evidence before taking action.',
    ),
    RouteExecutionLoadStatus.unknown => unifiedSwapText(
      context,
      'execution.status.unknownBody',
      'No movement action is available until the status is understood.',
    ),
    RouteExecutionLoadStatus.idle ||
    RouteExecutionLoadStatus.reviewRequired => '',
  };
}

String _phase(BuildContext context, RouteExecutionPhase phase) {
  final fallback = switch (phase) {
    RouteExecutionPhase.validating => 'Validating',
    RouteExecutionPhase.awaitingApproval => 'Awaiting approval',
    RouteExecutionPhase.approvalPending => 'Approval pending',
    RouteExecutionPhase.awaitingSignature => 'Awaiting signature',
    RouteExecutionPhase.signed => 'Signed',
    RouteExecutionPhase.broadcasting => 'Broadcasting',
    RouteExecutionPhase.sourcePending => 'Source transaction pending',
    RouteExecutionPhase.sourceConfirmed => 'Source confirmed',
    RouteExecutionPhase.bridgePending => 'Transfer pending',
    RouteExecutionPhase.destinationConfirmed => 'Destination confirmed',
    RouteExecutionPhase.atomicFill => 'Exchange',
    RouteExecutionPhase.partial => 'Intermediate holding',
    RouteExecutionPhase.awaitingUserAction => 'Awaiting your action',
    RouteExecutionPhase.stopAfterCurrent => 'Stopping after current step',
    RouteExecutionPhase.refundPending => 'Refund pending',
    RouteExecutionPhase.refunded => 'Refund verified',
    RouteExecutionPhase.manualIntervention => 'Manual recovery required',
    RouteExecutionPhase.completed => 'Completed',
    RouteExecutionPhase.cancelled => 'Cancelled',
    RouteExecutionPhase.failed => 'Failed',
    RouteExecutionPhase.unknown => 'Unknown phase',
  };
  return unifiedSwapText(context, 'execution.phase.${phase.name}', fallback);
}

String _outcome(BuildContext context, RouteExecutionOutcome outcome) {
  final fallback = switch (outcome) {
    RouteExecutionOutcome.active => 'Active',
    RouteExecutionOutcome.attentionRequired => 'Needs attention',
    RouteExecutionOutcome.recovery => 'Recovery',
    RouteExecutionOutcome.completed => 'Completed',
    RouteExecutionOutcome.cancelled => 'Cancelled',
    RouteExecutionOutcome.failed => 'Failed',
    RouteExecutionOutcome.unknown => 'Unknown outcome',
  };
  return unifiedSwapText(
    context,
    'execution.outcome.${outcome.name}',
    fallback,
  );
}

RouteReviewStep? _stagePlan(RouteExecutionProgress progress, int sequence) {
  for (final stage in progress.stages) {
    if (stage.sequence == sequence) return stage;
  }
  return null;
}

RouteReviewStep? _stagePlanById(
  RouteExecutionProgress progress,
  String stageId,
) {
  for (final stage in progress.stages) {
    if (stage.stageId == stageId) return stage;
  }
  return null;
}

RouteStageHistoryEntry? _stageResult(
  RouteExecutionProgress progress,
  int sequence,
) {
  for (final result in progress.stageResults) {
    if (result.sequence == sequence) return result;
  }
  return null;
}

String _timelineStageTitle(
  BuildContext context,
  int index,
  RouteReviewStep? stage,
) {
  if (stage == null) {
    return unifiedSwapText(
      context,
      'common.stepNumber',
      'Step {number}',
      namedArgs: {'number': '${index + 1}'},
    );
  }
  return unifiedSwapText(
    context,
    'execution.timeline.routeLeg',
    '{source} on {sourceNetwork} → {destination} on {destinationNetwork}',
    namedArgs: {
      'source': stage.source.ticker,
      'sourceNetwork': unifiedSwapNetworkLabel(context, stage.source),
      'destination': stage.destination.ticker,
      'destinationNetwork': unifiedSwapNetworkLabel(context, stage.destination),
    },
  );
}

String _stagePhaseLabel(BuildContext context, RouteStagePhase phase) {
  final fallback = switch (phase) {
    RouteStagePhase.preparing => 'Preparing',
    RouteStagePhase.approval => 'Approval',
    RouteStagePhase.sending => 'Sending',
    RouteStagePhase.receiving => 'Receiving',
    RouteStagePhase.reconciliation => 'Reconciling',
    RouteStagePhase.recovery => 'Recovery',
    RouteStagePhase.completed => 'Completed',
    RouteStagePhase.cancelled => 'Cancelled',
    RouteStagePhase.failed => 'Failed',
    RouteStagePhase.unknown => 'Unknown stage status',
  };
  return unifiedSwapText(
    context,
    'execution.timeline.phase.${phase.name}',
    fallback,
  );
}

String _timelineEvidence(BuildContext context, RouteSafeEvidence evidence) {
  final label = switch (evidence.kind) {
    RouteEvidenceKind.sourceReceipt => unifiedSwapText(
      context,
      'execution.timeline.sourceReceipt',
      'Source receipt',
    ),
    RouteEvidenceKind.receiving => unifiedSwapText(
      context,
      'execution.timeline.receivingEvidence',
      'Receiving evidence',
    ),
    RouteEvidenceKind.refund => unifiedSwapText(
      context,
      'execution.timeline.refundEvidence',
      'Refund evidence',
    ),
    RouteEvidenceKind.providerStatus => unifiedSwapText(
      context,
      'execution.timeline.routeStatusEvidence',
      'Route status evidence',
    ),
    RouteEvidenceKind.unknown => unifiedSwapText(
      context,
      'execution.timeline.unknownEvidence',
      'Unknown evidence',
    ),
  };
  final details = <String>[
    if (evidence.status case final String status) status,
    if (evidence.substatus case final String substatus) substatus,
    if (evidence.reference case final String reference)
      unifiedSwapShortIdentity(reference, leading: 8, tail: 6),
  ];
  return details.isEmpty ? label : '$label · ${details.join(' · ')}';
}

typedef _LastConfirmedProgressEvidence = ({
  RouteHolding? holding,
  RouteSafeEvidence? evidence,
  String? transactionHash,
});

_LastConfirmedProgressEvidence? _lastConfirmedProgressEvidence(
  RouteExecutionProgress progress,
) {
  for (final stage in progress.stageResults.reversed) {
    if (stage.holding case final holding?) {
      return (holding: holding, evidence: null, transactionHash: null);
    }
  }
  for (final stage in progress.stageResults.reversed) {
    for (final evidence in stage.evidence.reversed) {
      if (evidence.kind != RouteEvidenceKind.unknown) {
        return (holding: null, evidence: evidence, transactionHash: null);
      }
    }
    if (stage.transactionHashes case [..., final transactionHash]) {
      return (holding: null, evidence: null, transactionHash: transactionHash);
    }
  }
  if (progress.transactionHashes case [..., final transactionHash]) {
    return (holding: null, evidence: null, transactionHash: transactionHash);
  }
  return null;
}

String _lastConfirmedProgressDetails(
  BuildContext context,
  _LastConfirmedProgressEvidence? lastConfirmed,
) {
  if (lastConfirmed?.holding case final holding?) {
    return unifiedSwapText(
      context,
      'recovery.lastConfirmedHolding',
      'Last confirmed: {amount} at {address} on {network}. Current location '
          'is not verified.',
      namedArgs: {
        'amount': swapAmount(holding.amount, holding.asset),
        'address': unifiedSwapShortIdentity(holding.address),
        'network': unifiedSwapNetworkLabel(context, holding.asset),
      },
    );
  }
  if (lastConfirmed?.evidence case final evidence?) {
    return unifiedSwapText(
      context,
      'recovery.authoritativeEvidenceCurrentUnknown',
      '{evidence} is recorded for the last route boundary. Current fund '
          'location is not verified.',
      namedArgs: {'evidence': _timelineEvidence(context, evidence)},
    );
  }
  if (lastConfirmed?.transactionHash case final hash?) {
    return unifiedSwapText(
      context,
      'recovery.transactionEvidenceCurrentUnknown',
      'Transaction evidence {hash} is recorded and may still be pending. '
          'Current fund location is not verified.',
      namedArgs: {'hash': unifiedSwapShortIdentity(hash, leading: 8, tail: 6)},
    );
  }
  return unifiedSwapText(
    context,
    'recovery.noVerifiedLocation',
    'No verified current fund location is available. The wallet will not '
        'guess.',
  );
}

bool _isTerminal(RouteExecutionLoadStatus status) =>
    status == RouteExecutionLoadStatus.completed ||
    status == RouteExecutionLoadStatus.cancelled ||
    status == RouteExecutionLoadStatus.failed;

String _pendingTitle(BuildContext context, RoutePendingActionReason reason) {
  final fallback = switch (reason) {
    RoutePendingActionReason.candidateChanged => 'Route terms changed',
    RoutePendingActionReason.recoveryRequired => 'Recovery route required',
    RoutePendingActionReason.approvalRequired => 'Approval required',
    RoutePendingActionReason.stopAfterCurrent => 'Stop requested',
    RoutePendingActionReason.nonNetworkFeeLimitExceeded => 'Swap cost changed',
    RoutePendingActionReason.networkFeeCapExceeded => 'Network cost changed',
    RoutePendingActionReason.unknown => 'Unknown action required',
  };
  return unifiedSwapText(
    context,
    'execution.pending.${reason.name}Title',
    fallback,
  );
}

String _pendingMessage(BuildContext context, RoutePendingActionReason reason) {
  final fallback = switch (reason) {
    RoutePendingActionReason.candidateChanged =>
      'Changed terms require a new exact Review before acceptance.',
    RoutePendingActionReason.recoveryRequired =>
      'Use the verified holding above to review a recovery route.',
    RoutePendingActionReason.approvalRequired =>
      'Return to an exact approval Review before authorizing a token spend.',
    RoutePendingActionReason.stopAfterCurrent =>
      'The route can stop only at the server-authorized boundary.',
    RoutePendingActionReason.nonNetworkFeeLimitExceeded =>
      'A quoted non-network cost is above the exact consented limit. A fresh '
          'Review is required.',
    RoutePendingActionReason.networkFeeCapExceeded =>
      'A network cost is above the consented maximum. No further step will '
          'start without an authorized update.',
    RoutePendingActionReason.unknown =>
      'No action can be submitted for an unknown request.',
  };
  return unifiedSwapText(
    context,
    'execution.pending.${reason.name}Body',
    fallback,
  );
}

IconData _statusIcon(
  RouteExecutionLoadStatus status,
  RouteExecutionPhase? phase,
) => switch (status) {
  RouteExecutionLoadStatus.completed => Icons.check_rounded,
  RouteExecutionLoadStatus.cancelled => Icons.block_rounded,
  RouteExecutionLoadStatus.failed => Icons.error_outline_rounded,
  RouteExecutionLoadStatus.recovery => Icons.settings_backup_restore_rounded,
  RouteExecutionLoadStatus.attentionRequired => Icons.priority_high_rounded,
  RouteExecutionLoadStatus.unknown => Icons.help_outline_rounded,
  RouteExecutionLoadStatus.starting ||
  RouteExecutionLoadStatus.reattaching => Icons.sync_rounded,
  RouteExecutionLoadStatus.observing => switch (phase) {
    RouteExecutionPhase.awaitingApproval ||
    RouteExecutionPhase.approvalPending => Icons.verified_user_outlined,
    RouteExecutionPhase.awaitingSignature => Icons.draw_outlined,
    RouteExecutionPhase.signed => Icons.manage_search_rounded,
    RouteExecutionPhase.broadcasting ||
    RouteExecutionPhase.sourcePending => Icons.send_rounded,
    RouteExecutionPhase.sourceConfirmed ||
    RouteExecutionPhase.bridgePending => Icons.route_rounded,
    RouteExecutionPhase.destinationConfirmed ||
    RouteExecutionPhase.completed => Icons.check_rounded,
    RouteExecutionPhase.stopAfterCurrent => Icons.stop_circle_outlined,
    RouteExecutionPhase.partial ||
    RouteExecutionPhase.refundPending ||
    RouteExecutionPhase.refunded ||
    RouteExecutionPhase.manualIntervention =>
      Icons.settings_backup_restore_rounded,
    _ => Icons.route_rounded,
  },
  RouteExecutionLoadStatus.idle ||
  RouteExecutionLoadStatus.reviewRequired => Icons.swap_horiz_rounded,
};

UnifiedSwapNoticeTone _statusTone(
  RouteExecutionLoadStatus status,
  bool unknown,
) {
  if (unknown) return UnifiedSwapNoticeTone.warning;
  return switch (status) {
    RouteExecutionLoadStatus.completed => UnifiedSwapNoticeTone.success,
    RouteExecutionLoadStatus.cancelled => UnifiedSwapNoticeTone.neutral,
    RouteExecutionLoadStatus.failed => UnifiedSwapNoticeTone.danger,
    RouteExecutionLoadStatus.recovery ||
    RouteExecutionLoadStatus.attentionRequired => UnifiedSwapNoticeTone.warning,
    RouteExecutionLoadStatus.starting ||
    RouteExecutionLoadStatus.reattaching ||
    RouteExecutionLoadStatus.observing => UnifiedSwapNoticeTone.brand,
    RouteExecutionLoadStatus.unknown => UnifiedSwapNoticeTone.warning,
    RouteExecutionLoadStatus.idle ||
    RouteExecutionLoadStatus.reviewRequired => UnifiedSwapNoticeTone.neutral,
  };
}

String _recoveryHeadline(
  BuildContext context,
  RouteExecutionProgress progress,
) {
  return switch (progress.phase) {
    RouteExecutionPhase.signed ||
    RouteExecutionPhase.broadcasting => unifiedSwapText(
      context,
      'recovery.ambiguousHeadline',
      'We’re checking whether the transaction was sent',
    ),
    RouteExecutionPhase.partial => unifiedSwapText(
      context,
      'recovery.partialHeadline',
      'The route completed with an intermediate asset',
    ),
    RouteExecutionPhase.manualIntervention => unifiedSwapText(
      context,
      'recovery.manualHeadline',
      'Recovery needs your attention',
    ),
    RouteExecutionPhase.refundPending => unifiedSwapText(
      context,
      'recovery.refundPendingHeadline',
      'A refund is being checked',
    ),
    RouteExecutionPhase.refunded => unifiedSwapText(
      context,
      'recovery.refundedHeadline',
      'The refund was verified',
    ),
    _ => _phase(context, progress.phase),
  };
}

String _recoveryDetails(BuildContext context, RouteExecutionProgress progress) {
  return switch (progress.phase) {
    RouteExecutionPhase.signed ||
    RouteExecutionPhase.broadcasting => unifiedSwapText(
      context,
      'recovery.ambiguousBody',
      'The signing step completed, but the network result is unclear.',
    ),
    RouteExecutionPhase.partial => unifiedSwapText(
      context,
      'recovery.partialBody',
      'A different or intermediate asset was received. This does not by '
          'itself mean that only part of the amount arrived. Later steps '
          'remain stopped until the holding and evidence are verified.',
    ),
    RouteExecutionPhase.manualIntervention => unifiedSwapText(
      context,
      'recovery.manualBody',
      'Automatic progress stopped at a verified boundary.',
    ),
    RouteExecutionPhase.refundPending => unifiedSwapText(
      context,
      'recovery.refundPendingBody',
      'The wallet is reconciling refund evidence. Do not start a duplicate.',
    ),
    RouteExecutionPhase.refunded => unifiedSwapText(
      context,
      'recovery.refundedBody',
      'The returned holding is recorded with this execution.',
    ),
    _ => unifiedSwapText(
      context,
      'recovery.reconcilingBody',
      'The wallet is reconciling authoritative route status.',
    ),
  };
}

String _failure(BuildContext context, RouteExecutionFailure failure) {
  final fallback = switch (failure) {
    RouteExecutionFailure.invalidReview =>
      'The Review did not match the wallet-bound execution consent.',
    RouteExecutionFailure.reviewExpired =>
      'The exact reviewed terms expired before execution started.',
    RouteExecutionFailure.capabilityUnavailable =>
      'This wallet or exact route is no longer executable.',
    RouteExecutionFailure.controlNotAuthorized =>
      'That movement control is not authorized by current route status.',
    RouteExecutionFailure.actionNotAuthorized =>
      'That action is not authorized by the current route revision.',
    RouteExecutionFailure.notFound =>
      'No wallet-scoped durable execution was found for this ID.',
    RouteExecutionFailure.conflict =>
      'The execution identity conflicts with durable route state.',
    RouteExecutionFailure.networkUnavailable =>
      'Live observation stopped. Reattach before relying on status.',
    RouteExecutionFailure.storageUnavailable =>
      'Durable route state is temporarily unavailable.',
    RouteExecutionFailure.serviceUnavailable =>
      'The route service is temporarily unavailable.',
    RouteExecutionFailure.unknown =>
      'The wallet cannot safely interpret this execution state.',
  };
  return unifiedSwapText(
    context,
    'execution.failure.${failure.name}',
    fallback,
  );
}

String _executionDate(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final material = MaterialLocalizations.of(context);
  return '${material.formatMediumDate(local)} '
      '${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}

Future<void> _confirmCancellation(
  BuildContext context,
  String routeExecutionId,
  VoidCallback onConfirmed,
) async {
  final confirmed = await showUnifiedSwapSensitiveConfirmation(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      key: const Key('swap-cancel-confirmation'),
      scrollable: true,
      title: Text(
        unifiedSwapText(
          dialogContext,
          'execution.cancelDialogTitle',
          'Cancel this swap?',
        ),
      ),
      content: _exactExecutionRouteTarget(
        dialogContext,
        body: unifiedSwapText(
          dialogContext,
          'execution.cancelDialogBody',
          'Cancellation is available only at the current verified route '
              'boundary. Already completed steps cannot be reversed.',
        ),
        routeExecutionId: routeExecutionId,
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(
            unifiedSwapText(dialogContext, 'execution.keepSwap', 'Keep swap'),
          ),
        ),
        FilledButton(
          key: const Key('swap-confirm-cancel'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(
            unifiedSwapText(
              dialogContext,
              'execution.cancelSwap',
              'Cancel swap',
            ),
          ),
        ),
      ],
    ),
  );
  if (confirmed) onConfirmed();
}

Future<void> _confirmStopAfterCurrent(
  BuildContext context,
  String routeExecutionId,
  VoidCallback onConfirmed,
) async {
  final confirmed = await showUnifiedSwapSensitiveConfirmation(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      key: const Key('swap-stop-confirmation'),
      scrollable: true,
      title: Text(
        unifiedSwapText(
          dialogContext,
          'execution.stopDialogTitle',
          'Stop after the current step?',
        ),
      ),
      content: _exactExecutionRouteTarget(
        dialogContext,
        body: unifiedSwapText(
          dialogContext,
          'execution.stopDialogBody',
          'The current step will finish, then the route will stop at the next '
              'server-authorized boundary. Completed steps cannot be reversed.',
        ),
        routeExecutionId: routeExecutionId,
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(
            unifiedSwapText(dialogContext, 'execution.keepGoing', 'Keep going'),
          ),
        ),
        FilledButton(
          key: const Key('swap-confirm-stop'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(
            unifiedSwapText(
              dialogContext,
              'execution.confirmStop',
              'Stop after current step',
            ),
          ),
        ),
      ],
    ),
  );
  if (confirmed) onConfirmed();
}

Widget _exactExecutionRouteTarget(
  BuildContext context, {
  required String body,
  required String routeExecutionId,
}) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(body),
    const SizedBox(height: 12),
    Text(
      unifiedSwapText(
        context,
        'common.exactTargetIntro',
        'This action applies only to:',
      ),
    ),
    const SizedBox(height: 4),
    SelectableText(
      '${unifiedSwapText(context, 'common.executionId', 'Execution ID')}: '
      '$routeExecutionId',
    ),
  ],
);

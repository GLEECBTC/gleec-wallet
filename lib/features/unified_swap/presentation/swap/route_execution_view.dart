import 'package:flutter/material.dart';
import 'package:web_dex/features/unified_swap/application/route_execution_bloc.dart';
import 'package:web_dex/features/unified_swap/domain/route_activity_models.dart';
import 'package:web_dex/features/unified_swap/domain/route_execution_models.dart';
import 'package:web_dex/features/unified_swap/presentation/swap/swap_widgets.dart';
import 'package:web_dex/features/unified_swap/presentation/unified_swap_design.dart';

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
    return ColoredBox(
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
              ),
              const SizedBox(height: 12),
              UnifiedSwapStatusHero(
                title: _title(context, state.status),
                message: _description(context, state.status),
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
                  _HoldingCard(holding: progress.holding!),
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
    final hasEvidence = progress.transactionHashes.isNotEmpty;
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
              ? unifiedSwapText(
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
              ? hasEvidence
                    ? unifiedSwapText(
                        context,
                        'recovery.pendingEvidence',
                        'A transaction may still be pending. Reconciliation '
                            'continues from the last confirmed evidence.',
                      )
                    : unifiedSwapText(
                        context,
                        'recovery.noVerifiedLocation',
                        'No verified current fund location is available. The '
                            'wallet will not guess.',
                      )
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

class _HumanTimeline extends StatelessWidget {
  const _HumanTimeline({required this.progress});

  final RouteExecutionProgress progress;

  @override
  Widget build(BuildContext context) {
    final count = progress.stageCount;
    final current = progress.stageIndex.clamp(0, count - 1);
    final indices = <int>{};
    if (count <= 7) {
      indices.addAll(List.generate(count, (index) => index));
    } else {
      indices
        ..add(0)
        ..addAll([
          (current - 1).clamp(0, count - 1),
          current,
          (current + 1).clamp(0, count - 1),
        ])
        ..add(count - 1);
    }
    final ordered = indices.toList()..sort();
    return Column(
      children: [
        for (
          var visibleIndex = 0;
          visibleIndex < ordered.length;
          visibleIndex++
        ) ...[
          if (visibleIndex > 0 &&
              ordered[visibleIndex] - ordered[visibleIndex - 1] > 1)
            _CollapsedStages(
              count: ordered[visibleIndex] - ordered[visibleIndex - 1] - 1,
            ),
          _TimelineStage(
            index: ordered[visibleIndex],
            current: current,
            terminalFailure:
                progress.outcome == RouteExecutionOutcome.failed ||
                progress.outcome == RouteExecutionOutcome.cancelled,
          ),
        ],
      ],
    );
  }
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
            'execution.completedSteps',
            '{count} completed steps',
            namedArgs: {'count': '$count'},
          ),
          tone: UnifiedSwapNoticeTone.success,
        ),
      ),
    );
  }
}

class _TimelineStage extends StatelessWidget {
  const _TimelineStage({
    required this.index,
    required this.current,
    required this.terminalFailure,
  });

  final int index;
  final int current;
  final bool terminalFailure;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    final done = index < current;
    final active = index == current;
    final failed = active && terminalFailure;
    final toneColor = failed
        ? colors.danger
        : done
        ? colors.success
        : active
        ? colors.brandHover
        : colors.controlBorder;
    final background = failed
        ? colors.dangerContainer
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
                if (!active || !terminalFailure)
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
                  Text(
                    unifiedSwapText(
                      context,
                      'common.stepNumber',
                      'Step {number}',
                      namedArgs: {'number': '${index + 1}'},
                    ),
                    style: UnifiedSwapDesign.typography(context).labelLarge,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    failed
                        ? unifiedSwapText(
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
  const _HoldingCard({required this.holding});

  final RouteHolding holding;

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
          SelectableText(holding.address),
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

class _PendingActionCard extends StatelessWidget {
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
    return SwapSectionCard(
      title: _pendingTitle(context, pending.reason),
      icon: Icons.priority_high_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_pendingMessage(context, pending.reason)),
          if (allowed.contains(RouteExecutionActionKind.acceptReplacement)) ...[
            const SizedBox(height: 8),
            _ExecutionNotice(
              key: const Key('swap-replacement-review-required'),
              title: unifiedSwapText(
                context,
                'execution.updatedConsentTitle',
                'Updated consent required',
              ),
              message: unifiedSwapText(
                context,
                'execution.updatedConsentBody',
                'Accepting changed route terms stays disabled until the '
                    'wallet can show and bind an exact replacement Review.',
              ),
              error: false,
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
              if (allowed.contains(RouteExecutionActionKind.stopAfterCurrent))
                OutlinedButton(
                  key: const Key('swap-decision-stop'),
                  onPressed: controlInFlight
                      ? null
                      : () => onDecision(
                          RouteExecutionActionKind.stopAfterCurrent,
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
              onPressed: controlInFlight ? null : onStopAfterCurrent,
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
                  : () => _confirmCancellation(context, onCancel),
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

String _title(BuildContext context, RouteExecutionLoadStatus status) =>
    switch (status) {
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
        'Unified Swap needs attention',
      ),
      RouteExecutionLoadStatus.unknown => unifiedSwapText(
        context,
        'execution.status.unknownTitle',
        'Execution status unavailable',
      ),
      RouteExecutionLoadStatus.idle ||
      RouteExecutionLoadStatus.reviewRequired => unifiedSwapText(
        context,
        'execution.status.idleTitle',
        'Unified Swap',
      ),
    };

String _description(
  BuildContext context,
  RouteExecutionLoadStatus status,
) => switch (status) {
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
    'Do not start a duplicate route. Reattach and review recovery details.',
  ),
  RouteExecutionLoadStatus.unknown => unifiedSwapText(
    context,
    'execution.status.unknownBody',
    'No movement action is available until the status is understood.',
  ),
  RouteExecutionLoadStatus.idle ||
  RouteExecutionLoadStatus.reviewRequired => '',
};

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
    RouteExecutionPhase.partial => 'Partially completed',
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
  RouteExecutionLoadStatus.observing =>
    phase == RouteExecutionPhase.signed
        ? Icons.manage_search_rounded
        : Icons.route_rounded,
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
      'The swap completed only in part',
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
      'One or more steps completed. Later steps remain stopped until the '
          'holding and evidence are verified.',
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
  VoidCallback onConfirmed,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('swap-cancel-confirmation'),
      title: Text(
        unifiedSwapText(
          dialogContext,
          'execution.cancelDialogTitle',
          'Cancel this swap?',
        ),
      ),
      content: Text(
        unifiedSwapText(
          dialogContext,
          'execution.cancelDialogBody',
          'Cancellation is available only at the current verified route '
              'boundary. Already completed steps cannot be reversed.',
        ),
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
  if (confirmed == true) onConfirmed();
}

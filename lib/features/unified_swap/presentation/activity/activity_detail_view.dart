import 'package:flutter/material.dart';
import 'package:web_dex/features/unified_swap/application/route_activity_bloc.dart';
import 'package:web_dex/features/unified_swap/domain/route_activity_models.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';
import 'package:web_dex/features/unified_swap/presentation/activity/activity_widgets.dart';
import 'package:web_dex/features/unified_swap/presentation/unified_swap_design.dart';
import 'package:web_dex/features/unified_swap/presentation/unified_swap_sensitive_dialog.dart';

class RouteActivityDetailView extends StatelessWidget {
  const RouteActivityDetailView({
    required this.state,
    required this.routeExecutionId,
    required this.onBack,
    required this.onRetry,
    required this.clipboardWriter,
    required this.announcement,
    this.onCancelRequested,
    this.onStopAfterCurrentRequested,
    this.onRecoveryRequested,
    this.onProgressRequested,
    this.onProgressReattachRequested,
    this.progressReattachFailed = false,
    this.resumeProgress = false,
    this.liveControlInFlight = false,
    this.liveControlFailure,
    super.key,
  });

  final RouteActivityState state;
  final String routeExecutionId;
  final VoidCallback onBack;
  final VoidCallback onRetry;
  final ActivityClipboardWriter clipboardWriter;
  final ActivityAnnouncement announcement;
  final ValueChanged<String>? onCancelRequested;
  final ValueChanged<String>? onStopAfterCurrentRequested;
  final ValueChanged<String>? onRecoveryRequested;
  final ValueChanged<String>? onProgressRequested;
  final ValueChanged<String>? onProgressReattachRequested;
  final bool progressReattachFailed;
  final bool resumeProgress;
  final bool liveControlInFlight;
  final String? liveControlFailure;

  @override
  Widget build(BuildContext context) {
    final detail = state.selectedExecution;
    final hasMatchingDetail =
        detail?.summary.routeExecutionId == routeExecutionId;
    if ((state.isDetailLoading && !hasMatchingDetail) ||
        (detail != null && !hasMatchingDetail)) {
      return Center(
        child: Semantics(
          liveRegion: true,
          label: unifiedSwapText(
            context,
            'activity.loadingDetails',
            'Loading route details',
          ),
          child: const CircularProgressIndicator(),
        ),
      );
    }
    if (detail == null) {
      return Column(
        children: [
          _DetailBackBar(onBack: onBack),
          Expanded(
            child: RouteActivityPlaceholder(
              icon: Icons.receipt_long_outlined,
              title: unifiedSwapText(
                context,
                'activity.detailsUnavailableTitle',
                'Route details are unavailable',
              ),
              message: unifiedSwapText(
                context,
                'activity.detailsUnavailableBody',
                'The wallet could not safely load this authoritative route.',
              ),
              actionLabel: state.walletId == null
                  ? null
                  : unifiedSwapText(context, 'common.tryAgain', 'Try again'),
              onAction: state.walletId == null ? null : onRetry,
              liveRegion: state.failure != null,
            ),
          ),
        ],
      );
    }
    final allowsLiveProgress = _allowsLiveProgress(detail);

    return ColoredBox(
      color: UnifiedSwapDesign.colors(context).canvas,
      child: Column(
        children: [
          _DetailBackBar(onBack: onBack),
          if (state.isDetailLoading)
            LinearProgressIndicator(
              semanticsLabel: unifiedSwapText(
                context,
                'activity.refreshingDetails',
                'Refreshing route details',
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              key: const Key('route-activity-detail'),
              padding: UnifiedSwapDesign.pagePadding(context),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: UnifiedSwapDesign.contentWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DetailHeader(
                        detail: detail,
                        clipboardWriter: clipboardWriter,
                        announcement: announcement,
                      ),
                      if (detail.summary.status ==
                              RouteActivityStatus.attentionRequired ||
                          detail.summary.status == RouteActivityStatus.failed ||
                          detail.summary.status ==
                              RouteActivityStatus.unknown) ...[
                        const SizedBox(height: 12),
                        _ActivityRecoverySummary(
                          detail: detail,
                          clipboardWriter: clipboardWriter,
                          announcement: announcement,
                        ),
                      ],
                      if (state.failure != null) ...[
                        const SizedBox(height: 12),
                        RouteActivityFailureNotice(onRetry: onRetry),
                      ],
                      const SizedBox(height: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _RouteTermsCard(detail: detail),
                          if (detail.authoritativeStatus != null ||
                              detail.summary.terminalError != null) ...[
                            const SizedBox(height: 12),
                            _AuthoritativeStatusCard(detail: detail),
                          ],
                          const SizedBox(height: 12),
                          _RouteControlsCard(
                            detail: detail,
                            controlInFlight: liveControlInFlight,
                            controlFailure: liveControlFailure,
                            onCancelRequested: allowsLiveProgress
                                ? onCancelRequested
                                : null,
                            onStopAfterCurrentRequested: allowsLiveProgress
                                ? onStopAfterCurrentRequested
                                : null,
                            onRecoveryRequested: allowsLiveProgress
                                ? onRecoveryRequested
                                : null,
                          ),
                          if (detail.holding case final holding?) ...[
                            const SizedBox(height: 12),
                            _HoldingCard(
                              holding: holding,
                              clipboardWriter: clipboardWriter,
                              announcement: announcement,
                            ),
                          ],
                          if (detail.consent.fees.isNotEmpty ||
                              detail.consent.nonNetworkFeeLimits.isNotEmpty ||
                              detail.consent.networkFeeCaps.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _FeesCard(detail: detail),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      _StagesCard(stages: detail.stages),
                      if (allowsLiveProgress &&
                          (onProgressRequested != null ||
                              onProgressReattachRequested != null)) ...[
                        const SizedBox(height: 12),
                        _LiveProgressAction(
                          routeExecutionId: routeExecutionId,
                          resumeProgress: resumeProgress,
                          onProgressRequested: onProgressRequested,
                          onProgressReattachRequested:
                              onProgressReattachRequested,
                          progressReattachFailed: progressReattachFailed,
                        ),
                      ],
                      if (detail.revisions.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _RevisionsCard(revisions: detail.revisions),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

bool _allowsLiveProgress(RouteExecutionDetail detail) {
  if (detail.summary.status.isTerminal ||
      detail.summary.status == RouteActivityStatus.unknown ||
      detail.summary.terminalError != null) {
    return false;
  }
  final status = detail.authoritativeStatus;
  if (status == null || !status.isExecutable) return false;
  final terminal =
      status.executionPhase == RouteActivityExecutionPhase.failed ||
      status.executionPhase == RouteActivityExecutionPhase.cancelled ||
      status.executionPhase == RouteActivityExecutionPhase.refunded ||
      status.routePhase == RouteExecutionRoutePhase.completed ||
      status.routePhase == RouteExecutionRoutePhase.failed ||
      status.routePhase == RouteExecutionRoutePhase.cancelled ||
      status.routePhase == RouteExecutionRoutePhase.refunded;
  final historicalRefund =
      detail.controls.reconciliationOnly &&
      (status.executionPhase == RouteActivityExecutionPhase.refundPending ||
          status.executionPhase == RouteActivityExecutionPhase.refunded ||
          status.routePhase == RouteExecutionRoutePhase.refundPending ||
          status.routePhase == RouteExecutionRoutePhase.refunded);
  return !terminal && !historicalRefund;
}

class _LiveProgressAction extends StatelessWidget {
  const _LiveProgressAction({
    required this.routeExecutionId,
    required this.resumeProgress,
    required this.onProgressRequested,
    required this.onProgressReattachRequested,
    required this.progressReattachFailed,
  });

  final String routeExecutionId;
  final bool resumeProgress;
  final ValueChanged<String>? onProgressRequested;
  final ValueChanged<String>? onProgressReattachRequested;
  final bool progressReattachFailed;

  @override
  Widget build(BuildContext context) {
    final openProgress = onProgressRequested;
    if (openProgress != null) {
      return FilledButton.icon(
        key: Key(
          resumeProgress
              ? 'activity-resume-swap'
              : 'activity-view-swap-progress',
        ),
        style: UnifiedSwapDesign.primaryButtonStyle(context),
        onPressed: () => openProgress(routeExecutionId),
        icon: Icon(
          resumeProgress ? Icons.play_arrow_rounded : Icons.route_rounded,
        ),
        label: Text(
          resumeProgress
              ? unifiedSwapText(
                  context,
                  'activity.detail.resumeSwap',
                  'Resume swap',
                )
              : unifiedSwapText(
                  context,
                  'activity.detail.viewSwapProgress',
                  'View swap progress',
                ),
        ),
      );
    }

    final reconnect = onProgressReattachRequested!;
    if (!progressReattachFailed) {
      return FilledButton.icon(
        key: const Key('activity-resume-swap'),
        style: UnifiedSwapDesign.primaryButtonStyle(context),
        onPressed: () => reconnect(routeExecutionId),
        icon: const Icon(Icons.play_arrow_rounded),
        label: Text(
          unifiedSwapText(context, 'activity.detail.resumeSwap', 'Resume swap'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UnifiedSwapNotice(
          key: const Key('activity-live-progress-unavailable'),
          title: unifiedSwapText(
            context,
            'activity.detail.liveProgressUnavailable',
            'Live progress is temporarily unavailable',
          ),
          message: unifiedSwapText(
            context,
            'activity.detail.liveProgressUnavailableBody',
            'Activity still shows the durable record. Reconnect to this '
                'exact swap before relying on live progress or controls.',
          ),
          tone: UnifiedSwapNoticeTone.warning,
          icon: Icons.sync_problem_rounded,
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          key: const Key('activity-retry-live-progress'),
          style: UnifiedSwapDesign.primaryButtonStyle(context),
          onPressed: () => reconnect(routeExecutionId),
          icon: const Icon(Icons.sync_rounded),
          label: Text(
            unifiedSwapText(
              context,
              'activity.detail.retryLiveProgress',
              'Retry live progress',
            ),
          ),
        ),
      ],
    );
  }
}

class _ActivityRecoverySummary extends StatelessWidget {
  const _ActivityRecoverySummary({
    required this.detail,
    required this.clipboardWriter,
    required this.announcement,
  });

  final RouteExecutionDetail detail;
  final ActivityClipboardWriter clipboardWriter;
  final ActivityAnnouncement announcement;

  @override
  Widget build(BuildContext context) {
    final holding = detail.holding;
    final lastConfirmed = holding == null
        ? _lastConfirmedStageEvidence(detail)
        : null;
    final lastConfirmedHolding = lastConfirmed?.holding;
    final unknown = detail.summary.status == RouteActivityStatus.unknown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UnifiedSwapStatusHero(
          title: unknown
              ? unifiedSwapText(
                  context,
                  'activity.recovery.checkingTitle',
                  'We’re checking the latest verified status',
                )
              : unifiedSwapText(
                  context,
                  'activity.recovery.attentionTitle',
                  'This swap needs your attention',
                ),
          message: unifiedSwapText(
            context,
            'activity.recovery.heroBody',
            'The wallet shows only durable evidence and currently authorized '
                'actions.',
          ),
          icon: unknown
              ? Icons.manage_search_rounded
              : Icons.settings_backup_restore_rounded,
          tone: UnifiedSwapNoticeTone.warning,
        ),
        UnifiedSwapQuestion(
          first: true,
          question: unifiedSwapText(
            context,
            'recovery.whatHappened',
            'What happened?',
          ),
          answer: unknown
              ? unifiedSwapText(
                  context,
                  'activity.recovery.unknownState',
                  'The current execution state is not yet understood',
                )
              : unifiedSwapText(
                  context,
                  'activity.recovery.stoppedBoundary',
                  'Automatic progress stopped at a route boundary',
                ),
          details: unknown
              ? unifiedSwapText(
                  context,
                  'activity.recovery.verificationContinues',
                  'Later steps remain blocked while verification continues.',
                )
              : unifiedSwapText(
                  context,
                  'activity.recovery.reviewBelow',
                  'Review the fund location and available actions below.',
                ),
        ),
        UnifiedSwapQuestion(
          question: unifiedSwapText(
            context,
            'recovery.whereFunds',
            'Where are the funds?',
          ),
          answer: holding == null
              ? lastConfirmed == null
                    ? unifiedSwapText(
                        context,
                        'activity.recovery.locationUnknownTitle',
                        'Current location unknown',
                      )
                    : lastConfirmedHolding == null
                    ? unifiedSwapText(
                        context,
                        'activity.recovery.lastConfirmedEvidenceTitle',
                        'Last confirmed evidence · current location unknown',
                      )
                    : unifiedSwapText(
                        context,
                        'activity.recovery.lastConfirmedLocationTitle',
                        'Last confirmed location · current location unknown',
                      )
              : unifiedSwapText(
                  context,
                  'recovery.verifiedHolding',
                  'Verified current holding',
                ),
          details: holding == null
              ? _lastConfirmedDetails(context, detail, lastConfirmed)
              : unifiedSwapText(
                  context,
                  'activity.recovery.verifiedHoldingLocation',
                  '{amount} at {address} on {network}.',
                  namedArgs: {
                    'amount': routeActivityAmount(
                      holding.amount,
                      holding.asset,
                    ),
                    'address': unifiedSwapShortIdentity(holding.address),
                    'network': unifiedSwapNetworkLabel(context, holding.asset),
                  },
                ),
          child: lastConfirmedHolding == null
              ? null
              : RouteActivityCopyButton(
                  value: lastConfirmedHolding.address,
                  label: unifiedSwapText(
                    context,
                    'activity.detail.holdingAddress',
                    'Holding address',
                  ),
                  valueKey: 'last-confirmed-holding-address',
                  clipboardWriter: clipboardWriter,
                  announcement: announcement,
                ),
        ),
        UnifiedSwapQuestion(
          question: unifiedSwapText(
            context,
            'recovery.whatCanDo',
            'What can I do now?',
          ),
          answer: unifiedSwapText(
            context,
            'activity.recovery.authorizedControls',
            'Only the controls authorized by current status are shown',
          ),
          details: unifiedSwapText(
            context,
            'activity.recovery.freshReviewConsent',
            'A recovery swap always requires a fresh quote, Review, and '
                'explicit consent.',
          ),
        ),
      ],
    );
  }
}

class _DetailBackBar extends StatelessWidget {
  const _DetailBackBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: TextButton(
          key: const Key('activity-detail-back'),
          onPressed: onBack,
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Icon(Icons.arrow_back_rounded),
              Text(
                unifiedSwapText(
                  context,
                  'activity.backToActivity',
                  'Back to Activity',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.detail,
    required this.clipboardWriter,
    required this.announcement,
  });

  final RouteExecutionDetail detail;
  final ActivityClipboardWriter clipboardWriter;
  final ActivityAnnouncement announcement;

  @override
  Widget build(BuildContext context) {
    final summary = detail.summary;
    final source = summary.sourceAmount == null
        ? summary.source.ticker
        : routeActivityAmount(summary.sourceAmount!, summary.source);
    final destination = summary.expectedReceive == null
        ? summary.destination.ticker
        : routeActivityAmount(summary.expectedReceive!, summary.destination);
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Semantics(
                header: true,
                child: Text(
                  '$source → $destination',
                  style: UnifiedSwapDesign.typography(context).pageTitle,
                ),
              );
              final status = RouteActivityStatusChip(status: summary.status);
              final scaledBody = MediaQuery.textScalerOf(context).scale(16);
              if (constraints.maxWidth < 480 || scaledBody >= 32) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [title, const SizedBox(height: 8), status],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: title),
                  status,
                ],
              );
            },
          ),
          const SizedBox(height: 4),
          Text(
            unifiedSwapText(
              context,
              'common.updated',
              'Updated {date}',
              namedArgs: {
                'date': routeActivityDate(context, summary.updatedAt),
              },
            ),
          ),
          const SizedBox(height: 8),
          RouteActivityExecutionId(
            routeExecutionId: summary.routeExecutionId,
            clipboardWriter: clipboardWriter,
            announcement: announcement,
          ),
        ],
      ),
    );
  }
}

class _RouteTermsCard extends StatelessWidget {
  const _RouteTermsCard({required this.detail});

  final RouteExecutionDetail detail;

  @override
  Widget build(BuildContext context) {
    final consent = detail.consent;
    return RouteActivitySectionCard(
      title: unifiedSwapText(
        context,
        'activity.detail.persistedTerms',
        'Persisted route terms',
      ),
      icon: Icons.fact_check_outlined,
      child: Column(
        children: [
          _DetailRow(
            label: unifiedSwapText(context, 'entry.from', 'From'),
            value: routeActivityAssetLabel(context, consent.source),
          ),
          _DetailRow(
            label: unifiedSwapText(context, 'entry.to', 'To'),
            value: routeActivityAssetLabel(context, consent.destination),
          ),
          _DetailRow(
            label: unifiedSwapText(
              context,
              'activity.detail.sourceAmount',
              'Source amount',
            ),
            value: routeActivityAmount(consent.sourceAmount, consent.source),
          ),
          _DetailRow(
            label: unifiedSwapText(
              context,
              'review.expectedReceive',
              'Expected receive',
            ),
            value: routeActivityAmount(
              consent.expectedReceive,
              consent.destination,
            ),
          ),
          _DetailRow(
            label: unifiedSwapText(
              context,
              'review.minimumReceive',
              'Minimum receive',
            ),
            value: routeActivityAmount(
              consent.minimumReceive,
              consent.destination,
            ),
          ),
          _DetailRow(
            label: unifiedSwapText(
              context,
              'activity.detail.sourceAddress',
              'Source address',
            ),
            value:
                consent.resolvedSourceAddress ??
                unifiedSwapText(context, 'common.unavailable', 'Unavailable'),
            selectable: true,
          ),
          _DetailRow(
            label: unifiedSwapText(
              context,
              'activity.detail.recipient',
              'Recipient',
            ),
            value: consent.recipient,
            selectable: true,
          ),
        ],
      ),
    );
  }
}

class _AuthoritativeStatusCard extends StatelessWidget {
  const _AuthoritativeStatusCard({required this.detail});

  final RouteExecutionDetail detail;

  @override
  Widget build(BuildContext context) {
    return RouteActivitySectionCard(
      title: unifiedSwapText(
        context,
        'activity.detail.durableStatus',
        'Durable execution status',
      ),
      icon: Icons.verified_outlined,
      semanticLabel: unifiedSwapText(
        context,
        'activity.detail.durableStatusSemantics',
        'Authoritative execution status and evidence',
      ),
      child: _StatusEvidenceContent(
        status: detail.authoritativeStatus,
        terminalError: detail.summary.terminalError,
      ),
    );
  }
}

class _StatusEvidenceContent extends StatelessWidget {
  const _StatusEvidenceContent({
    required this.status,
    required this.terminalError,
  });

  final RouteAuthoritativeStatus? status;
  final RouteTerminalError? terminalError;

  @override
  Widget build(BuildContext context) {
    final status = this.status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (status == null)
          UnifiedSwapNotice(
            key: const Key('activity-authoritative-status-unavailable'),
            title: unifiedSwapText(
              context,
              'activity.detail.statusUnavailable',
              'Status record unavailable',
            ),
            message: unifiedSwapText(
              context,
              'activity.detail.statusUnavailableBody',
              'No typed durable status record is available. Controls remain '
                  'inert until the wallet can verify it.',
            ),
            tone: UnifiedSwapNoticeTone.warning,
            icon: Icons.help_outline_rounded,
          )
        else ...[
          _DetailRow(
            label: unifiedSwapText(
              context,
              'activity.detail.executionPhase',
              'Execution phase',
            ),
            value: _executionPhaseLabel(context, status.executionPhase),
          ),
          _DetailRow(
            label: unifiedSwapText(
              context,
              'activity.detail.routePhase',
              'Route phase',
            ),
            value: _executionRoutePhaseLabel(context, status.routePhase),
          ),
          _DetailRow(
            label: unifiedSwapText(
              context,
              'activity.detail.stateRevision',
              'State revision',
            ),
            value: '${status.stateRevision}',
          ),
          _DetailRow(
            label: unifiedSwapText(
              context,
              'activity.detail.currentStage',
              'Current stage',
            ),
            value: '${status.stageIndex + 1}',
          ),
          _DetailRow(
            label: unifiedSwapText(
              context,
              'activity.detail.stopRequested',
              'Stop after current',
            ),
            value: status.stopAfterCurrent
                ? unifiedSwapText(context, 'common.yes', 'Yes')
                : unifiedSwapText(context, 'common.no', 'No'),
          ),
          _DetailRow(
            label: unifiedSwapText(context, 'common.updated', 'Updated'),
            value: routeActivityDate(context, status.updatedAt),
          ),
          if (status.completedAt case final completedAt?)
            _DetailRow(
              label: unifiedSwapText(
                context,
                'activity.detail.completedAt',
                'Completed',
              ),
              value: routeActivityDate(context, completedAt),
            ),
          if (!status.isExecutable) ...[
            const SizedBox(height: 8),
            UnifiedSwapNotice(
              key: const Key('activity-authoritative-status-unknown'),
              title: unifiedSwapText(
                context,
                'activity.detail.unknownStatusEvidence',
                'Some status evidence is unknown',
              ),
              message: unifiedSwapText(
                context,
                'activity.detail.unknownStatusEvidenceBody',
                'The wallet cannot safely interpret part of this status. '
                    'Movement controls are disabled.',
              ),
              tone: UnifiedSwapNoticeTone.warning,
              icon: Icons.gpp_maybe_outlined,
            ),
          ],
          if (status.transactionHashes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              unifiedSwapText(
                context,
                'execution.transactions',
                'Transactions',
              ),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            for (final hash in status.transactionHashes)
              SelectableText(hash, maxLines: 2),
          ],
          if (status.evidence.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              unifiedSwapText(
                context,
                'activity.detail.statusEvidence',
                'Current status evidence',
              ),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            for (var index = 0; index < status.evidence.length; index++) ...[
              _EvidenceEntry(evidence: status.evidence[index]),
              if (index < status.evidence.length - 1) const Divider(height: 20),
            ],
          ],
          if (status.approvalRecovery case final recovery?) ...[
            const SizedBox(height: 12),
            _ApprovalRecoveryContent(recovery: recovery),
          ],
        ],
        if (terminalError case final error?) ...[
          if (status != null) const SizedBox(height: 12),
          UnifiedSwapNotice(
            key: const Key('activity-terminal-error'),
            title: error.isKnown
                ? unifiedSwapText(
                    context,
                    'activity.detail.terminalError',
                    'Recorded terminal error',
                  )
                : unifiedSwapText(
                    context,
                    'activity.detail.terminalErrorUnknown',
                    'Unknown terminal error type',
                  ),
            message: error.isKnown
                ? unifiedSwapText(
                    context,
                    'activity.detail.terminalErrorBody',
                    'The durable journal records a typed terminal failure. '
                        'Diagnostic details remain available to support.',
                  )
                : unifiedSwapText(
                    context,
                    'activity.detail.terminalErrorUnknownBody',
                    'The journal contains an unrecognized terminal failure. '
                        'No meaning or recovery action was inferred.',
                  ),
            tone: UnifiedSwapNoticeTone.warning,
            icon: error.isKnown
                ? Icons.error_outline_rounded
                : Icons.help_outline_rounded,
          ),
        ],
      ],
    );
  }
}

class _ApprovalRecoveryContent extends StatelessWidget {
  const _ApprovalRecoveryContent({required this.recovery});

  final RouteApprovalRecovery recovery;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          unifiedSwapText(
            context,
            'activity.detail.approvalRecovery',
            'Approval recovery',
          ),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        _DetailRow(
          label: unifiedSwapText(context, 'activity.detail.token', 'Token'),
          value: routeActivityAssetLabel(context, recovery.token),
        ),
        _DetailRow(
          label: unifiedSwapText(
            context,
            'activity.detail.remainingAllowance',
            'Remaining allowance',
          ),
          value: routeActivityAmount(
            recovery.remainingAllowance,
            recovery.token,
          ),
        ),
        _DetailRow(
          label: unifiedSwapText(
            context,
            'activity.detail.validatedSpender',
            'Validated spender',
          ),
          value: recovery.validatedSpender,
          selectable: true,
        ),
        _DetailRow(
          label: unifiedSwapText(
            context,
            'activity.detail.recoveryInstruction',
            'Instruction',
          ),
          value: _approvalRecoveryLabel(context, recovery.instruction),
        ),
        if (!recovery.isExecutable) ...[
          const SizedBox(height: 6),
          UnifiedSwapNotice(
            key: const Key('activity-approval-recovery-unknown'),
            title: unifiedSwapText(
              context,
              'activity.detail.approvalRecoveryUnknown',
              'Approval recovery is not understood',
            ),
            message: unifiedSwapText(
              context,
              'activity.detail.approvalRecoveryUnknownBody',
              'The exact record is shown, but the wallet will not infer or '
                  'offer an approval action for an unknown instruction.',
            ),
            tone: UnifiedSwapNoticeTone.warning,
            icon: Icons.gpp_maybe_outlined,
          ),
        ],
      ],
    );
  }
}

class _RouteControlsCard extends StatelessWidget {
  const _RouteControlsCard({
    required this.detail,
    required this.onCancelRequested,
    required this.onStopAfterCurrentRequested,
    required this.onRecoveryRequested,
    required this.controlInFlight,
    required this.controlFailure,
  });

  final RouteExecutionDetail detail;
  final ValueChanged<String>? onCancelRequested;
  final ValueChanged<String>? onStopAfterCurrentRequested;
  final ValueChanged<String>? onRecoveryRequested;
  final bool controlInFlight;
  final String? controlFailure;

  @override
  Widget build(BuildContext context) {
    final controls = detail.controls;
    final authoritativeStatus = detail.authoritativeStatus;
    final known =
        detail.summary.status != RouteActivityStatus.unknown &&
        (authoritativeStatus?.isExecutable ?? true) &&
        (detail.summary.terminalError?.isKnown ?? true);
    final routeExecutionId = detail.summary.routeExecutionId;
    final canCancel =
        known &&
        !controls.reconciliationOnly &&
        controls.canCancel &&
        onCancelRequested != null;
    final canStop =
        known &&
        !controls.reconciliationOnly &&
        controls.canStopAfterCurrent &&
        onStopAfterCurrentRequested != null;
    final canRecover =
        known && !controls.reconciliationOnly && onRecoveryRequested != null;
    return RouteActivitySectionCard(
      title: unifiedSwapText(
        context,
        'activity.detail.currentControls',
        'Current controls',
      ),
      icon: Icons.tune_rounded,
      semanticLabel: unifiedSwapText(
        context,
        'activity.detail.controlsSemantics',
        'Authoritative current route controls',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (controlInFlight) ...[
            LinearProgressIndicator(
              key: const Key('activity-control-progress'),
              semanticsLabel: unifiedSwapText(
                context,
                'activity.detail.controlBusy',
                'Applying route control',
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (controlFailure case final message?) ...[
            UnifiedSwapNotice(
              key: const Key('activity-control-failure'),
              title: unifiedSwapText(
                context,
                'activity.detail.controlFailedTitle',
                'Control was not applied',
              ),
              message: message,
              tone: UnifiedSwapNoticeTone.danger,
              icon: Icons.error_outline_rounded,
            ),
            const SizedBox(height: 10),
          ],
          if (!known)
            Text(
              unifiedSwapText(
                context,
                'activity.detail.controlsUnknown',
                'Controls are unavailable while the route status is unknown.',
              ),
              key: const Key('activity-controls-inert'),
            )
          else if (controls.reconciliationOnly)
            Text(
              unifiedSwapText(
                context,
                'activity.detail.controlsReconciliation',
                'This route is reconciliation-only. Movement controls are '
                    'disabled.',
              ),
              key: const Key('activity-controls-reconciliation'),
            )
          else if (!canCancel && !canStop && !canRecover)
            Text(
              unifiedSwapText(
                context,
                'activity.detail.controlsNone',
                'No executable controls are available in this view.',
              ),
              key: const Key('activity-controls-none'),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canCancel)
                  OutlinedButton.icon(
                    key: const Key('activity-control-cancel'),
                    onPressed: controlInFlight
                        ? null
                        : () => _confirmActivityCancellation(
                            context,
                            routeExecutionId,
                            () => onCancelRequested!(routeExecutionId),
                          ),
                    icon: const Icon(Icons.cancel_outlined),
                    label: Text(
                      unifiedSwapText(
                        context,
                        'execution.cancelRoute',
                        'Cancel route',
                      ),
                    ),
                  ),
                if (canStop)
                  FilledButton.tonalIcon(
                    key: const Key('activity-control-stop'),
                    onPressed: controlInFlight
                        ? null
                        : () => _confirmActivityStop(
                            context,
                            routeExecutionId,
                            () =>
                                onStopAfterCurrentRequested!(routeExecutionId),
                          ),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(
                      unifiedSwapText(
                        context,
                        'activity.detail.stopAfterStage',
                        'Stop after current stage',
                      ),
                    ),
                  ),
                if (canRecover)
                  FilledButton.icon(
                    key: const Key('activity-control-recovery'),
                    onPressed: controlInFlight
                        ? null
                        : () => _confirmActivityRecovery(
                            context,
                            routeExecutionId,
                            () => onRecoveryRequested!(routeExecutionId),
                          ),
                    icon: const Icon(Icons.settings_backup_restore_rounded),
                    label: Text(
                      unifiedSwapText(
                        context,
                        'activity.detail.reviewRecoveryOptions',
                        'Review recovery options',
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

class _HoldingCard extends StatelessWidget {
  const _HoldingCard({
    required this.holding,
    required this.clipboardWriter,
    required this.announcement,
  });

  final RouteHolding holding;
  final ActivityClipboardWriter clipboardWriter;
  final ActivityAnnouncement announcement;

  @override
  Widget build(BuildContext context) {
    return RouteActivitySectionCard(
      title: unifiedSwapText(
        context,
        'activity.detail.currentHolding',
        'Current holding',
      ),
      icon: Icons.account_balance_wallet_outlined,
      child: Column(
        children: [
          _DetailRow(
            label: unifiedSwapText(context, 'activity.detail.asset', 'Asset'),
            value: routeActivityAssetLabel(context, holding.asset),
          ),
          _DetailRow(
            label: unifiedSwapText(context, 'activity.detail.amount', 'Amount'),
            value: routeActivityAmount(holding.amount, holding.asset),
          ),
          _DetailRow(
            label: unifiedSwapText(
              context,
              'activity.detail.address',
              'Address',
            ),
            value: holding.address,
            selectable: true,
            action: RouteActivityCopyButton(
              value: holding.address,
              label: unifiedSwapText(
                context,
                'activity.detail.holdingAddress',
                'Holding address',
              ),
              valueKey: 'holding-address',
              clipboardWriter: clipboardWriter,
              announcement: announcement,
              compact: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeesCard extends StatelessWidget {
  const _FeesCard({required this.detail});

  final RouteExecutionDetail detail;

  @override
  Widget build(BuildContext context) {
    final consent = detail.consent;
    return RouteActivitySectionCard(
      title: unifiedSwapText(
        context,
        'activity.detail.feesAndLimits',
        'Fees and limits',
      ),
      icon: Icons.receipt_outlined,
      child: Column(
        children: [
          for (final fee in consent.fees)
            _DetailRow(
              label: unifiedSwapText(
                context,
                'activity.detail.feeLabel',
                '{kind} fee',
                namedArgs: {'kind': _feeLabel(context, fee.kind)},
              ),
              value:
                  '${routeActivityAmount(fee.amount, fee.asset)}'
                  '${fee.included ? ' · ${unifiedSwapText(context, 'fees.included', 'included')}' : ''}',
            ),
          for (final limit in consent.nonNetworkFeeLimits)
            _DetailRow(
              label: unifiedSwapText(
                context,
                'activity.detail.feeMaximum',
                '{kind} maximum',
                namedArgs: {'kind': _feeLabel(context, limit.kind)},
              ),
              value:
                  '${routeActivityAmount(limit.maximumAmount, limit.asset)}'
                  '${limit.stageId == null ? '' : ' · ${unifiedSwapText(context, 'activity.detail.stageIdInline', 'stage {id}', namedArgs: {'id': limit.stageId!})}'}',
            ),
          for (final cap in consent.networkFeeCaps)
            _DetailRow(
              label: unifiedSwapText(
                context,
                'activity.detail.stageNetworkMaximum',
                'Stage network maximum',
              ),
              value:
                  '${routeActivityAmount(cap.maximumAmount, cap.asset)} · '
                  '${unifiedSwapText(context, 'activity.detail.stageIdInline', 'stage {id}', namedArgs: {'id': cap.stageId})}',
            ),
        ],
      ),
    );
  }
}

class _StagesCard extends StatelessWidget {
  const _StagesCard({required this.stages});

  final List<RouteStageHistoryEntry> stages;

  @override
  Widget build(BuildContext context) {
    return RouteActivitySectionCard(
      title: unifiedSwapText(
        context,
        'activity.detail.stageHistory',
        'Stage history',
      ),
      icon: Icons.route_outlined,
      child: stages.isEmpty
          ? Text(
              unifiedSwapText(
                context,
                'activity.detail.noStageHistory',
                'No stage history is available yet.',
              ),
            )
          : Column(
              children: [
                for (var index = 0; index < stages.length; index++) ...[
                  _StageEntry(stage: stages[index]),
                  if (index != stages.length - 1) const Divider(height: 24),
                ],
              ],
            ),
    );
  }
}

class _StageEntry extends StatelessWidget {
  const _StageEntry({required this.stage});

  final RouteStageHistoryEntry stage;

  @override
  Widget build(BuildContext context) {
    final unknown = stage.phase == RouteStagePhase.unknown;
    return Semantics(
      container: true,
      label: unifiedSwapText(
        context,
        'activity.detail.stageSemantics',
        'Stage {number}, {phase}',
        namedArgs: {
          'number': '${stage.sequence + 1}',
          'phase': routeActivityPhaseLabel(context, stage.phase),
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Text(
                unifiedSwapText(
                  context,
                  'activity.detail.stageNumber',
                  'Stage {number}',
                  namedArgs: {'number': '${stage.sequence + 1}'},
                ),
                style: Theme.of(context).textTheme.titleSmall,
              );
              final phase = Chip(
                label: Text(routeActivityPhaseLabel(context, stage.phase)),
                avatar: Icon(
                  unknown ? Icons.help_outline : Icons.circle,
                  size: unknown ? 18 : 10,
                ),
                visualDensity: VisualDensity.compact,
              );
              final scaledBody = MediaQuery.textScalerOf(context).scale(16);
              if (constraints.maxWidth < 480 || scaledBody >= 32) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [title, const SizedBox(height: 4), phase],
                );
              }
              return Row(
                children: [
                  Expanded(child: title),
                  phase,
                ],
              );
            },
          ),
          SelectableText(
            stage.stageId,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (stage.updatedAt case final updatedAt?)
            Text(
              unifiedSwapText(
                context,
                'common.updated',
                'Updated {date}',
                namedArgs: {'date': routeActivityDate(context, updatedAt)},
              ),
            ),
          if (stage.holding case final holding?)
            Text(
              unifiedSwapText(
                context,
                'activity.detail.holdingAmount',
                'Holding {amount}',
                namedArgs: {
                  'amount': routeActivityAmount(holding.amount, holding.asset),
                },
              ),
            ),
          if (stage.transactionHashes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              unifiedSwapText(
                context,
                'execution.transactions',
                'Transactions',
              ),
            ),
            for (final hash in stage.transactionHashes)
              SelectableText(hash, maxLines: 2),
          ],
          if (stage.evidence.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              unifiedSwapText(context, 'activity.detail.evidence', 'Evidence'),
            ),
            const SizedBox(height: 6),
            for (var index = 0; index < stage.evidence.length; index++) ...[
              _EvidenceEntry(evidence: stage.evidence[index]),
              if (index < stage.evidence.length - 1) const Divider(height: 20),
            ],
          ],
        ],
      ),
    );
  }
}

class _EvidenceEntry extends StatelessWidget {
  const _EvidenceEntry({required this.evidence});

  final RouteSafeEvidence evidence;

  @override
  Widget build(BuildContext context) {
    final receipt = evidence.receipt;
    final provider = evidence.provider;
    final unknown = !evidence.isExecutable;
    final colors = UnifiedSwapDesign.colors(context);
    return UnifiedSwapSurface(
      padding: const EdgeInsets.all(12),
      radius: 12,
      borderColor: unknown ? colors.warning : colors.border,
      backgroundColor: unknown ? colors.warningContainer : colors.surface,
      semanticLabel: unknown
          ? unifiedSwapText(
              context,
              'activity.detail.unknownEvidenceSemantics',
              'Unknown evidence; no meaning inferred',
            )
          : _evidenceLabel(context, evidence.kind),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                unknown ? Icons.help_outline_rounded : Icons.verified_outlined,
                size: 18,
                color: unknown ? colors.warning : colors.brandHover,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _evidenceLabel(context, evidence.kind),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          if (unknown) ...[
            const SizedBox(height: 4),
            Text(
              unifiedSwapText(
                context,
                'activity.detail.unknownEvidenceBody',
                'This evidence type is preserved for support diagnostics, but '
                    'the wallet does not infer or display its infrastructure '
                    'meaning.',
              ),
            ),
          ],
          if (evidence.reference case final reference?)
            _DetailRow(
              label: unifiedSwapText(
                context,
                'activity.detail.reference',
                'Reference',
              ),
              value: reference,
              selectable: true,
            ),
          if (evidence.secondaryReference case final secondary?)
            _DetailRow(
              label: unifiedSwapText(
                context,
                'activity.detail.secondaryReference',
                'Multi-step reference',
              ),
              value: secondary,
              selectable: true,
            ),
          if (evidence.state case final state?)
            _DetailRow(
              label: unifiedSwapText(
                context,
                'activity.detail.evidenceState',
                'Evidence state',
              ),
              value: _evidenceStateLabel(context, state),
            ),
          if (receipt != null) ...[
            const Divider(height: 20),
            _ReceiptEvidence(receipt: receipt),
          ],
          if (provider != null) ...[
            const Divider(height: 20),
            _ProviderEvidenceDetails(provider: provider),
          ],
        ],
      ),
    );
  }
}

class _ReceiptEvidence extends StatelessWidget {
  const _ReceiptEvidence({required this.receipt});

  final RouteTransactionReceipt receipt;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          unifiedSwapText(
            context,
            'activity.detail.chainReceipt',
            'Chain receipt',
          ),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        _DetailRow(
          label: unifiedSwapText(
            context,
            'activity.detail.receiptStatus',
            'Receipt status',
          ),
          value: _transactionStatusLabel(context, receipt.status),
        ),
        _DetailRow(
          label: unifiedSwapText(
            context,
            'activity.detail.confirmations',
            'Confirmations',
          ),
          value: receipt.confirmations < 0
              ? unifiedSwapText(
                  context,
                  'activity.detail.confirmationsUnknown',
                  'Unknown',
                )
              : '${receipt.confirmations}',
        ),
        _DetailRow(
          label: unifiedSwapText(context, 'activity.detail.chain', 'Chain'),
          value:
              '${_chainFamilyLabel(context, receipt.chainFamily)} · '
              '${receipt.chainId}',
        ),
        if (receipt.blockHeight case final height?)
          _DetailRow(
            label: unifiedSwapText(
              context,
              'activity.detail.blockHeight',
              'Block height',
            ),
            value: height,
          ),
        if (receipt.blockHash case final hash?)
          _DetailRow(
            label: unifiedSwapText(
              context,
              'activity.detail.blockHash',
              'Block hash',
            ),
            value: hash,
            selectable: true,
          ),
        if (receipt.networkFee case final fee?)
          _DetailRow(
            label: unifiedSwapText(
              context,
              'activity.detail.networkFeePaid',
              'Network fee',
            ),
            value: routeActivityAmount(fee.amount, fee.asset),
          ),
        if (receipt.gasUsed case final gas?)
          _DetailRow(
            label: unifiedSwapText(
              context,
              'activity.detail.gasUsed',
              'Gas used',
            ),
            value: gas,
          ),
        if (receipt.effectiveGasPrice case final price?)
          _DetailRow(
            label: unifiedSwapText(
              context,
              'activity.detail.effectiveGasPrice',
              'Effective gas price',
            ),
            value: price,
          ),
        _DetailRow(
          label: unifiedSwapText(
            context,
            'activity.detail.observedAt',
            'Observed',
          ),
          value: routeActivityDate(context, receipt.observedAt),
        ),
        if (receipt.revertReason case final reason?) ...[
          const SizedBox(height: 6),
          UnifiedSwapNotice(
            key: const Key('activity-receipt-revert'),
            title: unifiedSwapText(
              context,
              'activity.detail.revertReason',
              'Transaction revert reason',
            ),
            message: reason,
            tone: UnifiedSwapNoticeTone.danger,
            icon: Icons.error_outline_rounded,
          ),
        ],
      ],
    );
  }
}

class _ProviderEvidenceDetails extends StatelessWidget {
  const _ProviderEvidenceDetails({required this.provider});

  final RouteProviderEvidence provider;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          unifiedSwapText(
            context,
            'activity.detail.providerEvidence',
            'Service transfer evidence',
          ),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (provider.fromAddress case final address?)
          _DetailRow(
            label: unifiedSwapText(
              context,
              'activity.detail.providerFrom',
              'Sending address',
            ),
            value: address,
            selectable: true,
          ),
        if (provider.toAddress case final address?)
          _DetailRow(
            label: unifiedSwapText(
              context,
              'activity.detail.providerTo',
              'Receiving address',
            ),
            value: address,
            selectable: true,
          ),
        for (final transfer in provider.transfers) ...[
          const Divider(height: 20),
          _ProviderTransferDetails(transfer: transfer),
        ],
      ],
    );
  }
}

class _ProviderTransferDetails extends StatelessWidget {
  const _ProviderTransferDetails({required this.transfer});

  final RouteEvidenceTransfer transfer;

  @override
  Widget build(BuildContext context) {
    final asset = transfer.asset;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _transferDirectionLabel(context, transfer.direction),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        _DetailRow(
          label: unifiedSwapText(
            context,
            'activity.detail.transactionHash',
            'Transaction hash',
          ),
          value: transfer.transactionHash,
          selectable: true,
        ),
        if (transfer.amount case final amount?)
          _DetailRow(
            label: unifiedSwapText(
              context,
              'activity.detail.transferAmount',
              'Transfer amount',
            ),
            value: asset == null
                ? unifiedSwapText(
                    context,
                    'activity.detail.smallestUnits',
                    '{amount} smallest units',
                    namedArgs: {'amount': amount},
                  )
                : _providerTransferAmount(amount, asset),
          ),
        if (asset != null) ...[
          _DetailRow(
            label: unifiedSwapText(
              context,
              'activity.detail.transferToken',
              'Transfer token',
            ),
            value: '${asset.symbol} · ${asset.tokenIdentifier}',
            selectable: true,
          ),
        ],
      ],
    );
  }
}

class _RevisionsCard extends StatelessWidget {
  const _RevisionsCard({required this.revisions});

  final List<RouteExecutionRevision> revisions;

  @override
  Widget build(BuildContext context) {
    return RouteActivitySectionCard(
      title: unifiedSwapText(
        context,
        'activity.detail.archivedRevisions',
        'Archived revisions',
      ),
      icon: Icons.history_toggle_off_rounded,
      child: Column(
        children: [
          for (final revision in revisions) _RevisionEntry(revision: revision),
        ],
      ),
    );
  }
}

class _RevisionEntry extends StatelessWidget {
  const _RevisionEntry({required this.revision});

  final RouteExecutionRevision revision;

  @override
  Widget build(BuildContext context) {
    final status = revision.authoritativeStatus;
    final title = Text(
      unifiedSwapText(
        context,
        'activity.detail.revisionNumber',
        'Revision {number}',
        namedArgs: {'number': '${revision.revision + 1}'},
      ),
    );
    final phase = status == null
        ? routeActivityPhaseLabel(context, revision.phase)
        : '${_executionPhaseLabel(context, status.executionPhase)} · '
              '${_executionRoutePhaseLabel(context, status.routePhase)}';
    final subtitle = Text(
      unifiedSwapText(
        context,
        'activity.detail.archivedAtWithStages',
        '{phase} · {count} stages · archived {date}',
        namedArgs: {
          'phase': phase,
          'count': '${revision.stages.length}',
          'date': routeActivityDate(context, revision.archivedAt),
        },
      ),
    );
    if (status == null) {
      return Material(
        color: Colors.transparent,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.archive_outlined),
          title: title,
          subtitle: subtitle,
        ),
      );
    }
    return Material(
      color: Colors.transparent,
      child: ExpansionTile(
        key: Key('activity-revision-${revision.revision}'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 12),
        leading: const Icon(Icons.archive_outlined),
        title: title,
        subtitle: subtitle,
        children: [_StatusEvidenceContent(status: status, terminalError: null)],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.selectable = false,
    this.action,
  });

  final String label;
  final String value;
  final bool selectable;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final valueWidget = selectable
        ? SelectableText(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodyMedium,
          )
        : Text(value, textAlign: TextAlign.end);
    final valueWithAction = action == null
        ? valueWidget
        : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: valueWidget),
              const SizedBox(width: 4),
              action!,
            ],
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          const SizedBox(width: 12),
          Expanded(flex: 6, child: valueWithAction),
        ],
      ),
    );
  }
}

typedef _LastConfirmedStageEvidence = ({
  RouteHolding? holding,
  RouteSafeEvidence? evidence,
});

_LastConfirmedStageEvidence? _lastConfirmedStageEvidence(
  RouteExecutionDetail detail,
) {
  for (final stage in detail.stages.reversed) {
    if (stage.holding case final holding?) {
      return (holding: holding, evidence: null);
    }
  }
  for (final stage in detail.stages.reversed) {
    for (final evidence in stage.evidence.reversed) {
      if (_isConfirmedEvidence(evidence)) {
        return (holding: null, evidence: evidence);
      }
    }
  }
  return null;
}

bool _isConfirmedEvidence(RouteSafeEvidence evidence) =>
    evidence.isExecutable &&
    (evidence.receipt?.status == RouteTransactionStatus.confirmed ||
        evidence.state == RouteEvidenceState.confirmed ||
        evidence.state == RouteEvidenceState.completed);

String _lastConfirmedDetails(
  BuildContext context,
  RouteExecutionDetail detail,
  _LastConfirmedStageEvidence? lastConfirmed,
) {
  if (lastConfirmed?.holding case final holding?) {
    return unifiedSwapText(
      context,
      'activity.recovery.lastConfirmedHolding',
      'Last confirmed: {amount} at {address} on {network}. Current location '
          'is not verified.',
      namedArgs: {
        'amount': routeActivityAmount(holding.amount, holding.asset),
        'address': unifiedSwapShortIdentity(holding.address),
        'network': unifiedSwapNetworkLabel(context, holding.asset),
      },
    );
  }
  if (lastConfirmed?.evidence case final evidence?) {
    final evidenceParts = <String>[
      _evidenceLabel(context, evidence.kind),
      if (evidence.reference case final reference?) reference,
    ];
    final network = switch (evidence.kind) {
      RouteEvidenceKind.sourceReceipt || RouteEvidenceKind.refund =>
        unifiedSwapNetworkLabel(context, detail.consent.source),
      RouteEvidenceKind.receiving => unifiedSwapNetworkLabel(
        context,
        detail.consent.destination,
      ),
      RouteEvidenceKind.providerStatus || RouteEvidenceKind.unknown => null,
    };
    return unifiedSwapText(
      context,
      'activity.recovery.lastConfirmedEvidence',
      'Last confirmed evidence: {evidence}{network}. Current location is '
          'unknown.',
      namedArgs: {
        'evidence': evidenceParts.join(' · '),
        'network': network == null ? '' : ' on $network',
      },
    );
  }
  return unifiedSwapText(
    context,
    'activity.recovery.noConfirmedLocation',
    'Current location is unknown. No authoritative last-confirmed location '
        'is available.',
  );
}

String _feeLabel(BuildContext context, RouteFeeKind kind) {
  final fallback = switch (kind) {
    RouteFeeKind.provider => 'Service',
    RouteFeeKind.bridge => 'Bridge',
    RouteFeeKind.exchange => 'Exchange',
    RouteFeeKind.network => 'Network',
    RouteFeeKind.kdf => 'Swap',
    RouteFeeKind.unknown => 'Unknown',
  };
  return unifiedSwapText(context, 'activity.feeKind.${kind.name}', fallback);
}

String _evidenceLabel(BuildContext context, RouteEvidenceKind kind) {
  final fallback = switch (kind) {
    RouteEvidenceKind.sourceReceipt => 'Source receipt',
    RouteEvidenceKind.receiving => 'Receiving transaction',
    RouteEvidenceKind.refund => 'Refund transaction',
    RouteEvidenceKind.providerStatus => 'Transfer status',
    RouteEvidenceKind.unknown => 'Evidence unavailable',
  };
  return unifiedSwapText(context, 'activity.evidence.${kind.name}', fallback);
}

String _evidenceStateLabel(BuildContext context, RouteEvidenceState state) {
  final fallback = switch (state) {
    RouteEvidenceState.broadcast => 'Broadcast',
    RouteEvidenceState.confirmed => 'Confirmed',
    RouteEvidenceState.published => 'Multi-step swap submitted',
    RouteEvidenceState.temporarilyUnavailable =>
      'Exchange status temporarily unavailable',
    RouteEvidenceState.invalidEvidence => 'Exchange evidence unavailable',
    RouteEvidenceState.failed => 'Multi-step exchange failed',
    RouteEvidenceState.completed => 'Multi-step exchange completed',
    RouteEvidenceState.unknown => 'Unknown',
  };
  return unifiedSwapText(
    context,
    'activity.evidenceState.${state.name}',
    fallback,
  );
}

String _transactionStatusLabel(
  BuildContext context,
  RouteTransactionStatus status,
) {
  final fallback = switch (status) {
    RouteTransactionStatus.notFound => 'Not found',
    RouteTransactionStatus.pending => 'Pending',
    RouteTransactionStatus.confirmed => 'Confirmed',
    RouteTransactionStatus.reverted => 'Reverted',
    RouteTransactionStatus.unknown => 'Unknown',
  };
  return unifiedSwapText(
    context,
    'activity.transactionStatus.${status.name}',
    fallback,
  );
}

String _executionPhaseLabel(
  BuildContext context,
  RouteActivityExecutionPhase phase,
) {
  final fallback = switch (phase) {
    RouteActivityExecutionPhase.planned => 'Planned',
    RouteActivityExecutionPhase.awaitingApproval => 'Awaiting approval',
    RouteActivityExecutionPhase.approvalPending => 'Approval pending',
    RouteActivityExecutionPhase.awaitingUserAction => 'Awaiting user action',
    RouteActivityExecutionPhase.awaitingSignature => 'Awaiting signature',
    RouteActivityExecutionPhase.signed => 'Signed',
    RouteActivityExecutionPhase.broadcasting => 'Broadcasting',
    RouteActivityExecutionPhase.sourcePending => 'Source pending',
    RouteActivityExecutionPhase.sourceConfirmed => 'Source confirmed',
    RouteActivityExecutionPhase.bridgePending => 'Bridge pending',
    RouteActivityExecutionPhase.destinationConfirmed => 'Destination confirmed',
    RouteActivityExecutionPhase.refundPending => 'Refund pending',
    RouteActivityExecutionPhase.partial => 'Completed in a different asset',
    RouteActivityExecutionPhase.refunded => 'Refunded',
    RouteActivityExecutionPhase.manualIntervention => 'Manual intervention',
    RouteActivityExecutionPhase.failed => 'Failed',
    RouteActivityExecutionPhase.cancelled => 'Cancelled',
    RouteActivityExecutionPhase.unknown => 'Unknown',
  };
  return unifiedSwapText(
    context,
    'activity.executionPhase.${phase.name}',
    fallback,
  );
}

String _executionRoutePhaseLabel(
  BuildContext context,
  RouteExecutionRoutePhase phase,
) {
  final fallback = switch (phase) {
    RouteExecutionRoutePhase.validating => 'Validating',
    RouteExecutionRoutePhase.executingStage => 'Executing stage',
    RouteExecutionRoutePhase.waitingSourceReceipt =>
      'Waiting for source receipt',
    RouteExecutionRoutePhase.waitingDestination => 'Waiting for destination',
    RouteExecutionRoutePhase.atomicFill => 'Multi-step exchange',
    RouteExecutionRoutePhase.awaitingUserAction => 'Awaiting user action',
    RouteExecutionRoutePhase.stopAfterCurrent => 'Stopping after current stage',
    RouteExecutionRoutePhase.manualIntervention => 'Manual intervention',
    RouteExecutionRoutePhase.partial => 'Completed in a different asset',
    RouteExecutionRoutePhase.refundPending => 'Refund pending',
    RouteExecutionRoutePhase.refunded => 'Refunded',
    RouteExecutionRoutePhase.completed => 'Completed',
    RouteExecutionRoutePhase.failed => 'Failed',
    RouteExecutionRoutePhase.cancelled => 'Cancelled',
    RouteExecutionRoutePhase.unknown => 'Unknown',
  };
  return unifiedSwapText(
    context,
    'activity.executionRoutePhase.${phase.name}',
    fallback,
  );
}

String _approvalRecoveryLabel(
  BuildContext context,
  RouteApprovalRecoveryInstruction instruction,
) {
  final fallback = switch (instruction) {
    RouteApprovalRecoveryInstruction.revokeAllowanceBeforeRetry =>
      'Revoke allowance before retrying',
    RouteApprovalRecoveryInstruction.noAllowanceRemains =>
      'No allowance remains',
    RouteApprovalRecoveryInstruction.unknown => 'Unknown instruction',
  };
  return unifiedSwapText(
    context,
    'activity.approvalRecovery.${instruction.name}',
    fallback,
  );
}

String _transferDirectionLabel(
  BuildContext context,
  RouteEvidenceTransferDirection direction,
) {
  final fallback = switch (direction) {
    RouteEvidenceTransferDirection.sending => 'Sending transfer',
    RouteEvidenceTransferDirection.receiving => 'Receiving transfer',
    RouteEvidenceTransferDirection.transfer => 'Service transfer',
  };
  return unifiedSwapText(
    context,
    'activity.transferDirection.${direction.name}',
    fallback,
  );
}

String _chainFamilyLabel(BuildContext context, UnifiedSwapChainFamily family) {
  final fallback = switch (family) {
    UnifiedSwapChainFamily.evm => 'EVM',
    UnifiedSwapChainFamily.tron => 'TRON',
    UnifiedSwapChainFamily.utxo => 'UTXO',
    UnifiedSwapChainFamily.solana => 'Solana',
    UnifiedSwapChainFamily.sui => 'Sui',
    UnifiedSwapChainFamily.other => 'Other',
    UnifiedSwapChainFamily.unknown => 'Unknown',
  };
  return unifiedSwapText(
    context,
    'activity.chainFamily.${family.name}',
    fallback,
  );
}

String _providerTransferAmount(
  String smallestUnits,
  RouteEvidenceTransferAsset asset,
) {
  if (asset.decimals <= 0) return '$smallestUnits ${asset.symbol}';
  final padded = smallestUnits.padLeft(asset.decimals + 1, '0');
  final split = padded.length - asset.decimals;
  final whole = padded.substring(0, split);
  final fraction = padded.substring(split).replaceFirst(RegExp(r'0+$'), '');
  return '${fraction.isEmpty ? whole : '$whole.$fraction'} ${asset.symbol}';
}

Future<void> _confirmActivityCancellation(
  BuildContext context,
  String routeExecutionId,
  VoidCallback onConfirmed,
) async {
  final confirmed = await showUnifiedSwapSensitiveConfirmation(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      key: const Key('activity-cancel-confirmation'),
      scrollable: true,
      title: Text(
        unifiedSwapText(
          dialogContext,
          'execution.cancelDialogTitle',
          'Cancel this swap?',
        ),
      ),
      content: _exactActivityRouteTarget(
        dialogContext,
        body: unifiedSwapText(
          dialogContext,
          'activity.cancelDialogBody',
          'Only the current server-authorized boundary can be cancelled. '
              'Completed transfers cannot be reversed.',
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
          key: const Key('activity-confirm-cancel'),
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

Future<void> _confirmActivityStop(
  BuildContext context,
  String routeExecutionId,
  VoidCallback onConfirmed,
) async {
  final confirmed = await showUnifiedSwapSensitiveConfirmation(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      key: const Key('activity-stop-confirmation'),
      scrollable: true,
      title: Text(
        unifiedSwapText(
          dialogContext,
          'activity.stopDialogTitle',
          'Stop after this stage?',
        ),
      ),
      content: _exactActivityRouteTarget(
        dialogContext,
        body: unifiedSwapText(
          dialogContext,
          'activity.stopDialogBody',
          'The current stage will continue. No later stage will start unless '
              'the latest durable controls still authorize this action.',
        ),
        routeExecutionId: routeExecutionId,
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(
            unifiedSwapText(
              dialogContext,
              'activity.keepRouteRunning',
              'Keep route running',
            ),
          ),
        ),
        FilledButton(
          key: const Key('activity-confirm-stop'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(
            unifiedSwapText(
              dialogContext,
              'activity.stopAfterCurrent',
              'Stop after current',
            ),
          ),
        ),
      ],
    ),
  );
  if (confirmed) onConfirmed();
}

Future<void> _confirmActivityRecovery(
  BuildContext context,
  String routeExecutionId,
  VoidCallback onConfirmed,
) async {
  final confirmed = await showUnifiedSwapSensitiveConfirmation(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      key: const Key('activity-recovery-confirmation'),
      scrollable: true,
      title: Text(
        unifiedSwapText(
          dialogContext,
          'activity.recoveryDialogTitle',
          'Review a recovery route?',
        ),
      ),
      content: _exactActivityRouteTarget(
        dialogContext,
        body: unifiedSwapText(
          dialogContext,
          'activity.recoveryDialogBody',
          'Recovery starts from the verified holding and still requires a '
              'fresh quote, prepared Review, and explicit consent.',
        ),
        routeExecutionId: routeExecutionId,
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(
            unifiedSwapText(dialogContext, 'activity.notNow', 'Not now'),
          ),
        ),
        FilledButton(
          key: const Key('activity-confirm-recovery'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(
            unifiedSwapText(
              dialogContext,
              'activity.reviewRecovery',
              'Review recovery',
            ),
          ),
        ),
      ],
    ),
  );
  if (confirmed) onConfirmed();
}

Widget _exactActivityRouteTarget(
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

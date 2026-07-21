import 'package:flutter/material.dart';
import 'package:web_dex/features/unified_swap/application/route_activity_bloc.dart';
import 'package:web_dex/features/unified_swap/domain/route_activity_models.dart';
import 'package:web_dex/features/unified_swap/presentation/activity/activity_widgets.dart';
import 'package:web_dex/features/unified_swap/presentation/unified_swap_design.dart';

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
                  constraints: const BoxConstraints(maxWidth: 1040),
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
                        _ActivityRecoverySummary(detail: detail),
                      ],
                      if (state.failure != null) ...[
                        const SizedBox(height: 12),
                        RouteActivityFailureNotice(onRetry: onRetry),
                      ],
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 760;
                          final width = wide
                              ? (constraints.maxWidth - 12) / 2
                              : constraints.maxWidth;
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              SizedBox(
                                width: width,
                                child: _RouteTermsCard(detail: detail),
                              ),
                              SizedBox(
                                width: width,
                                child: _RouteControlsCard(
                                  detail: detail,
                                  onCancelRequested: onCancelRequested,
                                  onStopAfterCurrentRequested:
                                      onStopAfterCurrentRequested,
                                  onRecoveryRequested: onRecoveryRequested,
                                ),
                              ),
                              if (detail.holding case final holding?)
                                SizedBox(
                                  width: width,
                                  child: _HoldingCard(holding: holding),
                                ),
                              if (detail.consent.fees.isNotEmpty ||
                                  detail
                                      .consent
                                      .nonNetworkFeeLimits
                                      .isNotEmpty ||
                                  detail.consent.networkFeeCaps.isNotEmpty)
                                SizedBox(
                                  width: width,
                                  child: _FeesCard(detail: detail),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      _StagesCard(stages: detail.stages),
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

class _ActivityRecoverySummary extends StatelessWidget {
  const _ActivityRecoverySummary({required this.detail});

  final RouteExecutionDetail detail;

  @override
  Widget build(BuildContext context) {
    final holding = detail.holding;
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
              ? unifiedSwapText(
                  context,
                  'activity.recovery.locationUnverified',
                  'Current location is not verified',
                )
              : unifiedSwapText(
                  context,
                  'recovery.verifiedHolding',
                  'Verified current holding',
                ),
          details: holding == null
              ? unifiedSwapText(
                  context,
                  'activity.recovery.noInferredLocation',
                  'The wallet does not infer or fabricate a location.',
                )
              : unifiedSwapText(
                  context,
                  'activity.recovery.holdingLocation',
                  '{amount} at {address}.',
                  namedArgs: {
                    'amount': routeActivityAmount(
                      holding.amount,
                      holding.asset,
                    ),
                    'address': unifiedSwapShortIdentity(holding.address),
                  },
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
                  '${summary.source.ticker} → '
                  '${summary.destination.ticker}',
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

class _RouteControlsCard extends StatelessWidget {
  const _RouteControlsCard({
    required this.detail,
    required this.onCancelRequested,
    required this.onStopAfterCurrentRequested,
    required this.onRecoveryRequested,
  });

  final RouteExecutionDetail detail;
  final ValueChanged<String>? onCancelRequested;
  final ValueChanged<String>? onStopAfterCurrentRequested;
  final ValueChanged<String>? onRecoveryRequested;

  @override
  Widget build(BuildContext context) {
    final controls = detail.controls;
    final known = detail.summary.status != RouteActivityStatus.unknown;
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
                    onPressed: () => _confirmActivityCancellation(
                      context,
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
                    onPressed: () => _confirmActivityStop(
                      context,
                      () => onStopAfterCurrentRequested!(routeExecutionId),
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
                    onPressed: () => _confirmActivityRecovery(
                      context,
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
  const _HoldingCard({required this.holding});

  final RouteHolding holding;

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
              value: routeActivityAmount(limit.maximumAmount, limit.asset),
            ),
          for (final cap in consent.networkFeeCaps)
            _DetailRow(
              label: unifiedSwapText(
                context,
                'activity.detail.stageNetworkMaximum',
                'Stage network maximum',
              ),
              value: routeActivityAmount(cap.maximumAmount, cap.asset),
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
            for (final evidence in stage.evidence)
              Text(
                evidence.reference == null
                    ? _evidenceLabel(context, evidence.kind)
                    : '${_evidenceLabel(context, evidence.kind)} · '
                          '${evidence.reference}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ],
      ),
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
          for (final revision in revisions)
            Material(
              color: Colors.transparent,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.archive_outlined),
                title: Text(
                  unifiedSwapText(
                    context,
                    'activity.detail.revisionNumber',
                    'Revision {number}',
                    namedArgs: {'number': '${revision.revision + 1}'},
                  ),
                ),
                subtitle: Text(
                  unifiedSwapText(
                    context,
                    'activity.detail.archivedAt',
                    '{phase} · archived {date}',
                    namedArgs: {
                      'phase': routeActivityPhaseLabel(context, revision.phase),
                      'date': routeActivityDate(context, revision.archivedAt),
                    },
                  ),
                ),
                trailing: Text(
                  unifiedSwapText(
                    context,
                    'activity.detail.stageCount',
                    '{count} stages',
                    namedArgs: {'count': '${revision.stages.length}'},
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.selectable = false,
  });

  final String label;
  final String value;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final valueWidget = selectable
        ? SelectableText(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodyMedium,
          )
        : Text(value, textAlign: TextAlign.end);
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
          Expanded(flex: 6, child: valueWidget),
        ],
      ),
    );
  }
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

Future<void> _confirmActivityCancellation(
  BuildContext context,
  VoidCallback onConfirmed,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('activity-cancel-confirmation'),
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
          'activity.cancelDialogBody',
          'Only the current server-authorized boundary can be cancelled. '
              'Completed transfers cannot be reversed.',
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
  if (confirmed == true) onConfirmed();
}

Future<void> _confirmActivityStop(
  BuildContext context,
  VoidCallback onConfirmed,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('activity-stop-confirmation'),
      title: Text(
        unifiedSwapText(
          dialogContext,
          'activity.stopDialogTitle',
          'Stop after this stage?',
        ),
      ),
      content: Text(
        unifiedSwapText(
          dialogContext,
          'activity.stopDialogBody',
          'The current stage will continue. No later stage will start unless '
              'the latest durable controls still authorize this action.',
        ),
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
  if (confirmed == true) onConfirmed();
}

Future<void> _confirmActivityRecovery(
  BuildContext context,
  VoidCallback onConfirmed,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('activity-recovery-confirmation'),
      title: Text(
        unifiedSwapText(
          dialogContext,
          'activity.recoveryDialogTitle',
          'Review a recovery route?',
        ),
      ),
      content: Text(
        unifiedSwapText(
          dialogContext,
          'activity.recoveryDialogBody',
          'Recovery starts from the verified holding and still requires a '
              'fresh quote, prepared Review, and explicit consent.',
        ),
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
  if (confirmed == true) onConfirmed();
}

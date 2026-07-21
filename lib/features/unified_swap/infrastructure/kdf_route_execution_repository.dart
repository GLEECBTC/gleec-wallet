import 'dart:async';

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as kdf;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/features/unified_swap/domain/route_activity_models.dart';
import 'package:web_dex/features/unified_swap/domain/route_execution_models.dart';
import 'package:web_dex/features/unified_swap/domain/route_execution_repository.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_quote_models.dart';
import 'package:web_dex/features/unified_swap/infrastructure/kdf_unified_swap_quote_repository.dart';

typedef UnifiedSwapExecutionEligibilityCheck =
    Future<bool> Function(RouteExecutionReview review);

/// Wallet-scoped adapter for KDF's durable route-execution task API.
///
/// Full fresh-init consent is held only in [_registeredReviews]. It is never
/// persisted and is consumed before an init request is attempted. Reattachment
/// always delegates to KDF's durable get-then-safe-consent flow instead.
final class KdfRouteExecutionRepository implements RouteExecutionRepository {
  KdfRouteExecutionRepository({
    required String walletId,
    required TradeRouteManager manager,
    UnifiedSwapExecutionEligibilityCheck? executionEligibilityCheck,
    DateTime Function()? now,
  }) : _walletId = _validWalletId(walletId),
       _manager = manager,
       _executionEligibilityCheck = executionEligibilityCheck,
       _now = now ?? _utcNow;

  final String _walletId;
  final TradeRouteManager _manager;
  final UnifiedSwapExecutionEligibilityCheck? _executionEligibilityCheck;
  final DateTime Function() _now;
  final Map<String, _RegisteredReview> _registeredReviews = {};
  final Map<String, _SessionBinding> _sessions = {};
  bool _isDisposed = false;

  /// Verifies and registers one server-prepared Review/consent authority.
  ///
  /// Callers cannot supply display values separately from KDF authority. The
  /// returned Review is projected only after all preparation digests, stage
  /// limits, approvals, addresses and economics have been checked. Its
  /// consent remains memory-only and one-shot.
  RouteExecutionReview registerVerifiedExecution({
    required String routeExecutionId,
    required KdfVerifiedPreparedExecution verified,
  }) {
    _ensureActive();
    final prepared = verified.prepared;
    _registeredReviews.removeWhere(
      (_, registered) => registered.review.isExpiredAt(_now()),
    );
    if (!_isUuid(routeExecutionId) || !_validatePreparedExecution(prepared)) {
      throw const RouteExecutionException(RouteExecutionFailure.invalidReview);
    }
    late final RouteExecutionReview review;
    try {
      review = _preparedReview(
        walletId: _walletId,
        routeExecutionId: routeExecutionId,
        prepared: prepared,
        intent: verified.intent,
      );
    } on Object {
      throw const RouteExecutionException(RouteExecutionFailure.invalidReview);
    }
    if (!review.isExecutable) {
      throw const RouteExecutionException(RouteExecutionFailure.invalidReview);
    }
    if (_registeredReviews.containsKey(review.reviewId)) {
      throw const RouteExecutionException(RouteExecutionFailure.invalidReview);
    }
    _registeredReviews[review.reviewId] = _RegisteredReview(
      review: review,
      consent: prepared.routeConsent,
    );
    return review;
  }

  /// Removes an unconsumed same-session authority that presentation rejected
  /// after an asynchronous preparation completed.
  void discardPreparedReview(RouteExecutionReview review) {
    if (_isDisposed || review.walletId != _walletId) return;
    final registered = _registeredReviews[review.reviewId];
    if (registered != null &&
        registered.review.routeExecutionId == review.routeExecutionId &&
        registered.review.consentDigest == review.consentDigest) {
      _registeredReviews.remove(review.reviewId);
    }
  }

  @override
  Future<RouteExecutionSession> initReviewedExecution({
    required String walletId,
    required String routeExecutionId,
    required String reviewId,
    required String consentDigest,
  }) async {
    _ensureActive();
    _requireWallet(walletId);
    if (!_isCanonicalValue(routeExecutionId) ||
        !_isCanonicalValue(reviewId) ||
        !_isCanonicalValue(consentDigest)) {
      throw const RouteExecutionException(RouteExecutionFailure.invalidReview);
    }

    final registered = _registeredReviews[reviewId];
    if (registered == null ||
        registered.review.routeExecutionId != routeExecutionId ||
        registered.review.consentDigest != consentDigest) {
      throw const RouteExecutionException(RouteExecutionFailure.invalidReview);
    }

    // Consume before any asynchronous work so one review can authorize at
    // most one fresh-init attempt, including when transport later fails.
    _registeredReviews.remove(reviewId);
    if (registered.review.isExpiredAt(_now())) {
      throw const RouteExecutionException(RouteExecutionFailure.reviewExpired);
    }
    if (!await _isEligible(registered.review)) {
      throw const RouteExecutionException(
        RouteExecutionFailure.capabilityUnavailable,
      );
    }

    try {
      final task = await _manager.initTradeRoute(
        routeExecutionId: routeExecutionId,
        routeConsent: registered.consent,
      );
      return _recordSession(task, registered.review.steps.length);
    } on Object catch (error) {
      throw _asExecutionException(error);
    }
  }

  Future<bool> _isEligible(RouteExecutionReview review) async {
    final eligibilityCheck = _executionEligibilityCheck;
    if (eligibilityCheck == null) return false;
    try {
      return await eligibilityCheck(review);
    } on Object {
      return false;
    }
  }

  @override
  Future<RouteExecutionSession> reattachExecution({
    required String walletId,
    required String routeExecutionId,
  }) async {
    _ensureActive();
    _requireWallet(walletId);
    _requireRouteId(routeExecutionId);
    try {
      final attached = await _manager.reattachTradeRoute(
        routeExecutionId: routeExecutionId,
      );
      return _recordSession(
        attached.task,
        attached.execution.candidate.stages.length,
        durableProgress: _progressFromDetails(
          attached.execution.status,
          taskKind: _taskKindForDurableStatus(attached.execution.status),
          stageCount: attached.execution.candidate.stages.length,
        ),
      );
    } on Object catch (error) {
      throw _asExecutionException(error);
    }
  }

  @override
  Stream<RouteExecutionProgress> observe(RouteExecutionSession session) {
    try {
      _ensureActive();
      final binding = _bindingFor(session);
      return _observe(binding);
    } on Object catch (error, stackTrace) {
      return Stream.error(_asExecutionException(error), stackTrace);
    }
  }

  Stream<RouteExecutionProgress> _observe(_SessionBinding binding) async* {
    try {
      final durableProgress = binding.durableProgress;
      if (durableProgress != null) {
        yield durableProgress;
        if (!_shouldContinueObservation(durableProgress)) return;
      }
      await for (final response in _manager.observeStatus(binding.task)) {
        yield _progress(response.result, stageCount: binding.stageCount);
      }
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(_asExecutionException(error), stackTrace);
    }
  }

  @override
  Future<void> cancelExecution({
    required String walletId,
    required String routeExecutionId,
  }) async {
    _ensureActive();
    _requireWallet(walletId);
    _requireRouteId(routeExecutionId);
    try {
      await _manager.cancelTradeRoute(routeExecutionId: routeExecutionId);
    } on Object catch (error) {
      throw _asExecutionException(error);
    }
  }

  @override
  Future<void> stopAfterCurrent({
    required String walletId,
    required String routeExecutionId,
  }) async {
    _ensureActive();
    _requireWallet(walletId);
    _requireRouteId(routeExecutionId);
    try {
      await _manager.stopAfterCurrent(routeExecutionId: routeExecutionId);
    } on Object catch (error) {
      throw _asExecutionException(error);
    }
  }

  @override
  Future<RouteActionAcknowledgement> submitDecision({
    required String walletId,
    required RouteExecutionSession session,
    required RouteExecutionDecision decision,
  }) async {
    _ensureActive();
    _requireWallet(walletId);
    final binding = _bindingFor(
      session,
      failure: RouteExecutionFailure.actionNotAuthorized,
    );
    if (!_isCanonicalValue(decision.actionId) ||
        decision.expectedStateRevision < 0) {
      throw const RouteExecutionException(
        RouteExecutionFailure.actionNotAuthorized,
      );
    }

    late final kdf.RouteExecutionUserAction action;
    try {
      action = await _actionFor(binding, decision);
    } on RouteExecutionException {
      rethrow;
    } on Object {
      throw const RouteExecutionException(
        RouteExecutionFailure.actionNotAuthorized,
      );
    }
    try {
      final acknowledgement = await _manager.deliverUserAction(
        task: binding.task,
        userAction: action,
      );
      return RouteActionAcknowledgement(
        wasDelivered: acknowledgement.wasDelivered,
      );
    } on Object catch (error) {
      throw _asExecutionException(error);
    }
  }

  /// Clears every same-session review and task binding for this wallet.
  ///
  /// The injected manager may be shared with the Activity adapter, so its
  /// lifecycle remains owned by the wallet composition root.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _registeredReviews.clear();
    _sessions.clear();
  }

  RouteExecutionSession _recordSession(
    TradeRouteTaskHandle task,
    int stageCount, {
    RouteExecutionProgress? durableProgress,
  }) {
    final binding = _SessionBinding(
      task: task,
      stageCount: stageCount,
      durableProgress: durableProgress,
    );
    _sessions[task.routeExecutionId] = binding;
    return RouteExecutionSession(
      routeExecutionId: task.routeExecutionId,
      taskId: task.taskId,
    );
  }

  _SessionBinding _bindingFor(
    RouteExecutionSession session, {
    RouteExecutionFailure failure = RouteExecutionFailure.conflict,
  }) {
    final binding = _sessions[session.routeExecutionId];
    if (binding == null || binding.task.taskId != session.taskId) {
      throw RouteExecutionException(failure);
    }
    return binding;
  }

  Future<kdf.RouteExecutionUserAction> _actionFor(
    _SessionBinding binding,
    RouteExecutionDecision decision,
  ) async {
    switch (decision.kind) {
      case RouteExecutionActionKind.rejectChange:
        return kdf.RouteExecutionUserAction.rejectChange(
          actionId: decision.actionId,
          expectedStateRevision: decision.expectedStateRevision,
        );
      case RouteExecutionActionKind.stopAfterCurrent:
        return kdf.RouteExecutionUserAction.stopAfterCurrent(
          actionId: decision.actionId,
          expectedStateRevision: decision.expectedStateRevision,
        );
      case RouteExecutionActionKind.selectRecoveryRoute:
        final recoveryReviewId = decision.recoveryReviewId;
        final registered = recoveryReviewId == null
            ? null
            : _registeredReviews[recoveryReviewId];
        if (registered == null ||
            registered.review.routeExecutionId !=
                binding.task.routeExecutionId ||
            registered.review.isExpiredAt(_now())) {
          throw const RouteExecutionException(
            RouteExecutionFailure.actionNotAuthorized,
          );
        }
        _registeredReviews.remove(recoveryReviewId);
        return kdf.RouteExecutionUserAction.selectRecoveryRoute(
          actionId: decision.actionId,
          expectedStateRevision: decision.expectedStateRevision,
          recoveryRouteConsent: registered.consent,
        );
      case RouteExecutionActionKind.acceptReplacement:
        final proposalDigest = decision.replacementProposalDigest;
        if (proposalDigest == null || !_isCanonicalValue(proposalDigest)) {
          throw const RouteExecutionException(
            RouteExecutionFailure.actionNotAuthorized,
          );
        }
        final execution = await _manager.getExecution(
          routeExecutionId: binding.task.routeExecutionId,
        );
        final status = execution.status;
        final pending = status.pendingUserAction;
        final summary = pending?.replacementSummary;
        final replacement = summary?.replacementStageConsent;
        if (execution.routeExecutionId != binding.task.routeExecutionId ||
            !status.isExecutable ||
            status.stateRevision != decision.expectedStateRevision ||
            pending == null ||
            !pending.isExecutable ||
            pending.actionId != decision.actionId ||
            pending.reason.knownValue == null ||
            !pending.allowedActions.any(
              (value) =>
                  value.knownValue == kdf.AllowedUserAction.acceptReplacement,
            ) ||
            summary == null ||
            !summary.isExecutable ||
            summary.proposalDigest != proposalDigest ||
            !summary.expiresAt.isAfter(_now()) ||
            replacement == null ||
            !_replacementConsentMatchesProjection(summary, replacement) ||
            !_replacementConsentMatchesDurableExecution(
              execution,
              summary,
              replacement,
            )) {
          throw const RouteExecutionException(
            RouteExecutionFailure.actionNotAuthorized,
          );
        }
        return kdf.RouteExecutionUserAction.acceptReplacement(
          actionId: decision.actionId,
          expectedStateRevision: decision.expectedStateRevision,
          proposalDigest: proposalDigest,
          replacementStageConsent: replacement,
        );
      case RouteExecutionActionKind.unknown:
        throw const RouteExecutionException(
          RouteExecutionFailure.actionNotAuthorized,
        );
    }
  }

  void _ensureActive() {
    if (_isDisposed) {
      throw const RouteExecutionException(
        RouteExecutionFailure.serviceUnavailable,
      );
    }
  }

  void _requireWallet(String walletId) {
    if (walletId != _walletId) {
      throw const RouteExecutionException(
        RouteExecutionFailure.capabilityUnavailable,
      );
    }
  }
}

final class _RegisteredReview {
  const _RegisteredReview({required this.review, required this.consent});

  final RouteExecutionReview review;
  final kdf.RouteConsent consent;
}

final class _SessionBinding {
  const _SessionBinding({
    required this.task,
    required this.stageCount,
    required this.durableProgress,
  });

  final TradeRouteTaskHandle task;
  final int stageCount;
  final RouteExecutionProgress? durableProgress;
}

RouteExecutionProgress _progress(
  kdf.TradeRouteTaskStatus status, {
  required int stageCount,
}) {
  return switch (status) {
    kdf.TradeRouteInProgressStatus(:final details) => _progressFromDetails(
      details,
      taskKind: _TaskKind.inProgress,
      stageCount: stageCount,
    ),
    kdf.TradeRouteUserActionRequiredStatus(:final details) =>
      _progressFromDetails(
        details,
        taskKind: _TaskKind.userActionRequired,
        stageCount: stageCount,
      ),
    kdf.TradeRouteOkStatus(:final details) => _progressFromDetails(
      details,
      taskKind: _TaskKind.ok,
      stageCount: stageCount,
    ),
    kdf.TradeRouteErrorStatus(:final details) => throw RouteExecutionException(
      _failureFor(details),
    ),
    kdf.UnknownTradeRouteTaskStatus() => throw const RouteExecutionException(
      RouteExecutionFailure.unknown,
    ),
  };
}

enum _TaskKind { inProgress, userActionRequired, ok }

_TaskKind _taskKindForDurableStatus(kdf.RouteExecutionStatus status) {
  if (status.pendingUserAction != null) return _TaskKind.userActionRequired;
  return switch (status.routePhase.knownValue) {
    kdf.RoutePhase.completed ||
    kdf.RoutePhase.cancelled ||
    kdf.RoutePhase.failed => _TaskKind.ok,
    _ => _TaskKind.inProgress,
  };
}

bool _shouldContinueObservation(RouteExecutionProgress progress) =>
    progress.isExecutable &&
    (progress.outcome == RouteExecutionOutcome.active ||
        progress.outcome == RouteExecutionOutcome.attentionRequired ||
        progress.outcome == RouteExecutionOutcome.recovery);

RouteExecutionProgress _progressFromDetails(
  kdf.RouteExecutionStatus details, {
  required _TaskKind taskKind,
  required int stageCount,
}) {
  final pending = _pendingAction(details.pendingUserAction);
  final phase = _executionPhase(details);
  final outcome = _executionOutcome(
    details,
    taskKind: taskKind,
    pendingAction: pending,
  );
  return RouteExecutionProgress(
    routeExecutionId: details.routeExecutionId,
    outcome: outcome.value,
    phase: phase.value,
    stateRevision: details.stateRevision,
    stageIndex: details.stageIndex,
    stageCount: stageCount,
    controls: _controls(details.controls),
    pendingAction: pending,
    holding: _holding(details.actualHolding),
    transactionHashes: details.txHashes,
    updatedAt: details.updatedAt,
    rawOutcomeDiscriminator: outcome.rawDiscriminator,
    rawPhaseDiscriminator: phase.rawDiscriminator,
  );
}

({RouteExecutionOutcome value, String? rawDiscriminator}) _executionOutcome(
  kdf.RouteExecutionStatus details, {
  required _TaskKind taskKind,
  required RoutePendingAction? pendingAction,
}) {
  if (!details.isExecutable) {
    return (
      value: RouteExecutionOutcome.unknown,
      rawDiscriminator: _safeNonExecutableDiscriminator(details),
    );
  }
  if (taskKind == _TaskKind.userActionRequired) {
    return (
      value: pendingAction?.reason == RoutePendingActionReason.recoveryRequired
          ? RouteExecutionOutcome.recovery
          : RouteExecutionOutcome.attentionRequired,
      rawDiscriminator: null,
    );
  }

  final routePhase = details.routePhase.knownValue!;
  final outcome = switch (routePhase) {
    kdf.RoutePhase.awaitingUserAction ||
    kdf.RoutePhase.stopAfterCurrent => RouteExecutionOutcome.attentionRequired,
    kdf.RoutePhase.manualIntervention ||
    kdf.RoutePhase.partial ||
    kdf.RoutePhase.refundPending ||
    kdf.RoutePhase.refunded => RouteExecutionOutcome.recovery,
    kdf.RoutePhase.completed => RouteExecutionOutcome.completed,
    kdf.RoutePhase.cancelled => RouteExecutionOutcome.cancelled,
    kdf.RoutePhase.failed => RouteExecutionOutcome.failed,
    _ => RouteExecutionOutcome.active,
  };
  if (taskKind == _TaskKind.ok && outcome == RouteExecutionOutcome.active) {
    return (
      value: RouteExecutionOutcome.unknown,
      rawDiscriminator: 'inconsistent_ok_status',
    );
  }
  return (value: outcome, rawDiscriminator: null);
}

({RouteExecutionPhase value, String? rawDiscriminator}) _executionPhase(
  kdf.RouteExecutionStatus details,
) {
  final routePhase = details.routePhase.knownValue;
  if (routePhase == null) {
    return (
      value: RouteExecutionPhase.unknown,
      rawDiscriminator: details.routePhase.rawValue,
    );
  }
  switch (routePhase) {
    case kdf.RoutePhase.validating:
      return (value: RouteExecutionPhase.validating, rawDiscriminator: null);
    case kdf.RoutePhase.atomicFill:
      return (value: RouteExecutionPhase.atomicFill, rawDiscriminator: null);
    case kdf.RoutePhase.stopAfterCurrent:
      return (
        value: RouteExecutionPhase.stopAfterCurrent,
        rawDiscriminator: null,
      );
    case kdf.RoutePhase.completed:
      return (value: RouteExecutionPhase.completed, rawDiscriminator: null);
    case kdf.RoutePhase.cancelled:
      return (value: RouteExecutionPhase.cancelled, rawDiscriminator: null);
    case kdf.RoutePhase.failed:
      return (value: RouteExecutionPhase.failed, rawDiscriminator: null);
    case kdf.RoutePhase.partial:
      return (value: RouteExecutionPhase.partial, rawDiscriminator: null);
    case kdf.RoutePhase.executingStage:
    case kdf.RoutePhase.waitingSourceReceipt:
    case kdf.RoutePhase.waitingDestination:
    case kdf.RoutePhase.awaitingUserAction:
    case kdf.RoutePhase.manualIntervention:
    case kdf.RoutePhase.refundPending:
    case kdf.RoutePhase.refunded:
      break;
  }

  final phase = details.phase.knownValue;
  if (phase == null) {
    return (
      value: RouteExecutionPhase.unknown,
      rawDiscriminator: details.phase.rawValue,
    );
  }
  final mapped = switch (phase) {
    kdf.ExecutionPhase.planned => RouteExecutionPhase.validating,
    kdf.ExecutionPhase.awaitingApproval => RouteExecutionPhase.awaitingApproval,
    kdf.ExecutionPhase.approvalPending => RouteExecutionPhase.approvalPending,
    kdf.ExecutionPhase.awaitingUserAction =>
      RouteExecutionPhase.awaitingUserAction,
    kdf.ExecutionPhase.awaitingSignature =>
      RouteExecutionPhase.awaitingSignature,
    kdf.ExecutionPhase.signed => RouteExecutionPhase.signed,
    kdf.ExecutionPhase.broadcasting => RouteExecutionPhase.broadcasting,
    kdf.ExecutionPhase.sourcePending => RouteExecutionPhase.sourcePending,
    kdf.ExecutionPhase.sourceConfirmed => RouteExecutionPhase.sourceConfirmed,
    kdf.ExecutionPhase.bridgePending => RouteExecutionPhase.bridgePending,
    kdf.ExecutionPhase.destinationConfirmed =>
      RouteExecutionPhase.destinationConfirmed,
    kdf.ExecutionPhase.refundPending => RouteExecutionPhase.refundPending,
    kdf.ExecutionPhase.refunded => RouteExecutionPhase.refunded,
    kdf.ExecutionPhase.manualIntervention =>
      RouteExecutionPhase.manualIntervention,
    kdf.ExecutionPhase.failed => RouteExecutionPhase.failed,
    kdf.ExecutionPhase.cancelled => RouteExecutionPhase.cancelled,
    kdf.ExecutionPhase.partial => RouteExecutionPhase.partial,
  };
  return (
    value: mapped,
    rawDiscriminator: mapped == RouteExecutionPhase.unknown
        ? phase.wireName
        : null,
  );
}

RoutePendingAction? _pendingAction(kdf.PendingUserAction? pending) {
  if (pending == null) return null;
  final reason = switch (pending.reason.knownValue) {
    kdf.PendingUserActionReason.quoteChanged => (
      value: RoutePendingActionReason.candidateChanged,
      rawDiscriminator: null,
    ),
    kdf.PendingUserActionReason.recoveryRequired => (
      value: RoutePendingActionReason.recoveryRequired,
      rawDiscriminator: null,
    ),
    kdf.PendingUserActionReason.nonNetworkFeeLimitExceeded => (
      value: RoutePendingActionReason.nonNetworkFeeLimitExceeded,
      rawDiscriminator: null,
    ),
    kdf.PendingUserActionReason.networkFeeCapExceeded => (
      value: RoutePendingActionReason.networkFeeCapExceeded,
      rawDiscriminator: null,
    ),
    null => (
      value: RoutePendingActionReason.unknown,
      rawDiscriminator: pending.reason.rawValue,
    ),
  };
  final knownActions = <RouteExecutionActionKind>[];
  final unknownActions = <String>[];
  for (final action in pending.allowedActions) {
    final mapped = switch (action.knownValue) {
      kdf.AllowedUserAction.acceptReplacement =>
        RouteExecutionActionKind.acceptReplacement,
      kdf.AllowedUserAction.rejectChange =>
        RouteExecutionActionKind.rejectChange,
      kdf.AllowedUserAction.selectRecoveryRoute =>
        RouteExecutionActionKind.selectRecoveryRoute,
      kdf.AllowedUserAction.stopAfterCurrent =>
        RouteExecutionActionKind.stopAfterCurrent,
      null => null,
    };
    if (mapped == null) {
      unknownActions.add(action.rawValue);
    } else {
      knownActions.add(mapped);
    }
  }
  return RoutePendingAction(
    actionId: pending.actionId,
    reason: reason.value,
    allowedActions: knownActions,
    rawReasonDiscriminator: reason.rawDiscriminator,
    rawAllowedActionDiscriminators: unknownActions,
    replacementProposal: _replacementProposal(pending.replacementSummary),
  );
}

RouteReplacementProposal? _replacementProposal(
  kdf.ReplacementSummary? summary,
) =>
    summary == null ||
        !summary.isExecutable ||
        !_replacementConsentMatchesProjection(
          summary,
          summary.replacementStageConsent!,
        )
    ? null
    : RouteReplacementProposal(
        proposalDigest: summary.proposalDigest,
        stageId: summary.stageId,
        providerStepDigest: summary.providerStepDigest,
        changedFields: summary.changedFields,
        expectedReceive: summary.expectedReceive,
        minimumReceive: summary.minimumReceive,
        fees: summary.fees.map(_reviewFee).toList(growable: false),
        requiredTotalNetworkFee: summary.requiredTotalNetworkFee == null
            ? null
            : RouteReplacementNetworkFee(
                asset: _asset(summary.requiredTotalNetworkFee!.asset),
                amount: summary.requiredTotalNetworkFee!.amount,
              ),
        expiresAt: summary.expiresAt,
      );

bool _replacementConsentMatchesProjection(
  kdf.ReplacementSummary summary,
  kdf.StageConsent replacement,
) {
  const knownChangedFields = {
    'expected_receive',
    'minimum_receive',
    'non_network_fees',
    'network_fee_cap',
  };
  final changedFields = summary.changedFields.toSet();
  final intent = replacement.stageIntent;
  final source = replacement.executionSource;
  if (!replacement.isExecutable ||
      replacement.preparedExecution == null ||
      summary.changedFields.isEmpty ||
      changedFields.length != summary.changedFields.length ||
      !changedFields.every(knownChangedFields.contains) ||
      intent.stageId != summary.stageId ||
      intent.acceptedExpectedReceive != summary.expectedReceive ||
      intent.minimumReceive != summary.minimumReceive ||
      !_sameWire(
        intent.selectedTools.toJson(),
        summary.selectedTools.toJson(),
      ) ||
      source is! kdf.ProviderIntentExecutionSource ||
      source.providerStepDigest != summary.providerStepDigest) {
    return false;
  }
  try {
    if (kdf.tradeRouteStageConsentDigest(replacement) !=
        replacement.consentDigest) {
      return false;
    }
    final requiredNetworkFee = summary.requiredTotalNetworkFee;
    if (requiredNetworkFee != null &&
        !_sameWire(
          intent.maxTotalNetworkFee.toJson(),
          requiredNetworkFee.toJson(),
        )) {
      return false;
    }
    if (changedFields.contains('non_network_fees') &&
        !_sameReplacementFees(summary.fees, intent.nonNetworkFeeLimits)) {
      return false;
    }
    return true;
  } on Object {
    return false;
  }
}

bool _replacementConsentMatchesDurableExecution(
  kdf.RouteExecutionDetails execution,
  kdf.ReplacementSummary summary,
  kdf.StageConsent replacement,
) {
  final routeConsent = execution.routeConsent;
  final matches = routeConsent.externalStageConsents
      .where((stage) => stage.stageIntent.stageId == summary.stageId)
      .toList(growable: false);
  final candidateStageIndex = execution.candidate.stages.indexWhere(
    (stage) => _candidateStageId(stage) == summary.stageId,
  );
  if (!routeConsent.isExecutable ||
      !execution.candidate.isExecutable ||
      routeConsent.digestVersion != 1 ||
      routeConsent.mode.knownValue != kdf.ExecutionMode.signAndBroadcast ||
      execution.candidate.candidateId != routeConsent.candidateId ||
      execution.candidate.candidateDigest != routeConsent.candidateDigest ||
      execution.recipientAddress != routeConsent.routeIntent.recipient ||
      candidateStageIndex < 0 ||
      matches.length != 1 ||
      replacement.digestVersion != 1 ||
      replacement.modeValue.knownValue != kdf.ExecutionMode.signAndBroadcast ||
      replacement.preparedExecution == null) {
    return false;
  }

  final original = matches.single;
  final originalReference = original.candidateReference;
  final replacementReference = replacement.candidateReference;
  final originalSource = original.executionSource;
  final replacementSource = replacement.executionSource;
  if (!original.isExecutable ||
      original.digestVersion != replacement.digestVersion ||
      original.mode.rawValue != replacement.modeValue.rawValue ||
      originalReference.evaluationId != routeConsent.evaluationId ||
      originalReference.candidateId != routeConsent.candidateId ||
      originalReference.candidateDigest != routeConsent.candidateDigest ||
      originalReference.stageId != summary.stageId ||
      replacementReference.evaluationId != originalReference.evaluationId ||
      replacementReference.candidateId != originalReference.candidateId ||
      replacementReference.candidateDigest !=
          originalReference.candidateDigest ||
      replacementReference.stageId != originalReference.stageId ||
      !_sameWire(
        replacement.routeIntent.toJson(),
        routeConsent.routeIntent.toJson(),
      ) ||
      replacement.stageIntent.routeIntentDigest !=
          kdf.tradeRouteIntentDigest(routeConsent.routeIntent) ||
      !_sameWire(
        replacement.atomicOrderGuard?.toJson(),
        original.atomicOrderGuard?.toJson(),
      ) ||
      originalSource is! kdf.RouteActivityProviderIntentSource ||
      replacementSource is! kdf.ProviderIntentExecutionSource ||
      replacementSource.providerStep != null ||
      !_sameProviderAuthority(originalSource, replacementSource, summary)) {
    return false;
  }

  final originalIntent = original.stageIntent.toJson();
  final replacementIntent = replacement.stageIntent.toJson();
  final actualChangedFields = <String>{};
  void recordChange(String wireField, String summaryField) {
    if (!_sameWire(originalIntent[wireField], replacementIntent[wireField])) {
      actualChangedFields.add(summaryField);
    }
    originalIntent.remove(wireField);
    replacementIntent.remove(wireField);
  }

  recordChange('accepted_expected_receive', 'expected_receive');
  recordChange('minimum_receive', 'minimum_receive');
  recordChange('non_network_fee_limits', 'non_network_fees');
  recordChange('max_total_network_fee', 'network_fee_cap');
  final declaredChangedFields = summary.changedFields.toSet();
  if (!_sameWire(originalIntent, replacementIntent) ||
      actualChangedFields.length != declaredChangedFields.length ||
      !actualChangedFields.every(declaredChangedFields.contains)) {
    return false;
  }

  final authority = replacement.preparedExecution!;
  final intent = replacement.stageIntent;
  final durableSourceAddress = execution.resolvedSourceAddress;
  try {
    return _isEvmAddress(authority.resolvedSourceAddress) &&
        (candidateStageIndex != 0 ||
            (durableSourceAddress != null &&
                authority.resolvedSourceAddress.toLowerCase() ==
                    durableSourceAddress.toLowerCase())) &&
        _validApproval(
          authority.approval,
          intent.fromAsset,
          intent.sourceAmount,
        ) &&
        _sameWire(
          authority.requiredMaxNetworkFee.asset.toJson(),
          intent.maxTotalNetworkFee.asset.toJson(),
        ) &&
        _isNativeEvmFeeAsset(
          intent.maxTotalNetworkFee.asset,
          intent.fromAsset,
        ) &&
        BigInt.parse(authority.requiredMaxNetworkFee.amount) <=
            BigInt.parse(intent.maxTotalNetworkFee.amount);
  } on Object {
    return false;
  }
}

String? _candidateStageId(kdf.RouteStage stage) => switch (stage) {
  kdf.KdfAtomicRouteStage(:final common) => common.stageId,
  kdf.ExternalLiquidityRouteStage(:final common) => common.stageId,
  kdf.UnknownRouteStage() => null,
};

bool _sameProviderAuthority(
  kdf.RouteActivityProviderIntentSource original,
  kdf.ProviderIntentExecutionSource replacement,
  kdf.ReplacementSummary summary,
) {
  final reference = replacement.providerStepReference;
  final originalReference = original.providerStepReference;
  final digest = summary.providerStepDigest;
  return digest != null &&
      digest.trim().isNotEmpty &&
      original.provider.rawValue == replacement.providerValue.rawValue &&
      original.materialization.rawValue ==
          replacement.materializationValue.rawValue &&
      original.providerObservedAt.isAtSameMomentAs(
        replacement.providerObservedAt,
      ) &&
      reference != null &&
      originalReference != null &&
      reference.evaluationId == originalReference.evaluationId &&
      reference.candidateId == originalReference.candidateId &&
      reference.stageId == originalReference.stageId &&
      originalReference.providerStepDigest == original.providerStepDigest &&
      reference.providerStepDigest == digest &&
      replacement.providerStepDigest == digest;
}

bool _sameReplacementFees(
  List<kdf.FeeComponent> fees,
  List<kdf.FeeLimit> limits,
) {
  final totals = <String, BigInt>{};
  for (final fee in fees) {
    if (fee.feeTypeValue.knownValue == kdf.FeeType.network) continue;
    final amount = BigInt.parse(fee.amount);
    if (amount == BigInt.zero) continue;
    final key = _feeKey(fee.feeTypeValue.rawValue, fee.asset);
    totals[key] = (totals[key] ?? BigInt.zero) + amount;
  }
  final maximums = <String, BigInt>{};
  for (final limit in limits) {
    if (limit.feeTypeValue.knownValue == kdf.FeeType.network) return false;
    final key = _feeKey(limit.feeTypeValue.rawValue, limit.asset);
    if (maximums.containsKey(key)) return false;
    maximums[key] = BigInt.parse(limit.maxAmount);
  }
  return totals.length == maximums.length &&
      totals.entries.every((entry) => maximums[entry.key] == entry.value);
}

RouteControlCapabilities _controls(kdf.RouteControlCapabilities controls) =>
    RouteControlCapabilities(
      canCancel: controls.canCancel,
      canStopAfterCurrent: controls.canStopAfterCurrent,
      reconciliationOnly: controls.reconciliationOnly,
    );

RouteHolding? _holding(kdf.AssetHolding? holding) => holding == null
    ? null
    : RouteHolding(
        asset: _asset(holding.asset),
        amount: holding.amount,
        address: holding.address,
      );

UnifiedSwapAssetIdentity _asset(kdf.RouteAsset asset) {
  final chainFamily = switch (asset.chainFamilyValue.knownValue) {
    kdf.ChainFamily.evm => UnifiedSwapChainFamily.evm,
    kdf.ChainFamily.tvm => UnifiedSwapChainFamily.tron,
    kdf.ChainFamily.utxo => UnifiedSwapChainFamily.utxo,
    kdf.ChainFamily.svm => UnifiedSwapChainFamily.solana,
    kdf.ChainFamily.sui => UnifiedSwapChainFamily.sui,
    kdf.ChainFamily.mvm => UnifiedSwapChainFamily.other,
    null => UnifiedSwapChainFamily.unknown,
  };
  final kind = switch (asset.assetKindValue.knownValue) {
    kdf.AssetKind.native => UnifiedSwapAssetKind.native,
    kdf.AssetKind.token => UnifiedSwapAssetKind.token,
    null => UnifiedSwapAssetKind.unknown,
  };
  return UnifiedSwapAssetIdentity(
    ticker: asset.ticker,
    chainFamily: chainFamily,
    chainId: asset.chainId,
    kind: kind,
    decimals: asset.decimals,
    contractAddress: asset.contractAddress,
    rawChainFamilyDiscriminator: asset.chainFamilyValue.isKnown
        ? null
        : asset.chainFamilyValue.rawValue,
    rawKindDiscriminator: asset.assetKindValue.isKnown
        ? null
        : asset.assetKindValue.rawValue,
  );
}

String _safeNonExecutableDiscriminator(kdf.RouteExecutionStatus status) {
  if (!status.routePhase.isKnown) return status.routePhase.rawValue;
  if (!status.phase.isKnown) return status.phase.rawValue;
  final pending = status.pendingUserAction;
  if (pending != null && !pending.reason.isKnown) {
    return pending.reason.rawValue;
  }
  return 'non_executable_status';
}

bool _validatePreparedExecution(kdf.PrepareExecutionResult prepared) {
  final review = prepared.review;
  final consent = prepared.routeConsent;
  final preparedAt = consent.preparedAt;
  final preparedReviewDigest = consent.preparedReviewDigest;
  if (!prepared.isExecutable ||
      review.reviewVersion != 1 ||
      consent.digestVersion != 1 ||
      preparedAt == null ||
      preparedReviewDigest == null ||
      !preparedAt.isAtSameMomentAs(review.preparedAt) ||
      consent.evaluationId != review.evaluationId ||
      consent.candidateId != review.candidateId ||
      consent.candidateDigest != review.candidateDigest ||
      consent.modeValue.knownValue != kdf.ExecutionMode.signAndBroadcast ||
      consent.routeIntent.minimumReceive != review.minimumReceive ||
      !consent.consentExpiresAt.isAtSameMomentAs(review.expiresAt) ||
      !consent.routeIntent.consentExpiresAt.isAtSameMomentAs(
        consent.consentExpiresAt,
      ) ||
      !_sameWire(
        consent.routeIntent.fromAsset.toJson(),
        review.sourceAsset.toJson(),
      ) ||
      !_sameWire(
        consent.routeIntent.toAsset.toJson(),
        review.destinationAsset.toJson(),
      ) ||
      !_sameWire(
        consent.routeIntent.sourceAddress.toJson(),
        review.sourceAddressSelector.toJson(),
      ) ||
      consent.routeIntent.sourceAmount != review.sourceAmount ||
      consent.routeIntent.recipient != review.recipient ||
      review.sourceAsset.chainFamilyValue.knownValue != kdf.ChainFamily.evm ||
      !_isEvmAddress(review.resolvedSourceAddress) ||
      review.recipient.trim().isEmpty ||
      BigInt.parse(review.minimumReceive) >
          BigInt.parse(review.expectedReceive) ||
      review.stages.isEmpty ||
      review.warningValues.any(_blocksV1Warning)) {
    return false;
  }

  try {
    if (kdf.tradeRoutePreparedExecutionReviewDigest(review) !=
            preparedReviewDigest ||
        kdf.tradeRouteConsentDigest(consent) != consent.routeConsentDigest ||
        consent.externalStageConsents.any(
          (stage) =>
              kdf.tradeRouteStageConsentDigest(stage) != stage.consentDigest,
        )) {
      return false;
    }
  } on kdf.TradeRouteDigestException {
    return false;
  }

  final stages = <kdf.KnownPreparedExecutionStageReview>[];
  for (var index = 0; index < review.stages.length; index++) {
    final stage = review.stages[index];
    if (stage is! kdf.KnownPreparedExecutionStageReview ||
        stage.stageIndex != index ||
        stage.warningValues.any(_blocksV1Warning) ||
        BigInt.parse(stage.minimumReceive) >
            BigInt.parse(stage.expectedReceive)) {
      return false;
    }
    stages.add(stage);
  }
  if (!_sameWire(
        stages.first.fromAsset.toJson(),
        review.sourceAsset.toJson(),
      ) ||
      stages.first.sourceAmount != review.sourceAmount ||
      !_sameWire(
        stages.last.toAsset.toJson(),
        review.destinationAsset.toJson(),
      ) ||
      stages.last.expectedReceive != review.expectedReceive ||
      stages.last.minimumReceive != review.minimumReceive ||
      stages.last.recipient != review.recipient) {
    return false;
  }
  for (var index = 1; index < stages.length; index++) {
    final previous = stages[index - 1];
    final current = stages[index];
    if (!_sameWire(previous.toAsset.toJson(), current.fromAsset.toJson()) ||
        current.sourceAmount != previous.minimumReceive) {
      return false;
    }
  }

  final consentByStage = <String, kdf.StageConsent>{};
  for (final stageConsent in consent.externalStageConsents) {
    if (consentByStage.putIfAbsent(
          stageConsent.stageIntent.stageId,
          () => stageConsent,
        ) !=
        stageConsent) {
      return false;
    }
  }
  var externalCount = 0;
  var atomicCount = 0;
  for (final stage in stages) {
    switch (stage.kind) {
      case kdf.PreparedExecutionStageKind.kdfAtomic:
        atomicCount++;
        if (stage.selectedTools != null ||
            stage.nonNetworkFeeLimits.isNotEmpty ||
            stage.maxTotalNetworkFee != null ||
            stage.requiredMaxNetworkFee != null ||
            stage.resolvedSourceAddress != null ||
            stage.approval != null ||
            consentByStage.containsKey(stage.stageId)) {
          return false;
        }
      case kdf.PreparedExecutionStageKind.externalLiquidity:
        externalCount++;
        final stageConsent = consentByStage[stage.stageId];
        if (stageConsent == null ||
            !_validatePreparedExternalStage(
              prepared,
              stage,
              stageConsent,
              requireRouteSource: stage.stageIndex == 0,
            )) {
          return false;
        }
    }
  }
  return externalCount == consent.externalStageConsents.length &&
      atomicCount == consent.atomicOrderGuards.length;
}

bool _validatePreparedExternalStage(
  kdf.PrepareExecutionResult prepared,
  kdf.KnownPreparedExecutionStageReview review,
  kdf.StageConsent consent, {
  required bool requireRouteSource,
}) {
  final routeConsent = prepared.routeConsent;
  final reference = consent.candidateReference;
  final intent = consent.stageIntent;
  final authority = consent.preparedExecution;
  final cap = review.maxTotalNetworkFee;
  final requiredFee = review.requiredMaxNetworkFee;
  final source = review.resolvedSourceAddress;
  final approval = review.approval;
  final routeIntentDigest = kdf.tradeRouteIntentDigest(
    routeConsent.routeIntent,
  );
  if (authority == null ||
      cap == null ||
      requiredFee == null ||
      source == null ||
      approval == null ||
      !_isEvmAddress(source) ||
      reference.evaluationId != routeConsent.evaluationId ||
      reference.candidateId != routeConsent.candidateId ||
      reference.candidateDigest != routeConsent.candidateDigest ||
      reference.stageId != review.stageId ||
      !_sameWire(
        consent.routeIntent.toJson(),
        routeConsent.routeIntent.toJson(),
      ) ||
      intent.stageId != review.stageId ||
      intent.routeIntentDigest != routeIntentDigest ||
      !_sameWire(intent.fromAsset.toJson(), review.fromAsset.toJson()) ||
      !_sameWire(intent.toAsset.toJson(), review.toAsset.toJson()) ||
      intent.sourceAmount != review.sourceAmount ||
      intent.acceptedExpectedReceive != review.expectedReceive ||
      intent.minimumReceive != review.minimumReceive ||
      intent.recipient != review.recipient ||
      intent.slippageBps != routeConsent.routeIntent.slippageBps ||
      !_sameWire(
        intent.sourceAddress.toJson(),
        routeConsent.routeIntent.sourceAddress.toJson(),
      ) ||
      intent.maxExpectedReceiveDegradationBps < 0 ||
      intent.maxExpectedReceiveDegradationBps > 10000 ||
      !intent.consentExpiresAt.isAtSameMomentAs(
        routeConsent.consentExpiresAt,
      ) ||
      !_sameWire(
        intent.selectedTools.toJson(),
        review.selectedTools?.toJson(),
      ) ||
      !_sameWire(
        intent.nonNetworkFeeLimits
            .map((fee) => fee.toJson())
            .toList(growable: false),
        review.nonNetworkFeeLimits
            .map((fee) => fee.toJson())
            .toList(growable: false),
      ) ||
      !_sameWire(intent.maxTotalNetworkFee.toJson(), cap.toJson()) ||
      authority.resolvedSourceAddress.toLowerCase() != source.toLowerCase() ||
      !_sameWire(authority.approval.toJson(), approval.toJson()) ||
      !_sameWire(
        authority.requiredMaxNetworkFee.toJson(),
        requiredFee.toJson(),
      ) ||
      !_sameWire(cap.asset.toJson(), requiredFee.asset.toJson()) ||
      !_isNativeEvmFeeAsset(cap.asset, review.fromAsset) ||
      BigInt.parse(requiredFee.amount) > BigInt.parse(cap.amount) ||
      !_feesWithinLimits(review.fees, review.nonNetworkFeeLimits) ||
      !_validApproval(approval, review.fromAsset, review.sourceAmount) ||
      (requireRouteSource &&
          source.toLowerCase() !=
              prepared.review.resolvedSourceAddress.toLowerCase())) {
    return false;
  }
  return true;
}

bool _feesWithinLimits(List<kdf.FeeComponent> fees, List<kdf.FeeLimit> limits) {
  final maximumByFee = <String, BigInt>{};
  for (final limit in limits) {
    if (limit.feeTypeValue.knownValue == kdf.FeeType.network) return false;
    final key = _feeKey(limit.feeTypeValue.rawValue, limit.asset);
    if (maximumByFee.containsKey(key)) return false;
    maximumByFee[key] = BigInt.parse(limit.maxAmount);
  }
  final actualByFee = <String, BigInt>{};
  for (final fee in fees) {
    if (fee.feeTypeValue.knownValue == kdf.FeeType.network) continue;
    final key = _feeKey(fee.feeTypeValue.rawValue, fee.asset);
    actualByFee[key] =
        (actualByFee[key] ?? BigInt.zero) + BigInt.parse(fee.amount);
  }
  for (final entry in actualByFee.entries) {
    final maximum = maximumByFee[entry.key];
    if (maximum == null || entry.value > maximum) return false;
  }
  return true;
}

bool _validApproval(
  kdf.PreparedApproval approval,
  kdf.RouteAsset fromAsset,
  String sourceAmount,
) => switch (approval) {
  kdf.NotApplicablePreparedApproval() =>
    fromAsset.assetKindValue.knownValue == kdf.AssetKind.native &&
        fromAsset.contractAddress == null,
  kdf.SufficientAllowancePreparedApproval(
    :final token,
    :final spender,
    :final currentAllowance,
    :final requiredAmount,
  ) =>
    fromAsset.assetKindValue.knownValue == kdf.AssetKind.token &&
        fromAsset.contractAddress != null &&
        _sameWire(token.toJson(), fromAsset.toJson()) &&
        _isEvmAddress(spender) &&
        requiredAmount == sourceAmount &&
        BigInt.parse(currentAllowance) >= BigInt.parse(requiredAmount),
  kdf.ExactApprovalRequiredPreparedApproval(
    :final token,
    :final spender,
    :final currentAllowance,
    :final requiredAmount,
  ) =>
    fromAsset.assetKindValue.knownValue == kdf.AssetKind.token &&
        fromAsset.contractAddress != null &&
        _sameWire(token.toJson(), fromAsset.toJson()) &&
        _isEvmAddress(spender) &&
        requiredAmount == sourceAmount &&
        BigInt.parse(currentAllowance) < BigInt.parse(requiredAmount),
  kdf.UnknownPreparedApproval() => false,
};

bool _isNativeEvmFeeAsset(kdf.RouteAsset feeAsset, kdf.RouteAsset source) =>
    source.chainFamilyValue.knownValue == kdf.ChainFamily.evm &&
    feeAsset.chainFamilyValue.knownValue == kdf.ChainFamily.evm &&
    feeAsset.assetKindValue.knownValue == kdf.AssetKind.native &&
    feeAsset.contractAddress == null &&
    feeAsset.chainId == source.chainId;

bool _isEvmAddress(String value) =>
    RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(value);

bool _blocksV1Warning(kdf.WireEnumValue<kdf.RouteWarning> warning) =>
    !warning.isKnown ||
    warning.knownValue == kdf.RouteWarning.clientMaterializedTransaction;

RouteExecutionReview _preparedReview({
  required String walletId,
  required String routeExecutionId,
  required kdf.PrepareExecutionResult prepared,
  required UnifiedSwapIntent intent,
}) {
  final wire = prepared.review;
  final stages = wire.stages.cast<kdf.KnownPreparedExecutionStageReview>();
  final warnings = <RouteReviewWarning>[];
  final warningKeys = <String>{};
  void addWarning(kdf.WireEnumValue<kdf.RouteWarning> warning) {
    final mapped = _reviewWarning(warning);
    final key = '${mapped.kind.name}:${mapped.rawKindDiscriminator ?? ''}';
    if (warningKeys.add(key)) warnings.add(mapped);
  }

  for (final warning in wire.warningValues) {
    addWarning(warning);
  }
  for (final stage in stages) {
    for (final warning in stage.warningValues) {
      addWarning(warning);
    }
  }
  if (wire.resolvedSourceAddress.toLowerCase() !=
      wire.recipient.toLowerCase()) {
    const warning = RouteReviewWarning(
      kind: RouteReviewWarningKind.externalRecipient,
    );
    if (warningKeys.add('${warning.kind.name}:')) warnings.add(warning);
  }
  return RouteExecutionReview(
    walletId: walletId,
    routeExecutionId: routeExecutionId,
    reviewId: prepared.routeConsent.preparedReviewDigest!,
    consentDigest: prepared.routeConsent.routeConsentDigest,
    candidateDigest: wire.candidateDigest,
    source: _asset(wire.sourceAsset),
    destination: _asset(wire.destinationAsset),
    sourceAmount: wire.sourceAmount,
    expectedReceive: wire.expectedReceive,
    minimumReceive: wire.minimumReceive,
    fees: wire.fees.map(_reviewFee).toList(growable: false),
    nonNetworkFeeLimits: [
      for (final stage in stages)
        for (final fee in stage.nonNetworkFeeLimits)
          _reviewFeeLimit(fee, stageId: stage.stageId),
    ],
    networkFeeCaps: stages
        .where((stage) => stage.maxTotalNetworkFee != null)
        .map(
          (stage) => RouteStageNetworkFeeCap(
            stageId: stage.stageId,
            asset: _asset(stage.maxTotalNetworkFee!.asset),
            maximumAmount: stage.maxTotalNetworkFee!.amount,
          ),
        )
        .toList(growable: false),
    resolvedSourceAddress: wire.resolvedSourceAddress,
    recipient: wire.recipient,
    estimatedDuration: Duration(seconds: wire.estimatedDurationSeconds ?? 0),
    steps: stages
        .map(
          (stage) => RouteReviewStep(
            sequence: stage.stageIndex,
            stageId: stage.stageId,
            kind: switch (stage.kind) {
              kdf.PreparedExecutionStageKind.kdfAtomic =>
                RouteReviewStepKind.atomic,
              kdf.PreparedExecutionStageKind.externalLiquidity =>
                RouteReviewStepKind.external,
            },
            source: _asset(stage.fromAsset),
            destination: _asset(stage.toAsset),
            sourceAmount: stage.sourceAmount,
            expectedReceive: stage.expectedReceive,
            minimumReceive: stage.minimumReceive,
          ),
        )
        .toList(growable: false),
    warnings: warnings,
    approvals: [
      for (final stage in stages)
        if (stage.approval case kdf.ExactApprovalRequiredPreparedApproval(
          :final token,
          :final spender,
          :final requiredAmount,
          :final resetRequired,
        ))
          RouteApprovalScope(
            stageId: stage.stageId,
            token: _asset(token),
            spender: spender,
            exactAmount: requiredAmount,
            resetRequired: resetRequired,
          ),
    ],
    expiresAt: wire.expiresAt,
    sourceSelectorKind: intent.sourceSelection.kind,
    externalRecipientConfirmed: intent.externalRecipientConfirmed,
  );
}

RouteReviewWarning _reviewWarning(
  kdf.WireEnumValue<kdf.RouteWarning> warning,
) => switch (warning.knownValue) {
  kdf.RouteWarning.notAtomicEndToEnd => const RouteReviewWarning(
    kind: RouteReviewWarningKind.notAtomicEndToEnd,
  ),
  kdf.RouteWarning.makerOrderNotReserved => const RouteReviewWarning(
    kind: RouteReviewWarningKind.makerOrderNotReserved,
  ),
  kdf.RouteWarning.bridgeRecoveryRequired => const RouteReviewWarning(
    kind: RouteReviewWarningKind.bridgeRecoveryRequired,
  ),
  kdf.RouteWarning.intermediateAssetPossible => const RouteReviewWarning(
    kind: RouteReviewWarningKind.intermediateAssetPossible,
  ),
  kdf.RouteWarning.unrankableFees => const RouteReviewWarning(
    kind: RouteReviewWarningKind.unrankableFees,
  ),
  kdf.RouteWarning.clientMaterializedTransaction || null => RouteReviewWarning(
    kind: RouteReviewWarningKind.unknown,
    rawKindDiscriminator: warning.rawValue,
  ),
};

RouteExecutionFee _reviewFee(kdf.FeeComponent fee) => RouteExecutionFee(
  kind: _reviewFeeKind(fee.feeTypeValue),
  asset: _asset(fee.asset),
  amount: fee.amount,
  included: fee.included,
  rawKindDiscriminator: fee.feeTypeValue.isKnown
      ? null
      : fee.feeTypeValue.rawValue,
);

RouteExecutionFeeLimit _reviewFeeLimit(kdf.FeeLimit fee, {String? stageId}) =>
    RouteExecutionFeeLimit(
      stageId: stageId,
      kind: _reviewFeeKind(fee.feeTypeValue),
      asset: _asset(fee.asset),
      maximumAmount: fee.maxAmount,
      rawKindDiscriminator: fee.feeTypeValue.isKnown
          ? null
          : fee.feeTypeValue.rawValue,
    );

RouteFeeKind _reviewFeeKind(kdf.WireEnumValue<kdf.FeeType> fee) =>
    switch (fee.knownValue) {
      kdf.FeeType.provider => RouteFeeKind.provider,
      kdf.FeeType.bridge => RouteFeeKind.bridge,
      kdf.FeeType.exchange => RouteFeeKind.exchange,
      kdf.FeeType.network => RouteFeeKind.network,
      kdf.FeeType.kdf => RouteFeeKind.kdf,
      null => RouteFeeKind.unknown,
    };

String _feeKey(String kind, kdf.RouteAsset asset) =>
    '$kind:${kdf.tradeRouteCanonicalDigest(asset.toJson())}';

bool _sameWire(Object? left, Object? right) {
  if (left == null || right == null) return left == right;
  try {
    return kdf.tradeRouteCanonicalDigest(left) ==
        kdf.tradeRouteCanonicalDigest(right);
  } on kdf.TradeRouteDigestException {
    return false;
  }
}

String _validWalletId(String walletId) {
  if (!_isCanonicalValue(walletId)) {
    throw ArgumentError.value(walletId, 'walletId', 'Must be trimmed');
  }
  return walletId;
}

bool _isCanonicalValue(String value) =>
    value.isNotEmpty && value.trim() == value;

bool _isUuid(String value) => RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
).hasMatch(value);

void _requireRouteId(String routeExecutionId) {
  if (!_isCanonicalValue(routeExecutionId)) {
    throw const RouteExecutionException(RouteExecutionFailure.notFound);
  }
}

DateTime _utcNow() => DateTime.now().toUtc();

RouteExecutionException _asExecutionException(Object error) =>
    error is RouteExecutionException
    ? error
    : RouteExecutionException(_failureFor(error));

RouteExecutionFailure _failureFor(Object error) {
  if (error is TradeRouteControlNotAuthorizedException) {
    return RouteExecutionFailure.controlNotAuthorized;
  }
  if (error is TradeRouteActionNotAuthorizedException) {
    return RouteExecutionFailure.actionNotAuthorized;
  }
  if (error is TradeRouteIdentityMismatchException) {
    return RouteExecutionFailure.conflict;
  }

  String? errorType;
  if (error is kdf.RouteRpcError) {
    errorType = error.rawDiscriminator;
  } else if (error is kdf.GeneralErrorResponse) {
    errorType = error.errorType;
  } else if (error is kdf.MmRpcException) {
    errorType = error.errorType;
  }

  if (errorType == 'QuoteExpired' || errorType == 'EvaluationNotFound') {
    return RouteExecutionFailure.reviewExpired;
  }
  if (const {
    'AssetNotActivated',
    'UnsupportedCapability',
    'AddressSelectionError',
    'ChainMismatch',
    'SenderMismatch',
    'RecipientMismatch',
    'AssetMismatch',
    'AmountMismatch',
    'ApprovalSpenderMismatch',
    'ProviderStepMismatch',
    'ApprovalRequired',
    'OrderUnavailable',
    'AtomicGuardMismatch',
    'AtomicFillNotReady',
  }.contains(errorType)) {
    return RouteExecutionFailure.capabilityUnavailable;
  }
  if (const {
    'ConsentDigestMismatch',
    'IdempotencyConflict',
    'ActionRevisionConflict',
    'InvalidUserActionState',
    'CandidateChanged',
    'QuoteChanged',
    'FeeLimitExceeded',
    'NetworkFeeCapExceeded',
  }.contains(errorType)) {
    return RouteExecutionFailure.conflict;
  }
  if (const {
    'NoSuchTask',
    'ExecutionNotFound',
    'RouteNotFound',
  }.contains(errorType)) {
    return RouteExecutionFailure.notFound;
  }
  if (errorType == 'PersistenceError') {
    return RouteExecutionFailure.storageUnavailable;
  }
  if (const {
    'Transport',
    'Timeout',
    'ProviderTransport',
    'ProviderRateLimited',
    'ChainTransport',
  }.contains(errorType)) {
    return RouteExecutionFailure.networkUnavailable;
  }
  if (const {
    'InvalidRequest',
    'ProviderRejected',
    'ProviderResponseInvalid',
    'SimulationFailed',
    'RecoveryRequired',
    'ApprovalFailed',
    'SigningFailed',
    'ChainResponseInvalid',
    'BroadcastFailed',
    'TransactionReverted',
    'Internal',
  }.contains(errorType)) {
    return RouteExecutionFailure.serviceUnavailable;
  }
  if (errorType != null) return RouteExecutionFailure.serviceUnavailable;
  if (error is TimeoutException) {
    return RouteExecutionFailure.networkUnavailable;
  }
  if (error is FormatException ||
      error is StateError ||
      error is ArgumentError ||
      error is TradeRouteManagerException) {
    return RouteExecutionFailure.serviceUnavailable;
  }
  return RouteExecutionFailure.unknown;
}

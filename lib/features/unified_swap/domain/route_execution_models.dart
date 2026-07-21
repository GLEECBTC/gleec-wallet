import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:web_dex/features/unified_swap/domain/route_activity_models.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_model_limits.dart';

enum RouteReviewStepKind { atomic, external, unknown }

enum RouteReviewWarningKind {
  highPriceImpact,
  lowLiquidity,
  unknownToken,
  notAtomicEndToEnd,
  makerOrderNotReserved,
  bridgeRecoveryRequired,
  intermediateAssetPossible,
  unrankableFees,
  externalRecipient,
  unknown,
}

enum RouteExecutionOutcome {
  active,
  attentionRequired,
  recovery,
  completed,
  cancelled,
  failed,
  unknown,
}

enum RouteExecutionPhase {
  validating,
  awaitingApproval,
  approvalPending,
  awaitingSignature,
  signed,
  broadcasting,
  sourcePending,
  sourceConfirmed,
  bridgePending,
  destinationConfirmed,
  atomicFill,
  awaitingUserAction,
  stopAfterCurrent,
  partial,
  refundPending,
  refunded,
  manualIntervention,
  completed,
  cancelled,
  failed,
  unknown,
}

enum RouteExecutionActionKind {
  acceptReplacement,
  rejectChange,
  selectRecoveryRoute,
  stopAfterCurrent,
  unknown,
}

enum RoutePendingActionReason {
  candidateChanged,
  nonNetworkFeeLimitExceeded,
  networkFeeCapExceeded,
  recoveryRequired,
  approvalRequired,
  stopAfterCurrent,
  unknown,
}

enum RouteExecutionFailure {
  invalidReview,
  reviewExpired,
  capabilityUnavailable,
  controlNotAuthorized,
  actionNotAuthorized,
  notFound,
  conflict,
  networkUnavailable,
  storageUnavailable,
  serviceUnavailable,
  unknown,
}

enum RouteLiveAnnouncement {
  none,
  starting,
  reattaching,
  validating,
  approvalRequired,
  sending,
  receiving,
  attentionRequired,
  recoveryRequired,
  completed,
  cancelled,
  failed,
  statusUnavailable,
}

@immutable
class RouteReviewWarning extends Equatable {
  RouteReviewWarning({required this.kind, this.rawKindDiscriminator}) {
    UnifiedSwapModelLimits.requireRawDiscriminator(
      rawKindDiscriminator,
      'rawKindDiscriminator',
      isUnknown: kind == RouteReviewWarningKind.unknown,
    );
  }

  final RouteReviewWarningKind kind;
  final String? rawKindDiscriminator;

  bool get isKnown => kind != RouteReviewWarningKind.unknown;

  @override
  List<Object?> get props => [kind, rawKindDiscriminator];
}

@immutable
class RouteReviewStep extends Equatable {
  RouteReviewStep({
    required this.sequence,
    required this.stageId,
    required this.kind,
    required this.source,
    required this.destination,
    required String sourceAmount,
    required String expectedReceive,
    required String minimumReceive,
    this.rawKindDiscriminator,
  }) : sourceAmount = _smallestUnitAmount(sourceAmount),
       expectedReceive = _smallestUnitAmount(expectedReceive),
       minimumReceive = _smallestUnitAmount(minimumReceive) {
    if (sequence < 0) {
      throw ArgumentError.value(sequence, 'sequence', 'Must not be negative');
    }
    UnifiedSwapModelLimits.requireString(stageId, 'stageId');
    UnifiedSwapModelLimits.requireRawDiscriminator(
      rawKindDiscriminator,
      'rawKindDiscriminator',
      isUnknown: kind == RouteReviewStepKind.unknown,
    );
    if (BigInt.parse(minimumReceive) > BigInt.parse(expectedReceive)) {
      throw ArgumentError('minimumReceive must not exceed expectedReceive');
    }
    if (!source.hasBoundedIdentity || !destination.hasBoundedIdentity) {
      throw ArgumentError(
        'Review step asset identity exceeds supported bounds',
      );
    }
  }

  final int sequence;
  final String stageId;
  final RouteReviewStepKind kind;
  final UnifiedSwapAssetIdentity source;
  final UnifiedSwapAssetIdentity destination;
  final String sourceAmount;
  final String expectedReceive;
  final String minimumReceive;
  final String? rawKindDiscriminator;

  bool get isExecutable =>
      kind != RouteReviewStepKind.unknown &&
      source.hasKnownBoundedIdentity &&
      destination.hasKnownBoundedIdentity &&
      _isPositiveAmount(sourceAmount) &&
      _isPositiveAmount(expectedReceive) &&
      _isPositiveAmount(minimumReceive);

  @override
  List<Object?> get props => [
    sequence,
    stageId,
    kind,
    ..._identityProps(source),
    ..._identityProps(destination),
    sourceAmount,
    expectedReceive,
    minimumReceive,
    rawKindDiscriminator,
  ];
}

@immutable
class RouteApprovalScope extends Equatable {
  RouteApprovalScope({
    required this.stageId,
    required this.token,
    required this.spender,
    required String exactAmount,
    required this.resetRequired,
  }) : exactAmount = _smallestUnitAmount(exactAmount) {
    UnifiedSwapModelLimits.requireString(stageId, 'stageId');
    UnifiedSwapModelLimits.requireString(
      spender,
      'spender',
      maximumLength: UnifiedSwapModelLimits.addressLength,
    );
    if (!token.hasBoundedIdentity) {
      throw ArgumentError('Approval token identity exceeds supported bounds');
    }
  }

  final String stageId;
  final UnifiedSwapAssetIdentity token;
  final String spender;
  final String exactAmount;
  final bool resetRequired;

  bool get isExecutable =>
      _hasKnownAssetIdentity(token) &&
      _isExecutableAddress(token, spender) &&
      _isPositiveAmount(exactAmount);

  @override
  List<Object?> get props => [
    stageId,
    ..._identityProps(token),
    _addressIdentity(token, spender),
    exactAmount,
    resetRequired,
  ];
}

@immutable
class RouteSufficientAllowanceScope extends Equatable {
  RouteSufficientAllowanceScope({
    required this.stageId,
    required this.token,
    required this.spender,
    required String requiredAmount,
  }) : requiredAmount = _smallestUnitAmount(requiredAmount) {
    UnifiedSwapModelLimits.requireString(stageId, 'stageId');
    UnifiedSwapModelLimits.requireString(
      spender,
      'spender',
      maximumLength: UnifiedSwapModelLimits.addressLength,
    );
    if (!token.hasBoundedIdentity) {
      throw ArgumentError('Allowance token identity exceeds supported bounds');
    }
  }

  final String stageId;
  final UnifiedSwapAssetIdentity token;
  final String spender;
  final String requiredAmount;

  bool get isExecutable =>
      _hasKnownAssetIdentity(token) &&
      _isExecutableAddress(token, spender) &&
      _isPositiveAmount(requiredAmount);

  @override
  List<Object?> get props => [
    stageId,
    ..._identityProps(token),
    _addressIdentity(token, spender),
    requiredAmount,
  ];
}

@immutable
class RouteExecutionReview extends Equatable {
  RouteExecutionReview({
    required this.walletId,
    required this.routeExecutionId,
    required this.reviewId,
    required this.consentDigest,
    required this.candidateDigest,
    required this.source,
    required this.destination,
    required String sourceAmount,
    required String expectedReceive,
    required String minimumReceive,
    required List<RouteExecutionFee> fees,
    required List<RouteExecutionFeeLimit> nonNetworkFeeLimits,
    required List<RouteStageNetworkFeeCap> networkFeeCaps,
    required this.resolvedSourceAddress,
    required this.recipient,
    required this.estimatedDuration,
    this.estimatedDurationKnown = true,
    required List<RouteReviewStep> steps,
    required List<RouteReviewWarning> warnings,
    required List<RouteApprovalScope> approvals,
    List<RouteSufficientAllowanceScope> sufficientAllowances = const [],
    required DateTime expiresAt,
    this.sourceSelectorKind = UnifiedSwapSourceSelectorKind.active,
    this.externalRecipientConfirmed = false,
  }) : sourceAmount = _smallestUnitAmount(sourceAmount),
       expectedReceive = _smallestUnitAmount(expectedReceive),
       minimumReceive = _smallestUnitAmount(minimumReceive),
       fees = List.unmodifiable(fees),
       nonNetworkFeeLimits = List.unmodifiable(nonNetworkFeeLimits),
       networkFeeCaps = List.unmodifiable(networkFeeCaps),
       steps = List.unmodifiable(
         [...steps]
           ..sort((left, right) => left.sequence.compareTo(right.sequence)),
       ),
       warnings = List.unmodifiable(warnings),
       approvals = List.unmodifiable(approvals),
       sufficientAllowances = List.unmodifiable(sufficientAllowances),
       expiresAt = expiresAt.toUtc() {
    UnifiedSwapModelLimits.requireString(walletId, 'walletId');
    UnifiedSwapModelLimits.requireString(routeExecutionId, 'routeExecutionId');
    UnifiedSwapModelLimits.requireString(reviewId, 'reviewId');
    UnifiedSwapModelLimits.requireString(
      consentDigest,
      'consentDigest',
      maximumLength: UnifiedSwapModelLimits.digestLength,
    );
    UnifiedSwapModelLimits.requireString(
      candidateDigest,
      'candidateDigest',
      maximumLength: UnifiedSwapModelLimits.digestLength,
    );
    UnifiedSwapModelLimits.requireString(
      resolvedSourceAddress,
      'resolvedSourceAddress',
      maximumLength: UnifiedSwapModelLimits.addressLength,
    );
    UnifiedSwapModelLimits.requireString(
      recipient,
      'recipient',
      maximumLength: UnifiedSwapModelLimits.addressLength,
    );
    if (!source.hasBoundedIdentity || !destination.hasBoundedIdentity) {
      throw ArgumentError('Review asset identity exceeds supported bounds');
    }
    UnifiedSwapModelLimits.requireListLength(fees.length, 'fees');
    UnifiedSwapModelLimits.requireListLength(
      nonNetworkFeeLimits.length,
      'nonNetworkFeeLimits',
    );
    UnifiedSwapModelLimits.requireListLength(
      networkFeeCaps.length,
      'networkFeeCaps',
    );
    UnifiedSwapModelLimits.requireListLength(
      steps.length,
      'steps',
      maximumLength: UnifiedSwapModelLimits.routeStages,
    );
    UnifiedSwapModelLimits.requireListLength(warnings.length, 'warnings');
    UnifiedSwapModelLimits.requireListLength(
      approvals.length,
      'approvals',
      maximumLength: UnifiedSwapModelLimits.routeStages,
    );
    UnifiedSwapModelLimits.requireListLength(
      sufficientAllowances.length,
      'sufficientAllowances',
      maximumLength: UnifiedSwapModelLimits.routeStages,
    );
    if (BigInt.parse(minimumReceive) > BigInt.parse(expectedReceive)) {
      throw ArgumentError('minimumReceive must not exceed expectedReceive');
    }
    if (estimatedDuration.isNegative) {
      throw ArgumentError.value(
        estimatedDuration,
        'estimatedDuration',
        'Must not be negative',
      );
    }
    final permissionStageIds = [
      ...this.approvals.map((approval) => approval.stageId),
      ...this.sufficientAllowances.map((allowance) => allowance.stageId),
    ];
    if (permissionStageIds.toSet().length != permissionStageIds.length) {
      throw ArgumentError(
        'A route stage must not expose conflicting permission states',
      );
    }
    final stepIds = this.steps.map((step) => step.stageId).toList();
    final networkCapStageIds = this.networkFeeCaps
        .map((cap) => cap.stageId)
        .toList();
    if (stepIds.toSet().length != stepIds.length ||
        this.steps.indexed.any((entry) => entry.$1 != entry.$2.sequence) ||
        permissionStageIds.any((stageId) => !stepIds.contains(stageId)) ||
        networkCapStageIds.toSet().length != networkCapStageIds.length ||
        networkCapStageIds.any((stageId) => !stepIds.contains(stageId)) ||
        this.nonNetworkFeeLimits.any(
          (limit) => limit.stageId == null || !stepIds.contains(limit.stageId),
        )) {
      throw ArgumentError(
        'Review stages must be ordered, unique, and own every limit',
      );
    }
    if (this.steps.isNotEmpty) {
      final first = this.steps.first;
      final last = this.steps.last;
      if (first.source != source ||
          first.sourceAmount != this.sourceAmount ||
          last.destination != destination ||
          last.expectedReceive != this.expectedReceive ||
          last.minimumReceive != this.minimumReceive ||
          this.steps.indexed.skip(1).any((entry) {
            final previous = this.steps[entry.$1 - 1];
            final current = entry.$2;
            final currentSourceAmount = BigInt.parse(current.sourceAmount);
            return current.source != previous.destination ||
                currentSourceAmount < BigInt.parse(previous.minimumReceive) ||
                currentSourceAmount > BigInt.parse(previous.expectedReceive);
          })) {
        throw ArgumentError(
          'Review stages must preserve exact route and amount continuity',
        );
      }
    }
  }

  final String walletId;
  final String routeExecutionId;
  final String reviewId;
  final String consentDigest;
  final String candidateDigest;
  final UnifiedSwapAssetIdentity source;
  final UnifiedSwapAssetIdentity destination;
  final String sourceAmount;
  final String expectedReceive;
  final String minimumReceive;
  final List<RouteExecutionFee> fees;
  final List<RouteExecutionFeeLimit> nonNetworkFeeLimits;
  final List<RouteStageNetworkFeeCap> networkFeeCaps;
  final String resolvedSourceAddress;
  final String recipient;
  final Duration estimatedDuration;
  final bool estimatedDurationKnown;
  final List<RouteReviewStep> steps;
  final List<RouteReviewWarning> warnings;
  final List<RouteApprovalScope> approvals;
  final List<RouteSufficientAllowanceScope> sufficientAllowances;
  final DateTime expiresAt;
  final UnifiedSwapSourceSelectorKind sourceSelectorKind;
  final bool externalRecipientConfirmed;

  bool isExpiredAt(DateTime value) => !expiresAt.isAfter(value.toUtc());

  bool get isExecutable =>
      _hasKnownAssetIdentity(source) &&
      _hasKnownAssetIdentity(destination) &&
      _isPositiveAmount(sourceAmount) &&
      _isPositiveAmount(expectedReceive) &&
      _isPositiveAmount(minimumReceive) &&
      _isExecutableAddress(source, resolvedSourceAddress) &&
      _isExecutableAddress(destination, recipient) &&
      steps.isNotEmpty &&
      steps.every((step) => step.isExecutable) &&
      warnings.every((warning) => warning.isKnown) &&
      fees.every(
        (fee) =>
            fee.kind != RouteFeeKind.unknown &&
            _hasKnownAssetIdentity(fee.asset),
      ) &&
      nonNetworkFeeLimits.every(
        (limit) =>
            limit.kind != RouteFeeKind.unknown &&
            _hasKnownAssetIdentity(limit.asset),
      ) &&
      networkFeeCaps.every((cap) => _hasKnownAssetIdentity(cap.asset)) &&
      approvals.every((approval) => approval.isExecutable) &&
      sufficientAllowances.every((allowance) => allowance.isExecutable) &&
      sourceSelectorKind != UnifiedSwapSourceSelectorKind.unknown;

  @override
  List<Object?> get props => [
    walletId,
    routeExecutionId,
    reviewId,
    consentDigest,
    candidateDigest,
    ..._identityProps(source),
    ..._identityProps(destination),
    sourceAmount,
    expectedReceive,
    minimumReceive,
    fees,
    nonNetworkFeeLimits,
    networkFeeCaps,
    _addressIdentity(source, resolvedSourceAddress),
    _addressIdentity(destination, recipient),
    estimatedDuration,
    estimatedDurationKnown,
    steps,
    warnings,
    approvals,
    sufficientAllowances,
    expiresAt,
    sourceSelectorKind,
    externalRecipientConfirmed,
  ];
}

@immutable
class RoutePendingAction extends Equatable {
  RoutePendingAction({
    required this.actionId,
    required this.reason,
    required List<RouteExecutionActionKind> allowedActions,
    this.rawReasonDiscriminator,
    List<String> rawAllowedActionDiscriminators = const [],
    this.replacementProposal,
  }) : allowedActions = List.unmodifiable(allowedActions),
       rawAllowedActionDiscriminators = List.unmodifiable(
         rawAllowedActionDiscriminators,
       ) {
    UnifiedSwapModelLimits.requireString(actionId, 'actionId');
    UnifiedSwapModelLimits.requireListLength(
      allowedActions.length,
      'allowedActions',
      maximumLength: RouteExecutionActionKind.values.length,
    );
    UnifiedSwapModelLimits.requireListLength(
      rawAllowedActionDiscriminators.length,
      'rawAllowedActionDiscriminators',
      maximumLength: RouteExecutionActionKind.values.length,
    );
    if (allowedActions.toSet().length != allowedActions.length) {
      throw ArgumentError('Allowed actions must not contain duplicates');
    }
    UnifiedSwapModelLimits.requireRawDiscriminator(
      rawReasonDiscriminator,
      'rawReasonDiscriminator',
      isUnknown: reason == RoutePendingActionReason.unknown,
    );
    for (final discriminator in rawAllowedActionDiscriminators) {
      UnifiedSwapModelLimits.requireString(
        discriminator,
        'rawAllowedActionDiscriminators',
        maximumLength: UnifiedSwapModelLimits.discriminatorLength,
      );
    }
    if (rawAllowedActionDiscriminators.toSet().length !=
        rawAllowedActionDiscriminators.length) {
      throw ArgumentError(
        'Raw allowed-action discriminators must not contain duplicates',
      );
    }
  }

  final String actionId;
  final RoutePendingActionReason reason;
  final List<RouteExecutionActionKind> allowedActions;
  final String? rawReasonDiscriminator;
  final List<String> rawAllowedActionDiscriminators;
  final RouteReplacementProposal? replacementProposal;

  bool get isExecutable =>
      reason != RoutePendingActionReason.unknown &&
      rawAllowedActionDiscriminators.isEmpty &&
      allowedActions.isNotEmpty &&
      !allowedActions.contains(RouteExecutionActionKind.unknown) &&
      (!allowedActions.contains(RouteExecutionActionKind.acceptReplacement) ||
          (replacementProposal?.isExecutable ?? false));

  @override
  List<Object?> get props => [
    actionId,
    reason,
    allowedActions,
    rawReasonDiscriminator,
    rawAllowedActionDiscriminators,
    replacementProposal,
  ];
}

/// Provider-neutral economics for a KDF-issued replacement challenge.
///
/// This is display and comparison data only. A proposal digest does not
/// authorize acceptance without a complete, separately verified replacement
/// `StageConsent`, so the repository continues to fail closed when that
/// authority is unavailable.
@immutable
class RouteReplacementProposal extends Equatable {
  RouteReplacementProposal({
    required this.proposalDigest,
    required this.stageId,
    required this.providerStepDigest,
    required List<String> changedFields,
    required String expectedReceive,
    required String minimumReceive,
    required List<RouteExecutionFee> fees,
    required this.requiredTotalNetworkFee,
    required DateTime expiresAt,
  }) : changedFields = List.unmodifiable(changedFields),
       expectedReceive = _smallestUnitAmount(expectedReceive),
       minimumReceive = _smallestUnitAmount(minimumReceive),
       fees = List.unmodifiable(fees),
       expiresAt = expiresAt.toUtc() {
    UnifiedSwapModelLimits.requireString(
      proposalDigest,
      'proposalDigest',
      maximumLength: UnifiedSwapModelLimits.digestLength,
    );
    UnifiedSwapModelLimits.requireString(stageId, 'stageId');
    UnifiedSwapModelLimits.requireOptionalString(
      providerStepDigest,
      'providerStepDigest',
      maximumLength: UnifiedSwapModelLimits.digestLength,
    );
    UnifiedSwapModelLimits.requireListLength(
      changedFields.length,
      'changedFields',
      maximumLength: UnifiedSwapModelLimits.changedFields,
    );
    UnifiedSwapModelLimits.requireListLength(fees.length, 'fees');
    for (final field in changedFields) {
      UnifiedSwapModelLimits.requireString(
        field,
        'changedFields',
        maximumLength: UnifiedSwapModelLimits.discriminatorLength,
      );
    }
    if (changedFields.toSet().length != changedFields.length) {
      throw ArgumentError('Changed fields must not contain duplicates');
    }
    if (BigInt.parse(minimumReceive) > BigInt.parse(expectedReceive)) {
      throw ArgumentError('minimumReceive must not exceed expectedReceive');
    }
  }

  static const knownChangedFields = {
    'expected_receive',
    'minimum_receive',
    'non_network_fees',
    'network_fee_cap',
  };

  final String proposalDigest;
  final String stageId;
  final String? providerStepDigest;
  final List<String> changedFields;
  final String expectedReceive;
  final String minimumReceive;
  final List<RouteExecutionFee> fees;
  final RouteReplacementNetworkFee? requiredTotalNetworkFee;
  final DateTime expiresAt;

  bool get isExecutable =>
      changedFields.isNotEmpty &&
      changedFields.toSet().length == changedFields.length &&
      changedFields.every(knownChangedFields.contains) &&
      _isPositiveAmount(expectedReceive) &&
      _isPositiveAmount(minimumReceive) &&
      fees.every(
        (fee) =>
            fee.kind != RouteFeeKind.unknown &&
            _hasKnownAssetIdentity(fee.asset),
      ) &&
      (requiredTotalNetworkFee?.isExecutable ?? true);

  bool isExpiredAt(DateTime value) => !expiresAt.isAfter(value.toUtc());

  @override
  List<Object?> get props => [
    proposalDigest,
    stageId,
    providerStepDigest,
    changedFields,
    expectedReceive,
    minimumReceive,
    fees,
    requiredTotalNetworkFee,
    expiresAt,
  ];
}

@immutable
class RouteReplacementNetworkFee extends Equatable {
  RouteReplacementNetworkFee({required this.asset, required String amount})
    : amount = _smallestUnitAmount(amount) {
    if (!asset.hasBoundedIdentity) {
      throw ArgumentError('Replacement fee asset exceeds supported bounds');
    }
  }

  final UnifiedSwapAssetIdentity asset;
  final String amount;

  bool get isExecutable => _hasKnownAssetIdentity(asset);

  @override
  List<Object?> get props => [..._identityProps(asset), amount];
}

@immutable
class RouteExecutionProgress extends Equatable {
  RouteExecutionProgress({
    required this.routeExecutionId,
    required this.outcome,
    required this.phase,
    required this.stateRevision,
    required this.stageIndex,
    required this.stageCount,
    required this.controls,
    required this.pendingAction,
    required this.holding,
    required List<String> transactionHashes,
    required DateTime updatedAt,
    List<RouteReviewStep> stages = const [],
    List<RouteStageHistoryEntry> stageResults = const [],
    this.approvalRecovery,
    this.rawOutcomeDiscriminator,
    this.rawPhaseDiscriminator,
  }) : transactionHashes = List.unmodifiable(transactionHashes),
       stages = List.unmodifiable(
         [...stages]
           ..sort((left, right) => left.sequence.compareTo(right.sequence)),
       ),
       stageResults = List.unmodifiable(
         [...stageResults]
           ..sort((left, right) => left.sequence.compareTo(right.sequence)),
       ),
       updatedAt = updatedAt.toUtc() {
    UnifiedSwapModelLimits.requireString(routeExecutionId, 'routeExecutionId');
    if (stateRevision < 0 ||
        stageIndex < 0 ||
        stageCount < 0 ||
        stageIndex > stageCount ||
        stageCount > UnifiedSwapModelLimits.routeStages) {
      throw ArgumentError('Progress indexes and revision must not be negative');
    }
    _validateTransactionHashes(transactionHashes, 'transactionHashes');
    UnifiedSwapModelLimits.requireListLength(
      stages.length,
      'stages',
      maximumLength: UnifiedSwapModelLimits.routeStages,
    );
    UnifiedSwapModelLimits.requireListLength(
      stageResults.length,
      'stageResults',
      maximumLength: UnifiedSwapModelLimits.routeStages,
    );
    UnifiedSwapModelLimits.requireRawDiscriminator(
      rawOutcomeDiscriminator,
      'rawOutcomeDiscriminator',
      isUnknown: outcome == RouteExecutionOutcome.unknown,
    );
    UnifiedSwapModelLimits.requireRawDiscriminator(
      rawPhaseDiscriminator,
      'rawPhaseDiscriminator',
      isUnknown: phase == RouteExecutionPhase.unknown,
    );
    if (this.stages.isNotEmpty &&
        (this.stages.length != stageCount ||
            this.stages.indexed.any(
              (entry) => entry.$1 != entry.$2.sequence,
            ))) {
      throw ArgumentError('Planned stages must exactly match the route order');
    }
    final resultSequences = this.stageResults
        .map((result) => result.sequence)
        .toSet();
    final resultIds = this.stageResults.map((result) => result.stageId).toSet();
    if (this.stageResults.any((result) => result.sequence >= stageCount) ||
        resultSequences.length != this.stageResults.length ||
        resultIds.length != this.stageResults.length) {
      throw ArgumentError('Stage results must map uniquely into the route');
    }
  }

  final String routeExecutionId;
  final RouteExecutionOutcome outcome;
  final RouteExecutionPhase phase;
  final int stateRevision;
  final int stageIndex;
  final int stageCount;
  final RouteControlCapabilities controls;
  final RoutePendingAction? pendingAction;
  final RouteHolding? holding;
  final List<String> transactionHashes;
  final List<RouteReviewStep> stages;
  final List<RouteStageHistoryEntry> stageResults;
  final RouteApprovalRecovery? approvalRecovery;
  final DateTime updatedAt;
  final String? rawOutcomeDiscriminator;
  final String? rawPhaseDiscriminator;

  bool get isExecutable =>
      outcome != RouteExecutionOutcome.unknown &&
      phase != RouteExecutionPhase.unknown &&
      _outcomeMatchesPhase(outcome, phase) &&
      (!_isTerminalOutcome(outcome) ||
          (!controls.canCancel &&
              !controls.canStopAfterCurrent &&
              pendingAction == null)) &&
      (pendingAction == null ||
          outcome == RouteExecutionOutcome.attentionRequired ||
          outcome == RouteExecutionOutcome.recovery) &&
      (pendingAction?.isExecutable ?? true) &&
      (holding?.isExecutable ?? true) &&
      stages.every((stage) => stage.isExecutable) &&
      stageResults.every(
        (result) =>
            result.phase != RouteStagePhase.unknown &&
            result.evidence.every(
              (evidence) => evidence.kind != RouteEvidenceKind.unknown,
            ) &&
            (stages.isEmpty ||
                stages.any(
                  (stage) =>
                      stage.sequence == result.sequence &&
                      stage.stageId == result.stageId,
                )),
      ) &&
      (approvalRecovery?.isExecutable ?? true);

  RouteLiveAnnouncement get announcement {
    if (!isExecutable) return RouteLiveAnnouncement.statusUnavailable;
    switch (outcome) {
      case RouteExecutionOutcome.attentionRequired:
        return RouteLiveAnnouncement.attentionRequired;
      case RouteExecutionOutcome.recovery:
        return RouteLiveAnnouncement.recoveryRequired;
      case RouteExecutionOutcome.completed:
        return RouteLiveAnnouncement.completed;
      case RouteExecutionOutcome.cancelled:
        return RouteLiveAnnouncement.cancelled;
      case RouteExecutionOutcome.failed:
        return RouteLiveAnnouncement.failed;
      case RouteExecutionOutcome.unknown:
        return RouteLiveAnnouncement.statusUnavailable;
      case RouteExecutionOutcome.active:
        break;
    }
    return switch (phase) {
      RouteExecutionPhase.awaitingApproval ||
      RouteExecutionPhase.approvalPending =>
        RouteLiveAnnouncement.approvalRequired,
      RouteExecutionPhase.awaitingSignature ||
      RouteExecutionPhase.signed ||
      RouteExecutionPhase.broadcasting ||
      RouteExecutionPhase.sourcePending => RouteLiveAnnouncement.sending,
      RouteExecutionPhase.sourceConfirmed ||
      RouteExecutionPhase.bridgePending ||
      RouteExecutionPhase.destinationConfirmed ||
      RouteExecutionPhase.atomicFill ||
      RouteExecutionPhase.refundPending ||
      RouteExecutionPhase.refunded => RouteLiveAnnouncement.receiving,
      RouteExecutionPhase.awaitingUserAction ||
      RouteExecutionPhase.stopAfterCurrent ||
      RouteExecutionPhase.manualIntervention =>
        RouteLiveAnnouncement.attentionRequired,
      RouteExecutionPhase.partial => RouteLiveAnnouncement.recoveryRequired,
      RouteExecutionPhase.completed => RouteLiveAnnouncement.completed,
      RouteExecutionPhase.cancelled => RouteLiveAnnouncement.cancelled,
      RouteExecutionPhase.failed => RouteLiveAnnouncement.failed,
      RouteExecutionPhase.unknown => RouteLiveAnnouncement.statusUnavailable,
      RouteExecutionPhase.validating => RouteLiveAnnouncement.validating,
    };
  }

  @override
  List<Object?> get props => [
    routeExecutionId,
    outcome,
    phase,
    stateRevision,
    stageIndex,
    stageCount,
    controls,
    pendingAction,
    holding,
    transactionHashes,
    stages,
    stageResults,
    approvalRecovery,
    updatedAt,
    rawOutcomeDiscriminator,
    rawPhaseDiscriminator,
  ];
}

@immutable
class RouteExecutionSession extends Equatable {
  RouteExecutionSession({
    required this.routeExecutionId,
    required this.taskId,
  }) {
    UnifiedSwapModelLimits.requireString(routeExecutionId, 'routeExecutionId');
    if (taskId < 0) throw RangeError.value(taskId, 'taskId');
  }

  final String routeExecutionId;
  final int taskId;

  @override
  List<Object?> get props => [routeExecutionId, taskId];
}

@immutable
class RouteExecutionDecision extends Equatable {
  RouteExecutionDecision({
    required this.kind,
    required this.actionId,
    required this.expectedStateRevision,
    this.recoveryReviewId,
    this.replacementProposalDigest,
  }) {
    UnifiedSwapModelLimits.requireString(actionId, 'actionId');
    UnifiedSwapModelLimits.requireOptionalString(
      recoveryReviewId,
      'recoveryReviewId',
    );
    UnifiedSwapModelLimits.requireOptionalString(
      replacementProposalDigest,
      'replacementProposalDigest',
      maximumLength: UnifiedSwapModelLimits.digestLength,
    );
    if (expectedStateRevision < 0) {
      throw RangeError.value(expectedStateRevision, 'expectedStateRevision');
    }
    final hasRecovery = recoveryReviewId != null;
    final hasReplacement = replacementProposalDigest != null;
    if ((kind == RouteExecutionActionKind.selectRecoveryRoute) != hasRecovery ||
        (kind == RouteExecutionActionKind.acceptReplacement) !=
            hasReplacement ||
        (hasRecovery && hasReplacement)) {
      throw ArgumentError('Decision authority does not match its action kind');
    }
  }

  final RouteExecutionActionKind kind;
  final String actionId;
  final int expectedStateRevision;
  final String? recoveryReviewId;
  final String? replacementProposalDigest;

  @override
  List<Object?> get props => [
    kind,
    actionId,
    expectedStateRevision,
    recoveryReviewId,
    replacementProposalDigest,
  ];
}

@immutable
class RouteActionAcknowledgement extends Equatable {
  const RouteActionAcknowledgement({required this.wasDelivered});

  final bool wasDelivered;

  @override
  List<Object?> get props => [wasDelivered];
}

String _smallestUnitAmount(String value) {
  if (value.length > UnifiedSwapModelLimits.amountDigits ||
      !RegExp(r'^(?:0|[1-9][0-9]*)$').hasMatch(value)) {
    throw ArgumentError.value(
      value,
      'amount',
      'Must be a non-negative integer in smallest units',
    );
  }
  return value;
}

String _addressIdentity(UnifiedSwapAssetIdentity asset, String address) =>
    asset.chainFamily == UnifiedSwapChainFamily.evm &&
        RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(address)
    ? address.toLowerCase()
    : address;

bool _hasKnownAssetIdentity(UnifiedSwapAssetIdentity asset) =>
    asset.hasKnownBoundedIdentity;

bool _isPositiveAmount(String amount) => BigInt.parse(amount) > BigInt.zero;

bool _isExecutableAddress(UnifiedSwapAssetIdentity asset, String address) =>
    asset.chainFamily != UnifiedSwapChainFamily.evm ||
    RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(address);

bool _isTerminalOutcome(RouteExecutionOutcome outcome) =>
    outcome == RouteExecutionOutcome.completed ||
    outcome == RouteExecutionOutcome.cancelled ||
    outcome == RouteExecutionOutcome.failed;

bool _outcomeMatchesPhase(
  RouteExecutionOutcome outcome,
  RouteExecutionPhase phase,
) => switch (outcome) {
  RouteExecutionOutcome.completed => phase == RouteExecutionPhase.completed,
  RouteExecutionOutcome.cancelled => phase == RouteExecutionPhase.cancelled,
  RouteExecutionOutcome.failed => phase == RouteExecutionPhase.failed,
  RouteExecutionOutcome.active ||
  RouteExecutionOutcome.attentionRequired ||
  RouteExecutionOutcome.recovery =>
    phase != RouteExecutionPhase.completed &&
        phase != RouteExecutionPhase.cancelled &&
        phase != RouteExecutionPhase.failed,
  RouteExecutionOutcome.unknown => false,
};

List<Object?> _identityProps(UnifiedSwapAssetIdentity identity) => [
  identity.ticker,
  identity.chainFamily,
  identity.chainId,
  identity.kind,
  identity.decimals,
  identity.contractIdentity,
  identity.rawChainFamilyDiscriminator,
  identity.rawKindDiscriminator,
];

void _validateTransactionHashes(List<String> hashes, String name) {
  UnifiedSwapModelLimits.requireListLength(
    hashes.length,
    name,
    maximumLength: UnifiedSwapModelLimits.nestedItems,
  );
  for (final hash in hashes) {
    UnifiedSwapModelLimits.requireString(hash, name);
  }
  if (hashes.toSet().length != hashes.length) {
    throw ArgumentError('$name must not contain duplicates');
  }
}

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:web_dex/features/unified_swap/domain/route_activity_models.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';

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
  const RouteReviewWarning({required this.kind, this.rawKindDiscriminator});

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
    if (stageId.trim().isEmpty) {
      throw ArgumentError.value(stageId, 'stageId', 'Must not be empty');
    }
    if (BigInt.parse(minimumReceive) > BigInt.parse(expectedReceive)) {
      throw ArgumentError('minimumReceive must not exceed expectedReceive');
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
      source.chainFamily != UnifiedSwapChainFamily.unknown &&
      source.kind != UnifiedSwapAssetKind.unknown &&
      destination.chainFamily != UnifiedSwapChainFamily.unknown &&
      destination.kind != UnifiedSwapAssetKind.unknown;

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
    if (stageId.trim().isEmpty || spender.trim().isEmpty) {
      if (stageId.trim().isEmpty) {
        throw ArgumentError.value(stageId, 'stageId', 'Must not be empty');
      }
      throw ArgumentError.value(spender, 'spender', 'Must not be empty');
    }
  }

  final String stageId;
  final UnifiedSwapAssetIdentity token;
  final String spender;
  final String exactAmount;
  final bool resetRequired;

  @override
  List<Object?> get props => [
    stageId,
    ..._identityProps(token),
    spender,
    exactAmount,
    resetRequired,
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
    required List<RouteReviewStep> steps,
    required List<RouteReviewWarning> warnings,
    required List<RouteApprovalScope> approvals,
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
       expiresAt = expiresAt.toUtc() {
    if (walletId.trim().isEmpty ||
        routeExecutionId.trim().isEmpty ||
        reviewId.trim().isEmpty ||
        consentDigest.trim().isEmpty ||
        candidateDigest.trim().isEmpty ||
        resolvedSourceAddress.trim().isEmpty ||
        recipient.trim().isEmpty) {
      throw ArgumentError(
        'Review identity and address fields must not be empty',
      );
    }
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
  final List<RouteReviewStep> steps;
  final List<RouteReviewWarning> warnings;
  final List<RouteApprovalScope> approvals;
  final DateTime expiresAt;
  final UnifiedSwapSourceSelectorKind sourceSelectorKind;
  final bool externalRecipientConfirmed;

  bool isExpiredAt(DateTime value) => !expiresAt.isAfter(value.toUtc());

  bool get isExecutable =>
      _hasKnownAssetIdentity(source) &&
      _hasKnownAssetIdentity(destination) &&
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
      approvals.every((approval) => _hasKnownAssetIdentity(approval.token)) &&
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
    resolvedSourceAddress,
    recipient,
    estimatedDuration,
    steps,
    warnings,
    approvals,
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
    if (actionId.trim().isEmpty) {
      throw ArgumentError.value(actionId, 'actionId', 'Must not be empty');
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
    if (proposalDigest.trim().isEmpty || stageId.trim().isEmpty) {
      throw ArgumentError('Replacement identity must not be empty');
    }
    if (providerStepDigest != null && providerStepDigest!.trim().isEmpty) {
      throw ArgumentError.value(providerStepDigest, 'providerStepDigest');
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
    : amount = _smallestUnitAmount(amount);

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
    this.rawOutcomeDiscriminator,
    this.rawPhaseDiscriminator,
  }) : transactionHashes = List.unmodifiable(transactionHashes),
       updatedAt = updatedAt.toUtc() {
    if (routeExecutionId.trim().isEmpty) {
      throw ArgumentError.value(
        routeExecutionId,
        'routeExecutionId',
        'Must not be empty',
      );
    }
    if (stateRevision < 0 || stageIndex < 0 || stageCount < 0) {
      throw ArgumentError('Progress indexes and revision must not be negative');
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
  final DateTime updatedAt;
  final String? rawOutcomeDiscriminator;
  final String? rawPhaseDiscriminator;

  bool get isExecutable =>
      outcome != RouteExecutionOutcome.unknown &&
      phase != RouteExecutionPhase.unknown &&
      (pendingAction?.isExecutable ?? true);

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
    updatedAt,
    rawOutcomeDiscriminator,
    rawPhaseDiscriminator,
  ];
}

@immutable
class RouteExecutionSession extends Equatable {
  const RouteExecutionSession({
    required this.routeExecutionId,
    required this.taskId,
  });

  final String routeExecutionId;
  final int taskId;

  @override
  List<Object?> get props => [routeExecutionId, taskId];
}

@immutable
class RouteExecutionDecision extends Equatable {
  const RouteExecutionDecision({
    required this.kind,
    required this.actionId,
    required this.expectedStateRevision,
    this.recoveryReviewId,
    this.replacementProposalDigest,
  });

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
  if (!RegExp(r'^(?:0|[1-9][0-9]*)$').hasMatch(value)) {
    throw ArgumentError.value(
      value,
      'amount',
      'Must be a non-negative integer in smallest units',
    );
  }
  return value;
}

bool _hasKnownAssetIdentity(UnifiedSwapAssetIdentity asset) =>
    asset.chainFamily != UnifiedSwapChainFamily.unknown &&
    asset.kind != UnifiedSwapAssetKind.unknown;

List<Object?> _identityProps(UnifiedSwapAssetIdentity identity) => [
  identity.ticker,
  identity.chainFamily,
  identity.chainId,
  identity.kind,
  identity.decimals,
  identity.contractAddress?.toLowerCase(),
  identity.rawChainFamilyDiscriminator,
  identity.rawKindDiscriminator,
];

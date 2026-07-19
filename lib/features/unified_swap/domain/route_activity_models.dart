import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';

enum RouteActivityStatus {
  active,
  attentionRequired,
  completed,
  cancelled,
  failed,
  unknown,
}

enum RouteActivityGroup { active, attentionRequired, completed }

enum RouteStagePhase {
  preparing,
  approval,
  sending,
  receiving,
  reconciliation,
  recovery,
  completed,
  cancelled,
  failed,
  unknown,
}

enum RouteEvidenceKind {
  sourceReceipt,
  receiving,
  refund,
  providerStatus,
  unknown,
}

enum RouteFeeKind { provider, bridge, exchange, network, kdf, unknown }

enum RouteActivityFailure {
  invalidRequest,
  invalidCursor,
  notFound,
  storageUnavailable,
  serviceUnavailable,
  unknown,
}

extension RouteActivityStatusX on RouteActivityStatus {
  bool get isTerminal =>
      this == RouteActivityStatus.completed ||
      this == RouteActivityStatus.cancelled ||
      this == RouteActivityStatus.failed;

  RouteActivityGroup get group {
    switch (this) {
      case RouteActivityStatus.active:
        return RouteActivityGroup.active;
      case RouteActivityStatus.attentionRequired:
      case RouteActivityStatus.unknown:
        return RouteActivityGroup.attentionRequired;
      case RouteActivityStatus.completed:
      case RouteActivityStatus.cancelled:
      case RouteActivityStatus.failed:
        return RouteActivityGroup.completed;
    }
  }
}

@immutable
class RouteActivitySummary extends Equatable {
  RouteActivitySummary({
    required this.routeExecutionId,
    required this.status,
    required this.source,
    required this.destination,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? completedAt,
    this.rawStatusDiscriminator,
  }) : createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc(),
       completedAt = completedAt?.toUtc() {
    if (routeExecutionId.trim().isEmpty) {
      throw ArgumentError.value(
        routeExecutionId,
        'routeExecutionId',
        'Must not be empty',
      );
    }
    if (this.updatedAt.isBefore(this.createdAt)) {
      throw ArgumentError('updatedAt must not be before createdAt');
    }
    if (this.completedAt?.isBefore(this.createdAt) ?? false) {
      throw ArgumentError('completedAt must not be before createdAt');
    }
    if (status == RouteActivityStatus.unknown &&
        (rawStatusDiscriminator == null ||
            rawStatusDiscriminator!.trim().isEmpty)) {
      throw ArgumentError('Unknown status must preserve its raw discriminator');
    }
  }

  final String routeExecutionId;
  final RouteActivityStatus status;
  final UnifiedSwapAssetIdentity source;
  final UnifiedSwapAssetIdentity destination;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final String? rawStatusDiscriminator;

  @override
  List<Object?> get props => [
    routeExecutionId,
    status,
    ..._identityProps(source),
    ..._identityProps(destination),
    createdAt,
    updatedAt,
    completedAt,
    rawStatusDiscriminator,
  ];
}

@immutable
class RouteControlCapabilities extends Equatable {
  RouteControlCapabilities({
    required this.canCancel,
    required this.canStopAfterCurrent,
    required this.reconciliationOnly,
  }) {
    if (reconciliationOnly && (canCancel || canStopAfterCurrent)) {
      throw ArgumentError(
        'Reconciliation-only routes cannot expose movement controls',
      );
    }
  }

  final bool canCancel;
  final bool canStopAfterCurrent;
  final bool reconciliationOnly;

  @override
  List<Object?> get props => [
    canCancel,
    canStopAfterCurrent,
    reconciliationOnly,
  ];
}

@immutable
class RouteExecutionFee extends Equatable {
  RouteExecutionFee({
    required this.kind,
    required this.asset,
    required String amount,
    required this.included,
    this.rawKindDiscriminator,
  }) : amount = _smallestUnitAmount(amount) {
    _validateUnknownFeeKind(kind, rawKindDiscriminator);
  }

  final RouteFeeKind kind;
  final UnifiedSwapAssetIdentity asset;
  final String amount;
  final bool included;
  final String? rawKindDiscriminator;

  @override
  List<Object?> get props => [
    kind,
    ..._identityProps(asset),
    amount,
    included,
    rawKindDiscriminator,
  ];
}

@immutable
class RouteExecutionFeeLimit extends Equatable {
  RouteExecutionFeeLimit({
    this.stageId,
    required this.kind,
    required this.asset,
    required String maximumAmount,
    this.rawKindDiscriminator,
  }) : maximumAmount = _smallestUnitAmount(maximumAmount) {
    if (stageId != null && stageId!.trim().isEmpty) {
      throw ArgumentError.value(stageId, 'stageId', 'Must not be empty');
    }
    _validateUnknownFeeKind(kind, rawKindDiscriminator);
  }

  final String? stageId;
  final RouteFeeKind kind;
  final UnifiedSwapAssetIdentity asset;
  final String maximumAmount;
  final String? rawKindDiscriminator;

  @override
  List<Object?> get props => [
    stageId,
    kind,
    ..._identityProps(asset),
    maximumAmount,
    rawKindDiscriminator,
  ];
}

@immutable
class RouteStageNetworkFeeCap extends Equatable {
  RouteStageNetworkFeeCap({
    required this.stageId,
    required this.asset,
    required String maximumAmount,
  }) : maximumAmount = _smallestUnitAmount(maximumAmount) {
    if (stageId.trim().isEmpty) {
      throw ArgumentError.value(stageId, 'stageId', 'Must not be empty');
    }
  }

  final String stageId;
  final UnifiedSwapAssetIdentity asset;
  final String maximumAmount;

  @override
  List<Object?> get props => [stageId, ..._identityProps(asset), maximumAmount];
}

@immutable
class RouteExecutionConsent extends Equatable {
  RouteExecutionConsent({
    required this.routeExecutionId,
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
  }) : sourceAmount = _smallestUnitAmount(sourceAmount),
       expectedReceive = _smallestUnitAmount(expectedReceive),
       minimumReceive = _smallestUnitAmount(minimumReceive),
       fees = List.unmodifiable(fees),
       nonNetworkFeeLimits = List.unmodifiable(nonNetworkFeeLimits),
       networkFeeCaps = List.unmodifiable(networkFeeCaps) {
    if (routeExecutionId.trim().isEmpty ||
        consentDigest.trim().isEmpty ||
        candidateDigest.trim().isEmpty ||
        recipient.trim().isEmpty) {
      throw ArgumentError('Persisted consent fields must not be empty');
    }
    if (resolvedSourceAddress != null &&
        resolvedSourceAddress!.trim().isEmpty) {
      throw ArgumentError(
        'resolvedSourceAddress must be null or a non-empty address',
      );
    }
    if (BigInt.parse(minimumReceive) > BigInt.parse(expectedReceive)) {
      throw ArgumentError('minimumReceive must not exceed expectedReceive');
    }
  }

  final String routeExecutionId;
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

  /// Null only for a legacy journal that predates resolved-address
  /// persistence. The wallet must display that as unavailable, never guess.
  final String? resolvedSourceAddress;
  final String recipient;

  @override
  List<Object?> get props => [
    routeExecutionId,
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
  ];
}

@immutable
class RouteSafeEvidence extends Equatable {
  RouteSafeEvidence({
    required this.kind,
    this.reference,
    this.status,
    this.substatus,
    this.rawKindDiscriminator,
  }) {
    if (reference != null && reference!.trim().isEmpty) {
      throw ArgumentError.value(
        reference,
        'reference',
        'Must be null or non-empty',
      );
    }
    if (status != null && status!.trim().isEmpty) {
      throw ArgumentError.value(status, 'status', 'Must be null or non-empty');
    }
    if (substatus != null && substatus!.trim().isEmpty) {
      throw ArgumentError.value(
        substatus,
        'substatus',
        'Must be null or non-empty',
      );
    }
    if (kind == RouteEvidenceKind.unknown &&
        (rawKindDiscriminator == null ||
            rawKindDiscriminator!.trim().isEmpty)) {
      throw ArgumentError(
        'Unknown evidence kind must preserve its raw discriminator',
      );
    }
  }

  final RouteEvidenceKind kind;
  final String? reference;
  final String? status;
  final String? substatus;
  final String? rawKindDiscriminator;

  @override
  List<Object?> get props => [
    kind,
    reference,
    status,
    substatus,
    rawKindDiscriminator,
  ];
}

@immutable
class RouteStageHistoryEntry extends Equatable {
  RouteStageHistoryEntry({
    required this.sequence,
    required this.stageId,
    required this.phase,
    DateTime? startedAt,
    DateTime? updatedAt,
    required List<String> transactionHashes,
    required List<RouteSafeEvidence> evidence,
    required this.holding,
    DateTime? completedAt,
    this.rawPhaseDiscriminator,
  }) : startedAt = startedAt?.toUtc(),
       updatedAt = updatedAt?.toUtc(),
       completedAt = completedAt?.toUtc(),
       transactionHashes = List.unmodifiable(transactionHashes),
       evidence = List.unmodifiable(evidence) {
    if (sequence < 0) {
      throw ArgumentError.value(sequence, 'sequence', 'Must not be negative');
    }
    if (stageId.trim().isEmpty) {
      throw ArgumentError.value(stageId, 'stageId', 'Must not be empty');
    }
    if (this.startedAt != null &&
        this.updatedAt?.isBefore(this.startedAt!) == true) {
      throw ArgumentError('Stage updatedAt must not be before startedAt');
    }
    if (this.startedAt != null &&
        this.completedAt?.isBefore(this.startedAt!) == true) {
      throw ArgumentError('Stage completedAt must not be before startedAt');
    }
    if (phase == RouteStagePhase.unknown &&
        (rawPhaseDiscriminator == null ||
            rawPhaseDiscriminator!.trim().isEmpty)) {
      throw ArgumentError('Unknown phase must preserve its raw discriminator');
    }
  }

  final int sequence;
  final String stageId;
  final RouteStagePhase phase;
  final DateTime? startedAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;
  final List<String> transactionHashes;
  final List<RouteSafeEvidence> evidence;
  final RouteHolding? holding;
  final String? rawPhaseDiscriminator;

  @override
  List<Object?> get props => [
    sequence,
    stageId,
    phase,
    startedAt,
    updatedAt,
    completedAt,
    transactionHashes,
    evidence,
    holding,
    rawPhaseDiscriminator,
  ];
}

@immutable
class RouteHolding extends Equatable {
  RouteHolding({
    required this.asset,
    required String amount,
    required this.address,
  }) : amount = _smallestUnitAmount(amount) {
    if (address.trim().isEmpty) {
      throw ArgumentError.value(address, 'address', 'Must not be empty');
    }
  }

  final UnifiedSwapAssetIdentity asset;
  final String amount;
  final String address;

  @override
  List<Object?> get props => [..._identityProps(asset), amount, address];
}

@immutable
class RouteExecutionRevision extends Equatable {
  RouteExecutionRevision({
    required this.revision,
    required this.consent,
    required this.phase,
    required this.holding,
    required List<RouteStageHistoryEntry> stages,
    DateTime? createdAt,
    required DateTime updatedAt,
    DateTime? completedAt,
    required DateTime archivedAt,
    this.rawPhaseDiscriminator,
  }) : stages = List.unmodifiable(
         [...stages]
           ..sort((left, right) => left.sequence.compareTo(right.sequence)),
       ),
       createdAt = createdAt?.toUtc(),
       updatedAt = updatedAt.toUtc(),
       completedAt = completedAt?.toUtc(),
       archivedAt = archivedAt.toUtc() {
    if (revision < 0) {
      throw ArgumentError.value(revision, 'revision', 'Must not be negative');
    }
    if (phase == RouteStagePhase.unknown &&
        (rawPhaseDiscriminator == null ||
            rawPhaseDiscriminator!.trim().isEmpty)) {
      throw ArgumentError(
        'Unknown revision phase must preserve its raw discriminator',
      );
    }
    if (this.createdAt != null && this.updatedAt.isBefore(this.createdAt!)) {
      throw ArgumentError('Revision updatedAt must not be before createdAt');
    }
    if (this.createdAt != null &&
        this.completedAt?.isBefore(this.createdAt!) == true) {
      throw ArgumentError('Revision completedAt must not be before createdAt');
    }
    final sequences = this.stages.map((stage) => stage.sequence).toSet();
    if (sequences.length != this.stages.length) {
      throw ArgumentError('Revision stage sequence values must be unique');
    }
  }

  final int revision;
  final RouteExecutionConsent consent;
  final RouteStagePhase phase;
  final RouteHolding? holding;
  final List<RouteStageHistoryEntry> stages;
  final DateTime? createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final DateTime archivedAt;
  final String? rawPhaseDiscriminator;

  @override
  List<Object?> get props => [
    revision,
    consent,
    phase,
    holding,
    stages,
    createdAt,
    updatedAt,
    completedAt,
    archivedAt,
    rawPhaseDiscriminator,
  ];
}

@immutable
class RouteExecutionDetail extends Equatable {
  RouteExecutionDetail({
    required this.summary,
    required this.consent,
    required this.controls,
    required this.holding,
    required List<RouteStageHistoryEntry> stages,
    required List<RouteExecutionRevision> revisions,
  }) : stages = List.unmodifiable(
         [...stages]
           ..sort((left, right) => left.sequence.compareTo(right.sequence)),
       ),
       revisions = List.unmodifiable(
         [...revisions]
           ..sort((left, right) => left.revision.compareTo(right.revision)),
       ) {
    if (summary.routeExecutionId != consent.routeExecutionId) {
      throw ArgumentError(
        'Summary and persisted consent must identify the same execution',
      );
    }
    final sequences = this.stages.map((stage) => stage.sequence).toSet();
    if (sequences.length != this.stages.length) {
      throw ArgumentError('Stage sequence values must be unique');
    }
  }

  final RouteActivitySummary summary;
  final RouteExecutionConsent consent;
  final RouteControlCapabilities controls;
  final RouteHolding? holding;
  final List<RouteStageHistoryEntry> stages;
  final List<RouteExecutionRevision> revisions;

  @override
  List<Object?> get props => [
    summary,
    consent,
    controls,
    holding,
    stages,
    revisions,
  ];
}

@immutable
class RouteActivityPage extends Equatable {
  RouteActivityPage({
    required List<RouteActivitySummary> executions,
    required this.nextCursor,
  }) : executions = List.unmodifiable(executions) {
    if (nextCursor != null && nextCursor!.isEmpty) {
      throw ArgumentError.value(
        nextCursor,
        'nextCursor',
        'Opaque cursor must not be empty',
      );
    }
  }

  final List<RouteActivitySummary> executions;
  final String? nextCursor;

  @override
  List<Object?> get props => [executions, nextCursor];
}

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

void _validateUnknownFeeKind(RouteFeeKind kind, String? rawKindDiscriminator) {
  if (kind == RouteFeeKind.unknown &&
      (rawKindDiscriminator == null || rawKindDiscriminator.trim().isEmpty)) {
    throw ArgumentError('Unknown fee kind must preserve its raw discriminator');
  }
}

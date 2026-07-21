import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_model_limits.dart';

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

enum RouteEvidenceState {
  broadcast,
  confirmed,
  published,
  temporarilyUnavailable,
  invalidEvidence,
  failed,
  completed,
  unknown,
}

enum RouteTransactionStatus { notFound, pending, confirmed, reverted, unknown }

enum RouteApprovalRecoveryInstruction {
  revokeAllowanceBeforeRetry,
  noAllowanceRemains,
  unknown,
}

/// The exact durable execution phase persisted by KDF.
///
/// This intentionally stays separate from [RouteStagePhase], which is a
/// customer-facing grouping and cannot represent every durable phase without
/// losing audit information.
enum RouteActivityExecutionPhase {
  planned,
  awaitingApproval,
  approvalPending,
  awaitingUserAction,
  awaitingSignature,
  signed,
  broadcasting,
  sourcePending,
  sourceConfirmed,
  bridgePending,
  destinationConfirmed,
  refundPending,
  partial,
  refunded,
  manualIntervention,
  failed,
  cancelled,
  unknown,
}

enum RouteExecutionRoutePhase {
  validating,
  executingStage,
  waitingSourceReceipt,
  waitingDestination,
  atomicFill,
  awaitingUserAction,
  stopAfterCurrent,
  manualIntervention,
  partial,
  refundPending,
  refunded,
  completed,
  failed,
  cancelled,
  unknown,
}

enum RouteEvidenceTransferDirection { sending, receiving, transfer }

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
    String? sourceAmount,
    String? expectedReceive,
    String? minimumReceive,
    this.requiresUserAttention = false,
    this.requiresUserAction = false,
    this.terminalError,
    this.rawStatusDiscriminator,
  }) : sourceAmount = sourceAmount == null
           ? null
           : _smallestUnitAmount(sourceAmount),
       expectedReceive = expectedReceive == null
           ? null
           : _smallestUnitAmount(expectedReceive),
       minimumReceive = minimumReceive == null
           ? null
           : _smallestUnitAmount(minimumReceive),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc(),
       completedAt = completedAt?.toUtc() {
    UnifiedSwapModelLimits.requireString(routeExecutionId, 'routeExecutionId');
    _validateBoundedAsset(source);
    _validateBoundedAsset(destination);
    if (this.updatedAt.isBefore(this.createdAt)) {
      throw ArgumentError('updatedAt must not be before createdAt');
    }
    if (this.completedAt?.isBefore(this.createdAt) ?? false) {
      throw ArgumentError('completedAt must not be before createdAt');
    }
    if (this.expectedReceive != null &&
        this.minimumReceive != null &&
        BigInt.parse(this.minimumReceive!) >
            BigInt.parse(this.expectedReceive!)) {
      throw ArgumentError('minimumReceive must not exceed expectedReceive');
    }
    UnifiedSwapModelLimits.requireRawDiscriminator(
      rawStatusDiscriminator,
      'rawStatusDiscriminator',
      isUnknown: status == RouteActivityStatus.unknown,
    );
  }

  final String routeExecutionId;
  final RouteActivityStatus status;
  final UnifiedSwapAssetIdentity source;
  final UnifiedSwapAssetIdentity destination;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final String? sourceAmount;
  final String? expectedReceive;
  final String? minimumReceive;
  final bool requiresUserAttention;
  final bool requiresUserAction;
  final RouteTerminalError? terminalError;
  final String? rawStatusDiscriminator;

  /// The activity bucket is driven by KDF's typed attention flags. The status
  /// remains a conservative fallback for legacy journals and unknown values.
  RouteActivityGroup get group {
    if (status != RouteActivityStatus.unknown &&
        (requiresUserAttention || requiresUserAction)) {
      return RouteActivityGroup.attentionRequired;
    }
    return status.group;
  }

  @override
  List<Object?> get props => [
    routeExecutionId,
    status,
    ..._identityProps(source),
    ..._identityProps(destination),
    createdAt,
    updatedAt,
    completedAt,
    sourceAmount,
    expectedReceive,
    minimumReceive,
    requiresUserAttention,
    requiresUserAction,
    terminalError,
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
    _validateBoundedAsset(asset);
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
    UnifiedSwapModelLimits.requireOptionalString(stageId, 'stageId');
    _validateUnknownFeeKind(kind, rawKindDiscriminator);
    _validateBoundedAsset(asset);
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
    UnifiedSwapModelLimits.requireString(stageId, 'stageId');
    _validateBoundedAsset(asset);
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
    UnifiedSwapModelLimits.requireString(routeExecutionId, 'routeExecutionId');
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
      recipient,
      'recipient',
      maximumLength: UnifiedSwapModelLimits.addressLength,
    );
    UnifiedSwapModelLimits.requireOptionalString(
      resolvedSourceAddress,
      'resolvedSourceAddress',
      maximumLength: UnifiedSwapModelLimits.addressLength,
    );
    UnifiedSwapModelLimits.requireListLength(fees.length, 'fees');
    UnifiedSwapModelLimits.requireListLength(
      nonNetworkFeeLimits.length,
      'nonNetworkFeeLimits',
    );
    UnifiedSwapModelLimits.requireListLength(
      networkFeeCaps.length,
      'networkFeeCaps',
    );
    if (BigInt.parse(minimumReceive) > BigInt.parse(expectedReceive)) {
      throw ArgumentError('minimumReceive must not exceed expectedReceive');
    }
    _validateBoundedAsset(source);
    _validateBoundedAsset(destination);
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
    resolvedSourceAddress == null
        ? null
        : _addressIdentity(source, resolvedSourceAddress!),
    _addressIdentity(destination, recipient),
  ];
}

@immutable
class RouteEvidenceAssetAmount extends Equatable {
  RouteEvidenceAssetAmount({required this.asset, required String amount})
    : amount = _smallestUnitAmount(amount) {
    _validateBoundedAsset(asset);
  }

  final UnifiedSwapAssetIdentity asset;
  final String amount;

  bool get isExecutable => asset.hasKnownBoundedIdentity;

  @override
  List<Object?> get props => [..._identityProps(asset), amount];
}

@immutable
class RouteTransactionReceipt extends Equatable {
  RouteTransactionReceipt({
    required this.chainFamily,
    required this.chainId,
    required this.transactionHash,
    required this.status,
    required this.confirmations,
    required DateTime observedAt,
    this.blockHash,
    this.blockHeight,
    this.gasUsed,
    this.effectiveGasPrice,
    this.networkFee,
    this.revertReason,
    this.rawChainFamilyDiscriminator,
    this.rawStatusDiscriminator,
  }) : observedAt = observedAt.toUtc() {
    UnifiedSwapModelLimits.requireString(
      chainId,
      'chainId',
      maximumLength: UnifiedSwapAssetIdentity.maximumChainIdLength,
    );
    UnifiedSwapModelLimits.requireString(transactionHash, 'transactionHash');
    UnifiedSwapModelLimits.requireOptionalString(blockHash, 'blockHash');
    UnifiedSwapModelLimits.requireOptionalString(
      blockHeight,
      'blockHeight',
      maximumLength: UnifiedSwapModelLimits.amountDigits,
    );
    UnifiedSwapModelLimits.requireOptionalString(
      gasUsed,
      'gasUsed',
      maximumLength: UnifiedSwapModelLimits.amountDigits,
    );
    UnifiedSwapModelLimits.requireOptionalString(
      effectiveGasPrice,
      'effectiveGasPrice',
      maximumLength: UnifiedSwapModelLimits.amountDigits,
    );
    UnifiedSwapModelLimits.requireOptionalString(
      revertReason,
      'revertReason',
      maximumLength: UnifiedSwapModelLimits.textLength,
    );
    if (confirmations < 0) {
      throw RangeError.value(confirmations, 'confirmations');
    }
    _validateUnknownChainFamily(chainFamily, rawChainFamilyDiscriminator);
    UnifiedSwapModelLimits.requireRawDiscriminator(
      rawStatusDiscriminator,
      'rawStatusDiscriminator',
      isUnknown: status == RouteTransactionStatus.unknown,
    );
  }

  final UnifiedSwapChainFamily chainFamily;
  final String chainId;
  final String transactionHash;
  final RouteTransactionStatus status;
  final int confirmations;
  final String? blockHash;
  final String? blockHeight;
  final String? gasUsed;
  final String? effectiveGasPrice;
  final RouteEvidenceAssetAmount? networkFee;
  final String? revertReason;
  final DateTime observedAt;
  final String? rawChainFamilyDiscriminator;
  final String? rawStatusDiscriminator;

  bool get isExecutable =>
      chainFamily != UnifiedSwapChainFamily.unknown &&
      status != RouteTransactionStatus.unknown &&
      confirmations >= 0 &&
      (networkFee?.isExecutable ?? true);

  @override
  List<Object?> get props => [
    chainFamily,
    chainId,
    transactionHash,
    status,
    confirmations,
    blockHash,
    blockHeight,
    gasUsed,
    effectiveGasPrice,
    networkFee,
    revertReason,
    observedAt,
    rawChainFamilyDiscriminator,
    rawStatusDiscriminator,
  ];
}

@immutable
class RouteEvidenceTransferAsset extends Equatable {
  RouteEvidenceTransferAsset({
    required this.providerChainId,
    required this.tokenIdentifier,
    required this.decimals,
    required this.symbol,
  }) {
    UnifiedSwapModelLimits.requireString(providerChainId, 'providerChainId');
    UnifiedSwapModelLimits.requireString(tokenIdentifier, 'tokenIdentifier');
    UnifiedSwapModelLimits.requireString(
      symbol,
      'symbol',
      maximumLength: UnifiedSwapAssetIdentity.maximumTickerLength,
    );
    if (decimals < 0 || decimals > 255) {
      throw RangeError.range(decimals, 0, 255, 'decimals');
    }
  }

  final String providerChainId;
  final String tokenIdentifier;
  final int decimals;
  final String symbol;

  bool get isExecutable =>
      providerChainId.trim().isNotEmpty &&
      tokenIdentifier.trim().isNotEmpty &&
      symbol.trim().isNotEmpty &&
      decimals >= 0;

  @override
  List<Object?> get props => [
    providerChainId,
    tokenIdentifier,
    decimals,
    symbol,
  ];
}

@immutable
class RouteEvidenceTransfer extends Equatable {
  RouteEvidenceTransfer({
    required this.direction,
    required this.transactionHash,
    required this.chainId,
    String? amount,
    this.asset,
  }) : amount = amount == null ? null : _smallestUnitAmount(amount) {
    UnifiedSwapModelLimits.requireString(transactionHash, 'transactionHash');
    UnifiedSwapModelLimits.requireString(
      chainId,
      'chainId',
      maximumLength: UnifiedSwapAssetIdentity.maximumChainIdLength,
    );
  }

  final RouteEvidenceTransferDirection direction;
  final String transactionHash;
  final String chainId;
  final String? amount;
  final RouteEvidenceTransferAsset? asset;

  bool get isExecutable =>
      transactionHash.trim().isNotEmpty &&
      chainId.trim().isNotEmpty &&
      (asset?.isExecutable ?? true);

  @override
  List<Object?> get props => [
    direction,
    transactionHash,
    chainId,
    amount,
    asset,
  ];
}

@immutable
class RouteProviderEvidence extends Equatable {
  RouteProviderEvidence({
    required this.provider,
    required this.providerKnown,
    required List<RouteEvidenceTransfer> transfers,
    this.transactionId,
    this.tool,
    this.fromAddress,
    this.toAddress,
    this.receivingProviderChainId,
  }) : transfers = List.unmodifiable(transfers) {
    UnifiedSwapModelLimits.requireString(
      provider,
      'provider',
      maximumLength: UnifiedSwapModelLimits.discriminatorLength,
    );
    UnifiedSwapModelLimits.requireOptionalString(
      transactionId,
      'transactionId',
    );
    UnifiedSwapModelLimits.requireOptionalString(
      tool,
      'tool',
      maximumLength: UnifiedSwapModelLimits.discriminatorLength,
    );
    UnifiedSwapModelLimits.requireOptionalString(
      fromAddress,
      'fromAddress',
      maximumLength: UnifiedSwapModelLimits.addressLength,
    );
    UnifiedSwapModelLimits.requireOptionalString(
      toAddress,
      'toAddress',
      maximumLength: UnifiedSwapModelLimits.addressLength,
    );
    UnifiedSwapModelLimits.requireOptionalString(
      receivingProviderChainId,
      'receivingProviderChainId',
    );
    UnifiedSwapModelLimits.requireListLength(
      transfers.length,
      'transfers',
      maximumLength: UnifiedSwapModelLimits.nestedItems,
    );
  }

  final String provider;
  final bool providerKnown;
  final String? transactionId;
  final String? tool;
  final String? fromAddress;
  final String? toAddress;
  final String? receivingProviderChainId;
  final List<RouteEvidenceTransfer> transfers;

  bool get isExecutable =>
      providerKnown &&
      provider.trim().isNotEmpty &&
      transfers.every((transfer) => transfer.isExecutable);

  @override
  List<Object?> get props => [
    provider,
    providerKnown,
    transactionId,
    tool,
    fromAddress,
    toAddress,
    receivingProviderChainId,
    transfers,
  ];
}

@immutable
class RouteSafeEvidence extends Equatable {
  RouteSafeEvidence({
    required this.kind,
    this.reference,
    this.secondaryReference,
    this.status,
    this.substatus,
    this.state,
    this.receipt,
    this.provider,
    this.rawKindDiscriminator,
    this.rawStateDiscriminator,
  }) {
    UnifiedSwapModelLimits.requireOptionalString(reference, 'reference');
    UnifiedSwapModelLimits.requireOptionalString(
      secondaryReference,
      'secondaryReference',
    );
    UnifiedSwapModelLimits.requireOptionalString(
      status,
      'status',
      maximumLength: UnifiedSwapModelLimits.discriminatorLength,
    );
    UnifiedSwapModelLimits.requireOptionalString(
      substatus,
      'substatus',
      maximumLength: UnifiedSwapModelLimits.discriminatorLength,
    );
    UnifiedSwapModelLimits.requireRawDiscriminator(
      rawKindDiscriminator,
      'rawKindDiscriminator',
      isUnknown: kind == RouteEvidenceKind.unknown,
    );
    if (state != null) {
      UnifiedSwapModelLimits.requireRawDiscriminator(
        rawStateDiscriminator,
        'rawStateDiscriminator',
        isUnknown: state == RouteEvidenceState.unknown,
      );
    } else if (rawStateDiscriminator != null) {
      throw ArgumentError.value(
        rawStateDiscriminator,
        'rawStateDiscriminator',
        'Evidence without a state must not retain a state discriminator',
      );
    }
  }

  final RouteEvidenceKind kind;
  final String? reference;
  final String? secondaryReference;
  final String? status;
  final String? substatus;
  final RouteEvidenceState? state;
  final RouteTransactionReceipt? receipt;
  final RouteProviderEvidence? provider;
  final String? rawKindDiscriminator;
  final String? rawStateDiscriminator;

  bool get isExecutable =>
      kind != RouteEvidenceKind.unknown &&
      state != RouteEvidenceState.unknown &&
      (receipt?.isExecutable ?? true) &&
      (provider?.isExecutable ?? true);

  @override
  List<Object?> get props => [
    kind,
    reference,
    secondaryReference,
    status,
    substatus,
    state,
    receipt,
    provider,
    rawKindDiscriminator,
    rawStateDiscriminator,
  ];
}

@immutable
class RouteApprovalRecovery extends Equatable {
  RouteApprovalRecovery({
    required this.token,
    required this.validatedSpender,
    required String remainingAllowance,
    required this.instruction,
    this.rawInstructionDiscriminator,
  }) : remainingAllowance = _smallestUnitAmount(remainingAllowance) {
    UnifiedSwapModelLimits.requireString(
      validatedSpender,
      'validatedSpender',
      maximumLength: UnifiedSwapModelLimits.addressLength,
    );
    UnifiedSwapModelLimits.requireRawDiscriminator(
      rawInstructionDiscriminator,
      'rawInstructionDiscriminator',
      isUnknown: instruction == RouteApprovalRecoveryInstruction.unknown,
    );
    _validateBoundedAsset(token);
  }

  final UnifiedSwapAssetIdentity token;
  final String validatedSpender;
  final String remainingAllowance;
  final RouteApprovalRecoveryInstruction instruction;
  final String? rawInstructionDiscriminator;

  bool get isExecutable =>
      token.hasKnownBoundedIdentity &&
      _isExecutableAddress(token, validatedSpender) &&
      instruction != RouteApprovalRecoveryInstruction.unknown;

  @override
  List<Object?> get props => [
    ..._identityProps(token),
    validatedSpender,
    remainingAllowance,
    instruction,
    rawInstructionDiscriminator,
  ];
}

@immutable
class RouteTerminalError extends Equatable {
  RouteTerminalError({required this.type, required this.isKnown}) {
    UnifiedSwapModelLimits.requireString(
      type,
      'type',
      maximumLength: UnifiedSwapModelLimits.discriminatorLength,
    );
  }

  final String type;
  final bool isKnown;

  @override
  List<Object?> get props => [type, isKnown];
}

@immutable
class RouteAuthoritativeStatus extends Equatable {
  RouteAuthoritativeStatus({
    required this.executionPhase,
    required this.routePhase,
    required this.stateRevision,
    required this.stageIndex,
    required this.stopAfterCurrent,
    required List<String> transactionHashes,
    required List<RouteSafeEvidence> evidence,
    required DateTime updatedAt,
    DateTime? completedAt,
    this.approvalRecovery,
    this.rawExecutionPhaseDiscriminator,
    this.rawRoutePhaseDiscriminator,
  }) : transactionHashes = List.unmodifiable(transactionHashes),
       evidence = List.unmodifiable(evidence),
       updatedAt = updatedAt.toUtc(),
       completedAt = completedAt?.toUtc() {
    if (stateRevision < 0 || stageIndex < 0) {
      throw ArgumentError(
        'Status revision and stage index must not be negative',
      );
    }
    _validateTransactionHashes(transactionHashes, 'transactionHashes');
    UnifiedSwapModelLimits.requireListLength(
      evidence.length,
      'evidence',
      maximumLength: UnifiedSwapModelLimits.nestedItems,
    );
    UnifiedSwapModelLimits.requireRawDiscriminator(
      rawExecutionPhaseDiscriminator,
      'rawExecutionPhaseDiscriminator',
      isUnknown: executionPhase == RouteActivityExecutionPhase.unknown,
    );
    UnifiedSwapModelLimits.requireRawDiscriminator(
      rawRoutePhaseDiscriminator,
      'rawRoutePhaseDiscriminator',
      isUnknown: routePhase == RouteExecutionRoutePhase.unknown,
    );
  }

  final RouteActivityExecutionPhase executionPhase;
  final RouteExecutionRoutePhase routePhase;
  final int stateRevision;
  final int stageIndex;
  final bool stopAfterCurrent;
  final List<String> transactionHashes;
  final List<RouteSafeEvidence> evidence;
  final RouteApprovalRecovery? approvalRecovery;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final String? rawExecutionPhaseDiscriminator;
  final String? rawRoutePhaseDiscriminator;

  bool get isExecutable =>
      executionPhase != RouteActivityExecutionPhase.unknown &&
      routePhase != RouteExecutionRoutePhase.unknown &&
      evidence.every((item) => item.isExecutable) &&
      (approvalRecovery?.isExecutable ?? true);

  @override
  List<Object?> get props => [
    executionPhase,
    routePhase,
    stateRevision,
    stageIndex,
    stopAfterCurrent,
    transactionHashes,
    evidence,
    approvalRecovery,
    updatedAt,
    completedAt,
    rawExecutionPhaseDiscriminator,
    rawRoutePhaseDiscriminator,
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
    UnifiedSwapModelLimits.requireString(stageId, 'stageId');
    _validateTransactionHashes(transactionHashes, 'transactionHashes');
    UnifiedSwapModelLimits.requireListLength(
      evidence.length,
      'evidence',
      maximumLength: UnifiedSwapModelLimits.nestedItems,
    );
    if (this.startedAt != null &&
        this.updatedAt?.isBefore(this.startedAt!) == true) {
      throw ArgumentError('Stage updatedAt must not be before startedAt');
    }
    if (this.startedAt != null &&
        this.completedAt?.isBefore(this.startedAt!) == true) {
      throw ArgumentError('Stage completedAt must not be before startedAt');
    }
    UnifiedSwapModelLimits.requireRawDiscriminator(
      rawPhaseDiscriminator,
      'rawPhaseDiscriminator',
      isUnknown: phase == RouteStagePhase.unknown,
    );
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
    if (address.trim().isEmpty ||
        address.trim() != address ||
        address.length > UnifiedSwapAssetIdentity.maximumIdentifierLength) {
      throw ArgumentError.value(address, 'address', 'Must not be empty');
    }
    _validateBoundedAsset(asset);
  }

  final UnifiedSwapAssetIdentity asset;
  final String amount;
  final String address;

  bool get isExecutable =>
      asset.hasKnownBoundedIdentity && _isExecutableAddress(asset, address);

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
    this.authoritativeStatus,
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
    UnifiedSwapModelLimits.requireListLength(
      stages.length,
      'stages',
      maximumLength: UnifiedSwapModelLimits.routeStages,
    );
    UnifiedSwapModelLimits.requireRawDiscriminator(
      rawPhaseDiscriminator,
      'rawPhaseDiscriminator',
      isUnknown: phase == RouteStagePhase.unknown,
    );
    if (this.createdAt != null && this.updatedAt.isBefore(this.createdAt!)) {
      throw ArgumentError('Revision updatedAt must not be before createdAt');
    }
    if (this.createdAt != null &&
        this.completedAt?.isBefore(this.createdAt!) == true) {
      throw ArgumentError('Revision completedAt must not be before createdAt');
    }
    if (archivedAt.toUtc().isBefore(this.updatedAt)) {
      throw ArgumentError('Revision archivedAt must not be before updatedAt');
    }
    if (this.completedAt != null &&
        this.archivedAt.isBefore(this.completedAt!)) {
      throw ArgumentError('Revision archivedAt must not be before completedAt');
    }
    final sequences = this.stages.map((stage) => stage.sequence).toSet();
    final stageIds = this.stages.map((stage) => stage.stageId).toSet();
    if (sequences.length != this.stages.length ||
        stageIds.length != this.stages.length) {
      throw ArgumentError('Revision stages must have unique IDs and sequences');
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
  final RouteAuthoritativeStatus? authoritativeStatus;
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
    authoritativeStatus,
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
    this.authoritativeStatus,
  }) : stages = List.unmodifiable(
         [...stages]
           ..sort((left, right) => left.sequence.compareTo(right.sequence)),
       ),
       revisions = List.unmodifiable(
         [...revisions]
           ..sort((left, right) => left.revision.compareTo(right.revision)),
       ) {
    UnifiedSwapModelLimits.requireListLength(
      stages.length,
      'stages',
      maximumLength: UnifiedSwapModelLimits.routeStages,
    );
    UnifiedSwapModelLimits.requireListLength(revisions.length, 'revisions');
    if (summary.routeExecutionId != consent.routeExecutionId ||
        summary.source != consent.source ||
        summary.destination != consent.destination ||
        (summary.sourceAmount != null &&
            summary.sourceAmount != consent.sourceAmount) ||
        (summary.expectedReceive != null &&
            summary.expectedReceive != consent.expectedReceive) ||
        (summary.minimumReceive != null &&
            summary.minimumReceive != consent.minimumReceive)) {
      throw ArgumentError(
        'Summary and persisted consent must describe the same execution',
      );
    }
    final sequences = this.stages.map((stage) => stage.sequence).toSet();
    final stageIds = this.stages.map((stage) => stage.stageId).toSet();
    final revisionNumbers = this.revisions
        .map((revision) => revision.revision)
        .toSet();
    if (sequences.length != this.stages.length ||
        stageIds.length != this.stages.length) {
      throw ArgumentError('Stages must have unique IDs and sequences');
    }
    if (revisionNumbers.length != this.revisions.length ||
        this.revisions.any(
          (revision) =>
              revision.consent.routeExecutionId != summary.routeExecutionId,
        )) {
      throw ArgumentError(
        'Revisions must be unique and identify the same execution',
      );
    }
  }

  final RouteActivitySummary summary;
  final RouteExecutionConsent consent;
  final RouteControlCapabilities controls;
  final RouteHolding? holding;
  final List<RouteStageHistoryEntry> stages;
  final List<RouteExecutionRevision> revisions;
  final RouteAuthoritativeStatus? authoritativeStatus;

  @override
  List<Object?> get props => [
    summary,
    consent,
    controls,
    holding,
    stages,
    revisions,
    authoritativeStatus,
  ];
}

@immutable
class RouteActivityPage extends Equatable {
  static const maximumPageSize = 100;

  RouteActivityPage({
    required List<RouteActivitySummary> executions,
    required this.nextCursor,
  }) : executions = List.unmodifiable(executions) {
    UnifiedSwapModelLimits.requireOptionalString(nextCursor, 'nextCursor');
    if (this.executions.length > maximumPageSize) {
      throw RangeError.range(
        this.executions.length,
        0,
        maximumPageSize,
        'executions.length',
      );
    }
    final routeIds = this.executions
        .map((execution) => execution.routeExecutionId)
        .toSet();
    if (routeIds.length != this.executions.length) {
      throw ArgumentError('An activity page must not contain duplicate routes');
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
  identity.contractIdentity,
  identity.rawChainFamilyDiscriminator,
  identity.rawKindDiscriminator,
];

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

bool _isExecutableAddress(UnifiedSwapAssetIdentity asset, String address) =>
    asset.chainFamily != UnifiedSwapChainFamily.evm ||
    RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(address);

void _validateUnknownFeeKind(RouteFeeKind kind, String? rawKindDiscriminator) {
  UnifiedSwapModelLimits.requireRawDiscriminator(
    rawKindDiscriminator,
    'rawKindDiscriminator',
    isUnknown: kind == RouteFeeKind.unknown,
  );
}

void _validateBoundedAsset(UnifiedSwapAssetIdentity asset) {
  if (!asset.hasBoundedIdentity) {
    throw ArgumentError('Asset identity exceeds supported bounds');
  }
}

void _validateUnknownChainFamily(
  UnifiedSwapChainFamily family,
  String? rawDiscriminator,
) {
  UnifiedSwapModelLimits.requireRawDiscriminator(
    rawDiscriminator,
    'rawChainFamilyDiscriminator',
    isUnknown: family == UnifiedSwapChainFamily.unknown,
  );
}

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

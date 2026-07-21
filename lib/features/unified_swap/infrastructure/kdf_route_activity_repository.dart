import 'dart:async';

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as kdf;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/features/unified_swap/domain/route_activity_models.dart';
import 'package:web_dex/features/unified_swap/domain/route_activity_repository.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';

/// Adapts KDF's wallet-scoped Activity journal into customer-domain models.
final class KdfRouteActivityRepository implements RouteActivityRepository {
  KdfRouteActivityRepository({
    required TradeRouteManager manager,
    required String walletId,
  }) : _manager = manager,
       _walletId = walletId {
    if (walletId.trim().isEmpty) {
      throw ArgumentError.value(walletId, 'walletId', 'Must not be empty');
    }
  }

  final TradeRouteManager _manager;
  final String _walletId;

  @override
  Future<RouteActivityPage> listExecutions({
    required String walletId,
    RouteActivityStatus? state,
    String? cursor,
    int limit = 50,
  }) async {
    _validateWalletScope(walletId);
    _validatePageRequest(cursor: cursor, limit: limit);
    final filter = _activityFilter(state);
    try {
      final page = await _manager.listExecutions(
        state: filter,
        cursor: cursor,
        limit: limit,
      );
      return RouteActivityPage(
        executions: page.executions.map(_summaryFromList).toList(),
        nextCursor: page.nextCursor,
      );
    } on RouteActivityException {
      rethrow;
    } on Object catch (error) {
      throw RouteActivityException(_failureFor(error));
    }
  }

  @override
  Future<RouteExecutionDetail> getExecution({
    required String walletId,
    required String routeExecutionId,
  }) async {
    _validateWalletScope(walletId);
    if (routeExecutionId.trim().isEmpty) {
      throw const RouteActivityException(RouteActivityFailure.invalidRequest);
    }
    try {
      final details = await _manager.getExecution(
        routeExecutionId: routeExecutionId,
      );
      return _detail(details);
    } on RouteActivityException {
      rethrow;
    } on Object catch (error) {
      throw RouteActivityException(_failureFor(error));
    }
  }

  void _validateWalletScope(String walletId) {
    if (walletId != _walletId) {
      throw const RouteActivityException(RouteActivityFailure.invalidRequest);
    }
  }
}

RouteActivitySummary _summaryFromList(kdf.RouteExecutionSummary summary) {
  final status = _activityStatus(summary.activityState);
  return RouteActivitySummary(
    routeExecutionId: summary.routeExecutionId,
    status: status.value,
    source: _asset(summary.fromAsset),
    destination: _asset(summary.toAsset),
    createdAt: summary.createdAt,
    updatedAt: summary.updatedAt,
    completedAt: summary.completedAt,
    rawStatusDiscriminator: status.rawDiscriminator,
  );
}

RouteActivitySummary _summaryFromDetails(kdf.RouteExecutionDetails details) {
  final status = _activityStatus(details.activityState);
  final intent = details.routeConsent.routeIntent;
  return RouteActivitySummary(
    routeExecutionId: details.routeExecutionId,
    status: status.value,
    source: _asset(intent.fromAsset),
    destination: _asset(intent.toAsset),
    createdAt: details.createdAt,
    updatedAt: details.updatedAt,
    completedAt: details.completedAt,
    rawStatusDiscriminator: status.rawDiscriminator,
  );
}

RouteExecutionDetail _detail(kdf.RouteExecutionDetails details) {
  final status = details.status;
  return RouteExecutionDetail(
    summary: _summaryFromDetails(details),
    consent: _consent(
      routeExecutionId: details.routeExecutionId,
      consent: details.routeConsent,
      candidate: details.candidate,
      resolvedSourceAddress: details.resolvedSourceAddress,
      recipient: details.recipientAddress,
    ),
    controls: _controls(status.controls),
    holding: _holding(status.actualHolding),
    stages: _stages(status.stageResults),
    revisions: details.routeRevisions
        .map((revision) => _revision(details.routeExecutionId, revision))
        .toList(),
  );
}

RouteExecutionConsent _consent({
  required String routeExecutionId,
  required kdf.RouteActivityConsent consent,
  required kdf.TradeRouteCandidate candidate,
  required String? resolvedSourceAddress,
  required String recipient,
}) {
  final intent = consent.routeIntent;
  final feeLimits = <RouteExecutionFeeLimit>[];
  final networkFeeCaps = <RouteStageNetworkFeeCap>[];
  for (final stageConsent in consent.externalStageConsents) {
    final stageIntent = stageConsent.stageIntent;
    feeLimits.addAll(stageIntent.nonNetworkFeeLimits.map(_feeLimit));
    networkFeeCaps.add(
      RouteStageNetworkFeeCap(
        stageId: stageIntent.stageId,
        asset: _asset(stageIntent.maxTotalNetworkFee.asset),
        maximumAmount: stageIntent.maxTotalNetworkFee.amount,
      ),
    );
  }
  return RouteExecutionConsent(
    routeExecutionId: routeExecutionId,
    consentDigest: consent.routeConsentDigest,
    candidateDigest: consent.candidateDigest,
    source: _asset(intent.fromAsset),
    destination: _asset(intent.toAsset),
    sourceAmount: intent.sourceAmount,
    expectedReceive: candidate.expectedReceive,
    minimumReceive: candidate.minimumReceive,
    fees: candidate.fees.map(_fee).toList(),
    nonNetworkFeeLimits: feeLimits,
    networkFeeCaps: networkFeeCaps,
    resolvedSourceAddress: resolvedSourceAddress,
    recipient: recipient,
  );
}

RouteExecutionRevision _revision(
  String routeExecutionId,
  kdf.RouteActivityRevision revision,
) {
  final phase = _stagePhase(revision.status.routePhase);
  return RouteExecutionRevision(
    revision: revision.revision,
    consent: _consent(
      routeExecutionId: routeExecutionId,
      consent: revision.routeConsent,
      candidate: revision.candidate,
      resolvedSourceAddress: revision.resolvedSourceAddress,
      recipient: revision.routeConsent.routeIntent.recipient,
    ),
    phase: phase.value,
    holding: _holding(revision.status.actualHolding),
    stages: _stages(revision.stages),
    createdAt: revision.status.createdAt,
    updatedAt: revision.status.updatedAt,
    completedAt: revision.status.completedAt,
    archivedAt: revision.archivedAt,
    rawPhaseDiscriminator: phase.rawDiscriminator,
  );
}

List<RouteStageHistoryEntry> _stages(List<kdf.RouteStageResult> stages) => [
  for (var sequence = 0; sequence < stages.length; sequence++)
    _stage(sequence, stages[sequence]),
];

RouteStageHistoryEntry _stage(int sequence, kdf.RouteStageResult stage) {
  final phase = _stagePhase(stage.routePhase);
  return RouteStageHistoryEntry(
    sequence: sequence,
    stageId: stage.stageId,
    phase: phase.value,
    startedAt: stage.startedAt,
    updatedAt: stage.updatedAt,
    completedAt: stage.completedAt,
    transactionHashes: stage.txHashes,
    evidence: _evidence(stage),
    holding: _holding(stage.actualHolding),
    rawPhaseDiscriminator: phase.rawDiscriminator,
  );
}

List<RouteSafeEvidence> _evidence(kdf.RouteStageResult stage) => [
  if (stage.sourceReceipt case final receipt?) _sourceReceipt(receipt),
  if (stage.receivingEvidence case final evidence?)
    _routeEvidence(
      evidence,
      RouteEvidenceKind.receiving,
      providerStatus: stage.rawProviderStatus,
      providerSubstatus: stage.rawProviderSubstatus,
    ),
  if (stage.refundEvidence case final evidence?)
    _routeEvidence(
      evidence,
      RouteEvidenceKind.refund,
      providerStatus: stage.rawProviderStatus,
      providerSubstatus: stage.rawProviderSubstatus,
    ),
  if (stage.rawProviderStatus != null &&
      stage.receivingEvidence is! kdf.ProviderStatusRouteEvidence &&
      stage.refundEvidence is! kdf.ProviderStatusRouteEvidence)
    RouteSafeEvidence(
      kind: RouteEvidenceKind.providerStatus,
      status: stage.rawProviderStatus,
      substatus: stage.rawProviderSubstatus,
    ),
];

RouteSafeEvidence _sourceReceipt(kdf.ChainTxReceipt receipt) {
  if (!receipt.isExecutable) {
    return RouteSafeEvidence(
      kind: RouteEvidenceKind.unknown,
      reference: receipt.txHash,
      rawKindDiscriminator: 'source_receipt',
    );
  }
  return RouteSafeEvidence(
    kind: RouteEvidenceKind.sourceReceipt,
    reference: receipt.txHash,
  );
}

RouteSafeEvidence _routeEvidence(
  kdf.RouteEvidence evidence,
  RouteEvidenceKind contextualKind, {
  String? providerStatus,
  String? providerSubstatus,
}) {
  if (!evidence.isExecutable || evidence is kdf.UnknownRouteEvidence) {
    return RouteSafeEvidence(
      kind: RouteEvidenceKind.unknown,
      reference: _safeEvidenceReference(evidence),
      rawKindDiscriminator: evidence.evidenceType,
    );
  }
  return RouteSafeEvidence(
    kind: evidence is kdf.ProviderStatusRouteEvidence
        ? RouteEvidenceKind.providerStatus
        : contextualKind,
    reference: _safeEvidenceReference(evidence),
    status: evidence is kdf.ProviderStatusRouteEvidence ? providerStatus : null,
    substatus: evidence is kdf.ProviderStatusRouteEvidence
        ? providerSubstatus
        : null,
  );
}

String? _safeEvidenceReference(kdf.RouteEvidence evidence) =>
    switch (evidence) {
      kdf.ExternalActionRouteEvidence(:final actionDigest) => actionDigest,
      kdf.SourceTransactionRouteEvidence(:final txHash) => txHash,
      kdf.AtomicSwapRouteEvidence(
        :final spendTransactionHash,
        :final swapUuid,
      ) =>
        spendTransactionHash ?? swapUuid,
      kdf.ProviderStatusRouteEvidence(:final receiving, :final sending) =>
        receiving?.txHash ?? sending?.txHash,
      kdf.ProviderTransferRouteEvidence(:final transfer) => transfer.txHash,
      kdf.UnknownRouteEvidence() => null,
    };

RouteHolding? _holding(kdf.AssetHolding? holding) => holding == null
    ? null
    : RouteHolding(
        asset: _asset(holding.asset),
        amount: holding.amount,
        address: holding.address,
      );

RouteControlCapabilities _controls(kdf.RouteControlCapabilities controls) =>
    RouteControlCapabilities(
      canCancel: controls.canCancel,
      canStopAfterCurrent: controls.canStopAfterCurrent,
      reconciliationOnly: controls.reconciliationOnly,
    );

RouteExecutionFee _fee(kdf.FeeComponent fee) {
  final kind = _feeKind(fee.feeTypeValue);
  return RouteExecutionFee(
    kind: kind.value,
    asset: _asset(fee.asset),
    amount: fee.amount,
    included: fee.included,
    rawKindDiscriminator: kind.rawDiscriminator,
  );
}

RouteExecutionFeeLimit _feeLimit(kdf.FeeLimit limit) {
  final kind = _feeKind(limit.feeTypeValue);
  return RouteExecutionFeeLimit(
    kind: kind.value,
    asset: _asset(limit.asset),
    maximumAmount: limit.maxAmount,
    rawKindDiscriminator: kind.rawDiscriminator,
  );
}

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

({RouteActivityStatus value, String? rawDiscriminator}) _activityStatus(
  kdf.WireEnumValue<kdf.RouteActivityState> status,
) => switch (status.knownValue) {
  kdf.RouteActivityState.active => (
    value: RouteActivityStatus.active,
    rawDiscriminator: null,
  ),
  kdf.RouteActivityState.attentionRequired => (
    value: RouteActivityStatus.attentionRequired,
    rawDiscriminator: null,
  ),
  kdf.RouteActivityState.completed => (
    value: RouteActivityStatus.completed,
    rawDiscriminator: null,
  ),
  kdf.RouteActivityState.cancelled => (
    value: RouteActivityStatus.cancelled,
    rawDiscriminator: null,
  ),
  kdf.RouteActivityState.failed => (
    value: RouteActivityStatus.failed,
    rawDiscriminator: null,
  ),
  null => (
    value: RouteActivityStatus.unknown,
    rawDiscriminator: status.rawValue,
  ),
};

({RouteStagePhase value, String? rawDiscriminator}) _stagePhase(
  kdf.WireEnumValue<kdf.RoutePhase> phase,
) => switch (phase.knownValue) {
  kdf.RoutePhase.validating => (
    value: RouteStagePhase.preparing,
    rawDiscriminator: null,
  ),
  kdf.RoutePhase.executingStage ||
  kdf.RoutePhase.waitingSourceReceipt ||
  kdf.RoutePhase.atomicFill => (
    value: RouteStagePhase.sending,
    rawDiscriminator: null,
  ),
  kdf.RoutePhase.waitingDestination => (
    value: RouteStagePhase.receiving,
    rawDiscriminator: null,
  ),
  kdf.RoutePhase.stopAfterCurrent => (
    value: RouteStagePhase.reconciliation,
    rawDiscriminator: null,
  ),
  kdf.RoutePhase.awaitingUserAction ||
  kdf.RoutePhase.manualIntervention ||
  kdf.RoutePhase.partial ||
  kdf.RoutePhase.refundPending ||
  kdf.RoutePhase.refunded => (
    value: RouteStagePhase.recovery,
    rawDiscriminator: null,
  ),
  kdf.RoutePhase.completed => (
    value: RouteStagePhase.completed,
    rawDiscriminator: null,
  ),
  kdf.RoutePhase.cancelled => (
    value: RouteStagePhase.cancelled,
    rawDiscriminator: null,
  ),
  kdf.RoutePhase.failed => (
    value: RouteStagePhase.failed,
    rawDiscriminator: null,
  ),
  null => (value: RouteStagePhase.unknown, rawDiscriminator: phase.rawValue),
};

({RouteFeeKind value, String? rawDiscriminator}) _feeKind(
  kdf.WireEnumValue<kdf.FeeType> kind,
) => switch (kind.knownValue) {
  kdf.FeeType.provider => (
    value: RouteFeeKind.provider,
    rawDiscriminator: null,
  ),
  kdf.FeeType.bridge => (value: RouteFeeKind.bridge, rawDiscriminator: null),
  kdf.FeeType.exchange => (
    value: RouteFeeKind.exchange,
    rawDiscriminator: null,
  ),
  kdf.FeeType.network => (value: RouteFeeKind.network, rawDiscriminator: null),
  kdf.FeeType.kdf => (value: RouteFeeKind.kdf, rawDiscriminator: null),
  null => (value: RouteFeeKind.unknown, rawDiscriminator: kind.rawValue),
};

kdf.RouteActivityState? _activityFilter(RouteActivityStatus? state) {
  if (state == null) return null;
  return switch (state) {
    RouteActivityStatus.active => kdf.RouteActivityState.active,
    RouteActivityStatus.attentionRequired =>
      kdf.RouteActivityState.attentionRequired,
    RouteActivityStatus.completed => kdf.RouteActivityState.completed,
    RouteActivityStatus.cancelled => kdf.RouteActivityState.cancelled,
    RouteActivityStatus.failed => kdf.RouteActivityState.failed,
    RouteActivityStatus.unknown => throw const RouteActivityException(
      RouteActivityFailure.invalidRequest,
    ),
  };
}

void _validatePageRequest({required String? cursor, required int limit}) {
  if (cursor != null && cursor.isEmpty) {
    throw const RouteActivityException(RouteActivityFailure.invalidCursor);
  }
  if (limit < 1 || limit > 100) {
    throw const RouteActivityException(RouteActivityFailure.invalidRequest);
  }
}

RouteActivityFailure _failureFor(Object error) {
  String? errorType;
  Object? errorData;
  if (error is kdf.GeneralErrorResponse) {
    errorType = error.errorType;
    errorData = error.errorData;
  } else if (error is kdf.MmRpcException) {
    errorType = error.errorType;
  }

  if (errorType == 'InvalidRequest') {
    if (errorData is Map && errorData['field'] == 'cursor') {
      return RouteActivityFailure.invalidCursor;
    }
    return RouteActivityFailure.invalidRequest;
  }
  if (errorType == 'RouteNotFound' || errorType == 'ExecutionNotFound') {
    return RouteActivityFailure.notFound;
  }
  if (errorType == 'PersistenceError') {
    return RouteActivityFailure.storageUnavailable;
  }
  if (const {
    'Transport',
    'Timeout',
    'ProviderTransport',
    'ProviderRateLimited',
    'ProviderRejected',
    'ProviderResponseInvalid',
    'ChainTransport',
    'ChainResponseInvalid',
    'BroadcastFailed',
    'SigningFailed',
    'Internal',
  }.contains(errorType)) {
    return RouteActivityFailure.serviceUnavailable;
  }
  if (error is TimeoutException ||
      error is FormatException ||
      error is StateError ||
      error is ArgumentError ||
      error is TradeRouteManagerException) {
    return RouteActivityFailure.serviceUnavailable;
  }
  return RouteActivityFailure.unknown;
}

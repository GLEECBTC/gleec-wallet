import 'dart:async';

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as kdf;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/features/unified_swap/domain/route_activity_models.dart';
import 'package:web_dex/features/unified_swap/domain/route_activity_repository.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_model_limits.dart';

/// User-visible Activity journal reads must finish before the presentation
/// layer's 30-second refresh guard. A timeout never changes execution state;
/// it only reports the journal service as temporarily unavailable.
const _activityReadDeadline = Duration(seconds: 15);

typedef KdfCurrentWalletId = Future<String?> Function();

/// Adapts KDF's wallet-scoped Activity journal into customer-domain models.
final class KdfRouteActivityRepository implements RouteActivityRepository {
  KdfRouteActivityRepository({
    required TradeRouteManager manager,
    required String walletId,
    required KdfCurrentWalletId currentWalletId,
  }) : _manager = manager,
       _walletId = walletId,
       _currentWalletId = currentWalletId {
    UnifiedSwapModelLimits.requireString(walletId, 'walletId');
  }

  final TradeRouteManager _manager;
  final String _walletId;
  final KdfCurrentWalletId _currentWalletId;

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
    final budget = _ActivityReadBudget();
    try {
      await _requireCurrentWallet(walletId, budget);
      final page = await budget.run(
        () => _manager.listExecutions(
          state: filter,
          cursor: cursor,
          limit: limit,
        ),
      );
      await _requireCurrentWallet(walletId, budget);
      if (page.executions.length > limit) {
        throw const RouteActivityException(
          RouteActivityFailure.serviceUnavailable,
        );
      }
      if (cursor != null && page.nextCursor == cursor) {
        throw const RouteActivityException(RouteActivityFailure.invalidCursor);
      }
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
    if (!UnifiedSwapModelLimits.isCanonicalString(routeExecutionId)) {
      throw const RouteActivityException(RouteActivityFailure.invalidRequest);
    }
    final budget = _ActivityReadBudget();
    try {
      await _requireCurrentWallet(walletId, budget);
      final details = await budget.run(
        () => _manager.getExecution(routeExecutionId: routeExecutionId),
      );
      await _requireCurrentWallet(walletId, budget);
      if (details.routeExecutionId != routeExecutionId) {
        throw const RouteActivityException(
          RouteActivityFailure.serviceUnavailable,
        );
      }
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

  Future<void> _requireCurrentWallet(
    String walletId,
    _ActivityReadBudget budget,
  ) async {
    final currentWalletId = await budget.run(_currentWalletId);
    if (currentWalletId != _walletId || currentWalletId != walletId) {
      throw const RouteActivityException(RouteActivityFailure.invalidRequest);
    }
  }
}

final class _ActivityReadBudget {
  _ActivityReadBudget() : _clock = Stopwatch()..start();

  final Stopwatch _clock;

  Future<T> run<T>(Future<T> Function() operation) {
    final remaining = _activityReadDeadline - _clock.elapsed;
    if (remaining <= Duration.zero) {
      return Future<T>.error(
        TimeoutException('Activity read deadline elapsed'),
      );
    }
    return operation().timeout(remaining);
  }
}

RouteActivitySummary _summaryFromList(kdf.RouteExecutionSummary summary) {
  final status = _activityStatus(summary.activityState);
  return RouteActivitySummary(
    routeExecutionId: summary.routeExecutionId,
    status: status.value,
    source: _asset(summary.fromAsset),
    destination: _asset(summary.toAsset),
    sourceAmount: summary.sourceAmount,
    expectedReceive: summary.expectedReceive,
    minimumReceive: summary.minimumReceive,
    createdAt: summary.createdAt,
    updatedAt: summary.updatedAt,
    completedAt: summary.completedAt,
    requiresUserAttention: summary.requiresUserAttention,
    requiresUserAction: summary.requiresUserAction,
    terminalError: _terminalError(summary.terminalError),
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
    sourceAmount: intent.sourceAmount,
    expectedReceive: details.candidate.expectedReceive,
    minimumReceive: details.candidate.minimumReceive,
    createdAt: details.createdAt,
    updatedAt: details.updatedAt,
    completedAt: details.completedAt,
    requiresUserAttention:
        status.value == RouteActivityStatus.attentionRequired,
    requiresUserAction: details.status.pendingUserAction != null,
    terminalError: _terminalError(details.terminalError),
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
    stages: _stages(details.candidate.stages, status.stageResults),
    revisions: details.routeRevisions
        .map((revision) => _revision(details.routeExecutionId, revision))
        .toList(),
    authoritativeStatus: _authoritativeStatus(status),
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
    feeLimits.addAll(
      stageIntent.nonNetworkFeeLimits.map(
        (limit) => _feeLimit(limit, stageId: stageIntent.stageId),
      ),
    );
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
    stages: _stages(revision.candidate.stages, revision.stages),
    createdAt: revision.status.createdAt,
    updatedAt: revision.status.updatedAt,
    completedAt: revision.status.completedAt,
    archivedAt: revision.archivedAt,
    authoritativeStatus: _authoritativeStatus(revision.status),
    rawPhaseDiscriminator: phase.rawDiscriminator,
  );
}

List<RouteStageHistoryEntry> _stages(
  List<kdf.RouteStage> planned,
  List<kdf.RouteStageResult> results,
) {
  final sequenceByStageId = <String, int>{};
  for (final (sequence, stage) in planned.indexed) {
    final stageId = switch (stage) {
      kdf.KdfAtomicRouteStage(:final common) => common.stageId,
      kdf.ExternalLiquidityRouteStage(:final common) => common.stageId,
      kdf.UnknownRouteStage() => null,
    };
    if (stageId == null ||
        stageId.trim().isEmpty ||
        sequenceByStageId.containsKey(stageId)) {
      throw StateError('Durable route contains an invalid planned stage set');
    }
    sequenceByStageId[stageId] = sequence;
  }
  if (results.length > planned.length) {
    throw StateError('Durable route contains more results than planned stages');
  }
  final resultIds = <String>{};
  final mapped = <RouteStageHistoryEntry>[];
  for (final result in results) {
    final sequence = sequenceByStageId[result.stageId];
    if (sequence == null || !resultIds.add(result.stageId)) {
      throw StateError(
        'Durable stage result does not map uniquely to its plan',
      );
    }
    mapped.add(_stage(sequence, result));
  }
  return mapped;
}

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

List<RouteSafeEvidence> _statusEvidence(kdf.RouteExecutionStatus status) => [
  if (status.receivingEvidence case final evidence?)
    _routeEvidence(
      evidence,
      RouteEvidenceKind.receiving,
      providerStatus: status.rawProviderStatus,
      providerSubstatus: status.rawProviderSubstatus,
    ),
  if (status.refundEvidence case final evidence?)
    _routeEvidence(
      evidence,
      RouteEvidenceKind.refund,
      providerStatus: status.rawProviderStatus,
      providerSubstatus: status.rawProviderSubstatus,
    ),
  if (status.rawProviderStatus != null &&
      status.receivingEvidence is! kdf.ProviderStatusRouteEvidence &&
      status.refundEvidence is! kdf.ProviderStatusRouteEvidence)
    RouteSafeEvidence(
      kind: RouteEvidenceKind.providerStatus,
      status: status.rawProviderStatus,
      substatus: status.rawProviderSubstatus,
    ),
];

RouteSafeEvidence _sourceReceipt(kdf.ChainTxReceipt receipt) {
  final mapped = _transactionReceipt(receipt);
  return RouteSafeEvidence(
    kind: mapped.isExecutable
        ? RouteEvidenceKind.sourceReceipt
        : RouteEvidenceKind.unknown,
    reference: receipt.txHash,
    receipt: mapped,
    rawKindDiscriminator: mapped.isExecutable ? null : 'source_receipt',
  );
}

RouteSafeEvidence _routeEvidence(
  kdf.RouteEvidence evidence,
  RouteEvidenceKind contextualKind, {
  String? providerStatus,
  String? providerSubstatus,
}) {
  final state = _evidenceState(evidence);
  final provider = _providerEvidence(evidence);
  final executable =
      evidence.isExecutable &&
      evidence is! kdf.UnknownRouteEvidence &&
      state.value != RouteEvidenceState.unknown &&
      (provider?.isExecutable ?? true);
  return RouteSafeEvidence(
    kind: executable
        ? evidence is kdf.ProviderStatusRouteEvidence
              ? RouteEvidenceKind.providerStatus
              : contextualKind
        : RouteEvidenceKind.unknown,
    reference: _safeEvidenceReference(evidence),
    secondaryReference: switch (evidence) {
      kdf.AtomicSwapRouteEvidence(
        :final spendTransactionHash,
        :final swapUuid,
      ) =>
        spendTransactionHash == null ? null : swapUuid,
      _ => null,
    },
    status: providerStatus,
    substatus: providerSubstatus,
    state: state.value,
    provider: provider,
    rawKindDiscriminator: executable ? null : evidence.evidenceType,
    rawStateDiscriminator: state.rawDiscriminator,
  );
}

RouteTransactionReceipt _transactionReceipt(kdf.ChainTxReceipt receipt) {
  final chain = _chainFamily(receipt.chainFamilyValue);
  final status = _transactionStatus(receipt.statusValue);
  return RouteTransactionReceipt(
    chainFamily: chain.value,
    chainId: receipt.chainId,
    transactionHash: receipt.txHash,
    status: status.value,
    confirmations: receipt.confirmations,
    blockHash: receipt.blockHash,
    blockHeight: receipt.blockHeight,
    gasUsed: receipt.gasUsed,
    effectiveGasPrice: receipt.effectiveGasPrice,
    networkFee: receipt.networkFee == null
        ? null
        : RouteEvidenceAssetAmount(
            asset: _asset(receipt.networkFee!.asset),
            amount: receipt.networkFee!.amount,
          ),
    revertReason: receipt.revertReason,
    observedAt: receipt.observedAt,
    rawChainFamilyDiscriminator: chain.rawDiscriminator,
    rawStatusDiscriminator: status.rawDiscriminator,
  );
}

({RouteEvidenceState? value, String? rawDiscriminator}) _evidenceState(
  kdf.RouteEvidence evidence,
) => switch (evidence) {
  kdf.SourceTransactionRouteEvidence(:final state) =>
    switch (state.knownValue) {
      kdf.SourceTransactionEvidenceState.broadcast => (
        value: RouteEvidenceState.broadcast,
        rawDiscriminator: null,
      ),
      kdf.SourceTransactionEvidenceState.confirmed => (
        value: RouteEvidenceState.confirmed,
        rawDiscriminator: null,
      ),
      null => (
        value: RouteEvidenceState.unknown,
        rawDiscriminator: state.rawValue,
      ),
    },
  kdf.AtomicSwapRouteEvidence(:final state) => switch (state.knownValue) {
    kdf.AtomicSwapEvidenceState.published => (
      value: RouteEvidenceState.published,
      rawDiscriminator: null,
    ),
    kdf.AtomicSwapEvidenceState.temporarilyUnavailable => (
      value: RouteEvidenceState.temporarilyUnavailable,
      rawDiscriminator: null,
    ),
    kdf.AtomicSwapEvidenceState.invalidEvidence => (
      value: RouteEvidenceState.invalidEvidence,
      rawDiscriminator: null,
    ),
    kdf.AtomicSwapEvidenceState.failed => (
      value: RouteEvidenceState.failed,
      rawDiscriminator: null,
    ),
    kdf.AtomicSwapEvidenceState.completed => (
      value: RouteEvidenceState.completed,
      rawDiscriminator: null,
    ),
    null => (
      value: RouteEvidenceState.unknown,
      rawDiscriminator: state.rawValue,
    ),
  },
  _ => (value: null, rawDiscriminator: null),
};

RouteProviderEvidence? _providerEvidence(kdf.RouteEvidence evidence) =>
    switch (evidence) {
      kdf.ProviderStatusRouteEvidence(
        :final provider,
        :final transactionId,
        :final tool,
        :final fromAddress,
        :final toAddress,
        :final sending,
        :final receiving,
        :final receivingChain,
      ) =>
        RouteProviderEvidence(
          provider: provider.rawValue,
          providerKnown: provider.isKnown,
          transactionId: transactionId,
          tool: tool,
          fromAddress: fromAddress,
          toAddress: toAddress,
          receivingProviderChainId: receivingChain?.providerChainId,
          transfers: [
            if (sending != null)
              _transfer(sending, RouteEvidenceTransferDirection.sending),
            if (receiving != null)
              _transfer(receiving, RouteEvidenceTransferDirection.receiving),
          ],
        ),
      kdf.ProviderTransferRouteEvidence(:final provider, :final transfer) =>
        RouteProviderEvidence(
          provider: provider.rawValue,
          providerKnown: provider.isKnown,
          transfers: [
            _transfer(transfer, RouteEvidenceTransferDirection.transfer),
          ],
        ),
      _ => null,
    };

RouteEvidenceTransfer _transfer(
  kdf.RouteTransferEvidence transfer,
  RouteEvidenceTransferDirection direction,
) => RouteEvidenceTransfer(
  direction: direction,
  transactionHash: transfer.txHash,
  chainId: transfer.chainId,
  amount: transfer.amount,
  asset: transfer.token == null
      ? null
      : RouteEvidenceTransferAsset(
          providerChainId: transfer.token!.providerChainId,
          tokenIdentifier: transfer.token!.tokenIdentifier,
          decimals: transfer.token!.decimals,
          symbol: transfer.token!.symbol,
        ),
);

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

RouteExecutionFeeLimit _feeLimit(kdf.FeeLimit limit, {String? stageId}) {
  final kind = _feeKind(limit.feeTypeValue);
  return RouteExecutionFeeLimit(
    stageId: stageId,
    kind: kind.value,
    asset: _asset(limit.asset),
    maximumAmount: limit.maxAmount,
    rawKindDiscriminator: kind.rawDiscriminator,
  );
}

RouteTerminalError? _terminalError(kdf.RouteRpcError? error) => error == null
    ? null
    : RouteTerminalError(type: error.rawDiscriminator, isKnown: error.isKnown);

RouteAuthoritativeStatus _authoritativeStatus(kdf.RouteExecutionStatus status) {
  final executionPhase = _executionPhase(status.phase);
  final routePhase = _executionRoutePhase(status.routePhase);
  return RouteAuthoritativeStatus(
    executionPhase: executionPhase.value,
    routePhase: routePhase.value,
    stateRevision: status.stateRevision,
    stageIndex: status.stageIndex,
    stopAfterCurrent: status.stopAfterCurrent,
    transactionHashes: status.txHashes,
    evidence: _statusEvidence(status),
    approvalRecovery: _approvalRecovery(status.approvalRecovery),
    updatedAt: status.updatedAt,
    completedAt: status.completedAt,
    rawExecutionPhaseDiscriminator: executionPhase.rawDiscriminator,
    rawRoutePhaseDiscriminator: routePhase.rawDiscriminator,
  );
}

RouteApprovalRecovery? _approvalRecovery(kdf.ApprovalRecovery? recovery) {
  if (recovery == null) return null;
  final instruction = switch (recovery.instructionValue.knownValue) {
    kdf.ApprovalRecoveryInstruction.revokeAllowanceBeforeRetry => (
      value: RouteApprovalRecoveryInstruction.revokeAllowanceBeforeRetry,
      rawDiscriminator: null,
    ),
    kdf.ApprovalRecoveryInstruction.noAllowanceRemains => (
      value: RouteApprovalRecoveryInstruction.noAllowanceRemains,
      rawDiscriminator: null,
    ),
    null => (
      value: RouteApprovalRecoveryInstruction.unknown,
      rawDiscriminator: recovery.instructionValue.rawValue,
    ),
  };
  return RouteApprovalRecovery(
    token: _asset(recovery.token),
    validatedSpender: recovery.validatedSpender,
    remainingAllowance: recovery.remainingAllowance,
    instruction: instruction.value,
    rawInstructionDiscriminator: instruction.rawDiscriminator,
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

({UnifiedSwapChainFamily value, String? rawDiscriminator}) _chainFamily(
  kdf.WireEnumValue<kdf.ChainFamily> family,
) => switch (family.knownValue) {
  kdf.ChainFamily.evm => (
    value: UnifiedSwapChainFamily.evm,
    rawDiscriminator: null,
  ),
  kdf.ChainFamily.tvm => (
    value: UnifiedSwapChainFamily.tron,
    rawDiscriminator: null,
  ),
  kdf.ChainFamily.utxo => (
    value: UnifiedSwapChainFamily.utxo,
    rawDiscriminator: null,
  ),
  kdf.ChainFamily.svm => (
    value: UnifiedSwapChainFamily.solana,
    rawDiscriminator: null,
  ),
  kdf.ChainFamily.sui => (
    value: UnifiedSwapChainFamily.sui,
    rawDiscriminator: null,
  ),
  kdf.ChainFamily.mvm => (
    value: UnifiedSwapChainFamily.other,
    rawDiscriminator: null,
  ),
  null => (
    value: UnifiedSwapChainFamily.unknown,
    rawDiscriminator: family.rawValue,
  ),
};

({RouteTransactionStatus value, String? rawDiscriminator}) _transactionStatus(
  kdf.WireEnumValue<kdf.ChainTxStatus> status,
) => switch (status.knownValue) {
  kdf.ChainTxStatus.notFound => (
    value: RouteTransactionStatus.notFound,
    rawDiscriminator: null,
  ),
  kdf.ChainTxStatus.pending => (
    value: RouteTransactionStatus.pending,
    rawDiscriminator: null,
  ),
  kdf.ChainTxStatus.confirmed => (
    value: RouteTransactionStatus.confirmed,
    rawDiscriminator: null,
  ),
  kdf.ChainTxStatus.reverted => (
    value: RouteTransactionStatus.reverted,
    rawDiscriminator: null,
  ),
  null => (
    value: RouteTransactionStatus.unknown,
    rawDiscriminator: status.rawValue,
  ),
};

({RouteActivityExecutionPhase value, String? rawDiscriminator}) _executionPhase(
  kdf.WireEnumValue<kdf.ExecutionPhase> phase,
) => switch (phase.knownValue) {
  kdf.ExecutionPhase.planned => (
    value: RouteActivityExecutionPhase.planned,
    rawDiscriminator: null,
  ),
  kdf.ExecutionPhase.awaitingApproval => (
    value: RouteActivityExecutionPhase.awaitingApproval,
    rawDiscriminator: null,
  ),
  kdf.ExecutionPhase.approvalPending => (
    value: RouteActivityExecutionPhase.approvalPending,
    rawDiscriminator: null,
  ),
  kdf.ExecutionPhase.awaitingUserAction => (
    value: RouteActivityExecutionPhase.awaitingUserAction,
    rawDiscriminator: null,
  ),
  kdf.ExecutionPhase.awaitingSignature => (
    value: RouteActivityExecutionPhase.awaitingSignature,
    rawDiscriminator: null,
  ),
  kdf.ExecutionPhase.signed => (
    value: RouteActivityExecutionPhase.signed,
    rawDiscriminator: null,
  ),
  kdf.ExecutionPhase.broadcasting => (
    value: RouteActivityExecutionPhase.broadcasting,
    rawDiscriminator: null,
  ),
  kdf.ExecutionPhase.sourcePending => (
    value: RouteActivityExecutionPhase.sourcePending,
    rawDiscriminator: null,
  ),
  kdf.ExecutionPhase.sourceConfirmed => (
    value: RouteActivityExecutionPhase.sourceConfirmed,
    rawDiscriminator: null,
  ),
  kdf.ExecutionPhase.bridgePending => (
    value: RouteActivityExecutionPhase.bridgePending,
    rawDiscriminator: null,
  ),
  kdf.ExecutionPhase.destinationConfirmed => (
    value: RouteActivityExecutionPhase.destinationConfirmed,
    rawDiscriminator: null,
  ),
  kdf.ExecutionPhase.refundPending => (
    value: RouteActivityExecutionPhase.refundPending,
    rawDiscriminator: null,
  ),
  kdf.ExecutionPhase.partial => (
    value: RouteActivityExecutionPhase.partial,
    rawDiscriminator: null,
  ),
  kdf.ExecutionPhase.refunded => (
    value: RouteActivityExecutionPhase.refunded,
    rawDiscriminator: null,
  ),
  kdf.ExecutionPhase.manualIntervention => (
    value: RouteActivityExecutionPhase.manualIntervention,
    rawDiscriminator: null,
  ),
  kdf.ExecutionPhase.failed => (
    value: RouteActivityExecutionPhase.failed,
    rawDiscriminator: null,
  ),
  kdf.ExecutionPhase.cancelled => (
    value: RouteActivityExecutionPhase.cancelled,
    rawDiscriminator: null,
  ),
  null => (
    value: RouteActivityExecutionPhase.unknown,
    rawDiscriminator: phase.rawValue,
  ),
};

({RouteExecutionRoutePhase value, String? rawDiscriminator})
_executionRoutePhase(kdf.WireEnumValue<kdf.RoutePhase> phase) =>
    switch (phase.knownValue) {
      kdf.RoutePhase.validating => (
        value: RouteExecutionRoutePhase.validating,
        rawDiscriminator: null,
      ),
      kdf.RoutePhase.executingStage => (
        value: RouteExecutionRoutePhase.executingStage,
        rawDiscriminator: null,
      ),
      kdf.RoutePhase.waitingSourceReceipt => (
        value: RouteExecutionRoutePhase.waitingSourceReceipt,
        rawDiscriminator: null,
      ),
      kdf.RoutePhase.waitingDestination => (
        value: RouteExecutionRoutePhase.waitingDestination,
        rawDiscriminator: null,
      ),
      kdf.RoutePhase.atomicFill => (
        value: RouteExecutionRoutePhase.atomicFill,
        rawDiscriminator: null,
      ),
      kdf.RoutePhase.awaitingUserAction => (
        value: RouteExecutionRoutePhase.awaitingUserAction,
        rawDiscriminator: null,
      ),
      kdf.RoutePhase.stopAfterCurrent => (
        value: RouteExecutionRoutePhase.stopAfterCurrent,
        rawDiscriminator: null,
      ),
      kdf.RoutePhase.manualIntervention => (
        value: RouteExecutionRoutePhase.manualIntervention,
        rawDiscriminator: null,
      ),
      kdf.RoutePhase.partial => (
        value: RouteExecutionRoutePhase.partial,
        rawDiscriminator: null,
      ),
      kdf.RoutePhase.refundPending => (
        value: RouteExecutionRoutePhase.refundPending,
        rawDiscriminator: null,
      ),
      kdf.RoutePhase.refunded => (
        value: RouteExecutionRoutePhase.refunded,
        rawDiscriminator: null,
      ),
      kdf.RoutePhase.completed => (
        value: RouteExecutionRoutePhase.completed,
        rawDiscriminator: null,
      ),
      kdf.RoutePhase.failed => (
        value: RouteExecutionRoutePhase.failed,
        rawDiscriminator: null,
      ),
      kdf.RoutePhase.cancelled => (
        value: RouteExecutionRoutePhase.cancelled,
        rawDiscriminator: null,
      ),
      null => (
        value: RouteExecutionRoutePhase.unknown,
        rawDiscriminator: phase.rawValue,
      ),
    };

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
  if (!UnifiedSwapModelLimits.isOptionalCanonicalString(cursor)) {
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

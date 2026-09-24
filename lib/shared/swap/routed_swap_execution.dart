import 'dart:async';

import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/shared/swap/routed_swap_source.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

/// Executes routed swaps through the SDK and follows them to a terminal
/// outcome.
class RoutedSwapExecutor implements SwapExecutor {
  /// Creates an executor over [manager].
  RoutedSwapExecutor(this.manager, {required SwapNetworks Function() networks})
    : _networks = networks;

  /// The SDK manager.
  final RoutedSwapManager manager;
  final SwapNetworks Function() _networks;

  @override
  SwapLiquiditySource get source => SwapLiquiditySource.routed;

  @override
  Future<SwapExecutionHandle> start(SwapQuote quote) async {
    final offer = quote.payload;
    if (offer is! RoutedSwapOffer) {
      throw const SwapStartRejectedException(SwapStartRejection.quoteStale);
    }
    final RoutedSwapHandle handle;
    try {
      handle = await manager.start(offer);
    } on RoutedSwapStartUnconfirmedException catch (error) {
      throw SwapStartUnconfirmedException(error.cause);
    } on RoutedSwapRpcException catch (error) {
      throw SwapStartRejectedException(switch (error) {
        RoutedSwapCoinNotActiveException() ||
        RoutedSwapPairNotSupportedException() ||
        RoutedSwapAmountOutOfBoundsException() ||
        RoutedSwapInvalidParamException() ||
        RoutedSwapMyAddressException() => SwapStartRejection.notAvailable,
        _ => SwapStartRejection.unknown,
      }, detail: '${error.errorType}: ${error.message}');
    }
    return _handleFor(handle, accepted: quote);
  }

  @override
  Future<SwapExecutionHandle?> resume(String id) async {
    try {
      return _handleFor(await manager.watch(id));
    } on RoutedSwapNotFoundException {
      return null;
    }
  }

  SwapExecutionHandle _handleFor(
    RoutedSwapHandle handle, {
    SwapQuote? accepted,
  }) {
    SwapExecutionSnapshot map(RoutedSwapProgress progress) =>
        routedSnapshotFrom(progress, networks: _networks(), accepted: accepted);
    return StreamSwapExecutionHandle(
      initial: map(handle.latest),
      source: handle.progress.map(map),
      cancel: () async {
        try {
          await handle.cancel();
        } on RoutedSwapNotCancellableException catch (error) {
          throw SwapCancelRefusedException(switch (error.refusal) {
            RoutedSwapCancelRefusal.alreadyBroadcast =>
              SwapCancelRefusal.alreadySent,
            RoutedSwapCancelRefusal.alreadyFinished =>
              SwapCancelRefusal.alreadyFinished,
            RoutedSwapCancelRefusal.notAddressable =>
              SwapCancelRefusal.notSupported,
          });
        } on RoutedSwapCancelUnconfirmedException catch (error) {
          throw SwapCancelUnconfirmedException(error.cause);
        }
      },
    );
  }
}

/// Describes a routed swap's [progress] as a [SwapExecutionSnapshot].
///
/// [accepted] is the quote the user consented to, when the swap was started in
/// this session; its figures stand in for fields the durable record does not
/// carry.
SwapExecutionSnapshot routedSnapshotFrom(
  RoutedSwapProgress progress, {
  required SwapNetworks networks,
  SwapQuote? accepted,
}) {
  final offer = progress.offer;
  final plan = offer == null
      ? accepted
      : routedQuoteFromOffer(offer, networks: networks);
  final requested = progress.requested;
  final receipt = progress.receipt;
  final failure = progress.failure;
  final approved = progress.approvalTxHashes.isNotEmpty;

  final outcome = switch ((receipt, failure)) {
    (final RoutedSwapReceipt receipt, _) => SwapExecutionOutcome(
      kind: switch (receipt.outcome) {
        RoutedSwapOutcome.completed => SwapOutcomeKind.completed,
        RoutedSwapOutcome.refunded => SwapOutcomeKind.refunded,
        RoutedSwapOutcome.partial =>
          receipt.partialReason == RoutedSwapPartialReason.belowMinimum
              ? SwapOutcomeKind.partialBelowMinimum
              : SwapOutcomeKind.partialOtherToken,
        // An outcome this build cannot interpret must never read as success.
        RoutedSwapOutcome.unknown => SwapOutcomeKind.partialOtherToken,
      },
      receivedAmount: receipt.amount,
      receivedAsset: receipt.assetId,
      receivedSymbol: receipt.assetId == null ? receipt.symbol : null,
    ),
    (_, final RoutedSwapFailure failure) => SwapExecutionOutcome(
      kind: failure.kind == RoutedSwapFailureKind.cancelled
          ? SwapOutcomeKind.cancelled
          : SwapOutcomeKind.failed,
      failure: failure.kind == RoutedSwapFailureKind.cancelled
          ? null
          : _failureOf(failure, networks: networks, accepted: accepted),
    ),
    _ => null,
  };

  final movement = switch ((receipt, failure)) {
    (RoutedSwapReceipt(), _) => SwapFundsMovement.sent,
    (_, final RoutedSwapFailure failure) => switch (failure.fundsMovement) {
      RoutedSwapFundsMovement.none => SwapFundsMovement.none,
      RoutedSwapFundsMovement.feesOnly => SwapFundsMovement.feesOnly,
      RoutedSwapFundsMovement.uncertain => SwapFundsMovement.uncertain,
      RoutedSwapFundsMovement.sent => SwapFundsMovement.sent,
    },
    _ => switch (progress.phase) {
      RoutedSwapPhase.preparing || RoutedSwapPhase.signing =>
        approved ? SwapFundsMovement.feesOnly : SwapFundsMovement.none,
      // An approval in flight spends gas, never the sold amount.
      RoutedSwapPhase.approving => SwapFundsMovement.feesOnly,
      RoutedSwapPhase.sending => SwapFundsMovement.uncertain,
      RoutedSwapPhase.confirming ||
      RoutedSwapPhase.bridging => SwapFundsMovement.sent,
      _ => SwapFundsMovement.uncertain,
    },
  };

  final stage = outcome != null
      ? null
      : switch (progress.phase) {
          RoutedSwapPhase.preparing => SwapProgressStage.preparing,
          RoutedSwapPhase.approving => SwapProgressStage.approving,
          RoutedSwapPhase.signing => SwapProgressStage.signing,
          RoutedSwapPhase.sending => SwapProgressStage.sending,
          RoutedSwapPhase.confirming => SwapProgressStage.confirming,
          RoutedSwapPhase.bridging => switch (progress.bridgeStage) {
            RoutedSwapBridgeStage.destinationPending =>
              SwapProgressStage.awaitingDelivery,
            RoutedSwapBridgeStage.refundPending => SwapProgressStage.refunding,
            RoutedSwapBridgeStage.actionRequired =>
              SwapProgressStage.actionRequired,
            _ => SwapProgressStage.bridging,
          },
          _ => SwapProgressStage.unknown,
        };

  // A permission granted for a swap that then did not spend it stays on-chain.
  final approvalRemains =
      approved &&
      outcome != null &&
      (outcome.kind == SwapOutcomeKind.cancelled ||
          (outcome.kind == SwapOutcomeKind.failed &&
              (movement == SwapFundsMovement.none ||
                  movement == SwapFundsMovement.feesOnly)));

  return SwapExecutionSnapshot(
    id: progress.uuid,
    source: SwapLiquiditySource.routed,
    routeKind:
        plan?.routeKind ??
        (requested != null &&
                requested.from != null &&
                requested.to != null &&
                networks.networkOf(requested.from!) ==
                    networks.networkOf(requested.to!)
            ? SwapRouteKind.sameChain
            : SwapRouteKind.crossChain),
    from: plan?.from ?? requested?.from,
    fromTicker: plan?.from.id ?? requested?.fromTicker ?? '',
    to: plan?.to ?? requested?.to,
    toTicker: plan?.to.id ?? requested?.toTicker ?? '',
    sellAmount: plan?.sellAmount ?? requested?.amount,
    expectedReceive: plan?.expectedReceive,
    minimumReceive: progress.minToAmountAccepted ?? plan?.guaranteedReceive,
    fromAddress: plan?.fromAddress,
    toAddress: plan?.toAddress,
    stage: stage,
    outcome: outcome,
    fundsMovement: movement,
    canCancel: progress.canCancel,
    approval: plan?.approval,
    approvalRemains: approvalRemains,
    stages: plan?.stages ?? const [],
    estimatedDuration: progress.estimatedDuration ?? plan?.estimatedDuration,
    createdAt: progress.createdAt,
    updatedAt: progress.updatedAt,
    finishedAt: progress.finishedAt,
    delayedSince: progress.delayedSince,
    evidence: SwapEvidence(
      executionId: progress.uuid,
      approvalTxHashes: progress.approvalTxHashes,
      sourceTxHash: progress.sourceTxHash,
      destinationTxHash: progress.destinationTxHash,
      providerExplorerUrl: progress.explorerUrl,
      providerRequestId: failure?.providerRequestId,
      providerStatus: progress.providerStatusDetail,
      rawState: progress.rawState,
      errorType: failure?.errorType,
      diagnostic: plan?.diagnostic,
      gasSpent: [
        for (final gas in progress.gasSpent)
          SwapGasSpent(
            ticker: gas.ticker,
            asset: gas.assetId,
            amount: gas.amount,
            txHash: gas.txHash,
          ),
      ],
    ),
  );
}

SwapExecutionFailure _failureOf(
  RoutedSwapFailure failure, {
  required SwapNetworks networks,
  SwapQuote? accepted,
}) {
  final fresh = failure.freshOffer;
  return SwapExecutionFailure(
    reason: switch (failure.kind) {
      RoutedSwapFailureKind.priceMoved => SwapFailureReason.priceMoved,
      RoutedSwapFailureKind.insufficientBalance =>
        SwapFailureReason.insufficientBalance,
      RoutedSwapFailureKind.approvalFailed => SwapFailureReason.approvalFailed,
      RoutedSwapFailureKind.swapTransactionFailed =>
        failure.txFailureReason ==
                RoutedSwapTxFailureReason.sourceTransactionReverted
            ? SwapFailureReason.reverted
            : SwapFailureReason.notConfirmed,
      RoutedSwapFailureKind.signingRejected => SwapFailureReason.walletRejected,
      RoutedSwapFailureKind.bridgeFailed => SwapFailureReason.routeFailed,
      RoutedSwapFailureKind.preflightRejected => SwapFailureReason.safetyCheck,
      RoutedSwapFailureKind.quoteUnavailable =>
        SwapFailureReason.quoteUnavailable,
      RoutedSwapFailureKind.abortedOnRestart => SwapFailureReason.restarted,
      RoutedSwapFailureKind.internalError => SwapFailureReason.internal,
      RoutedSwapFailureKind.cancelled ||
      RoutedSwapFailureKind.unknown => SwapFailureReason.unknown,
    },
    nextStep: switch (failure.retryPolicy) {
      RoutedSwapRetryPolicy.retry => SwapNextStep.retry,
      RoutedSwapRetryPolicy.requote => SwapNextStep.requote,
      RoutedSwapRetryPolicy.fixAndRetry => SwapNextStep.fixAndRetry,
      RoutedSwapRetryPolicy.wait => SwapNextStep.wait,
      RoutedSwapRetryPolicy.contactSupport => SwapNextStep.contactSupport,
    },
    retryable: failure.preflightCheck?.isRetryable ?? failure.isRetryable,
    shortfallAsset: failure.shortfall?.assetId,
    shortfallTicker: failure.shortfall?.ticker,
    shortfallAvailable: failure.shortfall?.available,
    shortfallRequired: failure.shortfall?.required,
    freshQuote: fresh == null
        ? null
        : routedQuoteFromOffer(
            fresh,
            networks: networks,
            order: accepted?.order,
          ),
    noRouteReasons: failure.noRouteReasons,
    detail: '${failure.errorType}: ${failure.message}',
  );
}

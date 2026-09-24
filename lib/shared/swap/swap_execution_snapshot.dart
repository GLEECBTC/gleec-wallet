import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_execution_outcome.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

export 'package:web_dex/shared/swap/swap_execution_outcome.dart';

/// Where a running swap has got to, in the moments a user distinguishes.
enum SwapProgressStage {
  /// Checking the latest details before anything is signed.
  preparing,

  /// Looking for a peer-to-peer counterparty. Nothing has moved.
  matching,

  /// Sending the exact-amount token permission (after a reset, when the token
  /// needs one). Network fees are being spent; the sold amount is not.
  approving,

  /// Signing locally. Nothing has been sent yet.
  signing,

  /// Handing the transaction to the network. No longer stoppable.
  sending,

  /// Waiting for the source network to confirm.
  confirming,

  /// Moving between networks.
  bridging,

  /// Waiting for delivery on the destination network.
  awaitingDelivery,

  /// The route is refunding on the source network.
  refunding,

  /// The user must act before the swap can continue.
  actionRequired,

  /// Exchanging with a peer-to-peer counterparty.
  exchanging,

  /// A stage this build does not recognise. Tracking continues.
  unknown,
}

/// Whether, and how, the sold funds moved.
enum SwapFundsMovement {
  /// Nothing was broadcast. The balance is unchanged.
  none,

  /// Only network fees were spent. The sold amount never left.
  feesOnly,

  /// The swap transaction may have gone out. Never tell the user the funds
  /// did not move.
  uncertain,

  /// The sold amount left the wallet.
  sent,
}

/// Actual gas paid by one transaction.
class SwapGasSpent extends Equatable {
  const SwapGasSpent({
    required this.ticker,
    required this.amount,
    this.asset,
    this.txHash,
  });

  /// The coin it was paid in.
  final String ticker;

  /// The wallet asset, when the ticker maps to one.
  final AssetId? asset;

  /// How much.
  final Decimal amount;

  /// The transaction, when itemised.
  final String? txHash;

  @override
  List<Object?> get props => [ticker, asset, amount, txHash];
}

/// What a swap left behind as proof: identifiers, hashes and links.
///
/// Support needs this; the user needs to be able to copy it. Addresses and
/// hashes never go to analytics.
class SwapEvidence extends Equatable {
  const SwapEvidence({
    required this.executionId,
    this.approvalTxHashes = const [],
    this.sourceTxHash,
    this.destinationTxHash,
    this.providerExplorerUrl,
    this.providerRequestId,
    this.providerStatus,
    this.rawState,
    this.errorType,
    this.diagnostic,
    this.gasSpent = const [],
  });

  /// The durable swap id.
  final String executionId;

  /// Approval transactions, in order.
  final List<String> approvalTxHashes;

  /// The source transaction.
  final String? sourceTxHash;

  /// The destination transaction.
  final String? destinationTxHash;

  /// The route's explorer link, when one exists.
  final String? providerExplorerUrl;

  /// The provider's support-correlation id.
  final String? providerRequestId;

  /// Opaque provider progress text. Diagnostic only.
  final String? providerStatus;

  /// The engine's raw state, for logs.
  final String? rawState;

  /// The engine's raw error type, for logs.
  final String? errorType;

  /// Infrastructure identity (provider and tool). Diagnostic only.
  final String? diagnostic;

  /// Gas actually paid.
  final List<SwapGasSpent> gasSpent;

  @override
  List<Object?> get props => [
    executionId,
    approvalTxHashes,
    sourceTxHash,
    destinationTxHash,
    providerExplorerUrl,
    providerRequestId,
    providerStatus,
    rawState,
    errorType,
    diagnostic,
    gasSpent,
  ];
}

/// A snapshot of one swap, running or finished, from either source.
///
/// The same type describes a swap started a second ago and one recovered from
/// the durable record after a restart, so no screen has to branch on where the
/// data came from.
class SwapExecutionSnapshot extends Equatable {
  const SwapExecutionSnapshot({
    required this.id,
    required this.source,
    required this.routeKind,
    required this.fromTicker,
    required this.toTicker,
    required this.fundsMovement,
    required this.canCancel,
    required this.evidence,
    this.from,
    this.to,
    this.sellAmount,
    this.expectedReceive,
    this.minimumReceive,
    this.fromAddress,
    this.toAddress,
    this.stage,
    this.outcome,
    this.approval,
    this.approvalRemains = false,
    this.stages = const [],
    this.estimatedDuration,
    this.createdAt,
    this.updatedAt,
    this.finishedAt,
    this.delayedSince,
  });

  /// The durable id.
  final String id;

  /// Which source runs this.
  final SwapLiquiditySource source;

  /// How it completes.
  final SwapRouteKind routeKind;

  /// The asset sold, when it maps to a wallet asset.
  final AssetId? from;

  /// Its ticker.
  final String fromTicker;

  /// The asset bought, when it maps to a wallet asset.
  final AssetId? to;

  /// Its ticker.
  final String toTicker;

  /// How much was sold.
  final Decimal? sellAmount;

  /// The expected receive, when known.
  final Decimal? expectedReceive;

  /// The accepted minimum, when known.
  final Decimal? minimumReceive;

  /// Where the funds were sent from.
  final String? fromAddress;

  /// Where the output lands.
  final String? toAddress;

  /// Where it has got to; null once terminal.
  final SwapProgressStage? stage;

  /// How it ended; null while running.
  final SwapExecutionOutcome? outcome;

  /// Whether the sold funds moved.
  final SwapFundsMovement fundsMovement;

  /// Whether cancelling would currently be accepted.
  final bool canCancel;

  /// The permission the swap needed, if any.
  final SwapApprovalRequirement? approval;

  /// Whether an exact token permission was granted and not used, so it
  /// remains on-chain after the swap stopped.
  final bool approvalRemains;

  /// How the swap completes, step by step.
  final List<SwapRouteStage> stages;

  /// The estimate for the whole swap.
  final Duration? estimatedDuration;

  /// When it started.
  final DateTime? createdAt;

  /// When it last changed.
  final DateTime? updatedAt;

  /// When it finished.
  final DateTime? finishedAt;

  /// Set while status reads are failing; the snapshot may be out of date. A
  /// delay is not a failure.
  final DateTime? delayedSince;

  /// Identifiers, hashes and links.
  final SwapEvidence evidence;

  /// Whether the swap has stopped, either way.
  bool get isTerminal => outcome != null;

  /// Whether it delivered what was asked for.
  bool get isSuccess => outcome?.isSuccess ?? false;

  /// Whether a finished swap needs the user to look at it.
  ///
  /// True for outcomes that are terminal but not what was asked for, for any
  /// failure where the funds may have moved, and where a permission remains —
  /// all of which would otherwise sit among ordinary completions.
  bool get needsAttention {
    final outcome = this.outcome;
    if (outcome == null) return stage == SwapProgressStage.actionRequired;
    return switch (outcome.kind) {
      SwapOutcomeKind.partialBelowMinimum ||
      SwapOutcomeKind.partialOtherToken => true,
      SwapOutcomeKind.completed || SwapOutcomeKind.refunded => false,
      SwapOutcomeKind.noMatch => false,
      SwapOutcomeKind.cancelled => approvalRemains,
      SwapOutcomeKind.failed =>
        fundsMovement != SwapFundsMovement.none || approvalRemains,
    };
  }

  @override
  List<Object?> get props => [
    id,
    source,
    routeKind,
    from,
    fromTicker,
    to,
    toTicker,
    sellAmount,
    expectedReceive,
    minimumReceive,
    fromAddress,
    toAddress,
    stage,
    outcome,
    fundsMovement,
    canCancel,
    approval,
    approvalRemains,
    stages,
    estimatedDuration,
    createdAt,
    updatedAt,
    finishedAt,
    delayedSince,
    evidence,
  ];
}

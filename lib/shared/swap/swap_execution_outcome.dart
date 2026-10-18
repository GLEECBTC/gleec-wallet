import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

/// How a finished swap ended.
enum SwapOutcomeKind {
  /// Delivered the requested asset, at or above the minimum.
  completed,

  /// Delivered the requested asset, but below the accepted minimum.
  partialBelowMinimum,

  /// Delivered a different, intermediate token.
  partialOtherToken,

  /// Did not happen; the funds came back.
  refunded,

  /// Stopped by the user before anything was broadcast.
  cancelled,

  /// No peer-to-peer counterparty matched. Nothing moved.
  noMatch,

  /// Failed. See [SwapExecutionFailure].
  failed,
}

/// What a user can sensibly do next.
enum SwapNextStep {
  /// Starting the same swap again is reasonable.
  retry,

  /// Get a fresh quote first.
  requote,

  /// Fix something outside the swap, usually a balance.
  fixAndRetry,

  /// Wait: the outcome is not settled yet.
  wait,

  /// Hand the evidence to support.
  contactSupport,

  /// Nothing to do.
  none,
}

/// Why a swap failed, in terms the UI can explain.
enum SwapFailureReason {
  /// The price moved below the accepted minimum before anything was sent.
  priceMoved,

  /// Not enough balance, including network fees.
  insufficientBalance,

  /// The token permission failed.
  approvalFailed,

  /// The network rejected the swap transaction.
  reverted,

  /// The transaction did not confirm in time and may still confirm.
  notConfirmed,

  /// A wallet declined or did not answer a signing request.
  walletRejected,

  /// The route failed after funds left, without resolving a refund.
  routeFailed,

  /// A pre-sign safety check blocked the swap.
  safetyCheck,

  /// Pricing failed while the swap was starting.
  quoteUnavailable,

  /// The app or engine restarted before anything was sent.
  restarted,

  /// A peer-to-peer swap failed; its own recovery applies.
  exchangeFailed,

  /// Something went wrong inside the wallet engine.
  internal,

  /// A failure this build does not recognise.
  unknown,
}

/// A failed swap's reason and evidence.
class SwapExecutionFailure extends Equatable {
  const SwapExecutionFailure({
    required this.reason,
    required this.nextStep,
    this.retryable = false,
    this.shortfallAsset,
    this.shortfallTicker,
    this.shortfallAvailable,
    this.shortfallRequired,
    this.freshQuote,
    this.noRouteReasons = const [],
    this.detail,
  });

  /// Why.
  final SwapFailureReason reason;

  /// What to offer next.
  final SwapNextStep nextStep;

  /// For a safety check: whether retrying is reasonable (a stale route) rather
  /// than something to report.
  final bool retryable;

  /// For [SwapFailureReason.insufficientBalance]: the asset that ran short.
  final AssetId? shortfallAsset;

  /// Its ticker, when it does not map to a wallet asset.
  final String? shortfallTicker;

  /// What was available.
  final Decimal? shortfallAvailable;

  /// What was required.
  final Decimal? shortfallRequired;

  /// For [SwapFailureReason.priceMoved]: the re-priced quote to consent to.
  final SwapQuote? freshQuote;

  /// For a missing route: display strings with no stable format.
  final List<String> noRouteReasons;

  /// Diagnostic text from the engine. Never primary copy.
  final String? detail;

  @override
  List<Object?> get props => [
    reason,
    nextStep,
    retryable,
    shortfallAsset,
    shortfallTicker,
    shortfallAvailable,
    shortfallRequired,
    freshQuote,
    noRouteReasons,
    detail,
  ];
}

/// What a finished swap delivered.
class SwapExecutionOutcome extends Equatable {
  const SwapExecutionOutcome({
    required this.kind,
    this.receivedAmount,
    this.receivedAsset,
    this.receivedSymbol,
    this.failure,
  });

  /// How it ended.
  final SwapOutcomeKind kind;

  /// What arrived (or came back, for a refund).
  final Decimal? receivedAmount;

  /// The asset that arrived, when it maps to a wallet asset.
  final AssetId? receivedAsset;

  /// The provider's symbol when it does not. Display-only; never a ticker.
  final String? receivedSymbol;

  /// Set for [SwapOutcomeKind.failed].
  final SwapExecutionFailure? failure;

  /// Whether this is the swap that was asked for.
  bool get isSuccess => kind == SwapOutcomeKind.completed;

  @override
  List<Object?> get props => [
    kind,
    receivedAmount,
    receivedAsset,
    receivedSymbol,
    failure,
  ];
}

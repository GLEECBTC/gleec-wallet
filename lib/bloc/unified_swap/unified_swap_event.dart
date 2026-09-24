import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

/// Base type for swap screen events.
sealed class UnifiedSwapEvent extends Equatable {
  const UnifiedSwapEvent();

  @override
  List<Object?> get props => const [];
}

/// Load what can be traded and open on a sensible pair.
final class UnifiedSwapStarted extends UnifiedSwapEvent {
  const UnifiedSwapStarted();
}

/// Prefill the form from a deep link or another screen's "Swap" action.
final class UnifiedSwapIntentApplied extends UnifiedSwapEvent {
  const UnifiedSwapIntentApplied({this.pay, this.receive, this.amount});

  /// Ticker to pay with.
  final String? pay;

  /// Ticker to receive.
  final String? receive;

  /// Amount to pay, in pay-asset units.
  final String? amount;

  @override
  List<Object?> get props => [pay, receive, amount];
}

/// The user picked the asset to pay with.
final class UnifiedSwapPayAssetChanged extends UnifiedSwapEvent {
  const UnifiedSwapPayAssetChanged(this.asset);

  /// The chosen asset.
  final AssetId asset;

  @override
  List<Object?> get props => [asset];
}

/// The user picked the asset to receive.
final class UnifiedSwapReceiveAssetChanged extends UnifiedSwapEvent {
  const UnifiedSwapReceiveAssetChanged(this.asset);

  /// The chosen asset.
  final AssetId asset;

  @override
  List<Object?> get props => [asset];
}

/// The user swapped the two sides.
final class UnifiedSwapSidesSwitched extends UnifiedSwapEvent {
  const UnifiedSwapSidesSwitched();
}

/// The amount field changed.
final class UnifiedSwapAmountChanged extends UnifiedSwapEvent {
  const UnifiedSwapAmountChanged(this.text);

  /// Raw field text, in the current amount mode.
  final String text;

  @override
  List<Object?> get props => [text];
}

/// Toggle entering the amount in US dollars or in the pay asset.
final class UnifiedSwapAmountModeToggled extends UnifiedSwapEvent {
  const UnifiedSwapAmountModeToggled();
}

/// Fill the amount with everything sellable, keeping what fees need.
final class UnifiedSwapMaxRequested extends UnifiedSwapEvent {
  const UnifiedSwapMaxRequested();
}

/// Evaluate options now: a retry, a refresh, or the debounce firing.
final class UnifiedSwapEvaluationRequested extends UnifiedSwapEvent {
  const UnifiedSwapEvaluationRequested({this.quiet = false});

  /// Keep the current options on screen while re-pricing.
  final bool quiet;

  @override
  List<Object?> get props => [quiet];
}

/// The user chose one of the options.
final class UnifiedSwapOptionSelected extends UnifiedSwapEvent {
  const UnifiedSwapOptionSelected(this.id);

  /// The option's id.
  final String id;

  @override
  List<Object?> get props => [id];
}

/// Open the review.
final class UnifiedSwapReviewOpened extends UnifiedSwapEvent {
  const UnifiedSwapReviewOpened();
}

/// Close the review and return to the form.
final class UnifiedSwapReviewClosed extends UnifiedSwapEvent {
  const UnifiedSwapReviewClosed();
}

/// Start the reviewed swap. Re-prices first.
final class UnifiedSwapStartRequested extends UnifiedSwapEvent {
  const UnifiedSwapStartRequested();
}

/// Start a swap from a re-priced quote the user consented to — after a price
/// move stopped a swap before anything was sent.
final class UnifiedSwapFreshQuoteAccepted extends UnifiedSwapEvent {
  const UnifiedSwapFreshQuoteAccepted(this.quote);

  /// The re-priced quote.
  final SwapQuote quote;

  @override
  List<Object?> get props => [quote];
}

/// Leave the progress screen. The swap keeps running in Activity.
final class UnifiedSwapProgressLeft extends UnifiedSwapEvent {
  const UnifiedSwapProgressLeft();
}

/// Return to an empty form for another swap.
final class UnifiedSwapResetRequested extends UnifiedSwapEvent {
  const UnifiedSwapResetRequested({this.keepPair = true});

  /// Keep the chosen assets.
  final bool keepPair;

  @override
  List<Object?> get props => [keepPair];
}

/// Start a fresh swap selling what an earlier swap delivered — for a
/// different token received, or a refund.
final class UnifiedSwapFollowUpRequested extends UnifiedSwapEvent {
  const UnifiedSwapFollowUpRequested({
    required this.pay,
    this.receive,
    this.amount,
  });

  /// The asset now held.
  final AssetId pay;

  /// The asset originally wanted.
  final AssetId? receive;

  /// How much is held.
  final String? amount;

  @override
  List<Object?> get props => [pay, receive, amount];
}

/// Whether the swap form is on screen. Re-pricing pauses while it is not.
final class UnifiedSwapVisibilityChanged extends UnifiedSwapEvent {
  const UnifiedSwapVisibilityChanged({required this.visible});

  /// Whether visible.
  final bool visible;

  @override
  List<Object?> get props => [visible];
}

/// The trading-availability or clock checks changed.
final class UnifiedSwapCapabilitiesChanged extends UnifiedSwapEvent {
  const UnifiedSwapCapabilitiesChanged({
    required this.tradingEnabled,
    required this.clockValid,
  });

  /// Whether trading is available here.
  final bool tradingEnabled;

  /// Whether the device clock is accurate enough.
  final bool clockValid;

  @override
  List<Object?> get props => [tradingEnabled, clockValid];
}

/// Re-read balances, e.g. after a swap changed them.
final class UnifiedSwapBalancesRefreshed extends UnifiedSwapEvent {
  const UnifiedSwapBalancesRefreshed();
}

/// Re-read what the sources can trade — after a list failed to load, say.
final class UnifiedSwapCatalogRefreshRequested extends UnifiedSwapEvent {
  const UnifiedSwapCatalogRefreshRequested();
}

/// The user activated [asset] from the swap form.
final class UnifiedSwapAssetActivated extends UnifiedSwapEvent {
  const UnifiedSwapAssetActivated(this.asset);

  /// The asset now active.
  final AssetId asset;

  @override
  List<Object?> get props => [asset];
}

/// Internal: the refresh or expiry timer fired.
final class UnifiedSwapTimerFired extends UnifiedSwapEvent {
  const UnifiedSwapTimerFired(this.kind);

  /// Which timer.
  final UnifiedSwapTimerKind kind;

  @override
  List<Object?> get props => [kind];
}

/// The timers the bloc runs.
enum UnifiedSwapTimerKind {
  /// Re-price while the form sits idle.
  refresh,

  /// The quote is too old to review.
  expiry,

  /// A rate-limit pause is over.
  rateLimitOver,
}

import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

/// Base type for swap screen events.
sealed class UnifiedSwapEvent extends Equatable {
  const UnifiedSwapEvent();

  @override
  List<Object?> get props => const [];
}

/// Load the assets that can be traded.
final class UnifiedSwapStarted extends UnifiedSwapEvent {
  const UnifiedSwapStarted();
}

/// The user picked the asset to sell.
final class UnifiedSwapSellAssetChanged extends UnifiedSwapEvent {
  const UnifiedSwapSellAssetChanged(this.asset);

  /// The chosen asset.
  final AssetId asset;

  @override
  List<Object?> get props => [asset];
}

/// The user picked the asset to buy.
final class UnifiedSwapReceiveAssetChanged extends UnifiedSwapEvent {
  const UnifiedSwapReceiveAssetChanged(this.asset);

  /// The chosen asset.
  final AssetId asset;

  @override
  List<Object?> get props => [asset];
}

/// The user swapped the two sides.
final class UnifiedSwapSidesReversed extends UnifiedSwapEvent {
  const UnifiedSwapSidesReversed();
}

/// The amount field changed.
final class UnifiedSwapAmountChanged extends UnifiedSwapEvent {
  const UnifiedSwapAmountChanged(this.amountText);

  /// Raw field text.
  final String amountText;

  @override
  List<Object?> get props => [amountText];
}

/// Fill the amount with everything spendable.
final class UnifiedSwapMaxAmountRequested extends UnifiedSwapEvent {
  const UnifiedSwapMaxAmountRequested();
}

/// Re-price the current form.
final class UnifiedSwapQuoteRequested extends UnifiedSwapEvent {
  const UnifiedSwapQuoteRequested();
}

/// The user chose one of several priced options.
final class UnifiedSwapQuoteSelected extends UnifiedSwapEvent {
  const UnifiedSwapQuoteSelected(this.quote);

  /// The chosen option.
  final SwapQuote quote;

  @override
  List<Object?> get props => [quote];
}

/// Move to the review step.
final class UnifiedSwapReviewRequested extends UnifiedSwapEvent {
  const UnifiedSwapReviewRequested();
}

/// Go back to the form.
final class UnifiedSwapReviewDismissed extends UnifiedSwapEvent {
  const UnifiedSwapReviewDismissed();
}

/// Execute the reviewed offer.
final class UnifiedSwapStartRequested extends UnifiedSwapEvent {
  const UnifiedSwapStartRequested();
}

/// Accept a price that changed during revalidation.
final class UnifiedSwapRepriceAccepted extends UnifiedSwapEvent {
  const UnifiedSwapRepriceAccepted();
}

/// Reject a price that changed during revalidation.
final class UnifiedSwapRepriceRejected extends UnifiedSwapEvent {
  const UnifiedSwapRepriceRejected();
}

/// Stop the running swap.
final class UnifiedSwapCancelRequested extends UnifiedSwapEvent {
  const UnifiedSwapCancelRequested();
}

/// A progress update arrived from the SDK. Internal.
final class UnifiedSwapProgressReceived extends UnifiedSwapEvent {
  const UnifiedSwapProgressReceived(this.progress);

  /// The new snapshot.
  final UnifiedSwapProgress progress;

  @override
  List<Object?> get props => [progress];
}

/// Return the screen to an empty form.
final class UnifiedSwapReset extends UnifiedSwapEvent {
  const UnifiedSwapReset();
}

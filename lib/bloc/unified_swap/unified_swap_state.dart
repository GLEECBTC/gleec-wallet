import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';

/// Where the user is in the swap flow.
enum UnifiedSwapStep {
  /// Choosing assets and an amount.
  fill,

  /// Reviewing a priced offer before committing.
  confirm,

  /// The swap is running.
  inProgress,

  /// The swap finished. Check the receipt — finished is not succeeded.
  complete,

  /// The swap failed.
  failed,
}

/// Why the form cannot be submitted.
enum UnifiedSwapFormError {
  /// No amount entered yet.
  amountMissing,

  /// The amount is not a number.
  amountMalformed,

  /// The amount is zero or negative.
  amountNotPositive,

  /// The amount exceeds the spendable balance.
  amountExceedsBalance,

  /// Both sides are the same asset.
  sameAsset,
}

/// What the quote lookup is doing.
enum UnifiedSwapQuoteStatus {
  /// Nothing requested yet.
  idle,

  /// A lookup is running.
  loading,

  /// At least one source produced a price.
  ready,

  /// No source could price it, but retrying might help.
  unavailable,

  /// No source will ever price this pair.
  unsupported,
}

/// The swap screen's state.
class UnifiedSwapState extends Equatable {
  const UnifiedSwapState({
    this.step = UnifiedSwapStep.fill,
    this.sellAsset,
    this.receiveAsset,
    this.amountText = '',
    this.spendableBalance,
    this.quoteStatus = UnifiedSwapQuoteStatus.idle,
    this.quotes,
    this.selectedQuote,
    this.formError,
    this.tradableAssets = const {},
    this.progress,
    this.isStarting = false,
    this.isRepricing = false,
    this.repricedQuote,
    this.startError,
    this.activeSwapUuid,
  });

  /// Which step the UI is showing.
  final UnifiedSwapStep step;

  /// The asset being sold.
  final AssetId? sellAsset;

  /// The asset being bought.
  final AssetId? receiveAsset;

  /// Raw text from the amount field, kept unparsed so the field never fights
  /// the user mid-entry.
  final String amountText;

  /// How much of [sellAsset] can actually be spent.
  final Decimal? spendableBalance;

  /// What the quote lookup is doing.
  final UnifiedSwapQuoteStatus quoteStatus;

  /// The last completed lookup.
  final UnifiedSwapQuotes? quotes;

  /// The offer the user is acting on.
  final SwapQuote? selectedQuote;

  /// Why the form is not submittable.
  final UnifiedSwapFormError? formError;

  /// Assets at least one source can trade.
  final Set<AssetId> tradableAssets;

  /// Live progress, once a swap is running.
  final RoutedSwapProgress? progress;

  /// Whether a start request is in flight.
  final bool isStarting;

  /// Whether the pre-start revalidation is running.
  final bool isRepricing;

  /// A materially different price found during revalidation.
  ///
  /// While this is set the user must accept the new numbers before the swap
  /// can start. Starting against the old figures would execute a trade they
  /// were never shown.
  final SwapQuote? repricedQuote;

  /// Why starting failed.
  final String? startError;

  /// The durable id of the running swap.
  final String? activeSwapUuid;

  /// The parsed amount, or null when the text is not a usable number.
  Decimal? get amount {
    final trimmed = amountText.trim();
    if (trimmed.isEmpty) return null;
    return Decimal.tryParse(trimmed);
  }

  /// Whether the form has everything needed to request a price.
  bool get canRequestQuote =>
      sellAsset != null &&
      receiveAsset != null &&
      sellAsset != receiveAsset &&
      (amount ?? Decimal.zero) > Decimal.zero &&
      formError == null;

  /// Whether the user may move to the confirm step.
  bool get canReview =>
      quoteStatus == UnifiedSwapQuoteStatus.ready &&
      selectedQuote != null &&
      formError == null;

  /// Whether the swap may be started.
  ///
  /// Blocked while a reprice is pending acceptance: the whole point of the
  /// prompt is that the user has not agreed to the new numbers yet.
  bool get canStart =>
      step == UnifiedSwapStep.confirm &&
      selectedQuote != null &&
      !isStarting &&
      !isRepricing &&
      repricedQuote == null;

  /// Whether the running swap can still be cancelled.
  bool get canCancel => progress?.canCancel ?? false;

  /// Copy of this state with the given fields replaced.
  ///
  /// Nullable fields take explicit `clear` flags: a swap form spends most of
  /// its life clearing errors and stale prices, and `null` as "leave alone"
  /// makes that impossible to express.
  UnifiedSwapState copyWith({
    UnifiedSwapStep? step,
    AssetId? sellAsset,
    AssetId? receiveAsset,
    String? amountText,
    Decimal? spendableBalance,
    UnifiedSwapQuoteStatus? quoteStatus,
    UnifiedSwapQuotes? quotes,
    SwapQuote? selectedQuote,
    UnifiedSwapFormError? formError,
    Set<AssetId>? tradableAssets,
    RoutedSwapProgress? progress,
    bool? isStarting,
    bool? isRepricing,
    SwapQuote? repricedQuote,
    String? startError,
    String? activeSwapUuid,
    bool clearFormError = false,
    bool clearQuotes = false,
    bool clearSelectedQuote = false,
    bool clearRepricedQuote = false,
    bool clearStartError = false,
    bool clearSpendableBalance = false,
  }) {
    return UnifiedSwapState(
      step: step ?? this.step,
      sellAsset: sellAsset ?? this.sellAsset,
      receiveAsset: receiveAsset ?? this.receiveAsset,
      amountText: amountText ?? this.amountText,
      spendableBalance: clearSpendableBalance
          ? null
          : (spendableBalance ?? this.spendableBalance),
      quoteStatus: quoteStatus ?? this.quoteStatus,
      quotes: clearQuotes ? null : (quotes ?? this.quotes),
      selectedQuote: clearSelectedQuote
          ? null
          : (selectedQuote ?? this.selectedQuote),
      formError: clearFormError ? null : (formError ?? this.formError),
      tradableAssets: tradableAssets ?? this.tradableAssets,
      progress: progress ?? this.progress,
      isStarting: isStarting ?? this.isStarting,
      isRepricing: isRepricing ?? this.isRepricing,
      repricedQuote: clearRepricedQuote
          ? null
          : (repricedQuote ?? this.repricedQuote),
      startError: clearStartError ? null : (startError ?? this.startError),
      activeSwapUuid: activeSwapUuid ?? this.activeSwapUuid,
    );
  }

  @override
  List<Object?> get props => [
    step,
    sellAsset,
    receiveAsset,
    amountText,
    spendableBalance,
    quoteStatus,
    quotes,
    selectedQuote,
    formError,
    tradableAssets,
    progress,
    isStarting,
    isRepricing,
    repricedQuote,
    startError,
    activeSwapUuid,
  ];
}

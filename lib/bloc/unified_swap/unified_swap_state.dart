import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';

/// Which screen of the swap flow is showing.
enum UnifiedSwapView {
  /// Choosing what to pay and receive.
  form,

  /// Reviewing the selected option before committing.
  review,

  /// Following the swap that was just started.
  progress,
}

/// How the pay amount is being entered.
enum SwapAmountMode {
  /// In units of the pay asset.
  token,

  /// In US dollars, converted at the current price.
  fiat,
}

/// Why the form cannot be evaluated or reviewed.
enum SwapFormIssue {
  /// No amount yet. Not an error — the user has not finished.
  amountMissing,

  /// The amount is not a number.
  amountMalformed,

  /// The amount is zero.
  amountZero,

  /// More decimal places than the pay asset supports.
  tooManyDecimals,

  /// More than the address can spend.
  insufficient,

  /// Not enough of the network's native coin for the network fees.
  insufficientForFees,

  /// Both sides are the same asset.
  sameAsset,

  /// No price for the fiat amount, so no token amount can be derived.
  fiatUnavailable,
}

/// What the quote evaluation is doing.
enum SwapEvaluationStatus {
  /// Nothing to evaluate yet.
  idle,

  /// Checking what is available.
  checking,

  /// At least one option is on offer.
  ready,

  /// Nothing could be priced; see the failure.
  failed,

  /// The options went stale and must be refreshed before review.
  expired,
}

/// What the review step is doing.
enum SwapReviewStatus {
  /// Ready to start.
  ready,

  /// Checking the latest quote before starting.
  revalidating,

  /// The latest quote could not be confirmed.
  revalidationFailed,

  /// The quote expired while in review.
  expired,

  /// The outcome or cost moved materially; consent to the new numbers.
  materialUpdate,

  /// The engine is starting the swap.
  starting,

  /// The engine refused; nothing started.
  rejected,

  /// The start could not be confirmed. The swap may be running — never offer
  /// to start again from here.
  unconfirmed,
}

/// The review of one option.
class SwapReview extends Equatable {
  const SwapReview({
    required this.quote,
    required this.status,
    this.previous,
    this.termsRequired = false,
    this.rejectionDetail,
  });

  /// The option under review — the latest one, after any revalidation.
  final SwapQuote quote;

  /// What the review is doing.
  final SwapReviewStatus status;

  /// For [SwapReviewStatus.materialUpdate]: the numbers first consented to.
  final SwapQuote? previous;

  /// Whether starting records acceptance of the routing provider's terms,
  /// because this wallet has not accepted them yet.
  final bool termsRequired;

  /// Diagnostic text for a rejection.
  final String? rejectionDetail;

  /// Whether the start action is available.
  bool get canStart => switch (status) {
    SwapReviewStatus.ready || SwapReviewStatus.materialUpdate => true,
    _ => false,
  };

  SwapReview copyWith({
    SwapQuote? quote,
    SwapReviewStatus? status,
    SwapQuote? previous,
    bool clearPrevious = false,
    bool? termsRequired,
    String? rejectionDetail,
  }) => SwapReview(
    quote: quote ?? this.quote,
    status: status ?? this.status,
    previous: clearPrevious ? null : (previous ?? this.previous),
    termsRequired: termsRequired ?? this.termsRequired,
    rejectionDetail: rejectionDetail ?? this.rejectionDetail,
  );

  @override
  List<Object?> get props => [
    quote,
    status,
    previous,
    termsRequired,
    rejectionDetail,
  ];
}

/// The swap screen's state.
class UnifiedSwapState extends Equatable {
  const UnifiedSwapState({
    this.view = UnifiedSwapView.form,
    this.loadingAssets = true,
    this.tradableAssets = const {},
    this.pay,
    this.receive,
    this.payAddress,
    this.receiveAddress,
    this.inputText = '',
    this.amountMode = SwapAmountMode.token,
    this.balance,
    this.feeBalance,
    this.maxApplied,
    this.issue,
    this.evaluation = SwapEvaluationStatus.idle,
    this.quotes,
    this.selectedId,
    this.manuallySelected = false,
    this.failure,
    this.rateLimitedUntil,
    this.review,
    this.activeExecutionId,
    this.structuralNotice = false,
    this.tradingEnabled = true,
    this.clockValid = true,
  });

  /// Which screen is showing.
  final UnifiedSwapView view;

  /// Whether the tradable assets are still loading.
  final bool loadingAssets;

  /// Assets at least one source can trade.
  final Set<AssetId> tradableAssets;

  /// The asset being sold.
  final AssetId? pay;

  /// The asset being bought.
  final AssetId? receive;

  /// The pay asset's enabled address, before a quote reports it.
  final String? payAddress;

  /// The receive asset's enabled address, before a quote reports it.
  final String? receiveAddress;

  /// Raw text from the amount field, in [amountMode] units — kept unparsed so
  /// the field never fights the user mid-entry.
  final String inputText;

  /// How the amount is being entered.
  final SwapAmountMode amountMode;

  /// Spendable balance of [pay] at its address.
  final Decimal? balance;

  /// Spendable balance of the coin that pays [pay]'s network fees, when that
  /// is not [pay] itself.
  final Decimal? feeBalance;

  /// The Max last applied, so the form can say what was kept back.
  final SwapMaxAmount? maxApplied;

  /// Why the form cannot proceed, if it cannot.
  final SwapFormIssue? issue;

  /// What the evaluation is doing.
  final SwapEvaluationStatus evaluation;

  /// The latest evaluation.
  final UnifiedSwapQuotes? quotes;

  /// The chosen option's id.
  final String? selectedId;

  /// Whether the user picked an option other than the preselected one.
  final bool manuallySelected;

  /// Why nothing could be priced, when nothing could.
  final SwapQuoteFailure? failure;

  /// While set, automatic re-pricing waits: the provider asked to slow down.
  final DateTime? rateLimitedUntil;

  /// The review step, while open.
  final SwapReview? review;

  /// The swap being followed on the progress screen.
  final String? activeExecutionId;

  /// Set when revalidation found the route's steps changed, and a fresh
  /// evaluation replaced the review.
  final bool structuralNotice;

  /// Whether trading is available here at all.
  final bool tradingEnabled;

  /// Whether the device clock is accurate enough for peer-to-peer swaps.
  final bool clockValid;

  /// The selected option.
  SwapQuote? get selectedQuote {
    final id = selectedId;
    return id == null ? null : quotes?.byId(id);
  }

  /// Every option on offer.
  List<SwapQuote> get options => quotes?.options ?? const [];

  /// Whether both assets are chosen and differ.
  bool get hasPair => pay != null && receive != null && pay != receive;

  /// Whether the review may be opened.
  bool get canReview =>
      view == UnifiedSwapView.form &&
      tradingEnabled &&
      evaluation == SwapEvaluationStatus.ready &&
      issue == null &&
      selectedQuote != null;

  @override
  List<Object?> get props => [
    view,
    loadingAssets,
    tradableAssets,
    pay,
    receive,
    payAddress,
    receiveAddress,
    inputText,
    amountMode,
    balance,
    feeBalance,
    maxApplied,
    issue,
    evaluation,
    quotes,
    selectedId,
    manuallySelected,
    failure,
    rateLimitedUntil,
    review,
    activeExecutionId,
    structuralNotice,
    tradingEnabled,
    clockValid,
  ];

  /// A copy with the given fields replaced. Nullable fields take explicit
  /// `clear` flags: a swap form spends most of its life clearing stale prices
  /// and errors, and `null` as "leave alone" makes that impossible to express.
  UnifiedSwapState copyWith({
    UnifiedSwapView? view,
    bool? loadingAssets,
    Set<AssetId>? tradableAssets,
    AssetId? pay,
    AssetId? receive,
    String? payAddress,
    String? receiveAddress,
    String? inputText,
    SwapAmountMode? amountMode,
    Decimal? balance,
    Decimal? feeBalance,
    SwapMaxAmount? maxApplied,
    SwapFormIssue? issue,
    SwapEvaluationStatus? evaluation,
    UnifiedSwapQuotes? quotes,
    String? selectedId,
    bool? manuallySelected,
    SwapQuoteFailure? failure,
    DateTime? rateLimitedUntil,
    SwapReview? review,
    String? activeExecutionId,
    bool? structuralNotice,
    bool? tradingEnabled,
    bool? clockValid,
    bool clearPay = false,
    bool clearReceive = false,
    bool clearPayAddress = false,
    bool clearReceiveAddress = false,
    bool clearBalance = false,
    bool clearFeeBalance = false,
    bool clearMaxApplied = false,
    bool clearIssue = false,
    bool clearQuotes = false,
    bool clearSelectedId = false,
    bool clearFailure = false,
    bool clearRateLimit = false,
    bool clearReview = false,
    bool clearActiveExecution = false,
  }) {
    return UnifiedSwapState(
      view: view ?? this.view,
      loadingAssets: loadingAssets ?? this.loadingAssets,
      tradableAssets: tradableAssets ?? this.tradableAssets,
      pay: clearPay ? null : (pay ?? this.pay),
      receive: clearReceive ? null : (receive ?? this.receive),
      payAddress: clearPayAddress ? null : (payAddress ?? this.payAddress),
      receiveAddress: clearReceiveAddress
          ? null
          : (receiveAddress ?? this.receiveAddress),
      inputText: inputText ?? this.inputText,
      amountMode: amountMode ?? this.amountMode,
      balance: clearBalance ? null : (balance ?? this.balance),
      feeBalance: clearFeeBalance ? null : (feeBalance ?? this.feeBalance),
      maxApplied: clearMaxApplied ? null : (maxApplied ?? this.maxApplied),
      issue: clearIssue ? null : (issue ?? this.issue),
      evaluation: evaluation ?? this.evaluation,
      quotes: clearQuotes ? null : (quotes ?? this.quotes),
      selectedId: clearSelectedId ? null : (selectedId ?? this.selectedId),
      manuallySelected: manuallySelected ?? this.manuallySelected,
      failure: clearFailure ? null : (failure ?? this.failure),
      rateLimitedUntil: clearRateLimit
          ? null
          : (rateLimitedUntil ?? this.rateLimitedUntil),
      review: clearReview ? null : (review ?? this.review),
      activeExecutionId: clearActiveExecution
          ? null
          : (activeExecutionId ?? this.activeExecutionId),
      structuralNotice: structuralNotice ?? this.structuralNotice,
      tradingEnabled: tradingEnabled ?? this.tradingEnabled,
      clockValid: clockValid ?? this.clockValid,
    );
  }
}

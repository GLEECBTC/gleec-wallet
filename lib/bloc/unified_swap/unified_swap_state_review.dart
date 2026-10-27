part of 'unified_swap_state.dart';

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

/// What a review whose latest quote could not be confirmed offers next.
enum SwapRevalidationRecovery {
  /// Ask again: the failure may pass.
  tryAgain,

  /// The source refused for its rate limit. Asking again before its pause
  /// ends is refused too.
  waitForSource,

  /// Asking again gets the same answer: the route is gone at this amount, or
  /// the wallet no longer meets what it needs. The form says which.
  backToForm,
}

/// The review of one option.
class SwapReview extends Equatable {
  const SwapReview({
    required this.quote,
    required this.status,
    this.previous,
    this.termsRequired = false,
    this.legalSnapshot,
    this.legalBypass = false,
    this.legalLoading = false,
    this.legalFailed = false,
    this.isRecovery = false,
    this.rejectionDetail,
    this.revalidationFailure,
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
  final LegalConsentSnapshot? legalSnapshot;
  final bool legalBypass;
  final bool legalLoading;
  final bool legalFailed;
  bool get showLegalFailure =>
      !(legalSnapshot?.covers(swapConsentDocuments) ?? false) &&
      (!legalLoading || legalFailed);
  final bool isRecovery;
  bool get legalAllowed =>
      quote.source != SwapLiquiditySource.routed ||
      isRecovery ||
      legalBypass ||
      (legalLoading && !legalFailed) ||
      (legalSnapshot?.covers(swapConsentDocuments) ?? false);

  /// Diagnostic text for a rejection.
  final String? rejectionDetail;

  /// For [SwapReviewStatus.revalidationFailed]: why the latest quote could
  /// not be confirmed, which decides whether asking again can help.
  final SwapQuoteFailure? revalidationFailure;

  /// Whether the start action is available.
  bool get canStart =>
      legalAllowed &&
      switch (status) {
        SwapReviewStatus.ready || SwapReviewStatus.materialUpdate => true,
        _ => false,
      };

  /// For [SwapReviewStatus.revalidationFailed]: what to offer next.
  SwapRevalidationRecovery get revalidationRecovery {
    final failure = revalidationFailure;
    if (failure?.kind == SwapQuoteFailureKind.rateLimited) {
      return SwapRevalidationRecovery.waitForSource;
    }
    return failure == null || failure.isTransient
        ? SwapRevalidationRecovery.tryAgain
        : SwapRevalidationRecovery.backToForm;
  }

  SwapReview copyWith({
    SwapQuote? quote,
    SwapReviewStatus? status,
    SwapQuote? previous,
    bool clearPrevious = false,
    bool? termsRequired,
    LegalConsentSnapshot? legalSnapshot,
    bool? legalLoading,
    bool? legalFailed,
    String? rejectionDetail,
    SwapQuoteFailure? revalidationFailure,
  }) => SwapReview(
    quote: quote ?? this.quote,
    status: status ?? this.status,
    previous: clearPrevious ? null : (previous ?? this.previous),
    termsRequired: termsRequired ?? this.termsRequired,
    legalSnapshot: legalSnapshot ?? this.legalSnapshot,
    legalLoading: legalLoading ?? this.legalLoading,
    legalFailed: legalFailed ?? this.legalFailed,
    legalBypass: legalBypass,
    isRecovery: isRecovery,
    rejectionDetail: rejectionDetail ?? this.rejectionDetail,
    revalidationFailure: revalidationFailure ?? this.revalidationFailure,
  );

  @override
  List<Object?> get props => [
    quote,
    status,
    previous,
    termsRequired,
    legalSnapshot,
    legalLoading,
    legalFailed,
    legalBypass,
    isRecovery,
    rejectionDetail,
    revalidationFailure,
  ];
}

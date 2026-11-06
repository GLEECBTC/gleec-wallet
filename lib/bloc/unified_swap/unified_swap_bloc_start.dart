part of 'unified_swap_bloc.dart';

/// The action confirmed before preparation begins. Re-pricing may replace the
/// executable quote, but never the session, review revision, or shown terms.
typedef _Confirmation = ({
  SwapSubmission submission,
  int walletEpoch,
  int version,
  SwapQuote quote,
  LegalConsentSnapshot? legalSnapshot,
});

extension _UnifiedSwapStart on UnifiedSwapBloc {
  _Confirmation? _confirm(
    SwapQuote quote, {
    LegalConsentSnapshot? legalSnapshot,
    SwapSubmission? reviewedIn,
  }) {
    if (_closing || isClosed) return null;
    if (reviewedIn != null && !_registry.isCurrent(reviewedIn)) return null;
    try {
      final submission = _registry.beginSubmission();
      if (reviewedIn != null && reviewedIn.session != submission.session) {
        return null;
      }
      return (
        submission: submission,
        walletEpoch: _walletEpoch,
        version: ++_startVersion,
        quote: quote,
        legalSnapshot: legalSnapshot,
      );
    } on SwapStartRejectedException {
      return null;
    }
  }

  /// A late handler may abandon only its own review, never a replacement.
  bool _ownsConfirmation(
    Emitter<UnifiedSwapState> emit,
    _Confirmation confirmation,
  ) =>
      !emit.isDone &&
      !_closing &&
      !isClosed &&
      confirmation.version == _startVersion &&
      confirmation.walletEpoch == _walletEpoch;

  bool _mayUpdateConfirmation(
    Emitter<UnifiedSwapState> emit,
    _Confirmation confirmation,
  ) =>
      _ownsConfirmation(emit, confirmation) &&
      _registry.isCurrent(confirmation.submission);

  bool _stillConfirmed(
    Emitter<UnifiedSwapState> emit,
    _Confirmation confirmation,
  ) => _mayUpdateConfirmation(emit, confirmation) && state.tradingEnabled;

  void _abandonStart(
    Emitter<UnifiedSwapState> emit,
    _Confirmation confirmation,
  ) {
    if (!_ownsConfirmation(emit, confirmation)) return;
    _startVersion++;
    emit(state.copyWith(view: UnifiedSwapView.form, clearReview: true));
  }

  bool _continuePreparation(
    Emitter<UnifiedSwapState> emit,
    _Confirmation confirmation,
  ) {
    if (_stillConfirmed(emit, confirmation)) return true;
    _abandonStart(emit, confirmation);
    return false;
  }

  Future<void> _start(
    Emitter<UnifiedSwapState> emit,
    SwapQuote quote, {
    required bool termsRequired,
    required _Confirmation confirmation,
  }) async {
    if (!_continuePreparation(emit, confirmation)) return;
    final review = state.review;
    if (review == null) return;
    // A review opened while documents were still loading may complete that
    // same read; an already presented snapshot remains frozen throughout.
    final legalSnapshot = confirmation.legalSnapshot?.isAvailable == true
        ? confirmation.legalSnapshot
        : review.legalSnapshot;
    if (quote.source == SwapLiquiditySource.routed &&
        !review.isRecovery &&
        !_terms.canSubmit(legalSnapshot)) {
      return;
    }
    emit(
      state.copyWith(
        review: review.copyWith(status: SwapReviewStatus.revalidating),
      ),
    );
    _refresh?.cancel();
    _expiry?.cancel();

    if (termsRequired) {
      try {
        await _terms.recordAcceptance(
          at: _now(),
          snapshot: legalSnapshot,
          walletKey: confirmation.submission.walletKey,
          stillCurrent: () => _stillConfirmed(emit, confirmation),
        );
      } on Object {
        _abandonStart(emit, confirmation);
        return;
      }
    }
    if (!_continuePreparation(emit, confirmation)) return;

    try {
      final execution = await _registry.start(
        quote,
        confirmation.submission,
        stillCurrent: () => _stillConfirmed(emit, confirmation),
        onDispatch: () {
          emit(
            state.copyWith(
              review: state.review!.copyWith(
                quote: quote,
                status: SwapReviewStatus.starting,
                clearPrevious: true,
              ),
            ),
          );
        },
      );
      if (!_mayUpdateConfirmation(emit, confirmation)) return;
      unawaited(
        _preferences.rememberPair(
          quote.from,
          quote.to,
          walletKey: confirmation.submission.walletKey,
        ),
      );
      _startVersion++;
      emit(
        state.copyWith(
          view: UnifiedSwapView.progress,
          activeExecutionId: execution.id,
          clearReview: true,
        ),
      );
    } on SwapStartRejectedException catch (error) {
      if (!_mayUpdateConfirmation(emit, confirmation)) {
        _abandonStart(emit, confirmation);
        return;
      }
      emit(
        state.copyWith(
          review: state.review?.copyWith(
            status: SwapReviewStatus.rejected,
            rejectionDetail: error.detail,
          ),
        ),
      );
    } on Object {
      // The registry owns recovery even if the form/session has since ended.
      // An unanswered dispatch must never re-arm the original Start action.
      if (!_mayUpdateConfirmation(emit, confirmation)) return;
      emit(
        state.copyWith(
          review: state.review?.copyWith(status: SwapReviewStatus.unconfirmed),
        ),
      );
    }
  }
}

part of 'unified_swap_bloc.dart';

/// A start the user confirmed: the registry's submission and the wallet
/// epoch it was confirmed in.
typedef _Confirmation = ({SwapSubmission submission, int walletEpoch});

/// The start itself, sent only while the form that confirmed it is open and
/// the wallet session it was confirmed in holds.
extension _UnifiedSwapStart on UnifiedSwapBloc {
  /// A start confirmed now. Taken when Start is pressed, before anything is
  /// awaited, so each wait after it is held to this session.
  _Confirmation _confirm() =>
      (submission: _registry.beginSubmission(), walletEpoch: _walletEpoch);

  /// Whether [confirmation] may still be sent: its form is open, no wallet
  /// has signed in or out, and the registry's session is the one it was
  /// confirmed in.
  bool _stillConfirmed(
    Emitter<UnifiedSwapState> emit,
    _Confirmation confirmation,
  ) =>
      !emit.isDone &&
      !_closing &&
      confirmation.walletEpoch == _walletEpoch &&
      _registry.isCurrent(confirmation.submission);

  /// Drops a start that lapsed before anything was sent.
  void _abandonStart(Emitter<UnifiedSwapState> emit) {
    _startVersion++;
    if (emit.isDone) return;
    emit(state.copyWith(view: UnifiedSwapView.form, clearReview: true));
  }

  Future<void> _start(
    Emitter<UnifiedSwapState> emit,
    SwapQuote quote, {
    required bool termsRequired,
    required _Confirmation confirmation,
  }) async {
    final review = state.review;
    if (review == null) return;
    if (quote.source == SwapLiquiditySource.routed &&
        !review.isRecovery &&
        !_terms.canSubmit(review.legalSnapshot)) {
      return;
    }
    emit(
      state.copyWith(
        review: review.copyWith(
          quote: quote,
          status: SwapReviewStatus.starting,
          clearPrevious: true,
        ),
      ),
    );
    _refresh?.cancel();
    _expiry?.cancel();

    if (termsRequired) {
      // Starting a routed swap after being shown the provider's terms is the
      // acceptance; it is recorded before anything is sent, and only for the
      // wallet that was shown them.
      try {
        await _terms.recordAcceptance(
          at: _now(),
          snapshot: review.legalSnapshot,
          stillCurrent: () => _stillConfirmed(emit, confirmation),
        );
      } on Object {
        _abandonStart(emit);
        return;
      }
    }
    // Checked again, with nothing awaited before the registry sends: the form
    // can close, the wallet session end and trading be turned off during the
    // re-price or that write, and a review already starting is kept open
    // through them.
    if (!_stillConfirmed(emit, confirmation)) {
      _abandonStart(emit);
      return;
    }
    if (!state.tradingEnabled) {
      _startVersion++;
      emit(state.copyWith(view: UnifiedSwapView.form, clearReview: true));
      return;
    }

    try {
      final execution = await _registry.start(quote, confirmation.submission);
      unawaited(_preferences.rememberPair(quote.from, quote.to));
      _startVersion++;
      emit(
        state.copyWith(
          view: UnifiedSwapView.progress,
          activeExecutionId: execution.id,
          clearReview: true,
        ),
      );
    } on SwapStartRejectedException catch (error) {
      emit(
        state.copyWith(
          review: state.review?.copyWith(
            status: SwapReviewStatus.rejected,
            rejectionDetail: error.detail,
          ),
        ),
      );
    } on Object {
      // The engine may already have the swap. Another tap here could start a
      // second real swap, so the review stays blocked and says where to look.
      emit(
        state.copyWith(
          review: state.review?.copyWith(status: SwapReviewStatus.unconfirmed),
        ),
      );
    }
  }
}

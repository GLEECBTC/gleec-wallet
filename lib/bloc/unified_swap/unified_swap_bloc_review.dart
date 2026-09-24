part of 'unified_swap_bloc.dart';

/// The review and the start, which re-prices before committing.
extension _UnifiedSwapReview on UnifiedSwapBloc {
  Future<void> _onReviewOpened(
    UnifiedSwapReviewOpened event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    if (!state.canReview) return;
    final quote = state.selectedQuote!;
    final termsRequired =
        quote.source == SwapLiquiditySource.routed &&
        !await _terms.hasAccepted();
    if (state.selectedQuote != quote || state.view != UnifiedSwapView.form) {
      return;
    }
    emit(
      state.copyWith(
        view: UnifiedSwapView.review,
        structuralNotice: false,
        review: SwapReview(
          quote: quote,
          status: quote.isExpiredAt(_now())
              ? SwapReviewStatus.expired
              : SwapReviewStatus.ready,
          termsRequired: termsRequired,
        ),
      ),
    );
  }

  void _onReviewClosed(
    UnifiedSwapReviewClosed event,
    Emitter<UnifiedSwapState> emit,
  ) {
    final review = state.review;
    // Once the engine has been asked to start, the answer must be seen —
    // closing now would hide a swap that may already be running.
    if (review != null && review.status == SwapReviewStatus.starting) return;
    _startVersion++;
    emit(state.copyWith(view: UnifiedSwapView.form, clearReview: true));
    final quote = state.selectedQuote;
    if (quote != null && quote.isExpiredAt(_now())) {
      add(const UnifiedSwapEvaluationRequested());
    } else {
      _armTimers(quote);
    }
  }

  Future<void> _onStartRequested(
    UnifiedSwapStartRequested event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    final review = state.review;
    if (review == null || state.view != UnifiedSwapView.review) return;

    if (review.status == SwapReviewStatus.expired ||
        review.status == SwapReviewStatus.revalidationFailed ||
        review.status == SwapReviewStatus.rejected) {
      // "Refresh quote" / "Try again": re-price the same route in place.
      await _revalidate(emit, review);
      return;
    }
    if (!review.canStart) return;

    if (review.status == SwapReviewStatus.materialUpdate) {
      // The user has seen the updated numbers side by side and accepted them.
      await _start(emit, review.quote, termsRequired: review.termsRequired);
      return;
    }
    final fresh = await _revalidate(emit, review);
    if (fresh == null) return;
    await _start(emit, fresh, termsRequired: review.termsRequired);
  }

  /// Re-prices [review]'s route. Returns the quote to start with when the
  /// change is quiet; otherwise leaves the review asking for consent or sends
  /// the user back to a fresh evaluation, and returns null.
  Future<SwapQuote?> _revalidate(
    Emitter<UnifiedSwapState> emit,
    SwapReview review,
  ) async {
    final version = ++_startVersion;
    final accepted = review.previous ?? review.quote;
    emit(
      state.copyWith(
        review: review.copyWith(status: SwapReviewStatus.revalidating),
      ),
    );

    SwapQuoteResult result;
    try {
      result = await _repository.requote(accepted).timeout(_evaluationTimeout);
    } on Object {
      result = const SwapQuoteRejected(
        SwapQuoteFailure(
          source: SwapLiquiditySource.routed,
          kind: SwapQuoteFailureKind.timeout,
        ),
      );
    }
    // Back was pressed while this ran: never start behind the user's back.
    if (version != _startVersion || state.view != UnifiedSwapView.review) {
      return null;
    }

    switch (result) {
      case SwapQuoteRejected(:final failure):
        emit(
          state.copyWith(
            review: review.copyWith(
              status: SwapReviewStatus.revalidationFailed,
              rejectionDetail: failure.detail,
            ),
          ),
        );
        return null;
      case SwapQuoteAvailable(quote: final fresh):
        if (_isStructuralChange(accepted, fresh)) {
          // The steps themselves changed; consent to the old ones means
          // nothing. Evaluate afresh from the form.
          _startVersion++;
          emit(
            state.copyWith(
              view: UnifiedSwapView.form,
              clearReview: true,
              structuralNotice: true,
            ),
          );
          add(const UnifiedSwapEvaluationRequested());
          return null;
        }
        if (_isMaterialChange(accepted, fresh)) {
          emit(
            state.copyWith(
              review: SwapReview(
                quote: fresh,
                previous: accepted,
                status: SwapReviewStatus.materialUpdate,
                termsRequired: review.termsRequired,
              ),
            ),
          );
          return null;
        }
        return fresh;
    }
  }

  Future<void> _start(
    Emitter<UnifiedSwapState> emit,
    SwapQuote quote, {
    required bool termsRequired,
  }) async {
    final review = state.review;
    if (review == null) return;
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
      // acceptance; it is recorded before anything is sent.
      await _terms.recordAcceptance(at: _now());
    }

    try {
      final execution = await _registry.start(quote);
      unawaited(_preferences.rememberPair(quote.from, quote.to));
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

  Future<void> _onFreshQuoteAccepted(
    UnifiedSwapFreshQuoteAccepted event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    // Consent was given on the progress screen, old against new, after the
    // engine stopped a swap before sending anything.
    emit(
      state.copyWith(
        view: UnifiedSwapView.review,
        review: SwapReview(quote: event.quote, status: SwapReviewStatus.ready),
        clearActiveExecution: true,
      ),
    );
    await _start(emit, event.quote, termsRequired: false);
  }

  void _onProgressLeft(
    UnifiedSwapProgressLeft event,
    Emitter<UnifiedSwapState> emit,
  ) => _resetForm(emit, keepPair: true);

  void _onResetRequested(
    UnifiedSwapResetRequested event,
    Emitter<UnifiedSwapState> emit,
  ) => _resetForm(emit, keepPair: event.keepPair);

  void _resetForm(Emitter<UnifiedSwapState> emit, {required bool keepPair}) {
    _invalidate();
    _startVersion++;
    emit(
      _validated(
        state.copyWith(
          view: UnifiedSwapView.form,
          inputText: '',
          amountMode: SwapAmountMode.token,
          clearActiveExecution: true,
          clearReview: true,
          clearQuotes: true,
          clearSelectedId: true,
          clearFailure: true,
          clearMaxApplied: true,
          clearPay: !keepPair,
          clearReceive: !keepPair,
          evaluation: SwapEvaluationStatus.idle,
          structuralNotice: false,
        ),
      ),
    );
    add(const UnifiedSwapBalancesRefreshed());
  }

  Future<void> _onFollowUpRequested(
    UnifiedSwapFollowUpRequested event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    _startVersion++;
    emit(state.copyWith(clearActiveExecution: true, clearReview: true));
    await _setPair(
      emit,
      pay: event.pay,
      receive: event.receive == event.pay ? null : event.receive,
      amount: event.amount ?? '',
    );
  }
}

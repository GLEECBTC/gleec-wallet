part of 'unified_swap_bloc.dart';

/// The review and the start, which re-prices before committing.
extension _UnifiedSwapReview on UnifiedSwapBloc {
  /// Whether the reviewed swap may be running, its start unanswered or lost.
  bool get _startInDoubt => switch (state.review?.status) {
    SwapReviewStatus.starting || SwapReviewStatus.unconfirmed => true,
    _ => false,
  };

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
    // Freeze the selected snapshot and ignore form requests already in flight.
    _invalidate();
    _startVersion++;
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
    _armExpiry(quote);
  }

  void _onReviewClosed(
    UnifiedSwapReviewClosed event,
    Emitter<UnifiedSwapState> emit,
  ) {
    // Once the engine has been asked to start, the answer must be seen —
    // closing now would hide a swap that may already be running.
    if (_startInDoubt) return;
    _startVersion++;
    final review = state.review;
    // Its source no longer prices the reviewed route: showing it on the form
    // again would only lead back to the same failure.
    final gone =
        review?.status == SwapReviewStatus.revalidationFailed &&
        review?.revalidationRecovery == SwapRevalidationRecovery.backToForm;
    emit(state.copyWith(view: UnifiedSwapView.form, clearReview: true));
    final quote = state.selectedQuote;
    if (gone || (quote != null && quote.isExpiredAt(_now()))) {
      add(const UnifiedSwapEvaluationRequested());
    } else {
      _armTimers(quote, shownAgain: true);
    }
  }

  Future<void> _onStartRequested(
    UnifiedSwapStartRequested event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    final review = state.review;
    if (review == null || state.view != UnifiedSwapView.review) return;
    if (!state.tradingEnabled) return;

    if (review.status == SwapReviewStatus.expired ||
        review.status == SwapReviewStatus.revalidationFailed ||
        review.status == SwapReviewStatus.rejected) {
      // "Refresh quote" / "Try again": re-price the same route in place.
      final fresh = await _revalidate(emit, review);
      if (fresh == null) return;
      emit(
        state.copyWith(
          review: SwapReview(
            quote: fresh,
            status: SwapReviewStatus.ready,
            termsRequired: review.termsRequired,
          ),
        ),
      );
      _armExpiry(fresh);
      return;
    }
    if (!review.canStart) return;

    if (review.status == SwapReviewStatus.materialUpdate &&
        !review.quote.isExpiredAt(_now())) {
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

    // Read alongside the price, for the quote's own asset, which need not be
    // the form's.
    final epoch = _walletEpoch;
    final reading = _heldOf(accepted.from);
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
    final held = await reading;
    _showHeld(emit, accepted.from, epoch, held);
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
              revalidationFailure: failure,
            ),
          ),
        );
        if (failure.kind == SwapQuoteFailureKind.rateLimited) {
          _pauseForRateLimit(emit, failure);
        }
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
        // KDF's checks at the start leave out the gas to refund the payment,
        // so the form's check is run again, for the amount that starts. A
        // price read without fees is held to the one reviewed.
        final checked = fresh.feesKnown ? fresh : accepted;
        final short = _shortfall(
          checked,
          _spending(state, checked, checked.sellAmount, held.balance),
          held,
        );
        if (short != null) {
          emit(
            state.copyWith(
              review: review.copyWith(
                status: SwapReviewStatus.revalidationFailed,
                revalidationFailure: SwapQuoteFailure(
                  source: fresh.source,
                  kind: SwapQuoteFailureKind.insufficientFunds,
                  asset: short == SwapFormIssue.insufficientForFees
                      ? fresh.from.parentId
                      : fresh.from,
                ),
              ),
            ),
          );
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
          _armExpiry(fresh);
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
    // Checked again: trading can be turned off during that write, and a
    // review already starting is kept open through it.
    if (!state.tradingEnabled) {
      _startVersion++;
      emit(state.copyWith(view: UnifiedSwapView.form, clearReview: true));
      return;
    }

    try {
      final execution = await _registry.start(quote);
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

  Future<void> _onFreshQuoteAccepted(
    UnifiedSwapFreshQuoteAccepted event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    // A start or re-price under way answers first: starting this beside it
    // could swap twice.
    bool refused() =>
        _startInDoubt ||
        state.review?.status == SwapReviewStatus.revalidating ||
        !state.tradingEnabled;
    if (refused()) return;
    final quote = event.quote;
    final termsRequired =
        quote.source == SwapLiquiditySource.routed &&
        !await _terms.hasAccepted();
    if (refused()) return;
    // Freeze the selected snapshot and ignore form requests already in flight.
    _invalidate();
    _startVersion++;
    final review = SwapReview(
      quote: quote,
      status: quote.isExpiredAt(_now())
          ? SwapReviewStatus.expired
          : SwapReviewStatus.ready,
      termsRequired: termsRequired,
    );
    emit(
      state.copyWith(
        view: UnifiedSwapView.review,
        review: review,
        clearActiveExecution: true,
      ),
    );
    // Consent was given on the progress screen, but does not skip the
    // re-price: a price read back from history is dated when read, however
    // old.
    if (termsRequired) {
      // The provider's terms are accepted by pressing Start beside them.
      _armExpiry(quote);
      return;
    }
    final fresh = await _revalidate(emit, review);
    if (fresh == null) return;
    await _start(emit, fresh, termsRequired: false);
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
    if (state.review?.status == SwapReviewStatus.starting) return;
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
          checkingMax: false,
          clearPay: !keepPair,
          clearReceive: !keepPair,
          evaluation: SwapEvaluationStatus.idle,
          structuralNotice: false,
        ),
      ),
    );
    add(const UnifiedSwapBalancesRefreshed());
    // The swap just made may have taken the last offer.
    if (keepPair) add(const UnifiedSwapOffersRequested(recount: true));
  }

  Future<void> _onFollowUpRequested(
    UnifiedSwapFollowUpRequested event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    if (_startInDoubt) return;
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

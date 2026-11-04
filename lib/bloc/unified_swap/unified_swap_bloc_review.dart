part of 'unified_swap_bloc.dart';

/// The review and the start, which re-prices before committing.
extension _UnifiedSwapReview on UnifiedSwapBloc {
  /// Whether the reviewed swap may be running, its start unanswered or lost.
  bool get _startInDoubt => state.startInDoubt;

  Future<void> _onReviewOpened(
    UnifiedSwapReviewOpened event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    if (!state.canReview) return;
    final quote = state.selectedQuote!;
    final SwapSubmission reviewedIn;
    try {
      reviewedIn = _registry.beginSubmission();
    } on SwapStartRejectedException {
      // The session lapsed since this form was built: Review stays off until
      // the registry announces the next one.
      emit(state.copyWith(sessionReady: false));
      return;
    }
    final version = ++_startVersion;
    final epoch = _walletEpoch;
    bool current() =>
        !_closing &&
        !isClosed &&
        !emit.isDone &&
        version == _startVersion &&
        epoch == _walletEpoch &&
        _registry.isCurrent(reviewedIn) &&
        identical(state.selectedQuote, quote) &&
        state.view == UnifiedSwapView.form;
    final routed = quote.source == SwapLiquiditySource.routed;
    final snapshot = routed ? await _terms.loadSnapshot() : null;
    if (!current()) return;
    final termsRequired =
        routed &&
        !await _terms.hasAccepted(
          snapshot: snapshot,
          walletKey: reviewedIn.walletKey,
        );
    if (!current()) return;
    _reviewSubmission = reviewedIn;
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
          legalSnapshot: snapshot,
          legalBypass: _terms.legalDocuments.bypassGate,
          legalLoading: routed && !(snapshot?.isAvailable ?? false),
        ),
      ),
    );
    _armExpiry(quote);
    if (routed) add(const UnifiedSwapLegalRequested());
  }

  Future<void> _onLegalRequested(
    UnifiedSwapLegalRequested event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    final review = state.review;
    if (review == null ||
        review.quote.source != SwapLiquiditySource.routed ||
        review.isRecovery ||
        _waitingForLegalSubmission ||
        _startInDoubt ||
        review.status == SwapReviewStatus.revalidating) {
      return;
    }
    if (!(review.legalSnapshot?.isAvailable ?? false)) {
      emit(
        state.copyWith(
          review: review.copyWith(
            legalLoading: true,
            legalFailed: review.showLegalFailure,
          ),
        ),
      );
    }
    final reviewedIn = _reviewSubmission;
    if (reviewedIn == null || !_registry.isCurrent(reviewedIn)) return;
    final version = ++_legalVersion;
    final reviewVersion = _startVersion;
    final epoch = _walletEpoch;
    bool currentRead() =>
        !_closing &&
        !isClosed &&
        !emit.isDone &&
        version == _legalVersion &&
        reviewVersion == _startVersion &&
        epoch == _walletEpoch &&
        _registry.isCurrent(reviewedIn) &&
        identical(state.review?.quote, review.quote) &&
        !_startInDoubt &&
        state.review?.status != SwapReviewStatus.revalidating;
    await _terms.refresh(force: event.retry);
    if (!currentRead()) return;
    final snapshot = await _terms.loadSnapshot();
    if (!currentRead()) return;
    final accepted = await _terms.hasAccepted(
      snapshot: snapshot,
      walletKey: reviewedIn.walletKey,
    );
    if (!currentRead()) return;
    final current = state.review!;
    emit(
      state.copyWith(
        review: current.copyWith(
          legalSnapshot: snapshot,
          legalLoading: false,
          legalFailed: !snapshot.isAvailable,
          termsRequired: !accepted,
        ),
      ),
    );
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
    var review = state.review;
    if (review == null || state.view != UnifiedSwapView.review) return;
    if (!_visible || !state.tradingEnabled) return;
    if (_waitingForLegalSubmission ||
        _startInDoubt ||
        review.status == SwapReviewStatus.revalidating) {
      return;
    }
    final reviewedIn = _reviewSubmission;
    if (reviewedIn == null || !_registry.isCurrent(reviewedIn)) {
      _startVersion++;
      emit(state.copyWith(view: UnifiedSwapView.form, clearReview: true));
      return;
    }
    final confirmation = _confirm(
      review.quote,
      legalSnapshot: review.legalSnapshot,
      reviewedIn: reviewedIn,
    );
    if (confirmation == null) return;
    if (review.legalLoading &&
        !_terms.canSubmit(review.legalSnapshot) &&
        !review.isRecovery &&
        review.quote.source == SwapLiquiditySource.routed) {
      _legalSubmissionVersion = confirmation.version;
      ++_legalVersion;
      try {
        await _terms.refresh();
        if (!_continuePreparation(emit, confirmation)) return;
        final snapshot = await _terms.loadSnapshot();
        if (!_continuePreparation(emit, confirmation)) return;
        final accepted = await _terms.hasAccepted(
          snapshot: snapshot,
          walletKey: confirmation.submission.walletKey,
        );
        if (!_continuePreparation(emit, confirmation)) return;
        review = state.review!.copyWith(
          legalSnapshot: snapshot,
          legalLoading: false,
          legalFailed: !snapshot.isAvailable,
          termsRequired: !accepted,
        );
        emit(state.copyWith(review: review));
        if (!_terms.canSubmit(snapshot)) return;
      } finally {
        if (_legalSubmissionVersion == confirmation.version) {
          _legalSubmissionVersion = null;
        }
        // A different review may have opened while this request was pending.
        // Refresh its display without replaying the abandoned start action.
        if (!isClosed &&
            state.view == UnifiedSwapView.review &&
            state.review?.legalLoading == true) {
          add(const UnifiedSwapLegalRequested());
        }
      }
    }

    if (review.status == SwapReviewStatus.expired ||
        review.status == SwapReviewStatus.revalidationFailed ||
        review.status == SwapReviewStatus.rejected) {
      // "Refresh quote" / "Try again": re-price the same route in place.
      final fresh = await _revalidate(emit, review, confirmation);
      if (fresh == null) return;
      emit(
        state.copyWith(
          review: SwapReview(
            quote: fresh,
            status: SwapReviewStatus.ready,
            termsRequired: review.termsRequired,
            legalSnapshot: review.legalSnapshot,
            legalBypass: review.legalBypass,
            legalLoading: review.legalLoading,
            legalFailed: review.legalFailed,
            isRecovery: review.isRecovery,
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
      await _start(
        emit,
        review.quote,
        termsRequired: review.termsRequired,
        confirmation: confirmation,
      );
      return;
    }
    final fresh = await _revalidate(emit, review, confirmation);
    if (fresh == null) return;
    await _start(
      emit,
      fresh,
      termsRequired: review.termsRequired,
      confirmation: confirmation,
    );
  }

  /// Re-prices [review]'s route. Returns the quote to start with when the
  /// change is quiet; otherwise leaves the review asking for consent or sends
  /// the user back to a fresh evaluation, and returns null.
  Future<SwapQuote?> _revalidate(
    Emitter<UnifiedSwapState> emit,
    SwapReview review,
    _Confirmation confirmation,
  ) async {
    if (!_continuePreparation(emit, confirmation)) return null;
    final accepted = review.previous ?? confirmation.quote;
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
    if (!_continuePreparation(emit, confirmation)) return null;
    final held = await reading;
    if (!_continuePreparation(emit, confirmation)) return null;
    _showHeld(emit, accepted.from, epoch, held);

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
                legalSnapshot: review.legalSnapshot,
                legalBypass: review.legalBypass,
                legalLoading: review.legalLoading,
                legalFailed: review.legalFailed,
                isRecovery: review.isRecovery,
              ),
            ),
          );
          _armExpiry(fresh);
          return null;
        }
        return fresh;
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
    final confirmation = _confirm(quote);
    if (confirmation == null) return;
    final routed = quote.source == SwapLiquiditySource.routed;
    final snapshot = routed ? await _terms.loadSnapshot() : null;
    if (!_continuePreparation(emit, confirmation)) return;
    final termsRequired =
        routed &&
        !await _terms.hasAccepted(
          snapshot: snapshot,
          walletKey: confirmation.submission.walletKey,
        );
    if (!_continuePreparation(emit, confirmation)) return;
    _reviewSubmission = confirmation.submission;
    // Freeze the selected snapshot and ignore form requests already in flight.
    _invalidate();
    final review = SwapReview(
      quote: quote,
      status: quote.isExpiredAt(_now())
          ? SwapReviewStatus.expired
          : SwapReviewStatus.ready,
      termsRequired: termsRequired,
      legalSnapshot: snapshot,
      legalBypass: _terms.legalDocuments.bypassGate,
      legalLoading: routed && !(snapshot?.isAvailable ?? false),
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
      if (routed) add(const UnifiedSwapLegalRequested());
      return;
    }
    final fresh = await _revalidate(emit, review, confirmation);
    if (fresh == null) return;
    await _start(emit, fresh, termsRequired: false, confirmation: confirmation);
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

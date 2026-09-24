part of 'unified_swap_bloc.dart';

/// Automatic pricing: debounced, versioned, refreshed and expired.
extension _UnifiedSwapEvaluation on UnifiedSwapBloc {
  void _scheduleEvaluation({bool immediate = false}) {
    _debounce?.cancel();
    if (!_evaluable(state)) return;
    _debounce = Timer(
      immediate ? Duration.zero : _debounceDelay,
      () => add(const UnifiedSwapEvaluationRequested()),
    );
  }

  bool _evaluable(UnifiedSwapState state) =>
      state.hasPair &&
      !_catalogLoading &&
      state.tradingEnabled &&
      state.issue == null &&
      (amountOf(state) ?? Decimal.zero) > Decimal.zero;

  Future<void> _onEvaluationRequested(
    UnifiedSwapEvaluationRequested event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    if (!_evaluable(state)) return;
    final amount = amountOf(state)!;
    final version = ++_evaluationVersion;
    final quiet = event.quiet && state.quotes != null;
    if (!quiet) {
      // The structural notice survives this: it explains why fresh options
      // are being checked, and clears when the user edits or reviews.
      emit(
        state.copyWith(
          evaluation: SwapEvaluationStatus.checking,
          clearFailure: true,
        ),
      );
    }

    final UnifiedSwapQuotes result;
    try {
      result = await _repository
          .quote(_request(state, amount))
          .timeout(_evaluationTimeout);
    } on TimeoutException {
      if (version != _evaluationVersion) return;
      _failEvaluation(
        emit,
        const SwapQuoteFailure(
          source: SwapLiquiditySource.routed,
          kind: SwapQuoteFailureKind.timeout,
        ),
        quiet: quiet,
      );
      return;
    }

    // The intent moved on while this was in flight. Emitting now would show a
    // price for an amount or pair the user has already left behind.
    if (version != _evaluationVersion) return;

    if (result.isEmpty) {
      _failEvaluation(
        emit,
        result.primaryFailure ??
            const SwapQuoteFailure(
              source: SwapLiquiditySource.routed,
              kind: SwapQuoteFailureKind.unknown,
            ),
        quiet: quiet,
        all: result.failures,
      );
      return;
    }

    // Keep the user's pick across a refresh when it is still on offer.
    final previous = state.selectedId;
    final keep =
        previous != null &&
        state.manuallySelected &&
        result.byId(previous) != null;
    final selected = keep ? result.byId(previous) : result.preselected;

    emit(
      _validated(
        state.copyWith(
          evaluation: SwapEvaluationStatus.ready,
          quotes: result,
          selectedId: selected?.id,
          clearSelectedId: selected == null,
          manuallySelected: keep,
          clearFailure: true,
          // Kept although options exist: a source that could not answer is
          // worth a quiet word, because the best option may be missing.
          failures: result.failures,
          clearRateLimit: true,
        ),
      ),
    );
    _armTimers(selected);
  }

  void _failEvaluation(
    Emitter<UnifiedSwapState> emit,
    SwapQuoteFailure failure, {
    required bool quiet,
    List<SwapQuoteFailure> all = const [],
  }) {
    // A refresh that fails keeps the options it had until they expire:
    // replacing a working quote with an error because one re-price blipped
    // would punish the user for waiting.
    if (quiet && state.selectedQuote != null) {
      if (failure.kind == SwapQuoteFailureKind.rateLimited) {
        _pauseForRateLimit(emit, failure);
      }
      return;
    }
    emit(
      state.copyWith(
        evaluation: SwapEvaluationStatus.failed,
        failure: failure,
        failures: all.isEmpty ? [failure] : all,
        clearQuotes: true,
        clearSelectedId: true,
      ),
    );
    if (failure.kind == SwapQuoteFailureKind.rateLimited) {
      _pauseForRateLimit(emit, failure);
    }
  }

  /// Waits out a rate limit — for as long as the source is holding requests
  /// back, when it says.
  void _pauseForRateLimit(
    Emitter<UnifiedSwapState> emit,
    SwapQuoteFailure failure,
  ) {
    final until = failure.retryAt ?? _now().add(_rateLimitPause);
    emit(state.copyWith(rateLimitedUntil: until));
    _refresh?.cancel();
    _rateLimit?.cancel();
    final wait = until.difference(_now());
    _rateLimit = Timer(
      wait.isNegative ? Duration.zero : wait,
      () =>
          add(const UnifiedSwapTimerFired(UnifiedSwapTimerKind.rateLimitOver)),
    );
  }

  /// What to price for [state]: the cheapest route, and the alternatives too
  /// while someone compares them or has chosen one.
  SwapQuoteRequest _request(UnifiedSwapState state, Decimal amount) {
    final comparing =
        _comparing == _intentKey(state) ||
        state.selectedQuote?.order == SwapQuoteOrder.fastest;
    return SwapQuoteRequest(
      from: state.pay!,
      to: state.receive!,
      amount: amount,
      orders: {SwapQuoteOrder.cheapest, if (comparing) SwapQuoteOrder.fastest},
      slippage: state.slippage,
    );
  }

  Object _intentKey(UnifiedSwapState state) =>
      (state.pay, state.receive, amountOf(state));

  Future<void> _onAlternativesRequested(
    UnifiedSwapAlternativesRequested event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    if (!_evaluable(state)) return;
    final key = _intentKey(state);
    final alreadyCompared = _comparing == key;
    _comparing = key;
    final quotes = state.quotes;
    // Not priced yet: the evaluation under way will include them.
    if (alreadyCompared || quotes == null) return;
    if (quotes.options.any((q) => q.order == SwapQuoteOrder.fastest)) return;
    if (!quotes.options.any((q) => q.source == SwapLiquiditySource.routed)) {
      return;
    }

    final version = _evaluationVersion;
    emit(state.copyWith(checkingAlternatives: true));
    List<SwapQuote> fresh;
    try {
      fresh = await _repository
          .alternatives(_request(state, amountOf(state)!))
          .timeout(_evaluationTimeout);
    } on Object {
      fresh = const [];
    }
    if (version != _evaluationVersion || state.quotes == null) {
      emit(state.copyWith(checkingAlternatives: false));
      return;
    }
    final current = state.quotes!;
    final added = [
      for (final quote in fresh)
        if (!current.options.any(
          (known) =>
              known.diagnostic == quote.diagnostic &&
              known.guaranteedReceive == quote.guaranteedReceive,
        ))
          quote,
    ];
    emit(
      _validated(
        state.copyWith(
          checkingAlternatives: false,
          quotes: added.isEmpty
              ? current
              : UnifiedSwapRepository.rank([
                  ...current.options,
                  ...added,
                ], current.failures),
        ),
      ),
    );
  }

  void _armTimers(SwapQuote? selected) {
    _refresh?.cancel();
    _expiry?.cancel();
    if (selected == null) return;
    _refresh = Timer(
      _refreshInterval,
      () => add(const UnifiedSwapTimerFired(UnifiedSwapTimerKind.refresh)),
    );
    final untilExpiry = selected.expiresAt.difference(_now());
    _expiry = Timer(
      untilExpiry.isNegative ? Duration.zero : untilExpiry,
      () => add(const UnifiedSwapTimerFired(UnifiedSwapTimerKind.expiry)),
    );
  }

  void _onTimerFired(
    UnifiedSwapTimerFired event,
    Emitter<UnifiedSwapState> emit,
  ) {
    switch (event.kind) {
      case UnifiedSwapTimerKind.refresh:
        final paused = state.rateLimitedUntil?.isAfter(_now()) ?? false;
        // Left alone long enough, the quote is allowed to expire rather than
        // re-priced for nobody; "Refresh quote" brings it back.
        final idle = _now().difference(_lastInteraction) >= _idleLimit;
        if (_present &&
            !idle &&
            !paused &&
            state.view == UnifiedSwapView.form &&
            state.evaluation == SwapEvaluationStatus.ready) {
          add(const UnifiedSwapEvaluationRequested(quiet: true));
        }
      case UnifiedSwapTimerKind.expiry:
        final quote = state.selectedQuote;
        if (quote == null || !quote.isExpiredAt(_now())) return;
        final review = state.review;
        if (state.view == UnifiedSwapView.review &&
            review != null &&
            review.status == SwapReviewStatus.ready) {
          emit(
            state.copyWith(
              review: review.copyWith(status: SwapReviewStatus.expired),
            ),
          );
        } else if (state.view == UnifiedSwapView.form &&
            state.evaluation == SwapEvaluationStatus.ready) {
          emit(state.copyWith(evaluation: SwapEvaluationStatus.expired));
        }
      case UnifiedSwapTimerKind.rateLimitOver:
        emit(state.copyWith(clearRateLimit: true));
        if (_present &&
            state.view == UnifiedSwapView.form &&
            state.failure?.kind == SwapQuoteFailureKind.rateLimited) {
          add(const UnifiedSwapEvaluationRequested());
        }
    }
  }

  void _onOptionSelected(
    UnifiedSwapOptionSelected event,
    Emitter<UnifiedSwapState> emit,
  ) {
    final quotes = state.quotes;
    if (quotes == null || quotes.byId(event.id) == null) return;
    emit(
      _validated(
        state.copyWith(
          selectedId: event.id,
          manuallySelected: quotes.preselected?.id != event.id,
        ),
      ),
    );
  }
}

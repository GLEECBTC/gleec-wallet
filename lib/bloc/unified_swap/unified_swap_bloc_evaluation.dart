part of 'unified_swap_bloc.dart';

/// Automatic pricing: debounced, versioned, refreshed and expired.
extension _UnifiedSwapEvaluation on UnifiedSwapBloc {
  void _scheduleEvaluation({bool immediate = false, bool quiet = false}) {
    _debounce?.cancel();
    if (!_evaluable(state)) return;
    _debounce = _after(
      immediate ? Duration.zero : _debounceDelay,
      UnifiedSwapEvaluationRequested(quiet: quiet),
    );
  }

  /// Adds [event] after [delay]; nothing once the bloc is closing.
  Timer? _after(Duration delay, UnifiedSwapEvent event) =>
      _closing ? null : Timer(delay, () => add(event));

  bool _evaluable(UnifiedSwapState state) =>
      state.view == UnifiedSwapView.form &&
      state.hasPair &&
      !_catalogLoading &&
      !state.checkingMax &&
      !state.preparingAssets &&
      state.tradingEnabled &&
      (state.issue?.stillPriced ?? true) &&
      (amountOf(state) ?? Decimal.zero) > Decimal.zero;

  Future<void> _onEvaluationRequested(
    UnifiedSwapEvaluationRequested event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    if (!_evaluable(state)) return;
    if (state.maxRequested && state.maxApplied == null) {
      await _onMaxRequested(const UnifiedSwapMaxRequested(), emit);
      return;
    }
    final amount = amountOf(state)!;
    final version = ++_evaluationVersion;
    _evaluationAlternatives = const [];
    final quiet = event.quiet && state.quotes != null;
    if (state.amountMode == SwapAmountMode.fiat && state.pay != null) {
      // Price enrichment must not change the concrete principal underneath
      // a quote. Editing the amount clears this conversion snapshot.
      emit(
        state.copyWith(
          converted: (asset: state.pay!, text: state.inputText, amount: amount),
        ),
      );
    }
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

    final request = _request(state, amount, automatic: event.quiet);
    _stopQuoteWatch();
    final done = Completer<void>();
    _finishQuoteWatch = () {
      if (!done.isCompleted) done.complete();
    };
    _quoteSubscription = _repository
        .watchQuotes(request, timeout: _evaluationTimeout, scope: _quoteScope)
        .listen(
          (update) {
            if (emit.isDone || version != _evaluationVersion || _closing) {
              return;
            }
            _applyQuoteUpdate(emit, update, request: request, quiet: quiet);
          },
          onError: (Object error) {
            if (!emit.isDone && version == _evaluationVersion && !_closing) {
              _failEvaluation(
                emit,
                SwapQuoteFailure(
                  source: SwapLiquiditySource.routed,
                  kind: error is TimeoutException
                      ? SwapQuoteFailureKind.timeout
                      : SwapQuoteFailureKind.unknown,
                ),
                quiet: quiet || state.selectedQuote != null,
              );
            }
            if (!done.isCompleted) done.complete();
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
          cancelOnError: true,
        );
    await done.future;
    if (version == _evaluationVersion) {
      _quoteSubscription = null;
      _finishQuoteWatch = null;
    }
  }

  void _applyQuoteUpdate(
    Emitter<UnifiedSwapState> emit,
    SwapQuoteUpdate update, {
    required SwapQuoteRequest request,
    required bool quiet,
  }) {
    final received = update.quotes;
    final result = _evaluationAlternatives.isEmpty || request.maxSource != null
        ? received
        : UnifiedSwapRepository.rank(
            [
              ...received.options,
              for (final alternative in _evaluationAlternatives)
                if (received.byId(alternative.id) == null &&
                    alternative.from == request.from &&
                    alternative.to == request.to &&
                    alternative.sellAmount == request.amount &&
                    !alternative.isExpiredAt(_now()))
                  _repository.pricing.price(alternative),
            ],
            received.failures,
            comparisonComplete: received.comparisonComplete,
          );
    emit(
      state.copyWith(
        quotesPending: !update.sourcesComplete,
        pricingPending: !update.pricingComplete,
      ),
    );
    if (result.isEmpty) {
      if (update.sourcesComplete) {
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
      }
      return;
    }

    // Once shown, an offer stays selected while another source/pricing read
    // arrives. A later better offer is an explicit choice, never a switch.
    final previous = state.selectedId;
    final keep = previous != null && result.byId(previous) != null;
    // Max clears the old quotes while retaining an explicit option choice.
    // A faster competing source must not erase that still-pending choice.
    if (state.manuallySelected &&
        previous != null &&
        !keep &&
        !update.sourcesComplete) {
      return;
    }
    // During quiet refresh the chosen source may still be outstanding. Keep
    // that known quote until its source settles rather than switching early,
    // and until it expires if that source fails: as when every source does,
    // a failed refresh never hands the choice to another kind of swap.
    final selectedBefore = state.selectedQuote;
    if (quiet && !keep && selectedBefore != null) {
      final status = update.sources[selectedBefore.source];
      if (status == SwapQuoteSourceStatus.pending) return;
      if (status == SwapQuoteSourceStatus.unavailable &&
          !selectedBefore.isExpiredAt(_now())) {
        final limit = result.failures.rateLimit;
        if (limit != null) _pauseForRateLimit(emit, limit);
        return;
      }
    }
    final selected = keep ? result.byId(previous) : result.preselected;
    final maximum = request.maxSource == null
        ? null
        : result.options
              .where(
                (quote) =>
                    quote.source == request.maxSource &&
                    quote.order == request.maxOrder,
              )
              .firstOrNull;
    emit(
      _validated(
        state.copyWith(
          inputText: maximum?.sellAmount.toString(),
          amountMode: maximum == null ? null : SwapAmountMode.token,
          maxApplied: maximum == null
              ? null
              : SwapMaxAmount(
                  amount: maximum.sellAmount,
                  reservedForFees:
                      maximum.maxRetainedBalance ??
                      maximum.fundingOnTopIn(maximum.from),
                  feeAsset: state.maxApplied?.feeAsset,
                  reserveCovers:
                      state.maxApplied?.reserveCovers ??
                      SwapMaxReserve.networkFees,
                  source: request.maxSource,
                  quote: maximum,
                ),
          evaluation: SwapEvaluationStatus.ready,
          quotes: result,
          selectedId: selected?.id,
          clearSelectedId: selected == null,
          manuallySelected: keep && state.manuallySelected,
          clearFailure: true,
          failures: result.failures,
          clearRateLimit: result.failures.rateLimit == null,
        ),
      ),
    );
    _requestMissingFunding();
    _armTimers(selected);
    if (result.failures.rateLimit case final limit?) {
      _pauseForRateLimit(emit, limit);
    }
  }

  void _failEvaluation(
    Emitter<UnifiedSwapState> emit,
    SwapQuoteFailure failure, {
    required bool quiet,
    List<SwapQuoteFailure> all = const [],
  }) {
    final failures = all.isEmpty ? [failure] : all;
    // Whichever failure explains the attempt, a source refused for its rate
    // limit is not asked again until its pause ends.
    final limit = failures.rateLimit;
    // A refresh that fails keeps the options it had until they expire:
    // replacing a working quote with an error because one re-price blipped
    // would punish the user for waiting.
    if (quiet && state.selectedQuote != null) {
      emit(state.copyWith(quotesPending: false, pricingPending: false));
      if (limit != null) _pauseForRateLimit(emit, limit);
      return;
    }
    // Re-checked, because an issue read from the cleared option's fees no
    // longer has the numbers its message needs.
    emit(
      _validated(
        state.copyWith(
          evaluation: SwapEvaluationStatus.failed,
          failure: failure,
          failures: failures,
          clearQuotes: true,
          clearSelectedId: true,
          hints: _hintsFrom(failures),
        ),
      ),
    );
    if (state.issue == SwapFormIssue.noOffers) _watchOffers(emit);
    if (limit != null) _pauseForRateLimit(emit, limit);
  }

  void _pauseForRateLimit(
    Emitter<UnifiedSwapState> emit,
    SwapQuoteFailure failure,
  ) {
    final until = failure.retryAt ?? _now().add(_rateLimitPause);
    emit(state.copyWith(rateLimitedUntil: until));
    _refresh?.cancel();
    _rateLimit?.cancel();
    final wait = until.difference(_now());
    _rateLimit = _after(
      wait.isNegative ? Duration.zero : wait,
      const UnifiedSwapTimerFired(UnifiedSwapTimerKind.rateLimitOver),
    );
  }

  SwapQuoteRequest _request(
    UnifiedSwapState state,
    Decimal amount, {
    bool automatic = false,
  }) {
    final comparing =
        _comparing == _intentKey(state) ||
        state.selectedQuote?.order == SwapQuoteOrder.fastest ||
        state.maxApplied?.quote?.order == SwapQuoteOrder.fastest;
    final balance = state.balance;
    final signedOut = !state.signedIn;
    return SwapQuoteRequest(
      from: state.pay!,
      to: state.receive!,
      amount: amount,
      orders: {SwapQuoteOrder.cheapest, if (comparing) SwapQuoteOrder.fastest},
      slippage: state.slippage,
      indicative: signedOut || (balance != null && amount > balance),
      signedOut: signedOut,
      automatic: automatic,
      maxSource: state.maxRequested ? state.maxApplied?.source : null,
      maxOrder:
          state.selectedQuote?.order ??
          state.maxApplied?.quote?.order ??
          SwapQuoteOrder.cheapest,
    );
  }

  /// Whether the selected price is kept fresh. A look the balance blocks is
  /// priced once, to spare the aggregator's budget; a signed-out look asks
  /// only the order book, which spends none.
  bool get _keepsFresh =>
      state.issue == null || state.issue == SwapFormIssue.signedOut;

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
    _evaluationAlternatives = [..._evaluationAlternatives, ...added];
    emit(
      _validated(
        state.copyWith(
          checkingAlternatives: false,
          quotes: added.isEmpty
              ? current
              : UnifiedSwapRepository.rank(
                  [...current.options, ...added],
                  current.failures,
                  comparisonComplete: current.comparisonComplete,
                ),
        ),
      ),
    );
  }

  void _onAlternativesDismissed(
    UnifiedSwapAlternativesDismissed event,
    Emitter<UnifiedSwapState> emit,
  ) {
    // A chosen alternative stays priced: it is what the user will start.
    _comparing = null;
  }

  void _armTimers(SwapQuote? selected, {bool shownAgain = false}) {
    _refresh?.cancel();
    _expiry?.cancel();
    if (selected == null) return;
    if (_keepsFresh) {
      // Renewed at the same age however it got here: reused from moments
      // ago, or shown again after a while.
      final due = _refreshInterval - _now().difference(selected.quotedAt);
      final Duration wait;
      if (due > _refreshInterval) {
        wait = _refreshInterval;
      } else if (due > Duration.zero) {
        wait = due;
      } else {
        // Shown again late, a price would expire before its refresh: renew
        // now. One priced already this old waits a full interval, so a
        // source whose clock runs behind cannot set off a loop.
        wait = shownAgain ? Duration.zero : _refreshInterval;
      }
      _refresh = _after(
        wait,
        const UnifiedSwapTimerFired(UnifiedSwapTimerKind.refresh),
      );
    }
    _armExpiry(selected);
  }

  void _armExpiry(SwapQuote quote) {
    _expiry?.cancel();
    final untilExpiry = quote.expiresAt.difference(_now());
    _expiry = _after(
      untilExpiry.isNegative ? Duration.zero : untilExpiry,
      const UnifiedSwapTimerFired(UnifiedSwapTimerKind.expiry),
    );
  }

  void _onTimerFired(
    UnifiedSwapTimerFired event,
    Emitter<UnifiedSwapState> emit,
  ) {
    switch (event.kind) {
      case UnifiedSwapTimerKind.refresh:
        final paused = state.rateLimitedUntil?.isAfter(_now()) ?? false;
        final idle = _now().difference(_lastInteraction) >= _idleLimit;
        if (_present &&
            !idle &&
            !paused &&
            state.view == UnifiedSwapView.form &&
            state.evaluation == SwapEvaluationStatus.ready) {
          add(const UnifiedSwapEvaluationRequested(quiet: true));
        }
      case UnifiedSwapTimerKind.expiry:
        final review = state.review;
        if (state.view == UnifiedSwapView.review && review != null) {
          if (review.canStart && review.quote.isExpiredAt(_now())) {
            emit(
              state.copyWith(
                review: review.copyWith(status: SwapReviewStatus.expired),
              ),
            );
          }
          return;
        }
        final quote = state.selectedQuote;
        if (quote == null || !quote.isExpiredAt(_now())) return;
        if (state.view == UnifiedSwapView.form &&
            state.evaluation == SwapEvaluationStatus.ready) {
          emit(state.copyWith(evaluation: SwapEvaluationStatus.expired));
        }
      case UnifiedSwapTimerKind.offers:
        if (state.issue != SwapFormIssue.noOffers && !_offersUnknown(state)) {
          return;
        }
        final idle = _now().difference(_lastInteraction) >= _offersIdleLimit;
        if (idle || !_present) {
          _watchOffers(emit);
        } else {
          add(const UnifiedSwapOffersRequested(quiet: true));
        }
      case UnifiedSwapTimerKind.rateLimitOver:
        // Only lets the user ask again. The limit can outlast this pause by
        // up to two hours, and asking into it is refused too.
        emit(state.copyWith(clearRateLimit: true));
    }
  }

  Future<void> _onOptionSelected(
    UnifiedSwapOptionSelected event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    final quotes = state.quotes;
    if (quotes == null || quotes.byId(event.id) == null) return;
    final previousSource = state.selectedQuote?.source;
    // On a wide screen this is picked beside the review, which closes unless
    // its start is in doubt.
    final leaveReview = state.view == UnifiedSwapView.review;
    if (leaveReview && (event.id == state.selectedId || _startInDoubt)) {
      return;
    }
    _startVersion++;
    if (state.maxRequested) _invalidate();
    emit(
      _validated(
        state.copyWith(
          selectedId: event.id,
          manuallySelected:
              state.maxRequested || quotes.preselected?.id != event.id,
          view: leaveReview ? UnifiedSwapView.form : null,
          clearReview: leaveReview,
        ),
      ),
    );
    _requestMissingFunding();
    if (state.maxRequested) {
      if (previousSource != state.selectedQuote?.source) {
        add(const UnifiedSwapMaxRequested());
      } else {
        _scheduleEvaluation(immediate: true);
      }
    } else {
      // The evaluation armed timers only for a preselected option.
      _armTimers(state.selectedQuote, shownAgain: leaveReview);
    }
  }
}

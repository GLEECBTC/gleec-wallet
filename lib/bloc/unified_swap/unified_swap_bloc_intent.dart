part of 'unified_swap_bloc.dart';

/// What the user asks for: the pair, the amount and how it is entered.
extension _UnifiedSwapIntent on UnifiedSwapBloc {
  Future<void> _onDraftRestored(
    UnifiedSwapDraftRestored event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    if (_intentApplied || _startInDoubt) return;
    final pay = event.pay == null ? null : _resolveAsset(event.pay!);
    final receive = event.receive == null
        ? null
        : _resolveAsset(event.receive!);
    if (pay == null && receive == null) return;
    _intentApplied = true;
    // A raised allowance belongs to the swap it was set for: it returns with
    // an amount not yet submitted, never after the swap it was sent with.
    if (event.input.trim().isNotEmpty) {
      emit(
        state.copyWith(
          slippage: event.slippage.clamp(swapMinSlippage, swapMaxSlippage),
        ),
      );
    }
    await _setPair(
      emit,
      pay: pay,
      receive: receive == pay ? null : receive,
      amount: event.input,
      amountMode: event.amountMode,
    );
  }

  Future<void> _onPayAssetChanged(
    UnifiedSwapPayAssetChanged event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    if (event.asset == state.pay) return;
    unawaited(_preferences.rememberAsset(event.asset));
    // Choosing what is already on the other side swaps the two, the way
    // people expect a two-sided form to behave.
    final receive = event.asset == state.receive ? state.pay : state.receive;
    await _setPair(
      emit,
      pay: event.asset,
      receive: receive,
      // The amount was in the old asset's units; keeping it would silently
      // re-denominate the trade.
      amount: '',
    );
  }

  Future<void> _onReceiveAssetChanged(
    UnifiedSwapReceiveAssetChanged event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    if (event.asset == state.receive) return;
    unawaited(_preferences.rememberAsset(event.asset));
    final pay = event.asset == state.pay ? state.receive : state.pay;
    await _setPair(
      emit,
      pay: pay,
      receive: event.asset,
      amount: pay == state.pay ? null : '',
    );
  }

  Future<void> _onSidesSwitched(
    UnifiedSwapSidesSwitched event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    if (state.pay == null && state.receive == null) return;
    await _setPair(
      emit,
      pay: state.receive,
      receive: state.pay,
      // The amount was denominated in the old pay asset.
      amount: '',
    );
  }

  Future<void> _onAmountChanged(
    UnifiedSwapAmountChanged event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    if (event.text == state.inputText && !state.maxRequested) return;
    if (_startInDoubt) return;
    _startVersion++;
    _invalidate();
    _amountModeVersion++;
    emit(
      _validated(
        state.copyWith(
          inputText: event.text,
          view: UnifiedSwapView.form,
          clearReview: true,
          clearConverted: true,
          clearMaxApplied: true,
          checkingMax: false,
          clearQuotes: true,
          clearSelectedId: true,
          clearFailure: true,
          evaluation: SwapEvaluationStatus.idle,
          structuralNotice: false,
        ),
      ),
    );
    _scheduleEvaluation();
    // The balance may have moved since the asset was chosen.
    await _reloadBalances(emit, immediate: false);
  }

  void _onAmountModeToggled(
    UnifiedSwapAmountModeToggled event,
    Emitter<UnifiedSwapState> emit,
  ) {
    final pay = state.pay;
    if (pay == null || _startInDoubt) return;
    final price = _repository.pricing.prices.usdPrice(pay);
    if (price == null || price <= Decimal.zero || _decimalsOf(pay) == null) {
      // A missing conversion must never turn a dollar draft into that many
      // crypto units. Keep it separately while the user enters crypto.
      if (state.amountMode == SwapAmountMode.fiat) {
        _fiatDraft = (asset: pay, text: state.inputText);
        _invalidate();
        _amountModeVersion++;
        emit(
          _validated(
            state.copyWith(
              amountMode: SwapAmountMode.token,
              inputText: '',
              clearConverted: true,
              clearQuotes: true,
              clearSelectedId: true,
              evaluation: SwapEvaluationStatus.idle,
            ),
          ),
        );
        unawaited(
          _preferences.rememberFiatAmount(false).catchError((Object _) {}),
        );
      } else if (_fiatDraft case final draft? when draft.asset == pay) {
        _invalidate();
        _amountModeVersion++;
        emit(
          _validated(
            state.copyWith(
              amountMode: SwapAmountMode.fiat,
              inputText: draft.text,
              clearConverted: true,
              clearQuotes: true,
              clearSelectedId: true,
              evaluation: SwapEvaluationStatus.idle,
            ),
          ),
        );
        unawaited(
          _preferences.rememberFiatAmount(true).catchError((Object _) {}),
        );
      }
      return;
    }
    _amountModeVersion++;
    // Convert what is typed, so toggling never changes the amount traded.
    final typed = amountOf(state);
    final decimals = _decimalsOf(pay);
    final amount = typed == null || decimals == null
        ? typed
        : typed.floor(scale: decimals);
    final nextMode = state.amountMode == SwapAmountMode.token
        ? SwapAmountMode.fiat
        : SwapAmountMode.token;
    final restoreDraft =
        nextMode == SwapAmountMode.fiat &&
        state.inputText.isEmpty &&
        _fiatDraft?.asset == pay;
    final text = restoreDraft
        ? _fiatDraft!.text
        : amount == null
        ? state.inputText
        : nextMode == SwapAmountMode.fiat
        ? (amount * price).floor(scale: 2).toString()
        : amount.toString();
    final converted = amount != null && nextMode == SwapAmountMode.fiat
        ? (asset: pay, text: text, amount: amount)
        : null;
    emit(
      _validated(
        state.copyWith(
          amountMode: nextMode,
          inputText: text,
          converted: converted,
          clearConverted: converted == null,
        ),
      ),
    );
    unawaited(
      _preferences
          .rememberFiatAmount(nextMode == SwapAmountMode.fiat)
          .catchError((Object _) {}),
    );
    // Converting can also lift what kept the amount from being priced, as
    // more decimals than the asset has.
    if (restoreDraft ||
        (state.selectedQuote == null &&
            state.evaluation == SwapEvaluationStatus.idle)) {
      _scheduleEvaluation(immediate: true);
    }
  }

  void _onSlippageChanged(
    UnifiedSwapSlippageChanged event,
    Emitter<UnifiedSwapState> emit,
  ) {
    final slippage = event.slippage.clamp(swapMinSlippage, swapMaxSlippage);
    if (slippage == state.slippage) return;
    // Also set beside the review on a wide screen.
    final leaveReview = state.view == UnifiedSwapView.review;
    if (leaveReview && _startInDoubt) return;
    _startVersion++;
    _invalidate();
    emit(
      _validated(
        state.copyWith(
          slippage: slippage,
          clearQuotes: true,
          clearSelectedId: true,
          clearFailure: true,
          evaluation: SwapEvaluationStatus.idle,
          view: leaveReview ? UnifiedSwapView.form : null,
          clearReview: leaveReview,
        ),
      ),
    );
    _scheduleEvaluation(immediate: true);
  }

  void _onAmountSuggested(
    UnifiedSwapAmountSuggested event,
    Emitter<UnifiedSwapState> emit,
  ) {
    if (_startInDoubt) return;
    _invalidate();
    _amountModeVersion++;
    emit(
      _validated(
        state.copyWith(
          inputText: event.amount.toString(),
          amountMode: SwapAmountMode.token,
          clearMaxApplied: true,
          checkingMax: false,
          clearQuotes: true,
          clearSelectedId: true,
          clearFailure: true,
          evaluation: SwapEvaluationStatus.idle,
          structuralNotice: false,
        ),
      ),
    );
    _scheduleEvaluation(immediate: true);
  }

  Future<void> _onMaxRequested(
    UnifiedSwapMaxRequested event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    final pay = state.pay;
    final receive = state.receive;
    final balance = state.balance;
    if (pay == null ||
        balance == null ||
        state.checkingMax ||
        state.preparingAssets ||
        state.loadingAssets ||
        state.preparationFailedAsset != null) {
      return;
    }
    _amountModeVersion++;
    if (_startInDoubt) return;
    if (receive == null) {
      // Without a destination no source can say what fees to keep; the whole
      // balance is the honest upper bound until one is chosen.
      _invalidate();
      emit(
        _validated(
          state.copyWith(
            inputText: balance.toString(),
            amountMode: SwapAmountMode.token,
            clearMaxApplied: true,
          ),
        ),
      );
      return;
    }

    // Keep what the selected route needs, read before its options clear.
    final selected = state.selectedQuote;
    final preferred = selected?.source;
    final version = ++_maxVersion;
    // The balance is provisional until KDF returns a fundable Max quote.
    // A rejection clears prices and blocks review.
    _invalidate();
    emit(
      _validated(
        state.copyWith(
          inputText: balance.toString(),
          amountMode: SwapAmountMode.token,
          checkingMax: true,
          maxRequested: true,
          clearMaxApplied: true,
          clearQuotes: true,
          clearSelectedId: true,
          clearFailure: true,
          evaluation: SwapEvaluationStatus.idle,
        ),
      ),
    );

    Map<SwapLiquiditySource, SwapMaxAmount> maxes;
    try {
      maxes = await _repository
          .maxAmounts(
            from: pay,
            to: receive,
            balance: balance,
            preferred: preferred,
            order: selected?.order ?? SwapQuoteOrder.cheapest,
            slippage: state.slippage,
          )
          .timeout(_evaluationTimeout * 3);
    } on SwapMaxUnavailableException catch (error) {
      if (version != _maxVersion || !state.checkingMax) return;
      emit(state.copyWith(checkingMax: false));
      _failEvaluation(emit, error.failure, quiet: false);
      return;
    } on TimeoutException {
      if (version != _maxVersion || !state.checkingMax) return;
      emit(state.copyWith(checkingMax: false));
      _failEvaluation(
        emit,
        SwapQuoteFailure(
          source: preferred ?? SwapLiquiditySource.routed,
          kind: SwapQuoteFailureKind.timeout,
        ),
        quiet: false,
      );
      return;
    }
    // Typing, another pair or wallet, or a later Max has taken over.
    if (version != _maxVersion || !state.checkingMax) return;

    // Take the larger, so at least one source can fill it.
    final max = maxes.isEmpty
        ? null
        : maxes.values.reduce((a, b) => a.amount >= b.amount ? a : b);
    if (max == null) {
      emit(state.copyWith(checkingMax: false));
      _failEvaluation(
        emit,
        SwapQuoteFailure(
          source: preferred ?? SwapLiquiditySource.routed,
          kind: SwapQuoteFailureKind.noRoute,
        ),
        quiet: false,
      );
      return;
    }
    emit(
      _validated(
        state.copyWith(
          inputText: max.amount.toString(),
          // The balance kept is in dollars if the unit was switched meanwhile.
          amountMode: SwapAmountMode.token,
          maxApplied: max,
          selectedId: maxes[preferred] == max ? selected?.id : null,
          manuallySelected: selected != null && maxes[preferred] == max,
          checkingMax: false,
        ),
      ),
    );
    _scheduleEvaluation(immediate: true);
  }

  Future<void> _onProgressLeft(
    UnifiedSwapProgressLeft event,
    Emitter<UnifiedSwapState> emit,
  ) => _resetForm(emit, keepPair: true);

  Future<void> _onResetRequested(
    UnifiedSwapResetRequested event,
    Emitter<UnifiedSwapState> emit,
  ) => _resetForm(emit, keepPair: event.keepPair);

  Future<void> _resetForm(
    Emitter<UnifiedSwapState> emit, {
    required bool keepPair,
  }) async {
    if (state.review?.status == SwapReviewStatus.starting) return;
    _invalidate();
    _startVersion++;
    _fiatDraft = null;
    _amountModeVersion++;
    emit(
      _validated(
        state.copyWith(
          view: UnifiedSwapView.form,
          inputText: '',
          clearConverted: true,
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
    await _preparePair(emit);
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
      amountMode: event.amount == null ? null : SwapAmountMode.token,
    );
  }
}

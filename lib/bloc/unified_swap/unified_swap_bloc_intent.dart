part of 'unified_swap_bloc.dart';

/// What the user asks for: the pair, the amount and how it is entered.
extension _UnifiedSwapIntent on UnifiedSwapBloc {
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

  void _onAmountChanged(
    UnifiedSwapAmountChanged event,
    Emitter<UnifiedSwapState> emit,
  ) {
    if (event.text == state.inputText && !state.maxRequested) return;
    _invalidate();
    emit(
      _validated(
        state.copyWith(
          inputText: event.text,
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
  }

  void _onAmountModeToggled(
    UnifiedSwapAmountModeToggled event,
    Emitter<UnifiedSwapState> emit,
  ) {
    final pay = state.pay;
    if (pay == null) return;
    final price = _repository.pricing.prices.usdPrice(pay);
    if (price == null || price <= Decimal.zero) return;
    // Convert what is typed, so toggling never changes the amount traded.
    final amount = amountOf(state);
    final nextMode = state.amountMode == SwapAmountMode.token
        ? SwapAmountMode.fiat
        : SwapAmountMode.token;
    final text = amount == null
        ? state.inputText
        : nextMode == SwapAmountMode.fiat
        ? (amount * price).floor(scale: 2).toString()
        : amount.toString();
    emit(_validated(state.copyWith(amountMode: nextMode, inputText: text)));
  }

  void _onSlippageChanged(
    UnifiedSwapSlippageChanged event,
    Emitter<UnifiedSwapState> emit,
  ) {
    final slippage = event.slippage.clamp(swapMinSlippage, swapMaxSlippage);
    if (slippage == state.slippage) return;
    _invalidate();
    emit(
      _validated(
        state.copyWith(
          slippage: slippage,
          clearQuotes: true,
          clearSelectedId: true,
          clearFailure: true,
          evaluation: SwapEvaluationStatus.idle,
        ),
      ),
    );
    _scheduleEvaluation(immediate: true);
  }

  void _onAmountSuggested(
    UnifiedSwapAmountSuggested event,
    Emitter<UnifiedSwapState> emit,
  ) {
    _invalidate();
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
    if (pay == null || balance == null || state.checkingMax) return;
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
}

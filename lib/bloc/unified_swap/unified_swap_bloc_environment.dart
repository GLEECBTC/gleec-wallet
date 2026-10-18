part of 'unified_swap_bloc.dart';

/// Where the form is shown, who is signed in, and what the wallet holds.
extension _UnifiedSwapEnvironment on UnifiedSwapBloc {
  bool get _present => _visible && _foreground;

  Future<void> _onVisibilityChanged(
    UnifiedSwapVisibilityChanged event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    final wasPresent = _present;
    _visible = event.visible;
    await _onPresenceChanged(emit, wasPresent: wasPresent);
  }

  Future<void> _onForegroundChanged(
    UnifiedSwapForegroundChanged event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    final wasPresent = _present;
    _foreground = event.foreground;
    await _onPresenceChanged(emit, wasPresent: wasPresent);
  }

  Future<void> _onPresenceChanged(
    Emitter<UnifiedSwapState> emit, {
    required bool wasPresent,
  }) async {
    if (!_present) {
      _refresh?.cancel();
      _offersWatch?.cancel();
      return;
    }
    _onShown();
    // Funds may have moved while the form was away.
    if (!wasPresent) await _reloadBalances(emit);
  }

  /// [_loadBalances], pricing the form if the balances lift what stopped
  /// it being priced.
  Future<void> _reloadBalances(
    Emitter<UnifiedSwapState> emit, {
    bool immediate = true,
  }) async {
    final blocked = !(state.issue?.stillPriced ?? true);
    await _loadBalances(emit);
    if (blocked && state.view == UnifiedSwapView.form) {
      _scheduleEvaluation(immediate: immediate);
    }
  }

  void _onShown() {
    if (state.view != UnifiedSwapView.form) return;
    if (state.issue == SwapFormIssue.noOffers || _offersUnknown(state)) {
      add(const UnifiedSwapOffersRequested(quiet: true));
      return;
    }
    final quote = state.selectedQuote;
    final stale =
        state.evaluation == SwapEvaluationStatus.expired ||
        (quote != null && quote.isExpiredAt(_now()));
    if (stale && _keepsFresh) {
      add(const UnifiedSwapEvaluationRequested());
    } else {
      _armTimers(quote, shownAgain: true);
    }
  }

  Future<void> _onCapabilitiesChanged(
    UnifiedSwapCapabilitiesChanged event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    if (event.tradingEnabled == state.tradingEnabled &&
        event.clockValid == state.clockValid &&
        event.signedIn == state.signedIn &&
        event.hardwareWallet == state.hardwareWallet) {
      return;
    }
    final signingChanged = event.signedIn != state.signedIn;
    if (!signingChanged) {
      // Without trading the review cannot go ahead, and the form says why.
      final leaveReview =
          !event.tradingEnabled &&
          state.view == UnifiedSwapView.review &&
          !_startInDoubt;
      if (leaveReview) _startVersion++;
      emit(
        state.copyWith(
          tradingEnabled: event.tradingEnabled,
          clockValid: event.clockValid,
          hardwareWallet: event.hardwareWallet,
          view: leaveReview ? UnifiedSwapView.form : null,
          clearReview: leaveReview,
        ),
      );
    } else {
      // Signed-out looks have no fees; signed-in quotes and balances are that
      // wallet's. A start in doubt keeps its review: its answer must be seen.
      _invalidate();
      _walletEpoch++;
      final leaveReview =
          state.view == UnifiedSwapView.review && !_startInDoubt;
      if (leaveReview) _startVersion++;
      emit(
        _validated(
          state.copyWith(
            tradingEnabled: event.tradingEnabled,
            clockValid: event.clockValid,
            signedIn: event.signedIn,
            hardwareWallet: event.hardwareWallet,
            view: leaveReview ? UnifiedSwapView.form : null,
            clearReview: leaveReview,
            evaluation: SwapEvaluationStatus.idle,
            clearQuotes: true,
            clearSelectedId: true,
            clearFailure: true,
            clearMaxApplied: true,
            checkingMax: false,
            clearBalance: true,
            clearFeeBalance: true,
            clearPayAddress: true,
            clearReceiveAddress: true,
          ),
        ),
      );
      await _loadBalances(emit);
      await _loadAddresses(emit);
    }
    if (event.tradingEnabled && state.view == UnifiedSwapView.form) {
      // Signing in makes the wallet's own orders known, and those are no
      // counterparty.
      add(const UnifiedSwapOffersRequested());
      _scheduleEvaluation(immediate: true);
    }
  }

  Future<void> _onBalancesRefreshed(
    UnifiedSwapBalancesRefreshed event,
    Emitter<UnifiedSwapState> emit,
  ) => _loadBalances(emit);

  Future<void> _loadBalances(Emitter<UnifiedSwapState> emit) async {
    final pay = state.pay;
    if (pay == null) {
      emit(state.copyWith(clearBalance: true, clearFeeBalance: true));
      return;
    }
    final epoch = _walletEpoch;
    _showHeld(emit, pay, epoch, await _heldOf(pay));
  }

  Future<_Held> _heldOf(AssetId asset) async {
    final feeAsset = asset.parentId;
    final balance = await _read(asset);
    final feeBalance = feeAsset == null ? null : await _read(feeAsset);
    return (balance: balance, feeBalance: feeBalance);
  }

  void _showHeld(
    Emitter<UnifiedSwapState> emit,
    AssetId pay,
    int epoch,
    _Held held,
  ) {
    if (state.pay != pay || epoch != _walletEpoch) return;
    emit(
      _validated(
        state.copyWith(
          balance: held.balance,
          clearBalance: held.balance == null,
          feeBalance: held.feeBalance,
          clearFeeBalance: held.feeBalance == null,
        ),
      ),
    );
  }

  Future<Decimal?> _read(AssetId asset) async {
    try {
      return await _spendableBalance(asset);
    } on Object {
      return null;
    }
  }

  Future<void> _loadAddresses(Emitter<UnifiedSwapState> emit) async {
    final pay = state.pay;
    final receive = state.receive;
    final epoch = _walletEpoch;
    final payAddress = pay == null ? null : await _address(pay);
    final receiveAddress = receive == null ? null : await _address(receive);
    if (state.pay != pay || state.receive != receive) return;
    if (epoch != _walletEpoch) return;
    emit(
      state.copyWith(
        payAddress: payAddress,
        clearPayAddress: payAddress == null,
        receiveAddress: receiveAddress,
        clearReceiveAddress: receiveAddress == null,
      ),
    );
  }

  Future<String?> _address(AssetId asset) async {
    try {
      return await _addressOf(asset);
    } on Object {
      return null;
    }
  }
}

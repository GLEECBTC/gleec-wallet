part of 'unified_swap_bloc.dart';

/// Catalog lifecycle, direct entry intents and immediate pair selection.
extension _UnifiedSwapPair on UnifiedSwapBloc {
  // ------------------------------------------------------------- lifecycle

  Future<void> _onStarted(
    UnifiedSwapStarted event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    final epoch = _walletEpoch;
    _catalogLoading = true;
    final SwapCatalog read;
    try {
      read = await _repository.catalog(signedIn: state.signedIn);
    } finally {
      _catalogLoading = false;
    }
    if (emit.isDone || epoch != _walletEpoch || _closing) return;
    // A later read may have returned first; the repository keeps the latest.
    final catalog = _repository.current ?? read;
    emit(_validated(state.copyWith(catalog: catalog, loadingAssets: false)));
    // Which pairs only the order book trades was unknown until now.
    if (state.pay != null || state.receive != null) {
      add(const UnifiedSwapOffersRequested());
    }
    if (_pairChosen) {
      // A selection may have returned while the catalog was still loading.
      // Preparation versions discard any older read this supersedes.
      if (state.pay != null || state.receive != null) {
        await _preparePair(emit);
      }
      return;
    }
    // Signed out there is no pair to find, and looking queues on the sign-in
    // lock.
    if (!state.signedIn) return;

    final pair = await _defaultPair({
      for (final source in catalog.sources) ...source.quotable,
    });
    if (pair == null || _pairChosen) return;
    await _setPair(emit, pay: pair.pay, receive: pair.receive);
  }

  /// Whether either side was chosen, so no default pair replaces it.
  bool get _pairChosen =>
      state.pay != null || state.receive != null || _intentApplied;

  Future<void> _refreshCatalog(Emitter<UnifiedSwapState> emit) async {
    final epoch = _walletEpoch;
    final read = await _repository.catalog(signedIn: state.signedIn);
    if (emit.isDone || epoch != _walletEpoch) return;
    final catalog = _repository.current ?? read;
    emit(_validated(state.copyWith(catalog: catalog, loadingAssets: false)));
  }

  Future<void> _onCatalogRefreshRequested(
    UnifiedSwapCatalogRefreshRequested event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    await _refreshCatalog(emit);
    _scheduleEvaluation(immediate: true);
  }

  void _onCatalogArrived(
    UnifiedSwapCatalogArrived event,
    Emitter<UnifiedSwapState> emit,
  ) {
    final catalog = _repository.current;
    if (catalog == null || catalog == state.catalog) return;
    final support = state.pairSupport;
    emit(_validated(state.copyWith(catalog: catalog)));
    // Only a change in who can price the pair is worth a request.
    if (state.view == UnifiedSwapView.form && state.pairSupport != support) {
      add(const UnifiedSwapOffersRequested());
      _scheduleEvaluation(immediate: true);
    }
  }

  Future<void> _onAssetActivated(
    UnifiedSwapAssetActivated event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    _invalidate();
    await _refreshCatalog(emit);
    await _preparePair(emit, chooseMode: false);
    // Max asked before the asset to receive was active could not read every
    // fee it must keep back, such as the gas to claim a token.
    if (state.maxApplied != null && event.asset == state.receive) {
      add(const UnifiedSwapMaxRequested());
    }
    _scheduleEvaluation(immediate: true);
  }

  Future<void> _onIntentApplied(
    UnifiedSwapIntentApplied event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    final pay = event.pay == null ? null : _resolveAsset(event.pay!);
    final receive = event.receive == null
        ? null
        : _resolveAsset(event.receive!);
    if (pay == null && receive == null) return;
    _intentApplied = true;
    await _setPair(
      emit,
      pay: pay ?? state.pay,
      receive: receive == pay ? null : (receive ?? state.receive),
      amount: event.amount,
      amountMode: event.amount == null ? null : event.amountMode,
    );
  }

  Future<void> _setPair(
    Emitter<UnifiedSwapState> emit, {
    AssetId? pay,
    AssetId? receive,
    String? amount,
    SwapAmountMode? amountMode,
  }) async {
    if (_startInDoubt) return;
    await _applyPair(
      emit,
      pay: pay,
      receive: receive,
      amount: amount,
      amountMode: amountMode,
    );
  }

  Future<void> _applyPair(
    Emitter<UnifiedSwapState> emit, {
    AssetId? pay,
    AssetId? receive,
    String? amount,
    SwapAmountMode? amountMode,
  }) async {
    // Max, applied or still asking, asks again for a new asset to receive,
    // rather than leave an amount sized for the old pair, or the whole
    // balance it shows while asking.
    final remax =
        (state.maxRequested || state.checkingMax || state.maxApplied != null) &&
        amount == null &&
        pay == state.pay;
    _invalidate();
    _startVersion++;
    if (pay != state.pay) _fiatDraft = null;
    emit(
      _validated(
        state.copyWith(
          view: UnifiedSwapView.form,
          pay: pay,
          receive: receive,
          clearPay: pay == null,
          clearReceive: receive == null,
          inputText: amount ?? state.inputText,
          amountMode: amount == null ? null : amountMode,
          // Until the new asset's own is read, the old balance would show
          // under its ticker and be what Max fills in.
          preparingAssets: true,
          clearPreparationFailure: true,
          clearPayAddress: pay != state.pay,
          clearReceiveAddress: receive != state.receive,
          clearBalance: pay != state.pay,
          clearFeeBalance: pay != state.pay,
          clearConverted: pay != state.pay,
          clearQuotes: true,
          clearSelectedId: true,
          clearFailure: true,
          clearMaxApplied: true,
          checkingMax: false,
          clearReview: true,
          evaluation: SwapEvaluationStatus.idle,
          structuralNotice: false,
        ),
      ),
    );
    _offersWatch?.cancel();
    add(const UnifiedSwapOffersRequested());
    // Direct asset-detail intents can arrive before the shell starts its
    // catalog read. Ensure preparation will resume when that read completes.
    if (state.loadingAssets && !_catalogLoading) {
      add(const UnifiedSwapStarted());
    }
    if (amountMode != null && amount?.isNotEmpty == true) _amountModeVersion++;
    final amountVersion = _amountModeVersion;
    final preparation = _preparationVersion + 1;
    await _preparePair(
      emit,
      chooseMode:
          amountMode == null && (amount?.isEmpty ?? state.inputText.isEmpty),
    );
    if (remax &&
        amountVersion == _amountModeVersion &&
        preparation == _preparationVersion &&
        !emit.isDone &&
        pay == state.pay &&
        receive == state.receive &&
        !state.preparingAssets &&
        state.preparationFailedAsset == null) {
      add(const UnifiedSwapMaxRequested());
    }
  }
}

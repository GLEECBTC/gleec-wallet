part of 'unified_swap_bloc.dart';

/// Prepares the selected pair independently of the picker that chose it.
extension _UnifiedSwapPreparation on UnifiedSwapBloc {
  Future<void> _onPreparationRetried(
    UnifiedSwapPreparationRetried event,
    Emitter<UnifiedSwapState> emit,
  ) => _preparePair(
    emit,
    chooseMode: state.inputText.isEmpty,
    activateRequired: state.failure?.kind == SwapQuoteFailureKind.assetInactive
        ? state.failure?.asset ?? state.pay
        : null,
  );

  Future<void> _preparePair(
    Emitter<UnifiedSwapState> emit, {
    bool chooseMode = true,
    AssetId? activateRequired,
  }) async {
    final version = ++_preparationVersion;
    final epoch = _walletEpoch;
    final pay = state.pay;
    final receive = state.receive;
    bool current() =>
        !emit.isDone &&
        !_closing &&
        version == _preparationVersion &&
        epoch == _walletEpoch &&
        pay == state.pay &&
        receive == state.receive;

    _quoteScope = Object();
    if (!state.signedIn) {
      // The service can resolve native/configured precision without a wallet.
      // Unknown token metadata stays unavailable without an authenticated RPC.
      if (pay != null) await _loadSpendDecimals(pay, current: current);
      if (!current()) return;
      emit(
        _validated(
          state.copyWith(preparingAssets: false, clearPreparationFailure: true),
        ),
      );
      _scheduleEvaluation(immediate: true);
      return;
    }
    // The arriving catalog restarts preparation. Do not activate merely
    // because a source has not finished listing its assets yet.
    if (state.loadingAssets) return;
    emit(state.copyWith(preparingAssets: true, clearPreparationFailure: true));
    // Unit selection and preparation are independent. A slow balance read
    // must not leave a priced empty field in crypto until after typing starts.
    final mode = chooseMode && state.inputText.isEmpty
        ? _chooseAmountMode(emit, current: current)
        : Future<void>.value();
    AssetId? preparing;
    try {
      if (state.inactiveAsset != null) {
        await _refreshCatalog(emit).timeout(_evaluationTimeout);
        if (!current()) return;
      }
      final activate = _activateAsset;
      for (final asset in {
        if (pay != null) pay,
        if (receive != null) receive,
        if (activateRequired != null) activateRequired,
      }) {
        if (state.catalog.isActive(asset) && asset != activateRequired) {
          continue;
        }
        if (activate == null || !state.tradingEnabled) {
          emit(_validated(state.copyWith(preparingAssets: false)));
          return;
        }
        preparing = asset;
        await activate(asset).timeout(_evaluationTimeout * 3);
        if (!current()) return;
      }
      if (preparing != null) {
        await _refreshCatalog(emit).timeout(_evaluationTimeout);
        if (!current()) return;
        if (state.inactiveAsset != null) {
          preparing = state.inactiveAsset;
          throw StateError('Asset is not ready after activation');
        }
      }
      await Future.wait([
        _loadBalances(emit),
        _loadAddresses(emit),
        if (pay != null) _loadSpendDecimals(pay, current: current),
      ]);
      if (!current()) return;
      final missing =
          pay != null &&
              ((_spendDecimalsOf != null && _decimalsOf(pay) == null) ||
                  state.balance == null ||
                  state.payAddress == null ||
                  (pay.parentId != null && state.feeBalance == null))
          ? pay
          : receive != null && state.receiveAddress == null
          ? receive
          : null;
      emit(
        _validated(
          state.copyWith(
            preparingAssets: false,
            preparationFailedAsset: missing,
            clearPreparationFailure: missing == null,
          ),
        ),
      );
      if (!current()) return;
      _scheduleEvaluation(immediate: true);
    } on Object {
      if (!current()) return;
      emit(
        _validated(
          state.copyWith(
            preparingAssets: false,
            preparationFailedAsset: preparing ?? pay ?? receive,
          ),
        ),
      );
    } finally {
      await mode;
    }
  }

  Future<void> _loadSpendDecimals(
    AssetId pay, {
    required bool Function() current,
  }) async {
    final read = _spendDecimalsOf;
    if (read == null) return;
    int? decimals;
    try {
      decimals = await read(pay).timeout(_evaluationTimeout);
    } on Object {
      // The existing preparation retry keeps the pair and dollar draft.
    }
    if (!current()) return;
    if (decimals != null && decimals >= 0 && decimals <= 255) {
      _resolvedSpendDecimals[pay] = decimals;
    } else {
      _resolvedSpendDecimals.remove(pay);
    }
  }

  /// Picks a unit only for an untouched empty field. An arriving price can
  /// never reinterpret a number that the user has already started entering.
  Future<void> _chooseAmountMode(
    Emitter<UnifiedSwapState> emit, {
    required bool Function() current,
  }) async {
    final pay = state.pay;
    if (pay == null) return;
    final version = _amountModeVersion;
    final preferred = await _preferences.prefersFiatAmount();
    if (!current() ||
        version != _amountModeVersion ||
        state.inputText.isNotEmpty) {
      return;
    }
    if (preferred == false) {
      emit(_validated(state.copyWith(amountMode: SwapAmountMode.token)));
      return;
    }
    var price = _repository.pricing.prices.usdPrice(pay);
    if (price == null || price <= Decimal.zero) {
      // Crypto remains usable while a fiat conversion is unavailable.
      emit(_validated(state.copyWith(amountMode: SwapAmountMode.token)));
      try {
        await _repository.pricing.prices
            .warm([pay])
            .timeout(const Duration(seconds: 2));
      } on Object {
        return;
      }
      if (!current() ||
          version != _amountModeVersion ||
          state.inputText.isNotEmpty) {
        return;
      }
      price = _repository.pricing.prices.usdPrice(pay);
    }
    if (price != null && price > Decimal.zero) {
      emit(_validated(state.copyWith(amountMode: SwapAmountMode.fiat)));
    }
  }
}

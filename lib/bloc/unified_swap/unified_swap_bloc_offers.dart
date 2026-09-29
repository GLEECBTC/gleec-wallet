part of 'unified_swap_bloc.dart';

/// What the order book offers for the chosen assets: read when the pair
/// changes, and checked again while a pair has no offers.
extension _UnifiedSwapOffers on UnifiedSwapBloc {
  Future<void> _onOffersRequested(
    UnifiedSwapOffersRequested event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    _offersWatch?.cancel();
    if (state.view != UnifiedSwapView.form || !state.tradingEnabled) return;
    final pay = state.pay;
    final receive = state.receive;
    final epoch = _walletEpoch;
    final version = ++_offersVersion;
    bool current() =>
        !_closing &&
        version == _offersVersion &&
        state.view == UnifiedSwapView.form &&
        state.pay == pay &&
        state.receive == receive &&
        epoch == _walletEpoch;

    final hints = state.hints;
    final pairRead =
        pay != null &&
            receive != null &&
            pay != receive &&
            _repository.orderBookOnly(pay, receive)
        ? _repository.offers(pay, receive)
        : null;
    // Who trades each asset is read once per asset: offers come and go, but
    // the pickers only need to know who trades at all.
    final payRead =
        pay != null && (event.recount || hints.payCounts?.anchor != pay)
        ? _repository.offeredWith(pay, anchorPays: true)
        : null;
    final receiveRead =
        receive != null &&
            (event.recount || hints.receiveCounts?.anchor != receive)
        ? _repository.offeredWith(receive, anchorPays: false)
        : null;

    if (pairRead != null) {
      final offers = await pairRead;
      if (!current()) return;
      _applyPairOffers(emit, pay!, receive!, offers);
    }
    if (payRead != null) {
      final offered = await payRead;
      if (!current()) return;
      if (offered != null) {
        emit(
          state.copyWith(
            hints: state.hints.copyWith(
              payCounts: SwapOfferCounts(pay!, offered),
            ),
          ),
        );
      }
    }
    if (receiveRead != null) {
      final offered = await receiveRead;
      if (!current()) return;
      if (offered != null) {
        emit(
          state.copyWith(
            hints: state.hints.copyWith(
              receiveCounts: SwapOfferCounts(receive!, offered),
            ),
          ),
        );
      }
    }
  }

  void _applyPairOffers(
    Emitter<UnifiedSwapState> emit,
    AssetId pay,
    AssetId receive,
    SwapOrderBookOffers? offers,
  ) {
    final blocked = state.issue == SwapFormIssue.noOffers;
    final none = offers?.isEmpty ?? false;
    // Pricing a pair no one offers can only miss.
    if (none) _invalidate();
    emit(
      _validated(
        state.copyWith(
          hints: offers == null
              ? state.hints.copyWith(clearOffers: true)
              : state.hints.copyWith(pair: (pay, receive), offers: offers),
          clearQuotes: none,
          clearSelectedId: none,
          clearFailure: none,
          evaluation: none ? SwapEvaluationStatus.idle : null,
        ),
      ),
    );
    _watchOffers(emit);
    if (blocked && state.issue != SwapFormIssue.noOffers) {
      _scheduleEvaluation(immediate: true);
    }
  }

  /// Keeps checking a pair no one offers while someone is looking, and says
  /// when it has stopped. Offers not read yet are asked for again sooner:
  /// the engine may still be finding its peers.
  void _watchOffers(Emitter<UnifiedSwapState> emit) {
    _offersWatch?.cancel();
    final idle = _now().difference(_lastInteraction) >= _idleLimit;
    final looking = state.view == UnifiedSwapView.form && _present && !idle;
    final none = state.issue == SwapFormIssue.noOffers;
    if (looking && (none || _offersUnknown(state))) {
      _offersWatch = _after(
        none ? _offersInterval : _offersInterval ~/ 3,
        const UnifiedSwapTimerFired(UnifiedSwapTimerKind.offers),
      );
    }
    final watching = looking && none;
    if (state.hints.watching != watching) {
      emit(state.copyWith(hints: state.hints.copyWith(watching: watching)));
    }
  }

  /// Whether [next]'s pair is one only the order book trades, not priced
  /// yet, whose offers could not be read.
  bool _offersUnknown(UnifiedSwapState next) {
    final pay = next.pay;
    final receive = next.receive;
    if (pay == null || receive == null || pay == receive) return false;
    if (!next.tradingEnabled || next.quotes != null) return false;
    return _repository.orderBookOnly(pay, receive) &&
        next.hints.offersFor(pay, receive) == null;
  }

  /// Whether only the order book trades [next]'s pair, and no one offers it.
  bool _offersNone(UnifiedSwapState next) {
    final pay = next.pay;
    final receive = next.receive;
    if (pay == null || receive == null || !next.tradingEnabled) return false;
    final sources = next.pairSupport?.sources;
    if (sources == null ||
        sources.length != 1 ||
        sources.single != SwapLiquiditySource.atomic) {
      return false;
    }
    return next.hints.offersFor(pay, receive)?.isEmpty ?? false;
  }

  /// [state]'s hints with the order book's answer in [failures], for a pair
  /// only it trades.
  SwapOrderBookHints? _hintsFrom(List<SwapQuoteFailure> failures) {
    final pay = state.pay;
    final receive = state.receive;
    if (pay == null || receive == null) return null;
    if (!_repository.orderBookOnly(pay, receive)) return null;
    for (final failure in failures) {
      final offers = failure.offers;
      if (failure.source == SwapLiquiditySource.atomic && offers != null) {
        return state.hints.copyWith(pair: (pay, receive), offers: offers);
      }
    }
    return null;
  }
}

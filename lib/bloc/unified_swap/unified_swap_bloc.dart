import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:decimal/decimal.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';

/// Drives the swap screen.
///
/// Two rules shape most of this and both come from the same place — the user
/// is committing money against a number that moves:
///
/// 1. **Nothing executes against a price the user has not seen.** Pressing
///    start re-prices first, and a materially different result pauses for
///    explicit acceptance rather than proceeding.
/// 2. **A stale answer never wins.** Quote lookups are versioned against the
///    form, so a slow reply for an amount the user has since changed is
///    discarded instead of overwriting a newer one.
class UnifiedSwapBloc extends Bloc<UnifiedSwapEvent, UnifiedSwapState> {
  /// Creates the bloc.
  UnifiedSwapBloc({
    required UnifiedSwapRepository repository,
    required List<SwapExecutor> executors,
    required Future<Decimal?> Function(AssetId asset) spendableBalance,
  }) : _repository = repository,
       _executors = executors,
       _spendableBalance = spendableBalance,
       super(const UnifiedSwapState()) {
    on<UnifiedSwapStarted>(_onStarted);
    on<UnifiedSwapSellAssetChanged>(_onSellAssetChanged);
    on<UnifiedSwapReceiveAssetChanged>(_onReceiveAssetChanged);
    on<UnifiedSwapSidesReversed>(_onSidesReversed);
    on<UnifiedSwapAmountChanged>(_onAmountChanged);
    on<UnifiedSwapMaxAmountRequested>(_onMaxRequested);
    on<UnifiedSwapQuoteRequested>(_onQuoteRequested);
    on<UnifiedSwapQuoteSelected>(_onQuoteSelected);
    on<UnifiedSwapReviewRequested>(_onReviewRequested);
    on<UnifiedSwapReviewDismissed>(_onReviewDismissed);
    on<UnifiedSwapStartRequested>(_onStartRequested);
    on<UnifiedSwapRepriceAccepted>(_onRepriceAccepted);
    on<UnifiedSwapRepriceRejected>(_onRepriceRejected);
    on<UnifiedSwapCancelRequested>(_onCancelRequested);
    on<UnifiedSwapProgressReceived>(_onProgressReceived);
    on<UnifiedSwapReset>(_onReset);
  }

  final UnifiedSwapRepository _repository;
  final List<SwapExecutor> _executors;
  final Future<Decimal?> Function(AssetId asset) _spendableBalance;

  /// Bumped on every change that invalidates an in-flight quote.
  int _quoteVersion = 0;

  SwapExecutionHandle? _handle;
  StreamSubscription<UnifiedSwapProgress>? _progressSubscription;

  /// How much worse a re-price may be before the user must re-consent.
  ///
  /// Any drop in the guaranteed amount is material. A swap that silently
  /// delivers less than the figure someone agreed to is the failure this
  /// whole flow exists to prevent, so the threshold is zero rather than a
  /// tolerance band.
  static bool _isMaterialChange(SwapQuote accepted, SwapQuote fresh) =>
      fresh.guaranteedReceive < accepted.guaranteedReceive;

  Future<void> _onStarted(
    UnifiedSwapStarted event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    final assets = await _repository.tradableAssets();
    emit(state.copyWith(tradableAssets: assets));
  }

  Future<void> _onSellAssetChanged(
    UnifiedSwapSellAssetChanged event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    _invalidateQuote();
    emit(
      _validated(
        state.copyWith(
          sellAsset: event.asset,
          clearQuotes: true,
          clearSelectedQuote: true,
          clearSpendableBalance: true,
          quoteStatus: UnifiedSwapQuoteStatus.idle,
        ),
      ),
    );
    final balance = await _spendableBalance(event.asset);
    emit(_validated(state.copyWith(spendableBalance: balance)));
  }

  void _onReceiveAssetChanged(
    UnifiedSwapReceiveAssetChanged event,
    Emitter<UnifiedSwapState> emit,
  ) {
    _invalidateQuote();
    emit(
      _validated(
        state.copyWith(
          receiveAsset: event.asset,
          clearQuotes: true,
          clearSelectedQuote: true,
          quoteStatus: UnifiedSwapQuoteStatus.idle,
        ),
      ),
    );
  }

  Future<void> _onSidesReversed(
    UnifiedSwapSidesReversed event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    final sell = state.sellAsset;
    final receive = state.receiveAsset;
    if (sell == null || receive == null) return;

    _invalidateQuote();
    emit(
      _validated(
        state.copyWith(
          sellAsset: receive,
          receiveAsset: sell,
          // The amount was denominated in the old sell asset, so keeping it
          // would silently re-denominate the trade.
          amountText: '',
          clearQuotes: true,
          clearSelectedQuote: true,
          clearSpendableBalance: true,
          quoteStatus: UnifiedSwapQuoteStatus.idle,
        ),
      ),
    );
    final balance = await _spendableBalance(receive);
    emit(_validated(state.copyWith(spendableBalance: balance)));
  }

  void _onAmountChanged(
    UnifiedSwapAmountChanged event,
    Emitter<UnifiedSwapState> emit,
  ) {
    _invalidateQuote();
    emit(
      _validated(
        state.copyWith(
          amountText: event.amountText,
          clearQuotes: true,
          clearSelectedQuote: true,
          quoteStatus: UnifiedSwapQuoteStatus.idle,
        ),
      ),
    );
  }

  void _onMaxRequested(
    UnifiedSwapMaxAmountRequested event,
    Emitter<UnifiedSwapState> emit,
  ) {
    final balance = state.spendableBalance;
    if (balance == null) return;
    add(UnifiedSwapAmountChanged(balance.toString()));
  }

  Future<void> _onQuoteRequested(
    UnifiedSwapQuoteRequested event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    if (!state.canRequestQuote) return;

    final version = ++_quoteVersion;
    emit(state.copyWith(quoteStatus: UnifiedSwapQuoteStatus.loading));

    final result = await _repository.quote(
      from: state.sellAsset!,
      to: state.receiveAsset!,
      amount: state.amount!,
    );

    // The form moved on while this was in flight. Emitting now would show a
    // price for an amount or pair the user has already left behind.
    if (version != _quoteVersion) return;

    if (result.isEmpty) {
      emit(
        state.copyWith(
          quotes: result,
          quoteStatus: result.isPermanentlyUnsupported
              ? UnifiedSwapQuoteStatus.unsupported
              : UnifiedSwapQuoteStatus.unavailable,
          clearSelectedQuote: true,
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        quotes: result,
        selectedQuote: result.best,
        quoteStatus: UnifiedSwapQuoteStatus.ready,
      ),
    );
  }

  void _onQuoteSelected(
    UnifiedSwapQuoteSelected event,
    Emitter<UnifiedSwapState> emit,
  ) {
    emit(state.copyWith(selectedQuote: event.quote));
  }

  void _onReviewRequested(
    UnifiedSwapReviewRequested event,
    Emitter<UnifiedSwapState> emit,
  ) {
    if (!state.canReview) return;
    emit(state.copyWith(step: UnifiedSwapStep.confirm, clearStartError: true));
  }

  void _onReviewDismissed(
    UnifiedSwapReviewDismissed event,
    Emitter<UnifiedSwapState> emit,
  ) {
    emit(
      state.copyWith(
        step: UnifiedSwapStep.fill,
        clearRepricedQuote: true,
        clearStartError: true,
      ),
    );
  }

  Future<void> _onStartRequested(
    UnifiedSwapStartRequested event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    if (!state.canStart) return;
    final accepted = state.selectedQuote!;

    // Re-price before committing. A quote goes stale in about a minute and
    // carries no reservation, so the figure on screen may already be gone.
    emit(state.copyWith(isRepricing: true, clearStartError: true));
    final fresh = await _repository.quote(
      from: accepted.from,
      to: accepted.to,
      amount: accepted.sellAmount,
    );
    final freshQuote = fresh.quotes
        .where((q) => q.source == accepted.source)
        .firstOrNull;

    if (freshQuote == null) {
      emit(
        state.copyWith(
          isRepricing: false,
          startError: 'This swap is no longer available at that price.',
        ),
      );
      return;
    }

    if (_isMaterialChange(accepted, freshQuote)) {
      // Stop and ask. Executing here would trade against numbers the user
      // never agreed to.
      emit(state.copyWith(isRepricing: false, repricedQuote: freshQuote));
      return;
    }

    emit(
      state.copyWith(
        isRepricing: false,
        selectedQuote: freshQuote,
        isStarting: true,
      ),
    );
    await _execute(freshQuote, emit);
  }

  Future<void> _onRepriceAccepted(
    UnifiedSwapRepriceAccepted event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    final reprice = state.repricedQuote;
    if (reprice == null) return;
    emit(
      state.copyWith(
        selectedQuote: reprice,
        clearRepricedQuote: true,
        isStarting: true,
      ),
    );
    await _execute(reprice, emit);
  }

  void _onRepriceRejected(
    UnifiedSwapRepriceRejected event,
    Emitter<UnifiedSwapState> emit,
  ) {
    emit(state.copyWith(step: UnifiedSwapStep.fill, clearRepricedQuote: true));
  }

  Future<void> _execute(SwapQuote quote, Emitter<UnifiedSwapState> emit) async {
    final executor = _executors
        .where((e) => e.source == quote.source)
        .firstOrNull;
    if (executor == null) {
      // Every source that can produce a quote must have a way to execute it.
      // Reaching here means the two lists disagree, which is a wiring bug, not
      // something the user can act on.
      emit(
        state.copyWith(
          isStarting: false,
          startError: 'This kind of swap cannot be started here.',
        ),
      );
      return;
    }

    try {
      final handle = await executor.start(quote);
      _handle = handle;
      emit(
        state.copyWith(
          isStarting: false,
          step: UnifiedSwapStep.inProgress,
          activeSwapUuid: handle.id,
        ),
      );
      await _progressSubscription?.cancel();
      _progressSubscription = handle.progress.listen(
        (progress) => add(UnifiedSwapProgressReceived(progress)),
      );
    } on Object catch (error) {
      emit(state.copyWith(isStarting: false, startError: error.toString()));
    }
  }

  Future<void> _onCancelRequested(
    UnifiedSwapCancelRequested event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    final handle = _handle;
    if (handle == null) return;
    try {
      await handle.cancel();
    } on Object {
      // Losing the race is expected: the transaction went out between the
      // button appearing and the tap landing. The progress stream already
      // reflects reality, so there is nothing to correct here.
    }
  }

  void _onProgressReceived(
    UnifiedSwapProgressReceived event,
    Emitter<UnifiedSwapState> emit,
  ) {
    final progress = event.progress;
    emit(
      state.copyWith(
        progress: progress,
        step: switch (progress.phase) {
          SwapPhase.finished => UnifiedSwapStep.complete,
          SwapPhase.failed => UnifiedSwapStep.failed,
          _ => UnifiedSwapStep.inProgress,
        },
      ),
    );
  }

  void _onReset(UnifiedSwapReset event, Emitter<UnifiedSwapState> emit) {
    _invalidateQuote();
    unawaited(_progressSubscription?.cancel());
    _progressSubscription = null;
    _handle = null;
    emit(
      UnifiedSwapState(
        tradableAssets: state.tradableAssets,
        sellAsset: state.sellAsset,
        receiveAsset: state.receiveAsset,
      ),
    );
  }

  void _invalidateQuote() => _quoteVersion++;

  /// Applies form validation to [next].
  UnifiedSwapState _validated(UnifiedSwapState next) {
    final error = _errorFor(next);
    return error == null
        ? next.copyWith(clearFormError: true)
        : next.copyWith(formError: error);
  }

  UnifiedSwapFormError? _errorFor(UnifiedSwapState next) {
    if (next.sellAsset != null && next.sellAsset == next.receiveAsset) {
      return UnifiedSwapFormError.sameAsset;
    }
    final text = next.amountText.trim();
    if (text.isEmpty) return UnifiedSwapFormError.amountMissing;

    final amount = Decimal.tryParse(text);
    if (amount == null) return UnifiedSwapFormError.amountMalformed;
    if (amount <= Decimal.zero) return UnifiedSwapFormError.amountNotPositive;

    final balance = next.spendableBalance;
    if (balance != null && amount > balance) {
      return UnifiedSwapFormError.amountExceedsBalance;
    }
    return null;
  }

  @override
  Future<void> close() async {
    await _progressSubscription?.cancel();
    return super.close();
  }
}

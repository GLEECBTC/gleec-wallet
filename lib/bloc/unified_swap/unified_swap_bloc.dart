import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:decimal/decimal.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_preferences.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/swap/swap_terms_repository.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';

part 'unified_swap_bloc_evaluation.dart';
part 'unified_swap_bloc_intent.dart';
part 'unified_swap_bloc_review.dart';
part 'unified_swap_bloc_rules.dart';

/// One asset the wallet holds, with its value, for choosing a default pair.
typedef SwapHolding = ({AssetId asset, Decimal usdValue});

/// Drives the swap screen: the intent, its automatic evaluation, the review
/// and the start.
///
/// Three rules shape most of this, all from the same place — the user is
/// committing money against a number that moves:
///
/// 1. **Nothing executes against a price the user has not seen.** Starting
///    re-prices first. A lower minimum or a materially higher cost stops for
///    old-versus-new consent; changed steps go back to a fresh evaluation.
/// 2. **A stale answer never wins.** Evaluations and starts are versioned, so a
///    slow reply for an intent the user has since changed is discarded.
/// 3. **A start is never repeated by accident.** A start whose answer was lost
///    may already be running, so it blocks another start and points at
///    Activity instead.
class UnifiedSwapBloc extends Bloc<UnifiedSwapEvent, UnifiedSwapState> {
  /// Creates the bloc.
  UnifiedSwapBloc({
    required UnifiedSwapRepository repository,
    required SwapExecutionRegistry registry,
    required SwapTermsRepository terms,
    required SwapPreferences preferences,
    required Future<Decimal?> Function(AssetId asset) spendableBalance,
    required Future<String?> Function(AssetId asset) addressOf,
    required AssetId? Function(String ticker) resolveAsset,
    Future<List<SwapHolding>> Function()? holdings,
    DateTime Function()? now,
    Duration debounce = const Duration(milliseconds: 500),
    Duration evaluationTimeout = const Duration(seconds: 25),
    Duration refreshInterval = const Duration(seconds: 30),
    Duration rateLimitPause = const Duration(seconds: 30),
  }) : _repository = repository,
       _registry = registry,
       _terms = terms,
       _preferences = preferences,
       _spendableBalance = spendableBalance,
       _addressOf = addressOf,
       _resolveAsset = resolveAsset,
       _holdings = holdings,
       _now = now ?? DateTime.now,
       _debounceDelay = debounce,
       _evaluationTimeout = evaluationTimeout,
       _refreshInterval = refreshInterval,
       _rateLimitPause = rateLimitPause,
       super(const UnifiedSwapState()) {
    on<UnifiedSwapStarted>(_onStarted);
    on<UnifiedSwapIntentApplied>(_onIntentApplied);
    on<UnifiedSwapPayAssetChanged>(_onPayAssetChanged);
    on<UnifiedSwapReceiveAssetChanged>(_onReceiveAssetChanged);
    on<UnifiedSwapSidesSwitched>(_onSidesSwitched);
    on<UnifiedSwapAmountChanged>(_onAmountChanged);
    on<UnifiedSwapAmountModeToggled>(_onAmountModeToggled);
    on<UnifiedSwapMaxRequested>(_onMaxRequested);
    on<UnifiedSwapEvaluationRequested>(_onEvaluationRequested);
    on<UnifiedSwapOptionSelected>(_onOptionSelected);
    on<UnifiedSwapReviewOpened>(_onReviewOpened);
    on<UnifiedSwapReviewClosed>(_onReviewClosed);
    on<UnifiedSwapStartRequested>(_onStartRequested);
    on<UnifiedSwapFreshQuoteAccepted>(_onFreshQuoteAccepted);
    on<UnifiedSwapProgressLeft>(_onProgressLeft);
    on<UnifiedSwapResetRequested>(_onResetRequested);
    on<UnifiedSwapFollowUpRequested>(_onFollowUpRequested);
    on<UnifiedSwapVisibilityChanged>(_onVisibilityChanged);
    on<UnifiedSwapCapabilitiesChanged>(_onCapabilitiesChanged);
    on<UnifiedSwapBalancesRefreshed>(_onBalancesRefreshed);
    on<UnifiedSwapTimerFired>(_onTimerFired);
  }

  final UnifiedSwapRepository _repository;
  final SwapExecutionRegistry _registry;
  final SwapTermsRepository _terms;
  final SwapPreferences _preferences;
  final Future<Decimal?> Function(AssetId asset) _spendableBalance;
  final Future<String?> Function(AssetId asset) _addressOf;
  final AssetId? Function(String ticker) _resolveAsset;
  final Future<List<SwapHolding>> Function()? _holdings;
  final DateTime Function() _now;
  final Duration _debounceDelay;
  final Duration _evaluationTimeout;
  final Duration _refreshInterval;
  final Duration _rateLimitPause;

  /// Bumped by every change that invalidates an in-flight evaluation.
  int _evaluationVersion = 0;

  /// Bumped when a review is left, so a start that is still re-pricing is
  /// abandoned rather than executed behind the user's back.
  int _startVersion = 0;

  var _visible = true;
  var _intentApplied = false;

  /// When the provider last asked to slow down. For a while after, only the
  /// default route is priced — comparing routes doubles the request rate.
  DateTime? _lastRateLimited;
  Timer? _debounce;
  Timer? _refresh;
  Timer? _expiry;
  Timer? _rateLimit;

  /// The amount in pay-asset units, parsed from the field.
  Decimal? amountOf(UnifiedSwapState state) {
    final text = state.inputText.trim();
    if (text.isEmpty) return null;
    final value = Decimal.tryParse(text);
    if (value == null) return null;
    if (state.amountMode == SwapAmountMode.token) return value;
    final pay = state.pay;
    final price = pay == null ? null : _repository.pricing.prices.usdPrice(pay);
    if (price == null || price <= Decimal.zero) return null;
    final raw = (value / price).toDecimal(scaleOnInfinitePrecision: 18);
    final decimals = pay!.chainId.decimals;
    return decimals == null ? raw : raw.floor(scale: decimals);
  }

  // ------------------------------------------------------------- lifecycle

  Future<void> _onStarted(
    UnifiedSwapStarted event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    final assets = await _repository.tradableAssets();
    emit(state.copyWith(tradableAssets: assets, loadingAssets: false));
    if (state.pay != null || _intentApplied) return;

    final pair = await _defaultPair(assets);
    if (pair == null || state.pay != null || _intentApplied) return;
    await _setPair(emit, pay: pair.pay, receive: pair.receive);
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
    );
  }

  Future<void> _setPair(
    Emitter<UnifiedSwapState> emit, {
    AssetId? pay,
    AssetId? receive,
    String? amount,
  }) async {
    _invalidate();
    emit(
      _validated(
        state.copyWith(
          view: UnifiedSwapView.form,
          pay: pay,
          receive: receive,
          clearPay: pay == null,
          clearReceive: receive == null,
          inputText: amount ?? state.inputText,
          amountMode: amount == null ? null : SwapAmountMode.token,
          clearQuotes: true,
          clearSelectedId: true,
          clearFailure: true,
          clearMaxApplied: true,
          clearReview: true,
          evaluation: SwapEvaluationStatus.idle,
          structuralNotice: false,
        ),
      ),
    );
    await _loadBalances(emit);
    await _loadAddresses(emit);
    _scheduleEvaluation(immediate: true);
  }

  // ---------------------------------------------------------- environment

  void _onVisibilityChanged(
    UnifiedSwapVisibilityChanged event,
    Emitter<UnifiedSwapState> emit,
  ) {
    _visible = event.visible;
    if (!event.visible) {
      _refresh?.cancel();
      return;
    }
    if (state.view != UnifiedSwapView.form) return;
    final quote = state.selectedQuote;
    if (state.evaluation == SwapEvaluationStatus.expired ||
        (quote != null && quote.isExpiredAt(_now()))) {
      add(const UnifiedSwapEvaluationRequested());
    } else {
      _armTimers(quote);
    }
  }

  void _onCapabilitiesChanged(
    UnifiedSwapCapabilitiesChanged event,
    Emitter<UnifiedSwapState> emit,
  ) {
    if (event.tradingEnabled == state.tradingEnabled &&
        event.clockValid == state.clockValid) {
      return;
    }
    emit(
      state.copyWith(
        tradingEnabled: event.tradingEnabled,
        clockValid: event.clockValid,
      ),
    );
    if (event.tradingEnabled && state.view == UnifiedSwapView.form) {
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
    final feeAsset = pay.parentId;
    final balance = await _read(pay);
    final feeBalance = feeAsset == null ? null : await _read(feeAsset);
    if (state.pay != pay) return;
    emit(
      _validated(
        state.copyWith(
          balance: balance,
          clearBalance: balance == null,
          feeBalance: feeBalance,
          clearFeeBalance: feeBalance == null,
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
    final payAddress = pay == null ? null : await _address(pay);
    final receiveAddress = receive == null ? null : await _address(receive);
    if (state.pay != pay || state.receive != receive) return;
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

  @override
  Future<void> close() {
    _debounce?.cancel();
    _refresh?.cancel();
    _expiry?.cancel();
    _rateLimit?.cancel();
    return super.close();
  }
}

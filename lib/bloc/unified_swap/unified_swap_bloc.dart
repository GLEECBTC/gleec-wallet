import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:decimal/decimal.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_preferences.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/swap/swap_terms_repository.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';

part 'unified_swap_bloc_environment.dart';
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
    Duration idleLimit = const Duration(minutes: 5),
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
       _idleLimit = idleLimit,
       super(const UnifiedSwapState()) {
    on<UnifiedSwapStarted>(_onStarted);
    on<UnifiedSwapIntentApplied>(_onIntentApplied);
    on<UnifiedSwapPayAssetChanged>(_onPayAssetChanged);
    on<UnifiedSwapReceiveAssetChanged>(_onReceiveAssetChanged);
    on<UnifiedSwapSidesSwitched>(_onSidesSwitched);
    on<UnifiedSwapAmountChanged>(_onAmountChanged);
    on<UnifiedSwapAmountModeToggled>(_onAmountModeToggled);
    on<UnifiedSwapMaxRequested>(_onMaxRequested);
    on<UnifiedSwapAmountSuggested>(_onAmountSuggested);
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
    on<UnifiedSwapCatalogRefreshRequested>(_onCatalogRefreshRequested);
    on<UnifiedSwapCatalogArrived>(_onCatalogArrived);
    on<UnifiedSwapAssetActivated>(_onAssetActivated);
    on<UnifiedSwapAlternativesRequested>(_onAlternativesRequested);
    on<UnifiedSwapSlippageChanged>(_onSlippageChanged);
    on<UnifiedSwapForegroundChanged>(_onForegroundChanged);
    on<UnifiedSwapTimerFired>(_onTimerFired);
    _arrivals = repository.arrivals.listen((_) {
      if (!isClosed) add(const UnifiedSwapCatalogArrived());
    });
  }

  final UnifiedSwapRepository _repository;
  late final StreamSubscription<void> _arrivals;
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

  /// How long the form keeps re-pricing without anyone touching it. After
  /// that the quote is left to expire, and refreshing is one tap away.
  final Duration _idleLimit;

  /// Bumped by every change that invalidates an in-flight evaluation.
  int _evaluationVersion = 0;

  /// Bumped when a review is left, so a start that is still re-pricing is
  /// abandoned rather than executed behind the user's back.
  int _startVersion = 0;

  /// Bumped when a wallet signs in or out, so reads for the previous one are
  /// dropped.
  var _walletEpoch = 0;

  var _visible = true;
  var _foreground = true;
  var _intentApplied = false;
  late DateTime _lastInteraction = _now();

  /// The intent someone opened a comparison for: its alternatives stay
  /// priced on every refresh until the intent changes.
  Object? _comparing;

  var _settingPair = 0;

  /// While the first catalog read is in flight, nothing says which sources
  /// can answer or whether an asset still needs activating.
  var _catalogLoading = false;

  Timer? _debounce;
  Timer? _refresh;
  Timer? _expiry;
  Timer? _rateLimit;

  /// Set when [close] starts: a price still in flight can land after the
  /// timers are cancelled, and must not start new ones.
  var _closing = false;

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
    _catalogLoading = true;
    final SwapCatalog read;
    try {
      read = await _repository.catalog(signedIn: state.signedIn);
    } finally {
      _catalogLoading = false;
    }
    // A later read may have returned first; the repository keeps the latest.
    final catalog = _repository.current ?? read;
    emit(_validated(state.copyWith(catalog: catalog, loadingAssets: false)));
    if (state.pay != null || _intentApplied) {
      // A pair set while the catalog loaded could not be priced then; one
      // still being set prices itself when it finishes.
      if (state.hasPair && _settingPair == 0) {
        _scheduleEvaluation(immediate: true);
      }
      return;
    }
    // Signed out there is no pair to find, and looking queues on the sign-in
    // lock.
    if (!state.signedIn) return;

    final pair = await _defaultPair({
      for (final source in catalog.sources) ...source.quotable,
    });
    if (pair == null || state.pay != null || _intentApplied) return;
    await _setPair(emit, pay: pair.pay, receive: pair.receive);
  }

  Future<void> _refreshCatalog(Emitter<UnifiedSwapState> emit) async {
    final read = await _repository.catalog(signedIn: state.signedIn);
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
      _scheduleEvaluation(immediate: true);
    }
  }

  Future<void> _onAssetActivated(
    UnifiedSwapAssetActivated event,
    Emitter<UnifiedSwapState> emit,
  ) async {
    _invalidate();
    await _refreshCatalog(emit);
    await _loadBalances(emit);
    await _loadAddresses(emit);
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
      amountMode: event.amountMode,
    );
  }

  Future<void> _setPair(
    Emitter<UnifiedSwapState> emit, {
    AssetId? pay,
    AssetId? receive,
    String? amount,
    SwapAmountMode amountMode = SwapAmountMode.token,
  }) async {
    if (_startInDoubt) return;
    _settingPair++;
    try {
      await _applyPair(
        emit,
        pay: pay,
        receive: receive,
        amount: amount,
        amountMode: amountMode,
      );
    } finally {
      _settingPair--;
    }
  }

  Future<void> _applyPair(
    Emitter<UnifiedSwapState> emit, {
    AssetId? pay,
    AssetId? receive,
    String? amount,
    required SwapAmountMode amountMode,
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
          amountMode: amount == null ? null : amountMode,
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
    // An asset the catalog thinks inactive may have been activated since —
    // by the picker a moment ago, or elsewhere in the app. Signed out,
    // nothing can have been.
    if (state.signedIn && !state.loadingAssets && state.inactiveAsset != null) {
      await _refreshCatalog(emit);
    }
    await _loadBalances(emit);
    await _loadAddresses(emit);
    _scheduleEvaluation(immediate: true);
  }

  // ---------------------------------------------------------- environment

  @override
  void onEvent(UnifiedSwapEvent event) {
    super.onEvent(event);
    final interaction = switch (event) {
      UnifiedSwapTimerFired() ||
      UnifiedSwapBalancesRefreshed() ||
      UnifiedSwapCatalogArrived() ||
      UnifiedSwapCapabilitiesChanged() => false,
      UnifiedSwapEvaluationRequested(:final quiet) => !quiet,
      UnifiedSwapVisibilityChanged(:final visible) => visible,
      UnifiedSwapForegroundChanged(:final foreground) => foreground,
      _ => true,
    };
    if (interaction) _lastInteraction = _now();
  }

  @override
  Future<void> close() {
    _closing = true;
    _debounce?.cancel();
    _refresh?.cancel();
    _expiry?.cancel();
    _rateLimit?.cancel();
    unawaited(_arrivals.cancel());
    return super.close();
  }
}

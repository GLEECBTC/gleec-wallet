import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:decimal/decimal.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/services/legal_documents/legal_document.dart';
import 'package:web_dex/services/wallet_access/wallet_operation_gate.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_order_book_offers.dart';
import 'package:web_dex/shared/swap/swap_preferences.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/swap/swap_terms_repository.dart';
import 'package:web_dex/shared/swap/swap_tickers.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';
import 'package:web_dex/shared/trading/trading_asset_policy.dart';

part 'unified_swap_bloc_environment.dart';
part 'unified_swap_bloc_evaluation.dart';
part 'unified_swap_bloc_intent.dart';
part 'unified_swap_bloc_offers.dart';
part 'unified_swap_bloc_pair.dart';
part 'unified_swap_bloc_preparation.dart';
part 'unified_swap_bloc_review.dart';
part 'unified_swap_bloc_rules.dart';
part 'unified_swap_bloc_start.dart';

/// One asset the wallet holds, with its value, for choosing a default pair.
typedef SwapHolding = ({AssetId asset, Decimal usdValue});

/// What a start takes from the pay balance: amount, on-top fees in the pay
/// asset, refund gas.
typedef SwapSpend = ({Decimal amount, Decimal fees, Decimal refundReserve});

typedef _Held = ({
  Decimal? balance,
  Decimal? feeBalance,
  Map<AssetId, Decimal?> fundingBalances,
});

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
    Future<void> Function(AssetId asset)? activateAsset,
    Future<int?> Function(AssetId asset)? spendDecimalsOf,
    DateTime Function()? now,
    Duration debounce = const Duration(milliseconds: 500),
    Duration evaluationTimeout = const Duration(seconds: 25),
    Duration refreshInterval = const Duration(seconds: 50),
    Duration rateLimitPause = const Duration(seconds: 30),
    Duration idleLimit = const Duration(minutes: 2),
    Duration offersInterval = const Duration(seconds: 30),
    Duration offersIdleLimit = const Duration(minutes: 5),
  }) : _repository = repository,
       _registry = registry,
       _terms = terms,
       _preferences = preferences,
       _spendableBalance = spendableBalance,
       _addressOf = addressOf,
       _resolveAsset = resolveAsset,
       _holdings = holdings,
       _activateAsset = activateAsset,
       _spendDecimalsOf = spendDecimalsOf,
       _now = now ?? DateTime.now,
       _debounceDelay = debounce,
       _evaluationTimeout = evaluationTimeout,
       _refreshInterval = refreshInterval,
       _rateLimitPause = rateLimitPause,
       _idleLimit = idleLimit,
       _offersInterval = offersInterval,
       _offersIdleLimit = offersIdleLimit,
       super(UnifiedSwapState(sessionReady: registry.acceptsSubmissions)) {
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
    // The repository coalesces requests for the same document. Keep each
    // review's refresh alive so opening a new review cannot lose its result.
    on<UnifiedSwapLegalRequested>(_onLegalRequested);
    _legalChanges = terms.changes.listen((_) {
      if (!isClosed) add(const UnifiedSwapLegalRequested());
    });
    on<UnifiedSwapReviewClosed>(_onReviewClosed);
    on<UnifiedSwapStartRequested>(_onStartRequested);
    on<UnifiedSwapFreshQuoteAccepted>(_onFreshQuoteAccepted);
    on<UnifiedSwapProgressLeft>(_onProgressLeft);
    on<UnifiedSwapResetRequested>(_onResetRequested);
    on<UnifiedSwapFollowUpRequested>(_onFollowUpRequested);
    on<UnifiedSwapVisibilityChanged>(_onVisibilityChanged);
    on<UnifiedSwapCapabilitiesChanged>(_onCapabilitiesChanged);
    on<UnifiedSwapSessionInvalidated>(_onSessionInvalidated);
    _sessionInvalidations = registry.invalidations.listen((_) {
      add(const UnifiedSwapSessionInvalidated());
    });
    on<UnifiedSwapBalancesRefreshed>(_onBalancesRefreshed);
    on<UnifiedSwapCatalogRefreshRequested>(_onCatalogRefreshRequested);
    on<UnifiedSwapCatalogArrived>(_onCatalogArrived);
    on<UnifiedSwapAssetActivated>(_onAssetActivated);
    on<UnifiedSwapPreparationRetried>(_onPreparationRetried);
    on<UnifiedSwapDraftRestored>(_onDraftRestored);
    on<UnifiedSwapAlternativesRequested>(_onAlternativesRequested);
    on<UnifiedSwapAlternativesDismissed>(_onAlternativesDismissed);
    on<UnifiedSwapSlippageChanged>(_onSlippageChanged);
    on<UnifiedSwapForegroundChanged>(_onForegroundChanged);
    on<UnifiedSwapTimerFired>(_onTimerFired);
    on<UnifiedSwapOffersRequested>(_onOffersRequested);
    _arrivals = repository.arrivals.listen((_) {
      if (!isClosed) add(const UnifiedSwapCatalogArrived());
    });
  }

  final UnifiedSwapRepository _repository;
  late final StreamSubscription<void> _arrivals;
  final SwapExecutionRegistry _registry;
  final SwapTermsRepository _terms;
  late final StreamSubscription<void> _legalChanges;
  late final StreamSubscription<void> _sessionInvalidations;
  final SwapPreferences _preferences;
  final Future<Decimal?> Function(AssetId asset) _spendableBalance;
  final Future<String?> Function(AssetId asset) _addressOf;
  final AssetId? Function(String ticker) _resolveAsset;
  final Future<List<SwapHolding>> Function()? _holdings;
  final Future<void> Function(AssetId asset)? _activateAsset;
  final Future<int?> Function(AssetId asset)? _spendDecimalsOf;
  final Map<AssetId, int> _resolvedSpendDecimals = {};
  int _preparationVersion = 0;
  int _balanceReadVersion = 0;
  int _amountModeVersion = 0;
  Object _quoteScope = Object();
  StreamSubscription<SwapQuoteUpdate>? _quoteSubscription;
  void Function()? _finishQuoteWatch;
  ({AssetId asset, String text})? _fiatDraft;
  final DateTime Function() _now;
  final Duration _debounceDelay;
  final Duration _evaluationTimeout;

  /// How old a price gets before it is renewed: close to its lifetime, since
  /// every renewal spends the aggregator's request budget.
  final Duration _refreshInterval;
  final Duration _rateLimitPause;

  /// How long the form keeps re-pricing without anyone touching it. After
  /// that the quote is left to expire, and refreshing is one tap away.
  final Duration _idleLimit;

  /// How often a pair no one offers is checked again.
  final Duration _offersInterval;

  /// How long a pair no one offers is watched without anyone touching the
  /// form. Longer than [_idleLimit]: reading the order book spends no
  /// aggregator budget.
  final Duration _offersIdleLimit;

  /// Bumped by every change that invalidates an in-flight evaluation.
  int _evaluationVersion = 0;

  /// Alternatives fetched beside this evaluation must survive its later
  /// source/pricing snapshots, which contain only the originally asked orders.
  List<SwapQuote> _evaluationAlternatives = const [];

  /// Bumped whenever a review is left or replaced, so a start that is still
  /// re-pricing is abandoned rather than executed behind the user's back.
  int _startVersion = 0;

  /// Ownership of the facts shown in the review, captured before its reads.
  /// This token is never submitted; each Start creates its own one-use token.
  SwapSubmission? _reviewSubmission;

  /// Only the latest legal read may update the presented review documents.
  int _legalVersion = 0;
  int? _legalSubmissionVersion;
  bool get _waitingForLegalSubmission =>
      _legalSubmissionVersion == _startVersion;

  /// Bumped when a wallet signs in or out, so reads for the previous one are
  /// dropped.
  var _walletEpoch = 0;

  /// Bumped by every read of the order book's offers; only the latest lands.
  var _offersVersion = 0;

  /// Bumped by every Max; only the latest answer lands.
  var _maxVersion = 0;

  var _visible = true;
  var _foreground = true;
  var _intentApplied = false;
  late DateTime _lastInteraction = _now();

  /// The intent someone has a comparison open for: its alternatives are
  /// priced on every refresh until the comparison closes or the intent
  /// changes.
  Object? _comparing;

  /// While the first catalog read is in flight, nothing says which sources
  /// can answer or whether an asset still needs activating.
  var _catalogLoading = false;

  Timer? _debounce;
  Timer? _refresh;
  Timer? _expiry;
  Timer? _rateLimit;
  Timer? _offersWatch;

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
    final decimals = pay == null ? null : _decimalsOf(pay);
    // A dollar amount is not a concrete token amount until its precision is
    // known. Never pass an unbounded division to either quote source.
    if (decimals == null) return null;
    final converted = state.converted;
    if (converted != null &&
        converted.asset == state.pay &&
        converted.text == state.inputText) {
      return converted.amount.floor(scale: decimals);
    }
    final price = _repository.pricing.prices.usdPrice(pay!);
    if (price == null || price <= Decimal.zero) return null;
    return (value / price)
        .toDecimal(scaleOnInfinitePrecision: decimals)
        .floor(scale: decimals);
  }

  int? _decimalsOf(AssetId asset) {
    final declared = asset.chainId.decimals;
    return declared != null && declared >= 0 && declared <= 255
        ? declared
        : _resolvedSpendDecimals[asset];
  }

  /// What starting the selected option takes from the pay balance, for the
  /// amount on the form. Null without a priced option.
  SwapSpend? spendOf(UnifiedSwapState state) {
    final quote = state.selectedQuote;
    return quote == null ? null : _spendFor(state, quote);
  }

  /// [spendOf] for [quote], which need not be the selected option.
  SwapSpend? _spendFor(UnifiedSwapState state, SwapQuote quote) {
    final amount = amountOf(state);
    if (state.pay == null || amount == null) return null;
    // The option is what starts, and switching to a dollar amount can leave
    // it priced for a little more than the amount now shown.
    final sold = quote.sellAmount > amount ? quote.sellAmount : amount;
    return _spending(state, quote, sold, state.balance);
  }

  /// Max counts only for a quote selling the form's pay asset.
  SwapSpend _spending(
    UnifiedSwapState state,
    SwapQuote quote,
    Decimal sold,
    Decimal? balance,
  ) {
    final max = quote.from == state.pay ? state.maxApplied : null;
    return (
      amount: sold,
      // Every fee, the order book's trading fee included: KDF checks the gas
      // to claim a token on the same network alone, never summed with the
      // rest, so only this total shows whether that claim can be paid. A
      // routed route's gas counts at the balance KDF requires for it.
      fees: quote.fundingOnTopIn(quote.from),
      // KDF's Max kept it back already, priced when Max was asked; counting
      // it again would refuse that Max once gas rises at all.
      refundReserve: max != null && max.coversRefundFor(sold, balance)
          ? Decimal.zero
          : quote.refundReserve ?? Decimal.zero,
    );
  }

  // ---------------------------------------------------------- environment

  @override
  void onEvent(UnifiedSwapEvent event) {
    super.onEvent(event);
    final interaction = switch (event) {
      UnifiedSwapTimerFired() ||
      UnifiedSwapBalancesRefreshed() ||
      UnifiedSwapCatalogArrived() ||
      UnifiedSwapCapabilitiesChanged() ||
      UnifiedSwapSessionInvalidated() => false,
      UnifiedSwapLegalRequested(:final retry) => retry,
      UnifiedSwapEvaluationRequested(:final quiet) => !quiet,
      UnifiedSwapOffersRequested(:final quiet) => !quiet,
      UnifiedSwapVisibilityChanged(:final visible) => visible,
      UnifiedSwapForegroundChanged(:final foreground) => foreground,
      _ => true,
    };
    if (interaction) _lastInteraction = _now();
  }

  @override
  Future<void> close() {
    _closing = true;
    _startVersion++;
    _legalVersion++;
    _preparationVersion++;
    _stopQuoteWatch();
    _debounce?.cancel();
    _refresh?.cancel();
    _expiry?.cancel();
    _rateLimit?.cancel();
    _offersWatch?.cancel();
    unawaited(_arrivals.cancel());
    unawaited(_legalChanges.cancel());
    unawaited(_sessionInvalidations.cancel());
    return super.close();
  }

  @override
  void add(UnifiedSwapEvent event) {
    // Events queued before closing are still handled, and running handlers
    // still finish, after the event stream has closed: an add there throws.
    if (_closing) return;
    super.add(event);
  }
}

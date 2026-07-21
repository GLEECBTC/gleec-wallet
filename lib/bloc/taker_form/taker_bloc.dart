import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart' hide BestOrder;
import 'package:logging/logging.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/analytics/events/advanced_trading_events.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/dex_repository.dart';
import 'package:web_dex/bloc/taker_form/taker_event.dart';
import 'package:web_dex/bloc/taker_form/taker_state.dart';
import 'package:web_dex/bloc/taker_form/taker_validator.dart';
import 'package:web_dex/bloc/trading_status/trading_status_service.dart';
import 'package:web_dex/bloc/transformers.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:web_dex/mm2/mm2_api/rpc/best_orders/best_orders.dart';
import 'package:web_dex/mm2/mm2_api/rpc/best_orders/best_orders_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/sell/sell_response.dart';
import 'package:web_dex/model/advanced_trade_preparation.dart';
import 'package:web_dex/model/available_balance_state.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/data_from_service.dart';
import 'package:web_dex/model/dex_form_error.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/shared/utils/kdf_error_display.dart';
import 'package:web_dex/shared/utils/kdf_wallet_authority.dart';
import 'package:web_dex/model/trade_preimage.dart';
import 'package:web_dex/model/trading_entity_id.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/views/dex/dex_helpers.dart';

class TakerBloc extends Bloc<TakerEvent, TakerState> {
  TakerBloc({
    required DexRepository dexRepository,
    required CoinsRepo coinsRepository,
    required KomodoDefiSdk kdfSdk,
    required AnalyticsBloc analyticsBloc,
    TradingStatusService? tradingStatusService,
    Future<bool> Function()? finalSystemClockCheck,
    Duration maxPreparedAge = const Duration(minutes: 2),
  }) : _dexRepo = dexRepository,
       _coinsRepo = coinsRepository,
       _sdk = kdfSdk,
       _analyticsBloc = analyticsBloc,
       _tradingStatusService = tradingStatusService,
       _finalSystemClockCheck = finalSystemClockCheck,
       _maxPreparedAge = maxPreparedAge,
       super(TakerState.initial()) {
    _validator = TakerValidator(
      bloc: this,
      coinsRepo: _coinsRepo,
      dexRepo: _dexRepo,
      sdk: kdfSdk,
    );

    on<TakerSetDefaults>(_onSetDefaults);
    on<TakerCoinSelectorClick>(_onCoinSelectorClick);
    on<TakerOrderSelectorClick>(_onOrderSelectorClick);
    on<TakerCoinSelectorOpen>(_onCoinSelectorOpen);
    on<TakerOrderSelectorOpen>(_onOrderSelectorOpen);
    on<TakerSetSellCoin>(_onSetSellCoin, transformer: restartable());
    on<TakerSelectOrder>(_onSelectOrder, transformer: restartable());
    on<TakerAddError>(_onAddError);
    on<TakerClearErrors>(_onClearErrors);
    on<TakerUpdateBestOrders>(_onUpdateBestOrders, transformer: restartable());
    on<TakerClear>(_onClear);
    on<TakerSellAmountChange>(_onSellAmountChange, transformer: debounce());
    on<TakerSetSellAmount>(_onSetSellAmount, transformer: sequential());
    on<TakerUpdateMaxSellAmount>(
      _onUpdateMaxSellAmount,
      transformer: restartable(),
    );
    on<TakerGetMinSellAmount>(_onGetMinSellAmount, transformer: restartable());
    on<TakerAmountButtonClick>(_onAmountButtonClick);
    on<TakerUpdateFees>(_onUpdateFees, transformer: restartable());
    on<TakerSetPreimage>(_onSetPreimage);
    on<TakerFormSubmitClick>(_onFormSubmitClick, transformer: droppable());
    on<TakerBackButtonClick>(_onBackButtonClick);
    on<TakerStartSwap>(_onStartSwap, transformer: droppable());
    on<TakerSetInProgress>(_onSetInProgress);
    on<TakerReInit>(_onReInit);
    on<TakerVerifyOrderVolume>(_onVerifyOrderVolume);
    on<TakerSetWalletIsReady>(_onSetWalletReady);
    on<TakerWalletChanged>(_onWalletChanged, transformer: sequential());

    _authorizationSubscription = kdfSdk.auth.watchCurrentUser().listen(
      (user) {
        if (_closing || isClosed) return;
        _authObservationEpoch++;
        _isLoggedIn = user != null;
        add(
          TakerWalletChanged(
            user?.walletId.compoundId,
            forceSessionChange: true,
          ),
        );
      },
      onError: (_) {
        if (_closing || isClosed) return;
        _authObservationEpoch++;
        _isLoggedIn = false;
        add(const TakerWalletChanged(null, forceSessionChange: true));
      },
      onDone: () {
        if (_closing || isClosed) return;
        _authObservationEpoch++;
        _isLoggedIn = false;
        add(const TakerWalletChanged(null, forceSessionChange: true));
      },
    );
    unawaited(_initializeWalletScope());
  }

  final DexRepository _dexRepo;
  final CoinsRepo _coinsRepo;
  final KomodoDefiSdk _sdk;
  final AnalyticsBloc _analyticsBloc;
  final TradingStatusService? _tradingStatusService;
  final Future<bool> Function()? _finalSystemClockCheck;
  final Duration _maxPreparedAge;
  Timer? _maxSellAmountTimer;
  int _activationOperations = 0;
  bool get _activatingAssets => _activationOperations > 0;
  bool _waitingForWallet = true;
  bool _isLoggedIn = false;
  bool _closing = false;
  int _authObservationEpoch = 0;
  int? _preparedAuthObservationEpoch;
  int _submissionGeneration = 0;
  final Set<String> _walletsRequiringSubmissionReconciliation = {};
  late TakerValidator _validator;
  late StreamSubscription<KdfUser?> _authorizationSubscription;
  final Logger _log = Logger('TakerBloc');

  TakerState _invalidatePreparation([TakerState? source]) {
    _preparedAuthObservationEpoch = null;
    final current = source ?? state;
    final isUncertain =
        current.submissionStatus == AdvancedTradeSubmissionStatus.uncertain ||
        current.submissionStatus == AdvancedTradeSubmissionStatus.submitting;
    if (isUncertain && current.walletId != null) {
      _walletsRequiringSubmissionReconciliation.add(current.walletId!);
    }
    return current.copyWith(
      formRevision: () => current.formRevision + 1,
      preparedTrade: () => null,
      submissionStatus: () => isUncertain
          ? AdvancedTradeSubmissionStatus.uncertain
          : AdvancedTradeSubmissionStatus.idle,
      submissionFailure: () =>
          isUncertain ? AdvancedTradeSubmissionFailure.uncertain : null,
      swapUuid: () => null,
    );
  }

  Future<void> _initializeWalletScope() async {
    final observationEpoch = _authObservationEpoch;
    try {
      final user = await _sdk.auth.currentUser;
      if (observationEpoch != _authObservationEpoch || isClosed) return;
      _isLoggedIn = user != null;
      add(TakerWalletChanged(user?.walletId.compoundId));
    } catch (_) {
      if (observationEpoch != _authObservationEpoch || isClosed) return;
      _isLoggedIn = false;
      add(const TakerWalletChanged(null));
    }
  }

  void _onWalletChanged(TakerWalletChanged event, Emitter<TakerState> emit) {
    if (!event.forceSessionChange && event.walletId == state.walletId) return;
    _preparedAuthObservationEpoch = null;

    if (state.walletId != null &&
        (state.submissionStatus == AdvancedTradeSubmissionStatus.uncertain ||
            state.submissionStatus ==
                AdvancedTradeSubmissionStatus.submitting)) {
      _walletsRequiringSubmissionReconciliation.add(state.walletId!);
    }
    final requiresReconciliation =
        event.walletId != null &&
        _walletsRequiringSubmissionReconciliation.contains(event.walletId);
    _submissionGeneration++;
    _maxSellAmountTimer?.cancel();
    emit(
      TakerState.initial().copyWith(
        walletId: () => event.walletId,
        formRevision: () => state.formRevision + 1,
        availableBalanceState: () => event.walletId == null
            ? AvailableBalanceState.unavailable
            : AvailableBalanceState.initial,
        submissionStatus: () => requiresReconciliation
            ? AdvancedTradeSubmissionStatus.uncertain
            : AdvancedTradeSubmissionStatus.idle,
        submissionFailure: () => requiresReconciliation
            ? AdvancedTradeSubmissionFailure.uncertain
            : null,
      ),
    );
    if (event.walletId != null) add(TakerSetDefaults());
  }

  Future<void> _onStartSwap(
    TakerStartSwap event,
    Emitter<TakerState> emit,
  ) async {
    final prepared = state.preparedTrade;
    final submissionGeneration = _submissionGeneration;
    if (prepared == null ||
        state.submissionStatus == AdvancedTradeSubmissionStatus.submitting ||
        state.submissionStatus == AdvancedTradeSubmissionStatus.accepted ||
        state.submissionStatus == AdvancedTradeSubmissionStatus.uncertain) {
      emit(
        state.copyWith(
          inProgress: () => false,
          submissionFailure: () =>
              state.submissionStatus == AdvancedTradeSubmissionStatus.uncertain
              ? AdvancedTradeSubmissionFailure.uncertain
              : AdvancedTradeSubmissionFailure.preparationInvalid,
        ),
      );
      add(
        TakerAddError(
          DexFormError(error: LocaleKeys.dexUnableToStartSwap.tr()),
        ),
      );
      return;
    }

    final gateFailure = await _submissionGateFailure(prepared);
    if (!_isCurrentPreparedSubmission(prepared, submissionGeneration)) return;
    if (gateFailure != null) {
      emit(
        state.copyWith(
          inProgress: () => false,
          preparedTrade:
              gateFailure == AdvancedTradeSubmissionFailure.walletChanged ||
                  gateFailure ==
                      AdvancedTradeSubmissionFailure.preparationExpired ||
                  gateFailure ==
                      AdvancedTradeSubmissionFailure.preparationInvalid
              ? () => null
              : null,
          submissionStatus: () => AdvancedTradeSubmissionStatus.failed,
          submissionFailure: () => gateFailure,
        ),
      );
      add(
        TakerAddError(
          DexFormError(error: LocaleKeys.dexUnableToStartSwap.tr()),
        ),
      );
      return;
    }

    final preRpcWalletId = await _currentWalletId();
    if (preRpcWalletId != prepared.walletId ||
        !_isCurrentPreparedSubmission(prepared, submissionGeneration)) {
      return;
    }

    emit(
      state.copyWith(
        inProgress: () => true,
        submissionStatus: () => AdvancedTradeSubmissionStatus.submitting,
        submissionFailure: () => null,
      ),
    );
    _analyticsBloc.add(
      AnalyticsAdvancedTradeLifecycleEvent(
        kind: AdvancedTradeKind.takerSwap,
        outcome: AdvancedTradeOutcome.initiated,
      ),
    );

    final submissionClock = Stopwatch()..start();
    try {
      final SellResponse response = await _dexRepo.sell(
        prepared.toRequest(),
        beforeMutation: () async {
          if (!_isCurrentPreparedSubmission(prepared, submissionGeneration) ||
              await freshKdfCurrentWalletId(_sdk) != prepared.walletId ||
              !_isCurrentPreparedSubmission(prepared, submissionGeneration)) {
            throw const KdfWalletAuthorityUnavailable();
          }
        },
      );
      final duration = submissionClock.elapsed;
      final String? uuid = normalizeTradingEntityUuid(response.result?.uuid);
      final postRpcWalletId = await _currentWalletId();
      if (!_isCurrentPreparedSubmission(prepared, submissionGeneration)) {
        return;
      }
      if (postRpcWalletId != prepared.walletId) {
        _markSubmissionUncertain(emit, submissionClock.elapsed);
        return;
      }

      // An RPC error or missing UUID cannot prove that the daemon did not
      // accept the swap. Keep retries blocked until the form is rebuilt and
      // reviewed against authoritative activity state.
      if (response.error != null || uuid == null || uuid.isEmpty) {
        _markSubmissionUncertain(emit, duration);
        return;
      }

      _walletsRequiringSubmissionReconciliation.remove(prepared.walletId);
      emit(
        state.copyWith(
          inProgress: () => false,
          swapUuid: () => uuid,
          submissionStatus: () => AdvancedTradeSubmissionStatus.accepted,
          submissionFailure: () => null,
        ),
      );
    } on KdfWalletAuthorityUnavailable {
      if (!_isCurrentPreparedSubmission(prepared, submissionGeneration)) {
        return;
      }
      emit(
        state.copyWith(
          inProgress: () => false,
          preparedTrade: () => null,
          submissionStatus: () => AdvancedTradeSubmissionStatus.failed,
          submissionFailure: () => AdvancedTradeSubmissionFailure.walletChanged,
        ),
      );
    } catch (_, stackTrace) {
      final postRpcWalletId = await _currentWalletId();
      if (!_isCurrentPreparedSubmission(prepared, submissionGeneration)) {
        return;
      }
      if (postRpcWalletId != prepared.walletId) {
        _markSubmissionUncertain(emit, submissionClock.elapsed);
        return;
      }
      _log.severe(
        'Advanced taker submission outcome is uncertain',
        null,
        stackTrace,
      );
      _markSubmissionUncertain(emit, submissionClock.elapsed);
    }
  }

  void _markSubmissionUncertain(Emitter<TakerState> emit, Duration duration) {
    _preparedAuthObservationEpoch = null;
    final walletId = state.walletId;
    if (walletId != null) {
      _walletsRequiringSubmissionReconciliation.add(walletId);
    }
    emit(
      state.copyWith(
        inProgress: () => false,
        preparedTrade: () => null,
        submissionStatus: () => AdvancedTradeSubmissionStatus.uncertain,
        submissionFailure: () => AdvancedTradeSubmissionFailure.uncertain,
      ),
    );
    add(
      TakerAddError(DexFormError(error: LocaleKeys.dexUnableToStartSwap.tr())),
    );
    _analyticsBloc.add(
      AnalyticsAdvancedTradeLifecycleEvent(
        kind: AdvancedTradeKind.takerSwap,
        outcome: AdvancedTradeOutcome.uncertain,
        durationBucket: advancedTradeDurationBucket(duration),
      ),
    );
  }

  bool _isCurrentPreparedSubmission(
    PreparedTakerTrade prepared,
    int submissionGeneration,
  ) {
    return !isClosed &&
        submissionGeneration == _submissionGeneration &&
        _preparedAuthObservationEpoch == _authObservationEpoch &&
        prepared.walletId == state.walletId &&
        prepared.formRevision == state.formRevision &&
        prepared == state.preparedTrade;
  }

  Future<String?> _currentWalletId() async {
    try {
      return await freshKdfCurrentWalletId(_sdk);
    } catch (_) {
      return null;
    }
  }

  Future<AdvancedTradeSubmissionFailure?> _submissionGateFailure(
    PreparedTakerTrade prepared,
  ) async {
    if (!prepared.isFreshAt(DateTime.timestamp(), maxAge: _maxPreparedAge)) {
      return AdvancedTradeSubmissionFailure.preparationExpired;
    }
    if (_preparedAuthObservationEpoch != _authObservationEpoch ||
        prepared.walletId != state.walletId ||
        prepared.formRevision != state.formRevision ||
        prepared != state.preparedTrade) {
      return AdvancedTradeSubmissionFailure.preparationInvalid;
    }

    final currentWalletId = await _currentWalletId();
    if (currentWalletId != prepared.walletId) {
      return AdvancedTradeSubmissionFailure.walletChanged;
    }

    final service = _tradingStatusService;
    if (service == null) {
      return AdvancedTradeSubmissionFailure.tradingUnavailable;
    }
    try {
      final status = await service.refreshStatus();
      if (!status.tradingEnabled ||
          status.disallowedAssets.contains(prepared.baseAssetId) ||
          status.disallowedAssets.contains(prepared.relAssetId)) {
        return AdvancedTradeSubmissionFailure.tradingUnavailable;
      }
    } catch (_) {
      return AdvancedTradeSubmissionFailure.tradingUnavailable;
    }

    final clockCheck = _finalSystemClockCheck;
    if (clockCheck == null) return AdvancedTradeSubmissionFailure.clockInvalid;
    try {
      if (!await clockCheck()) {
        return AdvancedTradeSubmissionFailure.clockInvalid;
      }
    } catch (_) {
      return AdvancedTradeSubmissionFailure.clockInvalid;
    }

    final recheckedWalletId = await _currentWalletId();
    if (recheckedWalletId != prepared.walletId) {
      return AdvancedTradeSubmissionFailure.walletChanged;
    }
    if (_preparedAuthObservationEpoch != _authObservationEpoch ||
        prepared.walletId != state.walletId ||
        prepared.formRevision != state.formRevision ||
        prepared != state.preparedTrade) {
      return AdvancedTradeSubmissionFailure.preparationInvalid;
    }
    if (!prepared.isFreshAt(DateTime.timestamp(), maxAge: _maxPreparedAge)) {
      return AdvancedTradeSubmissionFailure.preparationExpired;
    }
    return null;
  }

  void _onBackButtonClick(
    TakerBackButtonClick event,
    Emitter<TakerState> emit,
  ) {
    emit(
      _invalidatePreparation().copyWith(
        step: () => TakerStep.form,
        errors: () => [],
        tradePreimage: () => null,
      ),
    );
  }

  Future<void> _onFormSubmitClick(
    TakerFormSubmitClick event,
    Emitter<TakerState> emit,
  ) async {
    if (state.submissionStatus == AdvancedTradeSubmissionStatus.uncertain) {
      add(
        TakerAddError(
          DexFormError(error: LocaleKeys.dexUnableToStartSwap.tr()),
        ),
      );
      return;
    }

    emit(state.copyWith(inProgress: () => true, autovalidate: () => true));

    await pauseWhile(() => _waitingForWallet || _activatingAssets);

    final walletId = state.walletId;
    final authObservationEpoch = _authObservationEpoch;
    final revision = state.formRevision;
    final sellCoin = state.sellCoin;
    final order = state.selectedOrder;
    final amount = state.sellAmount;
    final buyCoin = order == null ? null : _coinsRepo.getCoin(order.coin);
    final preimage = await _validator.validateAndGetPreimage();
    final currentWalletId = await _currentWalletId();

    final unchanged =
        walletId != null &&
        currentWalletId == walletId &&
        authObservationEpoch == _authObservationEpoch &&
        revision == state.formRevision &&
        sellCoin == state.sellCoin &&
        order == state.selectedOrder &&
        amount == state.sellAmount;

    PreparedTakerTrade? prepared;
    if (unchanged &&
        sellCoin != null &&
        buyCoin != null &&
        order != null &&
        amount != null &&
        preimage != null) {
      try {
        prepared = PreparedTakerTrade(
          walletId: walletId,
          formRevision: revision,
          baseAssetId: sellCoin.id,
          relAssetId: buyCoin.id,
          base: sellCoin.abbr,
          rel: order.coin,
          volume: amount,
          price: order.price,
          makerOrderId: order.uuid,
          preimage: preimage,
        );
      } on ArgumentError {
        prepared = null;
      }
    }

    _preparedAuthObservationEpoch = prepared == null
        ? null
        : authObservationEpoch;

    emit(
      state.copyWith(
        inProgress: () => false,
        step: () => prepared == null ? TakerStep.form : TakerStep.confirm,
        tradePreimage: () => prepared?.preimage,
        preparedTrade: () => prepared,
        submissionStatus: () => prepared == null
            ? AdvancedTradeSubmissionStatus.failed
            : AdvancedTradeSubmissionStatus.prepared,
        submissionFailure: () => prepared == null
            ? AdvancedTradeSubmissionFailure.preparationInvalid
            : null,
      ),
    );

    if (preimage != null && prepared == null) {
      add(
        TakerAddError(
          DexFormError(error: LocaleKeys.dexUnableToStartSwap.tr()),
        ),
      );
    }
  }

  void _onAmountButtonClick(
    TakerAmountButtonClick event,
    Emitter<TakerState> emit,
  ) {
    final Rational? maxSellAmount = state.maxSellAmount;
    if (maxSellAmount == null) return;

    final Rational sellAmount = getFractionOfAmount(
      maxSellAmount,
      event.fraction,
    );

    add(TakerSetSellAmount(sellAmount));
  }

  void _onSellAmountChange(
    TakerSellAmountChange event,
    Emitter<TakerState> emit,
  ) {
    Rational? amount;
    if (event.value.isNotEmpty) {
      try {
        amount = parseLocaleAwareRational(event.value);
      } catch (_) {
        // Partial or malformed user input is represented as an empty amount.
        amount = null;
      }
    }

    if (amount == state.sellAmount) return;

    add(TakerSetSellAmount(amount));
  }

  Future<void> _onSetSellAmount(
    TakerSetSellAmount event,
    Emitter<TakerState> emit,
  ) async {
    final invalidated = _invalidatePreparation();
    emit(
      invalidated.copyWith(
        sellAmount: () => event.amount,
        buyAmount: () => calculateBuyAmount(
          selectedOrder: invalidated.selectedOrder,
          sellAmount: event.amount,
        ),
        tradePreimage: () => null,
      ),
    );

    final walletId = state.walletId;
    final revision = state.formRevision;

    if (state.autovalidate) {
      await _validator.validateForm();
    } else {
      add(TakerVerifyOrderVolume());
    }
    if (walletId != state.walletId || revision != state.formRevision) return;
    add(TakerUpdateFees());
  }

  void _onAddError(TakerAddError event, Emitter<TakerState> emit) {
    if ((event.walletId != null && event.walletId != state.walletId) ||
        (event.formRevision != null &&
            event.formRevision != state.formRevision)) {
      return;
    }
    final List<DexFormError> errorsList = List.from(state.errors);
    if (errorsList.any((e) => e.error == event.error.error)) {
      // Avoid adding duplicate errors
      return;
    }
    errorsList.add(event.error);

    emit(state.copyWith(errors: () => errorsList));
  }

  void _onClearErrors(TakerClearErrors event, Emitter<TakerState> emit) {
    if ((event.walletId != null && event.walletId != state.walletId) ||
        (event.formRevision != null &&
            event.formRevision != state.formRevision)) {
      return;
    }
    emit(state.copyWith(errors: () => []));
  }

  Future<void> _onSelectOrder(
    TakerSelectOrder event,
    Emitter<TakerState> emit,
  ) async {
    final bool switchingCoin =
        state.selectedOrder != null &&
        event.order != null &&
        state.selectedOrder!.coin != event.order!.coin;

    final invalidated = _invalidatePreparation();
    emit(
      invalidated.copyWith(
        selectedOrder: () => event.order,
        showOrderSelector: () => false,
        buyAmount: () => calculateBuyAmount(
          sellAmount: state.sellAmount,
          selectedOrder: event.order,
        ),
        tradePreimage: () => null,
        errors: () => [],
        autovalidate: switchingCoin ? () => false : null,
      ),
    );

    final walletId = state.walletId;
    final revision = state.formRevision;
    final selectedOrder = state.selectedOrder;

    // Auto-fill the exact maker amount when an order is selected
    final hasUserSetSellAmount =
        (state.sellAmount ?? Rational.zero) > Rational.zero;
    if (event.order != null && !hasUserSetSellAmount) {
      final maxSellAmount = state.maxSellAmount ?? Rational.zero;
      final desiredSellAmount = event.order!.maxVolume < maxSellAmount
          ? event.order!.maxVolume
          : maxSellAmount;
      add(TakerSetSellAmount(desiredSellAmount));
    }

    if (!state.autovalidate) add(TakerVerifyOrderVolume());

    final activationIsCurrent = await _autoActivateCoin(
      selectedOrder?.coin,
      walletId: walletId,
      revision: revision,
    );
    if (!activationIsCurrent ||
        walletId != state.walletId ||
        revision != state.formRevision ||
        selectedOrder != state.selectedOrder) {
      return;
    }
    if (state.autovalidate) await _validator.validateForm();
    if (walletId != state.walletId ||
        revision != state.formRevision ||
        selectedOrder != state.selectedOrder) {
      return;
    }
    add(TakerUpdateFees());
  }

  Future<void> _onSetDefaults(
    TakerSetDefaults event,
    Emitter<TakerState> emit,
  ) async {
    if (state.sellCoin == null) {
      final Coin? defaultCoin = _coinsRepo.getCoin(defaultDexCoin);
      add(TakerSetSellCoin(defaultCoin, setOnlyIfNotSet: true));
    }
  }

  Future<void> _onSetSellCoin(
    TakerSetSellCoin event,
    Emitter<TakerState> emit,
  ) async {
    if (event.setOnlyIfNotSet && state.sellCoin != null) return;

    final invalidated = _invalidatePreparation();
    emit(
      invalidated.copyWith(
        sellCoin: () => event.coin,
        showCoinSelector: () => false,
        selectedOrder: () => null,
        bestOrders: () => null,
        sellAmount: () => null,
        buyAmount: () => null,
        tradePreimage: () => null,
        maxSellAmount: () => null,
        minSellAmount: () => null,
        errors: () => [],
        autovalidate: () => false,
        availableBalanceState: () => AvailableBalanceState.initial,
      ),
    );

    add(TakerUpdateBestOrders(autoSelectOrderAbbr: event.autoSelectOrderAbbr));

    // Before login, show 0.00 instead of spinner
    if (!_isLoggedIn) {
      emit(
        state.copyWith(
          availableBalanceState: () => AvailableBalanceState.unavailable,
          maxSellAmount: () => null,
        ),
      );
      return;
    }

    final walletId = state.walletId;
    final revision = state.formRevision;
    final selectedCoin = state.sellCoin;
    final activationIsCurrent = await _autoActivateCoin(
      selectedCoin?.abbr,
      walletId: walletId,
      revision: revision,
    );
    if (!activationIsCurrent ||
        !_isCurrentInput(walletId, revision, selectedCoin)) {
      return;
    }
    _subscribeMaxSellAmount();
    add(TakerGetMinSellAmount());
  }

  Future<void> _onUpdateBestOrders(
    TakerUpdateBestOrders event,
    Emitter<TakerState> emit,
  ) async {
    final Coin? coin = state.sellCoin;
    final walletId = state.walletId;
    final revision = state.formRevision;

    emit(state.copyWith(bestOrders: () => null));

    if (coin == null) return;

    final BestOrders bestOrders = await _dexRepo.getBestOrders(
      BestOrdersRequest(
        coin: coin.abbr,
        type: BestOrdersRequestType.number,
        number: 1,
        action: 'sell',
      ),
    );

    if (emit.isDone ||
        walletId != state.walletId ||
        revision != state.formRevision ||
        coin.id != state.sellCoin?.id) {
      return;
    }

    /// Unsupported coins like ARRR cause downstream errors, so build a
    /// filtered copy without mutating repository/cache-owned response data.
    final filteredOrders = BestOrders(
      error: bestOrders.error,
      result: bestOrders.result == null
          ? null
          : Map<String, List<BestOrder>>.unmodifiable(
              Map.fromEntries(
                bestOrders.result!.entries
                    .where((entry) => !excludedAssetList.contains(entry.key))
                    .map(
                      (entry) => MapEntry(
                        entry.key,
                        List<BestOrder>.unmodifiable(entry.value),
                      ),
                    ),
              ),
            ),
    );

    emit(state.copyWith(bestOrders: () => filteredOrders));

    final buyCoin = event.autoSelectOrderAbbr;
    if (buyCoin != null) {
      final orders = filteredOrders.result?[buyCoin];
      if (orders != null && orders.isNotEmpty) {
        add(TakerSelectOrder(orders.first));
      }
    }
  }

  void _onCoinSelectorClick(
    TakerCoinSelectorClick event,
    Emitter<TakerState> emit,
  ) {
    emit(
      state.copyWith(
        showCoinSelector: () => !state.showCoinSelector,
        showOrderSelector: () => false,
      ),
    );
  }

  Future<void> _onOrderSelectorClick(
    TakerOrderSelectorClick event,
    Emitter<TakerState> emit,
  ) async {
    if (state.sellCoin == null) {
      await _validator.validateForm();
      return;
    }

    emit(
      state.copyWith(
        showOrderSelector: () => !state.showOrderSelector,
        showCoinSelector: () => false,
        bestOrders: _haveBestOrders ? () => state.bestOrders : () => null,
      ),
    );

    if (state.showOrderSelector && !_haveBestOrders) {
      add(TakerUpdateBestOrders());
    }
  }

  bool get _haveBestOrders {
    return state.bestOrders != null &&
        state.bestOrders!.result != null &&
        state.bestOrders!.result!.isNotEmpty;
  }

  void _onCoinSelectorOpen(
    TakerCoinSelectorOpen event,
    Emitter<TakerState> emit,
  ) {
    emit(state.copyWith(showCoinSelector: () => event.isOpen));
  }

  void _onOrderSelectorOpen(
    TakerOrderSelectorOpen event,
    Emitter<TakerState> emit,
  ) {
    emit(state.copyWith(showOrderSelector: () => event.isOpen));
  }

  void _onClear(TakerClear event, Emitter<TakerState> emit) {
    _maxSellAmountTimer?.cancel();
    final isUncertain =
        state.submissionStatus == AdvancedTradeSubmissionStatus.uncertain ||
        state.submissionStatus == AdvancedTradeSubmissionStatus.submitting ||
        (state.walletId != null &&
            _walletsRequiringSubmissionReconciliation.contains(state.walletId));

    emit(
      TakerState.initial().copyWith(
        walletId: () => state.walletId,
        formRevision: () => state.formRevision + 1,
        availableBalanceState: () => AvailableBalanceState.unavailable,
        submissionStatus: () => isUncertain
            ? AdvancedTradeSubmissionStatus.uncertain
            : AdvancedTradeSubmissionStatus.idle,
        submissionFailure: () =>
            isUncertain ? AdvancedTradeSubmissionFailure.uncertain : null,
      ),
    );
  }

  void _subscribeMaxSellAmount() {
    _maxSellAmountTimer?.cancel();

    add(const TakerUpdateMaxSellAmount());
    _maxSellAmountTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      add(const TakerUpdateMaxSellAmount());
    });
  }

  Future<void> _onUpdateMaxSellAmount(
    TakerUpdateMaxSellAmount event,
    Emitter<TakerState> emitter,
  ) async {
    final coin = state.sellCoin;
    final walletId = state.walletId;
    final revision = state.formRevision;
    if (coin == null) {
      _maxSellAmountTimer?.cancel();
      return;
    }
    // If not logged in, show 0.00 (unavailable) and skip spinner
    if (!_isLoggedIn) {
      emitter(
        state.copyWith(
          availableBalanceState: () => AvailableBalanceState.unavailable,
          maxSellAmount: () => null,
        ),
      );
      return;
    }

    if (state.availableBalanceState == AvailableBalanceState.initial ||
        event.setLoadingStatus) {
      emitter(
        state.copyWith(
          availableBalanceState: () => AvailableBalanceState.loading,
        ),
      );
    }

    try {
      // Required here because of the manual RPC calls that bypass the sdk
      final activeAssets = await _sdk.assets.getActivatedAssets();
      if (emitter.isDone || !_isCurrentInput(walletId, revision, coin)) return;
      final isAssetActive = activeAssets.any((asset) => asset.id == coin.id);
      if (!isAssetActive) {
        // Intentionally leave the state as loading so that a spinner is shown
        // instead of a "0.00" balance hinting that the asset is active when it
        // is not.
        if (state.availableBalanceState != AvailableBalanceState.loading) {
          emitter(
            state.copyWith(
              availableBalanceState: () => AvailableBalanceState.loading,
            ),
          );
        }
        return;
      }

      Rational? maxSellAmount = await _dexRepo.getMaxTakerVolume(coin.abbr);
      if (emitter.isDone || !_isCurrentInput(walletId, revision, coin)) return;
      if (maxSellAmount != null) {
        emitter(
          state.copyWith(
            maxSellAmount: () => maxSellAmount,
            availableBalanceState: () => AvailableBalanceState.success,
          ),
        );
      } else {
        maxSellAmount = await _frequentlyGetMaxTakerVolume(coin.abbr);
        if (emitter.isDone || !_isCurrentInput(walletId, revision, coin)) {
          return;
        }
        emitter(
          state.copyWith(
            maxSellAmount: () => maxSellAmount,
            availableBalanceState: maxSellAmount == null
                ? () => AvailableBalanceState.failure
                : () => AvailableBalanceState.success,
          ),
        );
      }
    } catch (_, s) {
      if (emitter.isDone || !_isCurrentInput(walletId, revision, coin)) return;
      _log.severe('Failed to update max sell amount', null, s);
      emitter(
        state.copyWith(
          availableBalanceState: () => AvailableBalanceState.failure,
        ),
      );
    }
  }

  Future<Rational?> _frequentlyGetMaxTakerVolume(String abbr) async {
    try {
      return await retry(
        () => _dexRepo.getMaxTakerVolume(abbr),
        maxAttempts: 3,
        backoffStrategy: LinearBackoff(
          initialDelay: const Duration(milliseconds: 500),
          maxDelay: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _onGetMinSellAmount(
    TakerGetMinSellAmount event,
    Emitter<TakerState> emit,
  ) async {
    final coin = state.sellCoin;
    final walletId = state.walletId;
    final revision = state.formRevision;
    if (coin == null) return;
    if (!_isLoggedIn) {
      emit(state.copyWith(minSellAmount: () => null));
      return;
    }

    final Rational? minSellAmount = await _dexRepo.getMinTradingVolume(
      coin.abbr,
    );

    if (emit.isDone || !_isCurrentInput(walletId, revision, coin)) return;
    emit(state.copyWith(minSellAmount: () => minSellAmount));
  }

  Future<void> _onUpdateFees(
    TakerUpdateFees event,
    Emitter<TakerState> emit,
  ) async {
    emit(state.copyWith(tradePreimage: () => null));

    if (!_validator.canRequestPreimage) return;

    final walletId = state.walletId;
    final revision = state.formRevision;
    final sellCoin = state.sellCoin;
    final order = state.selectedOrder;
    final amount = state.sellAmount;
    if (sellCoin == null || order == null || amount == null) return;

    final preimageData = await _getFeesData(
      base: sellCoin.abbr,
      rel: order.coin,
      price: order.price,
      volume: amount,
    );
    if (walletId != state.walletId ||
        revision != state.formRevision ||
        sellCoin.id != state.sellCoin?.id ||
        order != state.selectedOrder ||
        amount != state.sellAmount) {
      return;
    }
    add(
      TakerSetPreimage(
        preimageData.data,
        walletId: walletId,
        formRevision: revision,
      ),
    );
  }

  void _onSetPreimage(TakerSetPreimage event, Emitter<TakerState> emit) {
    if ((event.walletId != null && event.walletId != state.walletId) ||
        (event.formRevision != null &&
            event.formRevision != state.formRevision)) {
      return;
    }
    emit(state.copyWith(tradePreimage: () => event.tradePreimage));
  }

  Future<DataFromService<TradePreimage, BaseError>> _getFeesData({
    required String base,
    required String rel,
    required Rational price,
    required Rational volume,
  }) async {
    try {
      return await _dexRepo.getTradePreimage(base, rel, price, 'sell', volume);
    } catch (e, s) {
      log(
        'Unable to update taker fees',
        trace: s,
        path: 'taker_bloc::_getFeesData',
        isError: true,
      );
      return DataFromService(
        error: TextError(
          error: formatKdfUserFacingError(e),
          technicalDetails: extractKdfTechnicalDetails(e),
        ),
      );
    }
  }

  Future<bool> _autoActivateCoin(
    String? abbr, {
    String? walletId,
    int? revision,
  }) async {
    if (abbr == null || !_isLoggedIn) return false;

    final expectedWalletId = walletId ?? state.walletId;
    final expectedRevision = revision ?? state.formRevision;
    final expectedAuthObservationEpoch = _authObservationEpoch;
    if (expectedWalletId == null) return false;
    try {
      await _requireCoinActivationScope(
        expectedWalletId,
        expectedRevision,
        expectedAuthObservationEpoch,
        abbr,
      );
    } catch (_) {
      return false;
    }
    _activationOperations++;
    List<DexFormError> activationErrors = const [];
    try {
      activationErrors = await activateCoinIfNeeded(
        abbr,
        _coinsRepo,
        activationScopeKey:
            'taker:$expectedWalletId:$expectedRevision:'
            '$expectedAuthObservationEpoch:$abbr',
        beforeActivationMutation: () => _requireCoinActivationScope(
          expectedWalletId,
          expectedRevision,
          expectedAuthObservationEpoch,
          abbr,
        ),
      );
      await _requireCoinActivationScope(
        expectedWalletId,
        expectedRevision,
        expectedAuthObservationEpoch,
        abbr,
      );
    } catch (_, stackTrace) {
      _log.severe(
        'Unable to activate an Advanced trading asset',
        null,
        stackTrace,
      );
      return false;
    } finally {
      _activationOperations--;
    }

    final isCurrent =
        expectedAuthObservationEpoch == _authObservationEpoch &&
        expectedWalletId == state.walletId &&
        expectedRevision == state.formRevision &&
        (state.sellCoin?.abbr == abbr || state.selectedOrder?.coin == abbr);
    if (isCurrent && activationErrors.isNotEmpty) {
      add(TakerAddError(activationErrors.first));
    }
    return isCurrent;
  }

  Future<void> _requireCoinActivationScope(
    String walletId,
    int revision,
    int authObservationEpoch,
    String abbr,
  ) async {
    if (!_matchesCoinActivationScope(
      walletId,
      revision,
      authObservationEpoch,
      abbr,
    )) {
      throw const KdfWalletAuthorityUnavailable();
    }
    final currentWalletId = await freshKdfCurrentWalletId(_sdk);
    if (currentWalletId != walletId ||
        !_matchesCoinActivationScope(
          walletId,
          revision,
          authObservationEpoch,
          abbr,
        )) {
      throw const KdfWalletAuthorityUnavailable();
    }
  }

  bool _matchesCoinActivationScope(
    String walletId,
    int revision,
    int authObservationEpoch,
    String abbr,
  ) {
    return !_closing &&
        !isClosed &&
        authObservationEpoch == _authObservationEpoch &&
        walletId == state.walletId &&
        revision == state.formRevision &&
        (state.sellCoin?.abbr == abbr || state.selectedOrder?.coin == abbr);
  }

  bool _isCurrentInput(String? walletId, int revision, Coin? coin) {
    if (coin == null) return false;
    return walletId == state.walletId &&
        revision == state.formRevision &&
        coin.id == state.sellCoin?.id;
  }

  void _onSetInProgress(TakerSetInProgress event, Emitter<TakerState> emit) {
    emit(state.copyWith(inProgress: () => event.value));
  }

  void _onSetWalletReady(TakerSetWalletIsReady event, Emitter<TakerState> _) {
    _waitingForWallet = !event.ready;
  }

  void _onVerifyOrderVolume(
    TakerVerifyOrderVolume event,
    Emitter<TakerState> emit,
  ) {
    _validator.verifyOrderVolume();
  }

  Future<void> _onReInit(TakerReInit event, Emitter<TakerState> emit) async {
    emit(
      _invalidatePreparation().copyWith(
        errors: () => [],
        autovalidate: () => false,
        tradePreimage: () => null,
      ),
    );
    await _autoActivateCoin(state.sellCoin?.abbr);
    await _autoActivateCoin(state.selectedOrder?.coin);
  }

  @override
  Future<void> close() async {
    _closing = true;
    _submissionGeneration++;
    _maxSellAmountTimer?.cancel();
    await _authorizationSubscription.cancel();
    await super.close();
  }
}

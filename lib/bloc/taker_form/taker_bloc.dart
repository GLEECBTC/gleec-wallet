import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/analytics/events/transaction_events.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/dex_repository.dart';
import 'package:web_dex/bloc/taker_form/taker_event.dart';
import 'package:web_dex/bloc/taker_form/taker_state.dart';
import 'package:web_dex/bloc/taker_form/taker_validator.dart';
import 'package:web_dex/bloc/transformers.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:web_dex/mm2/mm2_api/rpc/best_orders/best_orders.dart';
import 'package:web_dex/mm2/mm2_api/rpc/best_orders/best_orders_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/sell/sell_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/sell/sell_response.dart';
import 'package:web_dex/model/available_balance_state.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/data_from_service.dart';
import 'package:web_dex/model/dex_form_error.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/shared/utils/kdf_error_display.dart';
import 'package:web_dex/model/trade_preimage.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/views/dex/dex_helpers.dart';

class TakerBloc extends Bloc<TakerEvent, TakerState> {
  TakerBloc({
    required DexRepository dexRepository,
    required CoinsRepo coinsRepository,
    required KomodoDefiSdk kdfSdk,
    required AnalyticsBloc analyticsBloc,
  }) : _dexRepo = dexRepository,
       _coinsRepo = coinsRepository,
       _sdk = kdfSdk,
       _analyticsBloc = analyticsBloc,
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
    on<TakerSelectOrder>(_onSelectOrder);
    on<TakerAddError>(_onAddError);
    on<TakerClearErrors>(_onClearErrors);
    on<TakerUpdateBestOrders>(_onUpdateBestOrders);
    on<TakerClear>(_onClear);
    on<TakerSellAmountChange>(_onSellAmountChange, transformer: debounce());
    on<TakerSetSellAmount>(_onSetSellAmount);
    on<TakerUpdateMaxSellAmount>(
      _onUpdateMaxSellAmount,
      transformer: restartable(),
    );
    on<TakerGetMinSellAmount>(_onGetMinSellAmount, transformer: restartable());
    on<TakerAmountButtonClick>(_onAmountButtonClick);
    on<TakerUpdateFees>(_onUpdateFees);
    on<TakerSetPreimage>(_onSetPreimage);
    on<TakerFormSubmitClick>(_onFormSubmitClick);
    on<TakerBackButtonClick>(_onBackButtonClick);
    on<TakerStartSwap>(_onStartSwap);
    on<TakerSetInProgress>(_onSetInProgress);
    on<TakerReInit>(_onReInit);
    on<TakerVerifyOrderVolume>(_onVerifyOrderVolume);
    on<TakerSetWalletIsReady>(_onSetWalletReady);

    _authorizationSubscription = kdfSdk.auth.watchCurrentUser().listen((event) {
      if (event != null && state.step == TakerStep.confirm) {
        add(TakerBackButtonClick());
      }
      if (event == null) {
        add(TakerClear());
        add(TakerSetDefaults());
      }
      _isLoggedIn = event != null;
    });
  }

  final DexRepository _dexRepo;
  final CoinsRepo _coinsRepo;
  final KomodoDefiSdk _sdk;
  final AnalyticsBloc _analyticsBloc;
  Timer? _maxSellAmountTimer;
  bool _activatingAssets = false;
  bool _waitingForWallet = true;
  bool _isLoggedIn = false;
  late TakerValidator _validator;
  late StreamSubscription<KdfUser?> _authorizationSubscription;
  final Logger _log = Logger('TakerBloc');

  Future<void> _onStartSwap(
    TakerStartSwap event,
    Emitter<TakerState> emit,
  ) async {
    final sellCoin = state.sellCoin;
    final selectedOrder = state.selectedOrder;
    final sellAmount = state.sellAmount;

    if (sellCoin == null || selectedOrder == null || sellAmount == null) {
      _log.warning(
        'Attempted to start swap with incomplete state. sellCoin: '
        '$sellCoin, selectedOrder: $selectedOrder, sellAmount: $sellAmount',
      );
      emit(state.copyWith(inProgress: () => false));
      add(
        TakerAddError(
          DexFormError(error: LocaleKeys.dexUnableToStartSwap.tr()),
        ),
      );
      return;
    }

    emit(state.copyWith(inProgress: () => true));

    final int callStart = DateTime.now().millisecondsSinceEpoch;
    final SellResponse response = await _dexRepo.sell(
      SellRequest(
        base: sellCoin.abbr,
        rel: selectedOrder.coin,
        volume: sellAmount,
        price: selectedOrder.price,
        orderType: SellBuyOrderType.fillOrKill,
      ),
    );
    final int durationMs = DateTime.now().millisecondsSinceEpoch - callStart;

    if (response.error != null) {
      add(TakerAddError(DexFormError(error: response.error!.message)));

      // Log swap failure analytics event for immediate RPC errors
      final walletType =
          (await _sdk.auth.currentUser)?.wallet.config.type.name ?? 'unknown';
      _analyticsBloc.logEvent(
        SwapFailedEventData(
          asset: sellCoin.abbr,
          secondaryAsset: selectedOrder.coin,
          network: sellCoin.protocolType,
          secondaryNetwork:
              _coinsRepo.getCoin(selectedOrder.coin)?.protocolType ?? 'unknown',
          failureStage: 'order_submission',
          hdType: walletType,
          durationMs: durationMs,
        ),
      );
    }

    final String? uuid = response.result?.uuid;

    emit(
      state.copyWith(
        inProgress: uuid == null ? () => false : null,
        swapUuid: () => uuid,
      ),
    );
  }

  void _onBackButtonClick(
    TakerBackButtonClick event,
    Emitter<TakerState> emit,
  ) {
    emit(state.copyWith(step: () => TakerStep.form, errors: () => []));
  }

  Future<void> _onFormSubmitClick(
    TakerFormSubmitClick event,
    Emitter<TakerState> emit,
  ) async {
    emit(state.copyWith(inProgress: () => true, autovalidate: () => true));

    await pauseWhile(() => _waitingForWallet || _activatingAssets);

    final bool isValid = await _validator.validate();

    emit(
      state.copyWith(
        inProgress: () => false,
        step: () => isValid ? TakerStep.confirm : TakerStep.form,
      ),
    );
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
    final Rational? amount = event.value.isNotEmpty
        ? parseLocaleAwareRational(event.value)
        : null;

    if (amount == state.sellAmount) return;

    add(TakerSetSellAmount(amount));
  }

  Future<void> _onSetSellAmount(
    TakerSetSellAmount event,
    Emitter<TakerState> emit,
  ) async {
    emit(
      state.copyWith(
        sellAmount: () => event.amount,
        buyAmount: () => calculateBuyAmount(
          selectedOrder: state.selectedOrder,
          sellAmount: event.amount,
        ),
      ),
    );

    if (state.autovalidate) {
      await _validator.validateForm();
    } else {
      add(TakerVerifyOrderVolume());
    }
    add(TakerUpdateFees());
  }

  void _onAddError(TakerAddError event, Emitter<TakerState> emit) {
    final List<DexFormError> errorsList = List.from(state.errors);
    if (errorsList.any((e) => e.error == event.error.error)) {
      // Avoid adding duplicate errors
      return;
    }
    errorsList.add(event.error);

    emit(state.copyWith(errors: () => errorsList));
  }

  void _onClearErrors(TakerClearErrors event, Emitter<TakerState> emit) {
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

    emit(
      state.copyWith(
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

    await _autoActivateCoin(state.selectedOrder?.coin);
    if (state.autovalidate) await _validator.validateForm();
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

    emit(
      state.copyWith(
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

    await _autoActivateCoin(state.sellCoin?.abbr);
    _subscribeMaxSellAmount();
    add(TakerGetMinSellAmount());
  }

  Future<void> _onUpdateBestOrders(
    TakerUpdateBestOrders event,
    Emitter<TakerState> emit,
  ) async {
    final Coin? coin = state.sellCoin;

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

    /// Unsupported coins like ARRR cause downstream errors, so we need to
    /// remove them from the list here
    bestOrders.result?.removeWhere(
      (coinId, _) => excludedAssetList.contains(coinId),
    );

    emit(state.copyWith(bestOrders: () => bestOrders));

    final buyCoin = event.autoSelectOrderAbbr;
    if (buyCoin != null) {
      final orders = bestOrders.result?[buyCoin];
      if (orders != null) {
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

    emit(
      TakerState.initial().copyWith(
        availableBalanceState: () => AvailableBalanceState.unavailable,
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
    if (state.sellCoin == null) {
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
      final isAssetActive = activeAssets.any(
        (asset) => asset.id == state.sellCoin!.id,
      );
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

      Rational? maxSellAmount = await _dexRepo.getMaxTakerVolume(
        state.sellCoin!.abbr,
      );
      if (maxSellAmount != null) {
        emitter(
          state.copyWith(
            maxSellAmount: () => maxSellAmount,
            availableBalanceState: () => AvailableBalanceState.success,
          ),
        );
      } else {
        maxSellAmount = await _frequentlyGetMaxTakerVolume();
        emitter(
          state.copyWith(
            maxSellAmount: () => maxSellAmount,
            availableBalanceState: maxSellAmount == null
                ? () => AvailableBalanceState.failure
                : () => AvailableBalanceState.success,
          ),
        );
      }
    } catch (e, s) {
      _log.severe('Failed to update max sell amount', e, s);
      emitter(
        state.copyWith(
          availableBalanceState: () => AvailableBalanceState.failure,
        ),
      );
    }
  }

  Future<Rational?> _frequentlyGetMaxTakerVolume() async {
    final String? abbr = state.sellCoin?.abbr;
    if (abbr == null) return null;

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
    if (state.sellCoin == null) return;
    if (!_isLoggedIn) {
      emit(state.copyWith(minSellAmount: () => null));
      return;
    }

    final Rational? minSellAmount = await _dexRepo.getMinTradingVolume(
      state.sellCoin!.abbr,
    );

    emit(state.copyWith(minSellAmount: () => minSellAmount));
  }

  Future<void> _onUpdateFees(
    TakerUpdateFees event,
    Emitter<TakerState> emit,
  ) async {
    emit(state.copyWith(tradePreimage: () => null));

    if (!_validator.canRequestPreimage) return;

    final preimageData = await _getFeesData();
    add(TakerSetPreimage(preimageData.data));
  }

  void _onSetPreimage(TakerSetPreimage event, Emitter<TakerState> emit) {
    emit(state.copyWith(tradePreimage: () => event.tradePreimage));
  }

  Future<DataFromService<TradePreimage, BaseError>> _getFeesData() async {
    try {
      return await _dexRepo.getTradePreimage(
        state.sellCoin!.abbr,
        state.selectedOrder!.coin,
        state.selectedOrder!.price,
        'sell',
        state.sellAmount,
      );
    } catch (e, s) {
      log(
        e.toString(),
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

  Future<void> _autoActivateCoin(String? abbr) async {
    if (abbr == null || !_isLoggedIn) return;

    _activatingAssets = true;
    final List<DexFormError> activationErrors = await activateCoinIfNeeded(
      abbr,
      _coinsRepo,
    );
    _activatingAssets = false;

    if (activationErrors.isNotEmpty) {
      add(TakerAddError(activationErrors.first));
    }
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
    emit(state.copyWith(errors: () => [], autovalidate: () => false));
    await _autoActivateCoin(state.sellCoin?.abbr);
    await _autoActivateCoin(state.selectedOrder?.coin);
  }

  @override
  Future<void> close() {
    _maxSellAmountTimer?.cancel();
    _authorizationSubscription.cancel();

    return super.close();
  }
}

import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart' show KomodoDefiSdk;
import 'package:komodo_defi_types/komodo_defi_type_utils.dart'
    show LinearBackoff, retry;
import 'package:komodo_defi_types/komodo_defi_types.dart' show KdfUser;
import 'package:rational/rational.dart';
import 'package:web_dex/analytics/events/cross_chain_events.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/bridge_form/bridge_event.dart';
import 'package:web_dex/bloc/bridge_form/bridge_repository.dart';
import 'package:web_dex/bloc/bridge_form/bridge_state.dart';
import 'package:web_dex/bloc/bridge_form/bridge_validator.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/dex_repository.dart';
import 'package:web_dex/bloc/transformers.dart';
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
import 'package:web_dex/model/trade_preimage.dart';
import 'package:web_dex/model/typedef.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/dex/dex_helpers.dart';

class BridgeBloc extends Bloc<BridgeEvent, BridgeState> {
  BridgeBloc({
    required BridgeRepository bridgeRepository,
    required DexRepository dexRepository,
    required CoinsRepo coinsRepository,
    required KomodoDefiSdk kdfSdk,
    required AnalyticsBloc analyticsBloc,
  }) : _bridgeRepository = bridgeRepository,
       _dexRepository = dexRepository,
       _coinsRepository = coinsRepository,
       _kdfSdk = kdfSdk,
       _analyticsBloc = analyticsBloc,
       super(BridgeState.initial()) {
    on<BridgeInit>(_onInit);
    on<BridgeReInit>(_onReInit);
    on<BridgeLogout>(_onLogout);
    on<BridgeTickerChanged>(_onTickerChanged);
    on<BridgeUpdateTickers>(_onUpdateTickers);
    on<BridgeShowTickerDropdown>(_onShowTickerDropdown);
    on<BridgeShowSourceDropdown>(_onShowSourceDropdown);
    on<BridgeShowTargetDropdown>(_onShowTargetDropdown);
    on<BridgeUpdateSellCoins>(_onUpdateSellCoins);
    on<BridgeSetSellCoin>(_onSetSellCoin);
    on<BridgeUpdateBestOrders>(_onUpdateBestOrders);
    on<BridgeSelectBestOrder>(_onSelectBestOrder);
    on<BridgeSetError>(_onSetError);
    on<BridgeClearErrors>(_onClearErrors);
    on<BridgeUpdateMaxSellAmount>(_onUpdateMaxSellAmount);
    on<BridgeAmountButtonClick>(_onAmountButtonClick);
    on<BridgeSellAmountChange>(_onSellAmountChange, transformer: debounce());
    on<BridgeSetSellAmount>(_onSetSellAmount);
    on<BridgeUpdateFees>(_onUpdateFees);
    on<BridgeGetMinSellAmount>(_onGetMinSellAmount);
    on<BridgeSetPreimage>(_onSetPreimage);
    on<BridgeSetInProgress>(_onSetInProgress);
    on<BridgeSubmitClick>(_onSubmitClick);
    on<BridgeBackClick>(_onBackClick);
    on<BridgeSetWalletIsReady>(_onSetWalletIsReady);
    on<BridgeStartSwap>(_onStartSwap);
    on<BridgeClear>(_onClear);
    on<BridgeVerifyOrderVolume>(_verifyOrderVolume);

    _validator = BridgeValidator(
      bloc: this,
      coinsRepository: coinsRepository,
      dexRepository: dexRepository,
      sdk: _kdfSdk,
    );

    _authorizationSubscription = _kdfSdk.auth.watchCurrentUser().listen((
      event,
    ) {
      _isLoggedIn = event != null;
      if (!_isLoggedIn) add(const BridgeLogout());
    });
  }

  final BridgeRepository _bridgeRepository;
  final DexRepository _dexRepository;
  final CoinsRepo _coinsRepository;
  final KomodoDefiSdk _kdfSdk;
  final AnalyticsBloc _analyticsBloc;

  bool _activatingAssets = false;
  bool _waitingForWallet = true;
  bool _isLoggedIn = false;
  late StreamSubscription<KdfUser?> _authorizationSubscription;
  late BridgeValidator _validator;
  Timer? _maxSellAmountTimer;
  Timer? _preimageTimer;

  void _onInit(BridgeInit event, Emitter<BridgeState> emit) {
    if (state.selectedTicker != null) return;

    final Coin? defaultTickerCoin = _coinsRepository.getCoin(event.ticker);
    emit(state.copyWith(selectedTicker: () => defaultTickerCoin?.abbr));

    add(const BridgeUpdateTickers());
  }

  Future<void> _onReInit(BridgeReInit event, Emitter<BridgeState> emit) async {
    _isLoggedIn = true;

    emit(state.copyWith(error: () => null, autovalidate: () => false));

    add(const BridgeUpdateMaxSellAmount(true));

    await _autoActivateCoin(state.sellCoin?.abbr);
    await _autoActivateCoin(state.bestOrder?.coin);

    add(const BridgeGetMinSellAmount());
    _subscribeFees();
  }

  void _onLogout(BridgeLogout event, Emitter<BridgeState> emit) {
    _isLoggedIn = false;

    emit(
      state.copyWith(
        availableBalanceState: () => AvailableBalanceState.unavailable,
        maxSellAmount: () => null,
        preimageData: () => null,
        step: () => BridgeStep.form,
      ),
    );
  }

  void _onTickerChanged(BridgeTickerChanged event, Emitter<BridgeState> emit) {
    emit(
      state.copyWith(
        selectedTicker: () => event.ticker,
        showTickerDropdown: () => false,
        sellCoin: () => null,
        sellAmount: () => null,
        bestOrders: () => null,
        bestOrder: () => null,
        buyAmount: () => null,
        maxSellAmount: () => null,
        availableBalanceState: () => AvailableBalanceState.unavailable,
        preimageData: () => null,
        error: () => null,
      ),
    );
  }

  Future<void> _onUpdateTickers(
    BridgeUpdateTickers event,
    Emitter<BridgeState> emit,
  ) async {
    final CoinsByTicker tickers = await _bridgeRepository.getAvailableTickers();

    emit(state.copyWith(tickers: () => tickers));

    add(const BridgeUpdateSellCoins());
  }

  void _onShowTickerDropdown(
    BridgeShowTickerDropdown event,
    Emitter<BridgeState> emit,
  ) {
    emit(
      state.copyWith(
        showTickerDropdown: () => event.show,
        showSourceDropdown: () => false,
        showTargetDropdown: () => false,
      ),
    );
  }

  void _onShowSourceDropdown(
    BridgeShowSourceDropdown event,
    Emitter<BridgeState> emit,
  ) {
    emit(
      state.copyWith(
        showSourceDropdown: () => event.show,
        showTickerDropdown: () => false,
        showTargetDropdown: () => false,
      ),
    );
  }

  void _onShowTargetDropdown(
    BridgeShowTargetDropdown event,
    Emitter<BridgeState> emit,
  ) {
    emit(
      state.copyWith(
        showTargetDropdown: () => event.show,
        showTickerDropdown: () => false,
        showSourceDropdown: () => false,
      ),
    );
  }

  Future<void> _onUpdateSellCoins(
    BridgeUpdateSellCoins event,
    Emitter<BridgeState> emit,
  ) async {
    final CoinsByTicker? sellCoins = await _bridgeRepository.getSellCoins(
      state.tickers,
    );

    emit(state.copyWith(sellCoins: () => sellCoins));
  }

  Future<void> _onSetSellCoin(
    BridgeSetSellCoin event,
    Emitter<BridgeState> emit,
  ) async {
    emit(
      state.copyWith(
        sellCoin: () => event.coin,
        sellAmount: () => null,
        showSourceDropdown: () => false,
        bestOrders: () => null,
        bestOrder: () => null,
        buyAmount: () => null,
        maxSellAmount: () => null,
        availableBalanceState: () => AvailableBalanceState.initial,
        preimageData: () => null,
        error: () => null,
        autovalidate: () => false,
      ),
    );

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

    await _autoActivateCoin(event.coin.abbr);
    _subscribeMaxSellAmount();

    add(const BridgeGetMinSellAmount());
    add(const BridgeUpdateBestOrders());
  }

  Future<void> _onUpdateBestOrders(
    BridgeUpdateBestOrders event,
    Emitter<BridgeState> emit,
  ) async {
    if (!event.silent) {
      emit(state.copyWith(bestOrders: () => null));
    }

    final sellCoin = state.sellCoin;
    if (sellCoin == null) return;

    final bestOrders = await _dexRepository.getBestOrders(
      BestOrdersRequest(
        coin: sellCoin.abbr,
        action: 'sell',
        type: BestOrdersRequestType.number,
        number: 1,
      ),
    );

    /// Unsupported coins like ARRR cause downstream errors, so we need to
    /// remove them from the list here
    bestOrders.result?.removeWhere(
      (coinId, _) => excludedAssetList.contains(coinId),
    );

    emit(state.copyWith(bestOrders: () => bestOrders));
  }

  void _onSelectBestOrder(
    BridgeSelectBestOrder event,
    Emitter<BridgeState> emit,
  ) async {
    final bool switchingCoin =
        state.bestOrder != null &&
        event.order != null &&
        state.bestOrder!.coin != event.order!.coin;

    emit(
      state.copyWith(
        bestOrder: () => event.order,
        showTargetDropdown: () => false,
        buyAmount: () => calculateBuyAmount(
          sellAmount: state.sellAmount,
          selectedOrder: event.order,
        ),
        error: () => null,
        autovalidate: switchingCoin ? () => false : null,
      ),
    );

    if (!state.autovalidate) add(const BridgeVerifyOrderVolume());

    await _autoActivateCoin(event.order?.coin);
    if (state.autovalidate) await _validator.validateForm();
    _subscribeFees();
  }

  void _onSetError(BridgeSetError event, Emitter<BridgeState> emit) {
    emit(state.copyWith(error: () => event.error));
  }

  void _onClearErrors(BridgeClearErrors event, Emitter<BridgeState> emit) {
    emit(state.copyWith(error: () => null));
  }

  void _subscribeFees() {
    _preimageTimer?.cancel();
    if (!_validator.canRequestPreimage) return;

    add(const BridgeUpdateFees());
    _preimageTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      add(const BridgeUpdateFees());
    });
  }

  void _subscribeMaxSellAmount() {
    _maxSellAmountTimer?.cancel();

    add(const BridgeUpdateMaxSellAmount(true));
    _maxSellAmountTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      add(const BridgeUpdateMaxSellAmount());
    });
  }

  void _onAmountButtonClick(
    BridgeAmountButtonClick event,
    Emitter<BridgeState> emit,
  ) {
    final Rational? maxSellAmount = state.maxSellAmount;
    if (maxSellAmount == null) return;
    final Rational sellAmount = getFractionOfAmount(
      maxSellAmount,
      event.fraction,
    );
    add(BridgeSetSellAmount(sellAmount));
  }

  void _onSellAmountChange(
    BridgeSellAmountChange event,
    Emitter<BridgeState> emit,
  ) {
    final Rational? amount = event.value.isNotEmpty
        ? Rational.tryParse(event.value)
        : null;

    if (amount == state.sellAmount) return;

    add(BridgeSetSellAmount(amount));
  }

  Future<void> _onSetSellAmount(
    BridgeSetSellAmount event,
    Emitter<BridgeState> emit,
  ) async {
    emit(
      state.copyWith(
        sellAmount: () => event.amount,
        buyAmount: () => calculateBuyAmount(
          selectedOrder: state.bestOrder,
          sellAmount: event.amount,
        ),
      ),
    );

    if (state.autovalidate) {
      await _validator.validateForm();
    } else {
      add(const BridgeVerifyOrderVolume());
    }
    _subscribeFees();
  }

  Future<void> _onUpdateMaxSellAmount(
    BridgeUpdateMaxSellAmount event,
    Emitter<BridgeState> emit,
  ) async {
    if (state.sellCoin == null) {
      _maxSellAmountTimer?.cancel();
      emit(
        state.copyWith(
          availableBalanceState: () => AvailableBalanceState.unavailable,
        ),
      );
      return;
    }

    // If not logged in, show 0.00 (unavailable) and skip spinner
    if (!_isLoggedIn) {
      emit(
        state.copyWith(
          availableBalanceState: () => AvailableBalanceState.unavailable,
          maxSellAmount: () => null,
        ),
      );
      return;
    }

    if (state.availableBalanceState == AvailableBalanceState.initial ||
        event.setLoadingStatus) {
      emit(
        state.copyWith(
          availableBalanceState: () => AvailableBalanceState.loading,
        ),
      );
    }

    {
      Rational? maxSellAmount = await _dexRepository.getMaxTakerVolume(
        state.sellCoin!.abbr,
      );
      if (maxSellAmount != null) {
        emit(
          state.copyWith(
            maxSellAmount: () => maxSellAmount,
            availableBalanceState: () => AvailableBalanceState.success,
          ),
        );
      } else {
        maxSellAmount = await _frequentlyGetMaxTakerVolume();
        emit(
          state.copyWith(
            maxSellAmount: () => maxSellAmount,
            availableBalanceState: maxSellAmount == null
                ? () => AvailableBalanceState.failure
                : () => AvailableBalanceState.success,
          ),
        );
      }
    }
  }

  void _onUpdateFees(BridgeUpdateFees event, Emitter<BridgeState> emit) async {
    emit(state.copyWith(preimageData: () => null));

    if (!_validator.canRequestPreimage) {
      _preimageTimer?.cancel();
      return;
    }

    final preimageData = await _getFeesData();
    add(BridgeSetPreimage(preimageData));
  }

  Future<void> _onGetMinSellAmount(
    BridgeGetMinSellAmount event,
    Emitter<BridgeState> emit,
  ) async {
    if (state.sellCoin == null) return;
    if (!_isLoggedIn) {
      emit(state.copyWith(minSellAmount: () => null));
      return;
    }

    final Rational? minSellAmount = await _dexRepository.getMinTradingVolume(
      state.sellCoin!.abbr,
    );

    emit(state.copyWith(minSellAmount: () => minSellAmount));
  }

  void _onSetPreimage(BridgeSetPreimage event, Emitter<BridgeState> emit) {
    emit(state.copyWith(preimageData: () => event.preimageData));
  }

  void _onSetInProgress(BridgeSetInProgress event, Emitter<BridgeState> emit) {
    emit(state.copyWith(inProgress: () => event.inProgress));
  }

  void _onSubmitClick(
    BridgeSubmitClick event,
    Emitter<BridgeState> emit,
  ) async {
    emit(state.copyWith(inProgress: () => true, autovalidate: () => true));

    await pauseWhile(() => _waitingForWallet || _activatingAssets);

    final bool isValid = await _validator.validate();

    emit(
      state.copyWith(
        inProgress: () => false,
        step: () => isValid ? BridgeStep.confirm : BridgeStep.form,
      ),
    );
  }

  void _onBackClick(BridgeBackClick event, Emitter<BridgeState> emit) {
    emit(state.copyWith(step: () => BridgeStep.form, error: () => null));
  }

  void _onSetWalletIsReady(
    BridgeSetWalletIsReady event,
    Emitter<BridgeState> emit,
  ) {
    _waitingForWallet = !event.isReady;
  }

  void _onStartSwap(BridgeStartSwap event, Emitter<BridgeState> emit) async {
    final sellCoin = state.sellCoin;
    final bestOrder = state.bestOrder;
    if (sellCoin != null && bestOrder != null) {
      final buyCoin = _coinsRepository.getCoin(bestOrder.coin);
      final walletType =
          (await _kdfSdk.auth.currentUser)?.wallet.config.type.name ?? '';
      _analyticsBloc.logEvent(
        BridgeInitiatedEventData(
          asset: sellCoin.abbr,
          secondaryAsset: buyCoin?.abbr ?? sellCoin.abbr,
          network: sellCoin.protocolType,
          secondaryNetwork: buyCoin?.protocolType ?? '',
          hdType: walletType,
        ),
      );
    }
    emit(state.copyWith(inProgress: () => true));
    final SellResponse response = await _dexRepository.sell(
      SellRequest(
        base: state.sellCoin!.abbr,
        rel: state.bestOrder!.coin,
        volume: state.sellAmount!,
        price: state.bestOrder!.price,
        orderType: SellBuyOrderType.fillOrKill,
      ),
    );

    final String? uuid = response.result?.uuid;

    if (uuid != null) {
      final buyCoin = _coinsRepository.getCoin(state.bestOrder!.coin);
      final walletType =
          (await _kdfSdk.auth.currentUser)?.wallet.config.type.name ?? '';
      _analyticsBloc.logEvent(
        BridgeSucceededEventData(
          asset: state.sellCoin!.abbr,
          secondaryAsset: buyCoin?.abbr ?? state.sellCoin!.abbr,
          network: state.sellCoin!.protocolType,
          secondaryNetwork: buyCoin?.protocolType ?? '',
          amount: state.sellAmount?.toDouble() ?? 0.0,
          hdType: walletType,
        ),
      );
    } else {
      final buyCoin = _coinsRepository.getCoin(state.bestOrder!.coin);
      final walletType =
          (await _kdfSdk.auth.currentUser)?.wallet.config.type.name ?? '';
      final error = response.error?.message ?? 'unknown';
      _analyticsBloc.logEvent(
        BridgeFailedEventData(
          asset: state.sellCoin!.abbr,
          secondaryAsset: buyCoin?.abbr ?? state.sellCoin!.abbr,
          network: state.sellCoin!.protocolType,
          secondaryNetwork: buyCoin?.protocolType ?? '',
          failureStage: 'start_swap',
          failureDetail: error,
          hdType: walletType,
        ),
      );
      add(BridgeSetError(DexFormError(error: error)));
    }

    emit(
      state.copyWith(
        inProgress: uuid == null ? () => false : null,
        swapUuid: () => uuid,
      ),
    );
  }

  void _verifyOrderVolume(
    BridgeVerifyOrderVolume event,
    Emitter<BridgeState> emit,
  ) {
    _validator.verifyOrderVolume();
  }

  void _onClear(BridgeClear event, Emitter<BridgeState> emit) {
    emit(BridgeState.initial());
  }

  Future<Rational?> _frequentlyGetMaxTakerVolume() async {
    final String? abbr = state.sellCoin?.abbr;
    if (abbr == null) return null;

    try {
      return await retry(
        () => _dexRepository.getMaxTakerVolume(abbr),
        maxAttempts: 5,
        backoffStrategy: LinearBackoff(
          initialDelay: const Duration(seconds: 2),
          increment: const Duration(seconds: 2),
          maxDelay: const Duration(seconds: 10),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _autoActivateCoin(String? abbr) async {
    if (abbr == null) return;

    _activatingAssets = true;
    final List<DexFormError> activationErrors = await activateCoinIfNeeded(
      abbr,
      _coinsRepository,
    );
    _activatingAssets = false;

    if (activationErrors.isNotEmpty) {
      add(BridgeSetError(activationErrors.first));
    }
  }

  List<BestOrder> prepareTargetsList(Map<String, List<BestOrder>> bestOrders) {
    final List<BestOrder> list = [];

    final Coin? sellCoin = state.sellCoin;
    if (sellCoin == null) return list;

    bestOrders.forEach((key, value) => list.addAll(value));

    list.removeWhere((order) {
      final Coin? item = _coinsRepository.getCoin(order.coin);
      if (item == null) return true;

      final sameTicker = abbr2Ticker(item.abbr) == abbr2Ticker(sellCoin.abbr);
      if (!sameTicker) return true;

      if (item.isSuspended) return true;
      if (item.walletOnly) return true;

      return false;
    });

    list.sort((a, b) => a.coin.compareTo(b.coin));

    return list;
  }

  Future<DataFromService<TradePreimage, BaseError>> _getFeesData() async {
    try {
      return await _dexRepository.getTradePreimage(
        state.sellCoin!.abbr,
        state.bestOrder!.coin,
        state.bestOrder!.price,
        'sell',
        state.sellAmount,
      );
    } catch (e, s) {
      log(
        e.toString(),
        trace: s,
        path: 'bridge_bloc::_getFeesData',
        isError: true,
      );
      return DataFromService(error: TextError(error: 'Failed to request fees'));
    }
  }

  @override
  Future<void> close() {
    _authorizationSubscription.cancel();
    _maxSellAmountTimer?.cancel();
    _preimageTimer?.cancel();

    return super.close();
  }
}

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:equatable/equatable.dart';
import 'package:formz/formz.dart';
import 'package:get_it/get_it.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:logging/logging.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/bloc/coins_bloc/asset_coin_extension.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/dex_repository.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_bot/market_maker_bot_wallet_session.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_order_list/trade_pair.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:web_dex/mm2/mm2_api/rpc/market_maker_bot/trade_coin_pair_config.dart';
import 'package:web_dex/mm2/mm2_api/rpc/market_maker_bot/trade_volume.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trade_preimage/trade_preimage_errors.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/data_from_service.dart';
import 'package:web_dex/model/forms/coin_select_input.dart';
import 'package:web_dex/model/forms/coin_trade_amount_input.dart';
import 'package:web_dex/model/forms/trade_margin_input.dart';
import 'package:web_dex/model/forms/trade_volume_input.dart';
import 'package:web_dex/model/forms/update_interval_input.dart';
import 'package:web_dex/model/orderbook/order.dart';
import 'package:web_dex/model/trade_preimage.dart';

part 'market_maker_trade_form_event.dart';
part 'market_maker_trade_form_state.dart';

class MarketMakerTradeFormBloc
    extends Bloc<MarketMakerTradeFormEvent, MarketMakerTradeFormState> {
  /// The market maker trade form bloc is used to manage the state of the trade
  /// form. The trade form is used to create a trade pair for the market maker
  /// bot.
  ///
  /// The [DexRepository] is used to get the trade preimage, which is used
  /// to pre-emptively check if a successful.
  ///
  /// The [CoinsRepo] is used to activate coins that are not active when
  /// they are selected in the trade form.
  MarketMakerTradeFormBloc({
    required DexRepository dexRepo,
    required CoinsRepo coinsRepo,
  }) : _dexRepository = dexRepo,
       _coinsRepo = coinsRepo,
       _log = Logger('MarketMakerTradeFormBloc'),
       super(MarketMakerTradeFormState.initial()) {
    on<MarketMakerTradeFormSellCoinChanged>(
      _onSellCoinChanged,
      transformer: restartable(),
    );
    on<MarketMakerTradeFormBuyCoinChanged>(
      _onBuyCoinChanged,
      transformer: restartable(),
    );
    on<MarketMakerTradeFormTradeVolumeChanged>(
      _onTradeVolumeChanged,
      transformer: restartable(),
    );
    on<MarketMakerTradeFormSwapCoinsRequested>(
      _onSwapCoinsRequested,
      transformer: restartable(),
    );
    on<MarketMakerTradeFormTradeMarginChanged>(_onTradeMarginChanged);
    on<MarketMakerTradeFormUpdateIntervalChanged>(_onUpdateIntervalChanged);
    on<MarketMakerTradeFormClearRequested>(_onClearForm);
    on<MarketMakerTradeFormEditOrderRequested>(
      _onEditOrder,
      transformer: restartable(),
    );
    on<MarketMakerTradeFormAskOrderbookSelected>(_onOrderbookSelected);
    on<MarketMakerConfirmationPreviewRequested>(
      _onPreviewConfirmation,
      transformer: restartable(),
    );
    on<MarketMakerConfirmationPreviewCancelRequested>(
      _onPreviewConfirmationCancelled,
    );
  }

  /// The dex repository is used to get the trade preimage, which is used
  /// to pre-emptively check if a trade will be successful
  final DexRepository _dexRepository;

  /// The coins repository is used to activate coins that are not active
  /// when they are selected in the trade form
  final CoinsRepo _coinsRepo;

  final Logger _log;

  final _sdk = GetIt.I<KomodoDefiSdk>();

  int _latestDraftRevision = 0;
  int _baseCoinRequestGeneration = 0;

  MarketMakerTradeFormState _draftChanged(
    MarketMakerTradeFormState next, {
    MarketMakerTradeFormStatus status = MarketMakerTradeFormStatus.success,
  }) {
    _latestDraftRevision++;
    return next.copyWith(
      stage: MarketMakerTradeFormStage.initial,
      status: status,
      draftRevision: _latestDraftRevision,
      preImageError: () => null,
      tradePreImage: () => null,
      rawErrorMessage: () => null,
      previewRevision: () => null,
      previewWalletSession: () => null,
    );
  }

  bool _isCurrentDraft(
    Emitter<MarketMakerTradeFormState> emit,
    int revision, {
    MarketMakerBotWalletSession? walletSession,
    bool requireConfirmationStage = false,
  }) {
    return !emit.isDone &&
        state.draftRevision == revision &&
        (walletSession == null || state.walletSession == walletSession) &&
        (!requireConfirmationStage ||
            state.stage == MarketMakerTradeFormStage.confirmationRequired);
  }

  bool _isCurrentBaseCoinRequest(
    Emitter<MarketMakerTradeFormState> emit,
    int generation,
    Coin? sellCoin, {
    MarketMakerBotWalletSession? walletSession,
  }) {
    return !emit.isDone &&
        generation == _baseCoinRequestGeneration &&
        state.sellCoin.value == sellCoin &&
        (walletSession == null || state.walletSession == walletSession);
  }

  Future<void> _onSellCoinChanged(
    MarketMakerTradeFormSellCoinChanged event,
    Emitter<MarketMakerTradeFormState> emit,
  ) async {
    final baseCoinRequestGeneration = ++_baseCoinRequestGeneration;
    final identicalBuyAndSellCoins = state.buyCoin.value == event.sellCoin;

    emit(
      _draftChanged(
        state.copyWith(
          sellCoin: CoinSelectInput.dirty(event.sellCoin),
          buyCoin: identicalBuyAndSellCoins
              ? const CoinSelectInput.dirty(null, -1)
              : state.buyCoin,
          sellAmount: const CoinTradeAmountInput.dirty(),
          buyAmount: const CoinTradeAmountInput.dirty(),
          maxMakerVolume: () => null,
          minTradingVolume: () => null,
          isLoadingMaxMakerVolume: true,
        ),
      ),
    );
    var revision = state.draftRevision;

    final maxMakerVolume = await _getMaxMakerVolumeWithFallback(event.sellCoin);
    if (!_isCurrentBaseCoinRequest(
      emit,
      baseCoinRequestGeneration,
      event.sellCoin,
    )) {
      return;
    }

    final minTradingVol = await _getMinTradingVolume(event.sellCoin);
    if (!_isCurrentBaseCoinRequest(
      emit,
      baseCoinRequestGeneration,
      event.sellCoin,
    )) {
      return;
    }

    final maxMakerVolumeDouble = maxMakerVolume?.toDouble() ?? 0;
    final newSellAmount = CoinTradeAmountInput.dirty(
      (state.maximumTradeVolume.value * maxMakerVolumeDouble).toString(),
    );

    // Calculate buy amount if applicable
    CoinTradeAmountInput newBuyAmount = const CoinTradeAmountInput.dirty();
    if (!identicalBuyAndSellCoins && state.buyCoin.value != null) {
      final double buyAmountValue = _getBuyAmountFromSellAmount(
        newSellAmount.value,
        state.priceFromUsdWithMargin,
      );
      newBuyAmount = CoinTradeAmountInput.dirty(buyAmountValue.toString());
    }

    emit(
      _draftChanged(
        state.copyWith(
          sellAmount: newSellAmount,
          buyAmount: newBuyAmount,
          maxMakerVolume: () => maxMakerVolume,
          minTradingVolume: () => minTradingVol,
          isLoadingMaxMakerVolume: false,
        ),
      ),
    );
    revision = state.draftRevision;

    await _autoActivateCoin(event.sellCoin);
    if (!_isCurrentDraft(emit, revision)) return;

    final snapshot = state;
    if (snapshot.buyCoin.value == null || snapshot.sellCoin.value == null) {
      return;
    }

    final preImage = await _getPreimageData(
      snapshot,
      isCurrent: () => _isCurrentDraft(emit, revision),
    );
    if (!_isCurrentDraft(emit, revision) || preImage == null) return;
    final error = _getPreImageError(preImage.error, snapshot);
    if (error != MarketMakerTradeFormError.none) {
      emit(state.copyWith(preImageError: () => error));
    }
  }

  Future<void> _onBuyCoinChanged(
    MarketMakerTradeFormBuyCoinChanged event,
    Emitter<MarketMakerTradeFormState> emit,
  ) async {
    final areBuyAndSellCoinsIdentical = event.buyCoin == state.sellCoin.value;
    if (areBuyAndSellCoinsIdentical) _baseCoinRequestGeneration++;

    var next = state.copyWith(
      buyCoin: CoinSelectInput.dirty(event.buyCoin, -1),
      sellCoin: areBuyAndSellCoinsIdentical
          ? const CoinSelectInput.dirty(null, -1)
          : state.sellCoin,
      sellAmount: areBuyAndSellCoinsIdentical
          ? const CoinTradeAmountInput.dirty()
          : state.sellAmount,
    );
    if (areBuyAndSellCoinsIdentical) {
      next = next.copyWith(
        maxMakerVolume: () => null,
        minTradingVolume: () => null,
      );
    }
    final newBuyAmount = _getBuyAmountFromSellAmount(
      next.sellAmount.value,
      next.priceFromUsdWithMargin,
    );
    next = next.copyWith(
      buyAmount: newBuyAmount > 0
          ? CoinTradeAmountInput.dirty(newBuyAmount.toString())
          : const CoinTradeAmountInput.dirty(),
    );
    emit(_draftChanged(next));
    final revision = state.draftRevision;

    await _autoActivateCoin(event.buyCoin);
    if (!_isCurrentDraft(emit, revision)) return;

    final snapshot = state;
    if (snapshot.buyCoin.value == null || snapshot.sellCoin.value == null) {
      return;
    }

    final preImage = await _getPreimageData(
      snapshot,
      isCurrent: () => _isCurrentDraft(emit, revision),
    );
    if (!_isCurrentDraft(emit, revision) || preImage == null) return;
    final preImageError = _getPreImageError(preImage.error, snapshot);
    if (preImageError != MarketMakerTradeFormError.none) {
      emit(state.copyWith(preImageError: () => preImageError));
    }
  }

  Future<void> _onTradeVolumeChanged(
    MarketMakerTradeFormTradeVolumeChanged event,
    Emitter<MarketMakerTradeFormState> emit,
  ) async {
    // Use cached maxMakerVolume instead of spendable balance, as only one
    // address in HD mode can be used for swaps, the "Swap address"
    final maxMakerVolumeDouble = state.maxMakerVolume?.toDouble() ?? 0;

    final maximumTradeVolume =
        double.tryParse(event.maximumTradeVolume.toString()) ?? 0.0;
    final newSellAmount = CoinTradeAmountInput.dirty(
      (maximumTradeVolume * maxMakerVolumeDouble).toString(),
      0,
      maxMakerVolumeDouble,
    );

    final newBuyAmount = _getBuyAmountFromSellAmount(
      newSellAmount.value,
      state.priceFromUsdWithMargin,
    );

    emit(
      _draftChanged(
        state.copyWith(
          sellAmount: newSellAmount,
          buyAmount: CoinTradeAmountInput.dirty(newBuyAmount.toString()),
          minimumTradeVolume: TradeVolumeInput.dirty(event.minimumTradeVolume),
          maximumTradeVolume: TradeVolumeInput.dirty(maximumTradeVolume),
        ),
      ),
    );
    final revision = state.draftRevision;

    final snapshot = state;
    if (snapshot.buyCoin.value == null || snapshot.sellCoin.value == null) {
      return;
    }

    final preImage = await _getPreimageData(
      snapshot,
      isCurrent: () => _isCurrentDraft(emit, revision),
    );
    if (!_isCurrentDraft(emit, revision) || preImage == null) return;
    final preImageError = _getPreImageError(preImage.error, snapshot);
    final newSellAmountFromPreImage = _getMaxSellAmountFromPreImage(
      preImage.error,
      newSellAmount,
      snapshot.sellCoin,
      snapshot.maxMakerVolume,
    );

    if (preImageError != MarketMakerTradeFormError.none) {
      final adjustedSellAmount = CoinTradeAmountInput.dirty(
        newSellAmountFromPreImage.toString(),
      );
      final adjustedBuyAmount = _getBuyAmountFromSellAmount(
        adjustedSellAmount.value,
        state.priceFromUsdWithMargin,
      );
      final changed = _draftChanged(
        state.copyWith(
          sellAmount: CoinTradeAmountInput.dirty(
            newSellAmountFromPreImage.toString(),
          ),
          buyAmount: CoinTradeAmountInput.dirty(adjustedBuyAmount.toString()),
        ),
      );
      emit(changed.copyWith(preImageError: () => preImageError));
    }
  }

  Future<void> _onSwapCoinsRequested(
    MarketMakerTradeFormSwapCoinsRequested event,
    Emitter<MarketMakerTradeFormState> emit,
  ) async {
    final baseCoinRequestGeneration = ++_baseCoinRequestGeneration;
    final sellCoin = state.buyCoin.value;
    final buyCoin = state.sellCoin.value;
    emit(
      _draftChanged(
        state.copyWith(
          sellCoin: CoinSelectInput.dirty(sellCoin),
          buyCoin: CoinSelectInput.dirty(buyCoin, -1, -1),
          sellAmount: const CoinTradeAmountInput.dirty(),
          buyAmount: const CoinTradeAmountInput.dirty('0', -1),
          maxMakerVolume: () => null,
          minTradingVolume: () => null,
          isLoadingMaxMakerVolume: true,
        ),
      ),
    );
    final maxMakerVolume = await _getMaxMakerVolumeWithFallback(sellCoin);
    if (!_isCurrentBaseCoinRequest(emit, baseCoinRequestGeneration, sellCoin)) {
      return;
    }

    final minTradingVol = await _getMinTradingVolume(sellCoin);
    if (!_isCurrentBaseCoinRequest(emit, baseCoinRequestGeneration, sellCoin)) {
      return;
    }

    final maxMakerVolumeDouble = maxMakerVolume?.toDouble() ?? 0;
    final maxVolumeValue = state.maximumTradeVolume.value;

    final newSellAmount = maxVolumeValue * maxMakerVolumeDouble;

    final newBuyAmount = state.buyCoin.value != null
        ? _getBuyAmountFromSellAmount(
            newSellAmount.toString(),
            state.priceFromUsdWithMargin,
          )
        : 0.0;

    emit(
      _draftChanged(
        state.copyWith(
          sellAmount: CoinTradeAmountInput.dirty(newSellAmount.toString()),
          buyAmount: CoinTradeAmountInput.dirty(newBuyAmount.toString()),
          maxMakerVolume: () => maxMakerVolume,
          minTradingVolume: () => minTradingVol,
          isLoadingMaxMakerVolume: false,
        ),
      ),
    );
  }

  void _onTradeMarginChanged(
    MarketMakerTradeFormTradeMarginChanged event,
    Emitter<MarketMakerTradeFormState> emit,
  ) {
    var next = state.copyWith(
      tradeMargin: TradeMarginInput.dirty(event.tradeMargin),
    );

    if (next.buyCoin.value != null) {
      final newBuyAmount = _getBuyAmountFromSellAmount(
        next.sellAmount.value,
        next.priceFromUsdWithMargin,
      );
      next = next.copyWith(
        buyAmount: CoinTradeAmountInput.dirty(newBuyAmount.toString()),
      );
    }
    emit(_draftChanged(next));
  }

  void _onUpdateIntervalChanged(
    MarketMakerTradeFormUpdateIntervalChanged event,
    Emitter<MarketMakerTradeFormState> emit,
  ) {
    _baseCoinRequestGeneration++;
    emit(
      _draftChanged(
        state.copyWith(
          updateInterval: UpdateIntervalInput.dirty(event.updateInterval),
        ),
      ),
    );
  }

  void _onClearForm(
    MarketMakerTradeFormClearRequested event,
    Emitter<MarketMakerTradeFormState> emit,
  ) {
    emit(
      _draftChanged(
        MarketMakerTradeFormState.initial(),
        status: MarketMakerTradeFormStatus.initial,
      ),
    );
  }

  Future<void> _onEditOrder(
    MarketMakerTradeFormEditOrderRequested event,
    Emitter<MarketMakerTradeFormState> emit,
  ) async {
    final baseCoinRequestGeneration = ++_baseCoinRequestGeneration;
    final sellCoin = CoinSelectInput.dirty(
      _coinsRepo.getCoin(event.tradePair.config.baseCoinId),
    );
    final buyCoin = CoinSelectInput.dirty(
      _coinsRepo.getCoin(event.tradePair.config.relCoinId),
    );
    final maxTradeVolume = event.tradePair.config.maxVolume?.value ?? 0.9;
    final minTradeVolume = event.tradePair.config.minVolume?.value ?? 0.01;
    final tradeMargin = TradeMarginInput.dirty(
      event.tradePair.config.margin.toStringAsFixed(2),
    );
    final updateInterval = UpdateIntervalInput.dirty(
      event.tradePair.config.updateInterval.seconds.toString(),
    );

    emit(
      _draftChanged(
        MarketMakerTradeFormState.initial().copyWith(
          sellCoin: sellCoin,
          minimumTradeVolume: TradeVolumeInput.dirty(minTradeVolume),
          maximumTradeVolume: TradeVolumeInput.dirty(maxTradeVolume),
          buyCoin: buyCoin,
          tradeMargin: tradeMargin,
          updateInterval: updateInterval,
          isLoadingMaxMakerVolume: true,
          walletSession: () => event.walletSession,
          originalConfig: () => event.tradePair.config,
        ),
      ),
    );
    final maxMakerVolume = await _getMaxMakerVolumeWithFallback(sellCoin.value);
    if (!_isCurrentBaseCoinRequest(
      emit,
      baseCoinRequestGeneration,
      sellCoin.value,
      walletSession: event.walletSession,
    )) {
      return;
    }

    final minTradingVol = await _getMinTradingVolume(sellCoin.value);
    if (!_isCurrentBaseCoinRequest(
      emit,
      baseCoinRequestGeneration,
      sellCoin.value,
      walletSession: event.walletSession,
    )) {
      return;
    }

    final maxMakerVolumeDouble = maxMakerVolume?.toDouble() ?? 0;
    final sellAmountFromVolume = maxTradeVolume * maxMakerVolumeDouble;

    final sellAmount = CoinTradeAmountInput.dirty(
      sellAmountFromVolume.toString(),
      0,
      maxMakerVolumeDouble,
    );
    var resolved = state.copyWith(
      sellAmount: sellAmount,
      maxMakerVolume: () => maxMakerVolume,
      minTradingVolume: () => minTradingVol,
      isLoadingMaxMakerVolume: false,
    );

    final newBuyAmount = _getBuyAmountFromSellAmount(
      sellAmount.value,
      resolved.priceFromUsdWithMargin,
    );
    resolved = resolved.copyWith(
      buyAmount: CoinTradeAmountInput.dirty(newBuyAmount.toString()),
    );
    emit(_draftChanged(resolved));
  }

  void _onOrderbookSelected(
    MarketMakerTradeFormAskOrderbookSelected event,
    Emitter<MarketMakerTradeFormState> emit,
  ) {
    final askPrice = event.order.price.toDouble();
    final coinPrice = state.priceFromUsd ?? state.priceFromAmount;
    final numerator = (askPrice - coinPrice) * 100;
    final denomiator = (askPrice + coinPrice) / 2;
    final margin = numerator / denomiator;
    if (!margin.isFinite) return;

    emit(
      _draftChanged(
        state.copyWith(
          tradeMargin: TradeMarginInput.dirty(margin.toStringAsFixed(2)),
        ),
      ),
    );
  }

  Future<void> _onPreviewConfirmation(
    MarketMakerConfirmationPreviewRequested event,
    Emitter<MarketMakerTradeFormState> emit,
  ) async {
    final requestedSession = event.walletSession;
    final current = state;
    if (event.draftRevision != current.draftRevision ||
        requestedSession == null ||
        (current.walletSession != null &&
            current.walletSession != requestedSession)) {
      return;
    }

    if (current.isLoadingMaxMakerVolume) return;

    if (!current.isValid ||
        current.sellCoin.value == null ||
        current.buyCoin.value == null) {
      emit(
        current.copyWith(
          stage: MarketMakerTradeFormStage.initial,
          status: MarketMakerTradeFormStatus.error,
          preImageError: () =>
              MarketMakerTradeFormError.insufficientBalanceBase,
          tradePreImage: () => null,
          rawErrorMessage: () => null,
          previewRevision: () => null,
          previewWalletSession: () => null,
        ),
      );
      return;
    }

    final revision = current.draftRevision;
    emit(
      current.copyWith(
        stage: MarketMakerTradeFormStage.confirmationRequired,
        status: MarketMakerTradeFormStatus.loading,
        preImageError: () => null,
        tradePreImage: () => null,
        rawErrorMessage: () => null,
        walletSession: () => requestedSession,
        previewRevision: () => null,
        previewWalletSession: () => null,
      ),
    );

    final snapshot = state;
    final preImage = await _getPreimageData(
      snapshot,
      isCurrent: () => _isCurrentDraft(
        emit,
        revision,
        walletSession: requestedSession,
        requireConfirmationStage: true,
      ),
    );
    if (!_isCurrentDraft(
          emit,
          revision,
          walletSession: requestedSession,
          requireConfirmationStage: true,
        ) ||
        preImage == null) {
      return;
    }
    final preImageError = _getPreImageError(preImage.error, snapshot);
    if (preImage.error is TradePreimageTransportError) {
      emit(
        state.copyWith(
          status: MarketMakerTradeFormStatus.error,
          tradePreImage: () => null,
          rawErrorMessage: () => LocaleKeys.somethingWrong.tr(),
          previewRevision: () => null,
          previewWalletSession: () => null,
        ),
      );
      return;
    }

    if (preImageError == MarketMakerTradeFormError.none &&
        preImage.data != null) {
      emit(
        state.copyWith(
          tradePreImage: () => preImage.data,
          rawErrorMessage: () => null,
          status: MarketMakerTradeFormStatus.success,
          previewRevision: () => revision,
          previewWalletSession: () => requestedSession,
        ),
      );
      return;
    }

    final isInsufficientBaseBalance =
        preImageError == MarketMakerTradeFormError.insufficientBalanceBase;
    if (isInsufficientBaseBalance) {
      final previousSellAmount =
          double.tryParse(snapshot.sellAmount.value) ?? 0;
      final newSellAmount = _getMaxSellAmountFromPreImage(
        preImage.error,
        snapshot.sellAmount,
        snapshot.sellCoin,
        snapshot.maxMakerVolume,
      );
      if (newSellAmount > 0 && newSellAmount < previousSellAmount) {
        final adjustedSellAmount = CoinTradeAmountInput.dirty(
          newSellAmount.toString(),
        );
        final adjustedBuyAmount = _getBuyAmountFromSellAmount(
          adjustedSellAmount.value,
          state.priceFromUsdWithMargin,
        );
        final adjusted =
            _draftChanged(
              state.copyWith(
                sellAmount: adjustedSellAmount,
                buyAmount: CoinTradeAmountInput.dirty(
                  adjustedBuyAmount.toString(),
                ),
              ),
            ).copyWith(
              stage: MarketMakerTradeFormStage.confirmationRequired,
              status: MarketMakerTradeFormStatus.loading,
              walletSession: () => requestedSession,
            );
        emit(adjusted);
        add(
          MarketMakerConfirmationPreviewRequested(
            walletSession: requestedSession,
            draftRevision: adjusted.draftRevision,
          ),
        );
        return;
      }
    }

    emit(
      state.copyWith(
        tradePreImage: () => null,
        preImageError: () => preImageError == MarketMakerTradeFormError.none
            ? null
            : preImageError,
        rawErrorMessage: () => preImageError == MarketMakerTradeFormError.none
            ? LocaleKeys.somethingWrong.tr()
            : null,
        status: MarketMakerTradeFormStatus.error,
        previewRevision: () => null,
        previewWalletSession: () => null,
      ),
    );
  }

  void _onPreviewConfirmationCancelled(
    MarketMakerConfirmationPreviewCancelRequested event,
    Emitter<MarketMakerTradeFormState> emit,
  ) {
    emit(
      state.copyWith(
        stage: MarketMakerTradeFormStage.initial,
        status: MarketMakerTradeFormStatus.success,
        preImageError: () => null,
        tradePreImage: () => null,
        rawErrorMessage: () => null,
        previewRevision: () => null,
        previewWalletSession: () => null,
      ),
    );
  }

  double _getBuyAmountFromSellAmount(
    String sellAmount,
    double? priceFromUsdWithMargin,
  ) {
    final double sellAmountValue = double.tryParse(sellAmount) ?? 0;

    if (priceFromUsdWithMargin != null) {
      final currentPrice = priceFromUsdWithMargin;
      final double newBuyAmount = sellAmountValue * currentPrice;
      return newBuyAmount;
    }

    return 0;
  }

  /// Check for preimage errors, return the matching error state and include the
  /// new sell amount if the error is due to insufficient balance.
  double _getMaxSellAmountFromPreImage(
    BaseError? preImageError,
    CoinTradeAmountInput sellAmount,
    CoinSelectInput sellCoin,
    Rational? maxMakerVolume,
  ) {
    if (preImageError is TradePreimageNotSufficientBalanceError) {
      final sellAmountValue = double.tryParse(sellAmount.value) ?? 0;
      if (sellCoin.value?.abbr != preImageError.coin) {
        return sellAmountValue;
      }

      final requiredAmount = double.tryParse(preImageError.required) ?? 0;
      final maxMakerVolumeValue = maxMakerVolume?.toDouble() ?? 0;
      final newSellAmount =
          sellAmountValue - (requiredAmount - maxMakerVolumeValue);

      // Clamp to minimum of 0 to prevent negative sell amounts
      return newSellAmount.clamp(0, double.infinity);
    }

    return sellAmount.valueAsRational.toDouble();
  }

  /// Check for preimage errors, return the matching error state and include the
  /// new sell amount if the error is due to insufficient balance.
  MarketMakerTradeFormError _getPreImageError(
    BaseError? preImageError,
    MarketMakerTradeFormState formStateSnapshot,
  ) {
    if (preImageError is TradePreimageNotSufficientBalanceError) {
      if (formStateSnapshot.sellCoin.value?.abbr != preImageError.coin) {
        return MarketMakerTradeFormError.insufficientBalanceRel;
      }

      return MarketMakerTradeFormError.insufficientBalanceBase;
    } else if (preImageError
        is TradePreimageNotSufficientBaseCoinBalanceError) {
      // if Rel coin has a parent, e.g. 1INCH-AVX-20, then the error is
      // due to insufficient balance of the parent coin
      return MarketMakerTradeFormError.insufficientBalanceRelParent;
    } else if (preImageError is TradePreimageVolumeTooLowError) {
      // Explicit VolumeTooLow should map to insufficient trade amount
      return MarketMakerTradeFormError.insufficientTradeAmount;
    } else if (preImageError is TradePreimageTransportError) {
      // Transport is a generic connectivity/transport layer issue; don't
      // mislabel it as a min-volume problem
      return MarketMakerTradeFormError.none;
    } else {
      return MarketMakerTradeFormError.none;
    }
  }

  Future<DataFromService<TradePreimage, BaseError>?> _getPreimageData(
    MarketMakerTradeFormState state, {
    required bool Function() isCurrent,
  }) async {
    try {
      final base = state.sellCoin.value?.abbr;
      final rel = state.buyCoin.value?.abbr;
      final coinPrice = state.priceFromUsd ?? state.priceFromAmount;
      final price = Rational.parse(coinPrice.toString());
      if (state.sellAmount.value.isEmpty) {
        throw ArgumentError('Sell amount must be set');
      }
      final Rational volume = Rational.parse(state.sellAmount.value);

      if (base == null || rel == null) {
        throw ArgumentError('Base and rel coins must be set');
      }

      // initial attempt
      DataFromService<TradePreimage, BaseError> preimageData =
          await _dexRepository.getTradePreimage(
            base,
            rel,
            price,
            'setprice',
            volume,
          );
      if (!isCurrent()) return null;

      int attemptsLeft = 10;
      while (preimageData.error is TradePreimageTransportError &&
          attemptsLeft > 0) {
        _log.warning(
          'market_maker_preimage_transport_retry '
          'attempt=${11 - attemptsLeft}',
        );
        await Future<void>.delayed(const Duration(seconds: 1));
        if (!isCurrent()) return null;
        preimageData = await _dexRepository.getTradePreimage(
          base,
          rel,
          price,
          'setprice',
          volume,
        );
        if (!isCurrent()) return null;
        attemptsLeft--;
      }

      return preimageData;
    } on Object {
      if (!isCurrent()) return null;
      _log.warning('market_maker_preimage_failed');
      return DataFromService(
        error: TradePreimageTransportError(
          error: LocaleKeys.somethingWrong.tr(),
        ),
      );
    }
  }

  /// Activate the coin if it is not active. If the coin is a child coin,
  /// activate the parent coin as well.
  /// Throws an error if the coin cannot be activated.
  Future<void> _autoActivateCoin(Coin? coin) async {
    if (coin == null) {
      return;
    }

    if (!coin.isActive) {
      await _coinsRepo.activateCoinsSync([coin]);
    } else {
      final Coin? parentCoin = coin.parentCoin;
      if (parentCoin != null && !parentCoin.isActive) {
        await _coinsRepo.activateCoinsSync([parentCoin]);
      }
    }
  }

  /// Fetches the max maker volume for a coin with automatic fallback.
  ///
  /// First attempts to fetch from the DEX API via [getMaxMakerVolume].
  /// If that fails or returns null, falls back to [_getSwapAddressBalance].
  ///
  /// Returns null if the coin is null or all attempts fail.
  Future<Rational?> _getMaxMakerVolumeWithFallback(Coin? coin) async {
    if (coin == null) {
      return null;
    }

    try {
      // Fetch max maker volume from DEX API
      final maxMakerVolume = await _dexRepository.getMaxMakerVolume(coin.abbr);

      // Fallback to swap address balance if RPC fails
      if (maxMakerVolume == null) {
        return await _getSwapAddressBalance(coin);
      }

      return maxMakerVolume;
    } on Object {
      _log.warning('market_maker_max_volume_failed; using_balance_fallback');
      // Fallback to swap address balance on error
      return await _getSwapAddressBalance(coin);
    }
  }

  Future<Rational?> _getMinTradingVolume(Coin? coin) async {
    if (coin == null) return null;
    try {
      return await _dexRepository.getMinTradingVolume(coin.abbr);
    } on Object {
      _log.warning('market_maker_min_trading_volume_failed');
      return null;
    }
  }

  /// Get the swap address balance as a fallback when getMaxMakerVolume fails.
  /// This method retrieves the spendable balance from the address marked as
  /// active for swaps (derivationPath ending with '/0' or null).
  Future<Rational?> _getSwapAddressBalance(Coin coin) async {
    try {
      final asset = _sdk.getSdkAsset(coin.abbr);
      final pubkeys = _sdk.pubkeys.lastKnown(asset.id);

      if (pubkeys == null) {
        return null;
      }

      // Find the swap address (isActiveForSwap = true)
      final swapAddress = pubkeys.keys.firstWhere(
        (pubkey) => pubkey.isActiveForSwap,
        orElse: () => pubkeys.keys.first,
      );

      final spendable = swapAddress.balance.spendable;
      return Rational.parse(spendable.toString());
    } on Object {
      _log.warning('market_maker_swap_balance_fallback_failed');
      return null;
    }
  }
}

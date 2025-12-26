import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:formz/formz.dart';
import 'package:get_it/get_it.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:logging/logging.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/bloc/coins_bloc/asset_coin_extension.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/dex_repository.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_order_list/trade_pair.dart';
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
    on<MarketMakerTradeFormSellCoinChanged>(_onSellCoinChanged);
    on<MarketMakerTradeFormBuyCoinChanged>(_onBuyCoinChanged);
    on<MarketMakerTradeFormTradeVolumeChanged>(_onTradeVolumeChanged);
    // Prevent/reduce spamming by only processing one event at a time
    on<MarketMakerTradeFormSwapCoinsRequested>(
      _onSwapCoinsRequested,
      transformer: droppable(),
    );
    on<MarketMakerTradeFormTradeMarginChanged>(_onTradeMarginChanged);
    on<MarketMakerTradeFormUpdateIntervalChanged>(_onUpdateIntervalChanged);
    on<MarketMakerTradeFormClearRequested>(_onClearForm);
    on<MarketMakerTradeFormEditOrderRequested>(_onEditOrder);
    on<MarketMakerTradeFormAskOrderbookSelected>(_onOrderbookSelected);
    on<MarketMakerConfirmationPreviewRequested>(_onPreviewConfirmation);
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

  Future<void> _onSellCoinChanged(
    MarketMakerTradeFormSellCoinChanged event,
    Emitter<MarketMakerTradeFormState> emit,
  ) async {
    final identicalBuyAndSellCoins = state.buyCoin.value == event.sellCoin;
    final sellCoin = event.sellCoin?.id;
    double sellCoinBalance = 0;

    if (sellCoin != null) {
      // Use repo guard to avoid SDK calls if inactive
      sellCoinBalance =
          (await _coinsRepo.tryGetBalanceInfo(sellCoin)).spendable.toDouble();
    }

    // Emit immediately with new coin selection for fast UI update
    emit(
      state.copyWith(
        sellCoin: CoinSelectInput.dirty(event.sellCoin),
        buyCoin: identicalBuyAndSellCoins
            ? const CoinSelectInput.dirty(null, -1)
            : state.buyCoin,
        status: MarketMakerTradeFormStatus.success,
        isLoadingMaxMakerVolume: true,
      ),
    );

    // Fetch max maker volume with fallback to swap address balance
    final maxMakerVolume = await _getMaxMakerVolumeWithFallback(event.sellCoin);
    // Fetch coin-specific minimum trading volume
    final minTradingVol = event.sellCoin == null
        ? null
        : await _dexRepository.getMinTradingVolume(event.sellCoin!.abbr);

    final maxMakerVolumeDouble = maxMakerVolume?.toDouble() ?? 0;
    final newSellAmount = CoinTradeAmountInput.dirty(
      (state.maximumTradeVolume.value * maxMakerVolumeDouble).toString(),
    );

    // Calculate buy amount if applicable
    CoinTradeAmountInput? newBuyAmount;
    if (!identicalBuyAndSellCoins && state.buyCoin.value != null) {
      final double buyAmountValue = _getBuyAmountFromSellAmount(
        newSellAmount.value,
        state.priceFromUsdWithMargin,
      );
      newBuyAmount = CoinTradeAmountInput.dirty(buyAmountValue.toString());
    }

    // Emit with calculated amounts after fetching max maker volume
    emit(
      state.copyWith(
        sellAmount: newSellAmount,
        buyAmount: newBuyAmount,
        maxMakerVolume: maxMakerVolume,
        minTradingVolume: minTradingVol,
        isLoadingMaxMakerVolume: false,
      ),
    );

    // Activate coin before checking preimage
    // TODO: consider removing this, as only enabled coins with a balance are
    // displayed in the sell coins dropdown
    await _autoActivateCoin(event.sellCoin);

    // Check for preimage errors using the current state asynchronously
    if (state.buyCoin.value != null) {
      final preImage = await _getPreimageData(state);
      final error = await _getPreImageError(preImage.error, state);
      if (error != MarketMakerTradeFormError.none) {
        emit(state.copyWith(preImageError: error));
      }
    }
  }

  Future<void> _onBuyCoinChanged(
    MarketMakerTradeFormBuyCoinChanged event,
    Emitter<MarketMakerTradeFormState> emit,
  ) async {
    // Update the buy and sell coins first before calculating the buy amount
    // since the priceFromUsdWithMargin is dependent on the buy coin.
    // An alternative approach would be to calculate the new price with margin
    // here and pass that to the function, but that would require a lot of
    // code duplication and would be harder to maintain.
    final areBuyAndSellCoinsIdentical = event.buyCoin == state.sellCoin.value;

    // Emit immediately with new coin selection for fast UI update
    emit(
      state.copyWith(
        buyCoin: CoinSelectInput.dirty(event.buyCoin, -1),
        sellCoin: areBuyAndSellCoinsIdentical
            ? const CoinSelectInput.dirty(null, -1)
            : state.sellCoin,
        status: MarketMakerTradeFormStatus.success,
      ),
    );

    await _autoActivateCoin(event.buyCoin);

    // Buy coin does not have to have a balance, so set the minimum balance to
    // -1 to avoid the insufficient balance error
    final newBuyAmount = _getBuyAmountFromSellAmount(
      state.sellAmount.value,
      state.priceFromUsdWithMargin,
    );

    // Emit updated buy amount
    emit(
      state.copyWith(
        buyAmount: newBuyAmount > 0
            ? CoinTradeAmountInput.dirty(newBuyAmount.toString())
            : const CoinTradeAmountInput.dirty(),
        status: MarketMakerTradeFormStatus.success,
      ),
    );

    // Check for preimage errors asynchronously
    final preImage = await _getPreimageData(state);
    final preImageError = await _getPreImageError(preImage.error, state);

    if (preImageError != MarketMakerTradeFormError.none) {
      emit(state.copyWith(preImageError: preImageError));
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

    // Emit immediately with new volume values for fast UI update
    emit(
      state.copyWith(
        sellAmount: newSellAmount,
        buyAmount: CoinTradeAmountInput.dirty(newBuyAmount.toString()),
        minimumTradeVolume: TradeVolumeInput.dirty(event.minimumTradeVolume),
        maximumTradeVolume: TradeVolumeInput.dirty(maximumTradeVolume),
      ),
    );

    // Trade preimage requires both buy and sell coins to be set, so no use in
    // calling it before both are set. _getPreimageData checks this internally,
    // but emits unnecessary failure states.
    if (state.buyCoin.value == null || state.sellCoin.value == null) {
      return;
    }

    final preImage = await _getPreimageData(state);
    final preImageError = await _getPreImageError(preImage.error, state);
    final newSellAmountFromPreImage = await _getMaxSellAmountFromPreImage(
      preImage.error,
      newSellAmount,
      state.sellCoin,
    );

    // Emit error and adjusted sell amount if preimage validation fails
    if (preImageError != MarketMakerTradeFormError.none) {
      emit(
        state.copyWith(
          preImageError: preImageError,
          sellAmount: CoinTradeAmountInput.dirty(
            newSellAmountFromPreImage.toString(),
          ),
        ),
      );
    }
  }

  Future<void> _onSwapCoinsRequested(
    MarketMakerTradeFormSwapCoinsRequested event,
    Emitter<MarketMakerTradeFormState> emit,
  ) async {
    // Emit immediately with swapped coins for fast UI update
    final sellCoin = state.buyCoin.value;
    final buyCoin = state.sellCoin.value;
    emit(
      state.copyWith(
        sellCoin: CoinSelectInput.dirty(sellCoin),
        buyCoin: CoinSelectInput.dirty(buyCoin, -1, -1),
        buyAmount: const CoinTradeAmountInput.dirty('0', -1),
        isLoadingMaxMakerVolume: true,
      ),
    );

    // Fetch max maker volume with fallback to swap address balance
    final maxMakerVolume = await _getMaxMakerVolumeWithFallback(sellCoin);
    // Fetch coin-specific minimum trading volume for new base coin
    final minTradingVol = sellCoin == null
        ? null
        : await _dexRepository.getMinTradingVolume(sellCoin.abbr);

    final maxMakerVolumeDouble = maxMakerVolume?.toDouble() ?? 0;
    final maxVolumeValue =
        double.tryParse(state.maximumTradeVolume.value.toString()) ?? 0.0;

    final newSellAmount = maxVolumeValue * maxMakerVolumeDouble;

    // Calculate buy amount if applicable
    final newBuyAmount = state.buyCoin.value != null
        ? _getBuyAmountFromSellAmount(
            newSellAmount.toString(),
            state.priceFromUsdWithMargin,
          )
        : 0.0;

    // Emit with calculated amounts after fetching max maker volume
    // Always clear loading flag, even on error
    emit(
      state.copyWith(
        sellAmount: CoinTradeAmountInput.dirty(newSellAmount.toString()),
        buyAmount: CoinTradeAmountInput.dirty(newBuyAmount.toString()),
        maxMakerVolume: maxMakerVolume,
        minTradingVolume: minTradingVol,
        isLoadingMaxMakerVolume: false,
      ),
    );
  }

  Future<void> _onTradeMarginChanged(
    MarketMakerTradeFormTradeMarginChanged event,
    Emitter<MarketMakerTradeFormState> emit,
  ) async {
    emit(
      state.copyWith(tradeMargin: TradeMarginInput.dirty(event.tradeMargin)),
    );

    if (state.buyCoin.value != null) {
      final newBuyAmount = _getBuyAmountFromSellAmount(
        state.sellAmount.value,
        state.priceFromUsdWithMargin,
      );
      emit(
        state.copyWith(
          buyAmount: CoinTradeAmountInput.dirty(newBuyAmount.toString()),
        ),
      );
    }
  }

  Future<void> _onUpdateIntervalChanged(
    MarketMakerTradeFormUpdateIntervalChanged event,
    Emitter<MarketMakerTradeFormState> emit,
  ) async {
    emit(
      state.copyWith(
        updateInterval: UpdateIntervalInput.dirty(event.updateInterval),
      ),
    );
  }

  Future<void> _onClearForm(
    MarketMakerTradeFormClearRequested event,
    Emitter<MarketMakerTradeFormState> emit,
  ) async {
    emit(MarketMakerTradeFormState.initial());
  }

  Future<void> _onEditOrder(
    MarketMakerTradeFormEditOrderRequested event,
    Emitter<MarketMakerTradeFormState> emit,
  ) async {
    final sellCoin = CoinSelectInput.dirty(
      _coinsRepo.getCoin(event.tradePair.config.baseCoinId),
    );
    final buyCoin = CoinSelectInput.dirty(
      _coinsRepo.getCoin(event.tradePair.config.relCoinId),
    );
    final maxTradeVolume = event.tradePair.config.maxVolume?.value ?? 0.9;
    final minTradeVolume = event.tradePair.config.minVolume?.value ?? 0.01;

    // Fetch max maker volume with fallback to swap address balance
    final maxMakerVolume = await _getMaxMakerVolumeWithFallback(sellCoin.value);
    // Fetch coin-specific minimum trading volume for base coin
    final minTradingVol = sellCoin.value == null
        ? null
        : await _dexRepository.getMinTradingVolume(sellCoin.value!.abbr);

    final maxMakerVolumeDouble = maxMakerVolume?.toDouble() ?? 0;
    final sellAmountFromVolume = maxTradeVolume * maxMakerVolumeDouble;

    final sellAmount = CoinTradeAmountInput.dirty(
      sellAmountFromVolume.toString(),
      0,
      maxMakerVolumeDouble,
    );
    final tradeMargin = TradeMarginInput.dirty(
      event.tradePair.config.margin.toStringAsFixed(2),
    );
    final updateInterval = UpdateIntervalInput.dirty(
      event.tradePair.config.updateInterval.seconds.toString(),
    );

    emit(
      MarketMakerTradeFormState.initial().copyWith(
        sellCoin: sellCoin,
        sellAmount: sellAmount,
        minimumTradeVolume: TradeVolumeInput.dirty(minTradeVolume),
        maximumTradeVolume: TradeVolumeInput.dirty(maxTradeVolume),
        buyCoin: buyCoin,
        buyAmount: const CoinTradeAmountInput.dirty('0'),
        tradeMargin: tradeMargin,
        updateInterval: updateInterval,
        maxMakerVolume: maxMakerVolume,
        minTradingVolume: minTradingVol,
      ),
    );

    final newBuyAmount = _getBuyAmountFromSellAmount(
      sellAmount.value,
      state.priceFromUsdWithMargin,
    );
    emit(
      state.copyWith(
        buyAmount: CoinTradeAmountInput.dirty(newBuyAmount.toString()),
      ),
    );
  }

  Future<void> _onOrderbookSelected(
    MarketMakerTradeFormAskOrderbookSelected event,
    Emitter<MarketMakerTradeFormState> emit,
  ) async {
    final askPrice = event.order.price.toDouble();
    final coinPrice = state.priceFromUsd ?? state.priceFromAmount;
    final numerator = (askPrice - coinPrice) * 100;
    final denomiator = (askPrice + coinPrice) / 2;
    final margin = numerator / denomiator;

    emit(
      state.copyWith(
        tradeMargin: TradeMarginInput.dirty(margin.toStringAsFixed(2)),
      ),
    );
  }

  Future<void> _onPreviewConfirmation(
    MarketMakerConfirmationPreviewRequested event,
    Emitter<MarketMakerTradeFormState> emit,
  ) async {
    emit(
      state.copyWith(
        stage: MarketMakerTradeFormStage.confirmationRequired,
        status: MarketMakerTradeFormStatus.loading,
      ),
    );

    if (state.sellCoin.value == null || state.buyCoin.value == null) {
      emit(
        state.copyWith(
          stage: MarketMakerTradeFormStage.initial,
          status: MarketMakerTradeFormStatus.error,
          preImageError: MarketMakerTradeFormError.insufficientBalanceBase,
        ),
      );
      return;
    }

    final preImage = await _getPreimageData(state);
    final preImageError = await _getPreImageError(preImage.error, state);
    if (preImage.error is TradePreimageTransportError) {
      // After retries, still transport error -> show raw error
      emit(
        state.copyWith(
          status: MarketMakerTradeFormStatus.error,
          rawErrorMessage: (preImage.error as TradePreimageTransportError)
              .message,
        ),
      );
      return;
    }

    if (preImageError == MarketMakerTradeFormError.none) {
      return emit(
        state.copyWith(
          tradePreImage: preImage.data,
          rawErrorMessage: null,
          status: MarketMakerTradeFormStatus.success,
        ),
      );
    }

    double newSellAmount = state.sellAmount.valueAsRational.toDouble();
    final bool isInsufficientBaseBalance =
        preImageError == MarketMakerTradeFormError.insufficientBalanceBase;
    if (isInsufficientBaseBalance) {
      newSellAmount = await _getMaxSellAmountFromPreImage(
        preImage.error,
        state.sellAmount,
        state.sellCoin,
      );
    }

    emit(
      state.copyWith(
        tradePreImage: preImage.data,
        preImageError: isInsufficientBaseBalance ? null : preImageError,
        rawErrorMessage: null,
        sellAmount: isInsufficientBaseBalance
            ? CoinTradeAmountInput.dirty(newSellAmount.toString())
            : state.sellAmount,
        status: isInsufficientBaseBalance
            ? MarketMakerTradeFormStatus.success
            : MarketMakerTradeFormStatus.error,
      ),
    );
    return;
  }

  Future<void> _onPreviewConfirmationCancelled(
    MarketMakerConfirmationPreviewCancelRequested event,
    Emitter<MarketMakerTradeFormState> emit,
  ) async {
    emit(
      state.copyWith(
        stage: MarketMakerTradeFormStage.initial,
        status: MarketMakerTradeFormStatus.success,
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
  Future<double> _getMaxSellAmountFromPreImage(
    BaseError? preImageError,
    CoinTradeAmountInput sellAmount,
    CoinSelectInput sellCoin,
  ) async {
    if (preImageError is TradePreimageNotSufficientBalanceError) {
      final sellAmountValue = double.tryParse(sellAmount.value) ?? 0;
      if (sellCoin.value?.abbr != preImageError.coin) {
        return sellAmountValue;
      }

      final requiredAmount = double.tryParse(preImageError.required) ?? 0;
      final maxMakerVolume = state.maxMakerVolume?.toDouble() ?? 0;
      final newSellAmount = sellAmountValue - (requiredAmount - maxMakerVolume);

      // Clamp to minimum of 0 to prevent negative sell amounts
      return newSellAmount.clamp(0, double.infinity);
    }

    return sellAmount.valueAsRational.toDouble();
  }

  /// Check for preimage errors, return the matching error state and include the
  /// new sell amount if the error is due to insufficient balance.
  Future<MarketMakerTradeFormError> _getPreImageError(
    BaseError? preImageError,
    MarketMakerTradeFormState formStateSnapshot,
  ) async {
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

  Future<DataFromService<TradePreimage, BaseError>> _getPreimageData(
    MarketMakerTradeFormState state,
  ) async {
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

      // If transport error, retry every second up to 10 seconds while UI
      // remains in loading state.
      int attemptsLeft = 10;
      while (preimageData.error is TradePreimageTransportError &&
          attemptsLeft > 0) {
        _log.warning(
          'trade_preimage transport error for $base/$rel, retrying... '
          '(${11 - attemptsLeft}/10)',
        );
        await Future<void>.delayed(const Duration(seconds: 1));
        preimageData = await _dexRepository.getTradePreimage(
          base,
          rel,
          price,
          'setprice',
          volume,
        );
        attemptsLeft--;
      }

      return preimageData;
    } catch (e, s) {
      _log.shout(
        'Failed to get preimage data for ${state.sellCoin.value?.abbr}/${state.buyCoin.value?.abbr}',
        e,
        s,
      );
      return DataFromService(
        error: TradePreimagePriceTooLowError(
          price: '0',
          threshold: '0',
          error: e.toString(),
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

    // Gate auto-activations until initial activation completes
    await _coinsRepo.waitForInitialActivationToComplete(
      timeout: const Duration(seconds: 30),
    );

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
    } catch (e, s) {
      _log.warning(
        'Failed to get max maker volume for ${coin.abbr}, falling back to swap address balance',
        e,
        s,
      );
      // Fallback to swap address balance on error
      return await _getSwapAddressBalance(coin);
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
    } catch (e, s) {
      _log.shout('Failed to get swap address balance for ${coin.abbr}', e, s);
      return null;
    }
  }
}

import 'package:easy_localization/easy_localization.dart';
import 'package:get_it/get_it.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/bloc/coins_bloc/asset_coin_extension.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/dex_repository.dart';
import 'package:web_dex/bloc/taker_form/taker_bloc.dart';
import 'package:web_dex/bloc/taker_form/taker_event.dart';
import 'package:web_dex/bloc/taker_form/taker_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:web_dex/mm2/mm2_api/rpc/best_orders/best_orders.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trade_preimage/trade_preimage_errors.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/data_from_service.dart';
import 'package:web_dex/model/dex_form_error.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/shared/utils/kdf_error_display.dart';
import 'package:web_dex/model/trade_preimage.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/dex/dex_helpers.dart';
import 'package:web_dex/views/dex/simple/form/error_list/dex_form_error_with_action.dart';

class TakerValidator {
  TakerValidator({
    required TakerBloc bloc,
    required CoinsRepo coinsRepo,
    required DexRepository dexRepo,
    required KomodoDefiSdk sdk,
  }) : _bloc = bloc,
       _coinsRepo = coinsRepo,
       _dexRepo = dexRepo,
       _sdk = sdk,
       add = bloc.add;

  final TakerBloc _bloc;
  final CoinsRepo _coinsRepo;
  final DexRepository _dexRepo;
  final KomodoDefiSdk _sdk;

  final Function(TakerEvent) add;
  TakerState get state => _bloc.state;

  Future<bool> validate() async {
    final bool isFormValid = await validateForm();
    if (!isFormValid) return false;

    final bool tradingWithSelf = await _checkTradeWithSelf();
    if (tradingWithSelf) return false;

    final bool isPreimageValid = await _validatePreimage();
    if (!isPreimageValid) return false;

    return true;
  }

  Future<bool> _validatePreimage() async {
    add(TakerClearErrors());

    final preimageData = await _getPreimageData();
    final preimageError = _parsePreimageError(preimageData);

    if (preimageError != null) {
      add(TakerAddError(preimageError));
      return false;
    }

    add(TakerSetPreimage(preimageData.data));
    return true;
  }

  DexFormError? _parsePreimageError(
    DataFromService<TradePreimage, BaseError> preimageData,
  ) {
    final BaseError? error = preimageData.error;

    if (error is TradePreimageNotSufficientBalanceError) {
      return _insufficientBalanceError(
        Rational.parse(error.required),
        error.coin,
      );
    } else if (error is TradePreimageNotSufficientBaseCoinBalanceError) {
      return _insufficientBalanceError(
        Rational.parse(error.required),
        error.coin,
      );
    } else if (error is TradePreimageTransportError) {
      return DexFormError(error: LocaleKeys.notEnoughBalanceForGasError.tr());
    } else if (error is TradePreimageNoSuchCoinError) {
      return DexFormError(
        error: LocaleKeys.connectionToServersFailing.tr(args: [error.coin]),
      );
    } else if (error is TradePreimageVolumeTooLowError) {
      return DexFormError(
        error: LocaleKeys.lowTradeVolumeError.tr(
          args: [formatAmt(double.parse(error.threshold)), error.coin],
        ),
      );
    } else if (error != null) {
      return DexFormError(error: error.message);
    } else if (preimageData.data == null) {
      return DexFormError(error: LocaleKeys.somethingWrong.tr());
    }

    return null;
  }

  Future<bool> validateForm() async {
    add(TakerClearErrors());

    if (!_isSellCoinSelected) {
      add(TakerAddError(_selectSellCoinError()));
      return false;
    }

    if (!_isOrderSelected) {
      add(TakerAddError(_selectOrderError()));
      return false;
    }

    if (!await _validateCoinAndParent(state.sellCoin!.abbr)) return false;
    if (!await _validateCoinAndParent(state.selectedOrder!.coin)) return false;

    if (!_validateAmount()) return false;

    return true;
  }

  bool _validateAmount() {
    if (!_validateMinAmount()) return false;
    if (!_validateMaxAmount()) return false;

    return true;
  }

  Future<bool> _checkTradeWithSelf() async {
    add(TakerClearErrors());

    if (state.selectedOrder == null) return false;
    final BestOrder selectedOrder = state.selectedOrder!;

    final selectedOrderAddress = selectedOrder.address;
    final asset = _sdk.getSdkAsset(selectedOrder.coin);
    final cached = _sdk.pubkeys.lastKnown(asset.id);
    final ownPubkeys = cached ?? await _sdk.pubkeys.getPubkeys(asset);
    final ownAddresses = ownPubkeys.keys
        .where((pubkeyInfo) => pubkeyInfo.isActiveForSwap)
        .map((e) => e.address)
        .toSet();

    if (ownAddresses.contains(selectedOrderAddress.addressData)) {
      add(TakerAddError(_tradingWithSelfError()));
      return true;
    }
    return false;
  }

  bool _validateMaxAmount() {
    final Rational? availableBalance = state.maxSellAmount;
    if (availableBalance == null) return true; // validated on preimage side

    final Rational? maxOrderVolume = state.selectedOrder?.maxVolume;
    if (maxOrderVolume == null) {
      add(TakerAddError(_selectOrderError()));
      return false;
    }

    final Rational? sellAmount = state.sellAmount;
    if (sellAmount == null || sellAmount == Rational.zero) {
      add(TakerAddError(_enterSellAmountError()));
      return false;
    }

    if (maxOrderVolume <= availableBalance && sellAmount > maxOrderVolume) {
      add(TakerAddError(_setOrderMaxError(maxOrderVolume)));
      return false;
    }

    if (availableBalance < maxOrderVolume && sellAmount > availableBalance) {
      final Rational minAmount = maxRational([
        state.minSellAmount ?? Rational.zero,
        state.selectedOrder!.minVolume,
      ])!;

      if (availableBalance < minAmount) {
        add(
          TakerAddError(
            _insufficientBalanceError(minAmount, state.sellCoin!.abbr),
          ),
        );
      } else {
        add(TakerAddError(_setMaxError(availableBalance)));
      }

      return false;
    }

    return true;
  }

  bool _validateMinAmount() {
    final Rational minTradingVolume = state.minSellAmount ?? Rational.zero;
    final Rational minOrderVolume =
        state.selectedOrder?.minVolume ?? Rational.zero;

    final Rational minAmount =
        maxRational([minTradingVolume, minOrderVolume]) ?? Rational.zero;
    final Rational sellAmount = state.sellAmount ?? Rational.zero;

    if (sellAmount < minAmount) {
      final Rational available = state.maxSellAmount ?? Rational.zero;
      if (available < minAmount) {
        add(
          TakerAddError(
            _insufficientBalanceError(minAmount, state.sellCoin!.abbr),
          ),
        );
      } else {
        add(TakerAddError(_setMinError(minAmount)));
      }

      return false;
    }

    return true;
  }

  Future<bool> _validateCoinAndParent(String abbr) async {
    final coin = _sdk.getSdkAsset(abbr);
    final activatedAssetIds = await _coinsRepo.getActivatedAssetIds();
    final parentId = coin.id.parentId;

    if (!activatedAssetIds.contains(coin.id)) {
      add(TakerAddError(_coinNotActiveError(coin.id.id)));
      return false;
    }

    if (parentId != null && !activatedAssetIds.contains(parentId)) {
      add(TakerAddError(_coinNotActiveError(parentId.id)));
      return false;
    }

    return true;
  }

  bool get _isSellCoinSelected => state.sellCoin != null;

  bool get _isOrderSelected => state.selectedOrder != null;

  bool get canRequestPreimage {
    // used to fetch the coin balance via the new balance function
    final sdk = GetIt.I<KomodoDefiSdk>();

    final Coin? sellCoin = state.sellCoin;
    if (sellCoin == null) return false;
    if (sellCoin.isSuspended) return false;

    final Rational? sellAmount = state.sellAmount;
    if (sellAmount == null) return false;
    if (sellAmount == Rational.zero) return false;
    final Rational? minSellAmount = state.minSellAmount;
    if (minSellAmount != null && sellAmount < minSellAmount) return false;
    final Rational? maxSellAmount = state.maxSellAmount;
    if (maxSellAmount != null && sellAmount > maxSellAmount) return false;

    final Coin? parentSell = sellCoin.parentCoin;
    if (parentSell != null) {
      if (parentSell.isSuspended) return false;
      if (parentSell.balance(sdk) == 0.00) return false;
    }

    final BestOrder? selectedOrder = state.selectedOrder;
    if (selectedOrder == null) return false;
    final Coin? buyCoin = _coinsRepo.getCoin(selectedOrder.coin);
    if (buyCoin == null) return false;

    final Coin? parentBuy = buyCoin.parentCoin;
    if (parentBuy != null) {
      if (parentBuy.isSuspended) return false;
      if (parentBuy.balance(sdk) == 0.00) return false;
    }

    return true;
  }

  void verifyOrderVolume() {
    final Coin? sellCoin = state.sellCoin;
    final BestOrder? selectedOrder = state.selectedOrder;
    final Rational? sellAmount = state.sellAmount;

    if (sellCoin == null) return;
    if (selectedOrder == null) return;
    if (sellAmount == null) return;

    add(TakerClearErrors());
    if (sellAmount > selectedOrder.maxVolume) {
      add(TakerAddError(_setOrderMaxError(selectedOrder.maxVolume)));
      return;
    }
  }

  DataFromService<TradePreimage, BaseError>? get _cachedPreimage {
    final preimage = state.tradePreimage;
    if (preimage == null) return null;

    final request = preimage.request;
    if (state.sellCoin?.abbr != request.base) return null;
    if (state.selectedOrder?.coin != request.rel) return null;
    if (state.selectedOrder?.price != request.price) return null;
    if (state.sellAmount != request.volume) return null;

    return DataFromService(data: preimage);
  }

  Future<DataFromService<TradePreimage, BaseError>> _getPreimageData() async {
    final cached = _cachedPreimage;
    if (cached != null) return cached;

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
        path: 'taker_validator::_getPreimageData',
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

  DexFormError _coinNotActiveError(String abbr) {
    return DexFormError(error: LocaleKeys.coinIsNotActive.tr(args: [abbr]));
  }

  DexFormError _selectSellCoinError() =>
      DexFormError(error: LocaleKeys.dexSelectSellCoinError.tr());

  DexFormError _selectOrderError() =>
      DexFormError(error: LocaleKeys.dexSelectBuyCoinError.tr());

  DexFormError _enterSellAmountError() =>
      DexFormError(error: LocaleKeys.dexEnterSellAmountError.tr());

  DexFormError _insufficientBalanceError(Rational required, String abbr) {
    return DexFormError(
      error: LocaleKeys.dexBalanceNotSufficientError.tr(
        args: [abbr, formatDexAmt(required), abbr],
      ),
    );
  }

  DexFormError _setOrderMaxError(Rational maxAmount) {
    return DexFormError(
      error: LocaleKeys.dexMaxOrderVolume.tr(
        args: [formatDexAmt(maxAmount), state.sellCoin!.abbr],
      ),
      type: DexFormErrorType.largerMaxSellVolume,
      action: DexFormErrorAction(
        text: LocaleKeys.setMax.tr(),
        callback: () async {
          add(TakerSetSellAmount(maxAmount));
        },
      ),
    );
  }

  DexFormError _setMaxError(Rational available) {
    return DexFormError(
      error: LocaleKeys.dexInsufficientFundsError.tr(
        args: [formatDexAmt(available), state.sellCoin!.abbr],
      ),
      type: DexFormErrorType.largerMaxSellVolume,
      action: DexFormErrorAction(
        text: LocaleKeys.setMax.tr(),
        callback: () async {
          add(TakerSetSellAmount(available));
        },
      ),
    );
  }

  DexFormError _setMinError(Rational minAmount) {
    return DexFormError(
      type: DexFormErrorType.lessMinVolume,
      error: LocaleKeys.dexMinSellAmountError.tr(
        args: [formatDexAmt(minAmount), state.sellCoin!.abbr],
      ),
      action: DexFormErrorAction(
        text: LocaleKeys.setMin.tr(),
        callback: () async {
          add(TakerSetSellAmount(minAmount));
        },
      ),
    );
  }

  DexFormError _tradingWithSelfError() {
    return DexFormError(error: LocaleKeys.dexTradingWithSelfError.tr());
  }
}

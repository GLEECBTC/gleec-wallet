import 'package:easy_localization/easy_localization.dart';
import 'package:get_it/get_it.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/bloc/bridge_form/bridge_bloc.dart';
import 'package:web_dex/bloc/bridge_form/bridge_event.dart';
import 'package:web_dex/bloc/bridge_form/bridge_state.dart';
import 'package:web_dex/bloc/coins_bloc/asset_coin_extension.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/dex_repository.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:web_dex/mm2/mm2_api/rpc/best_orders/best_orders.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trade_preimage/trade_preimage_errors.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/data_from_service.dart';
import 'package:web_dex/model/dex_form_error.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/model/trade_preimage.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/dex/dex_helpers.dart';
import 'package:web_dex/views/dex/simple/form/error_list/dex_form_error_with_action.dart';

class BridgeValidator {
  BridgeValidator({
    required BridgeBloc bloc,
    required CoinsRepo coinsRepository,
    required DexRepository dexRepository,
    required KomodoDefiSdk sdk,
  }) : _bloc = bloc,
       _coinsRepo = coinsRepository,
       _dexRepo = dexRepository,
       _sdk = sdk,
       _add = bloc.add;

  final BridgeBloc _bloc;
  final CoinsRepo _coinsRepo;
  final DexRepository _dexRepo;
  final KomodoDefiSdk _sdk;

  final Function(BridgeEvent) _add;
  BridgeState get _state => _bloc.state;

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
    _add(const BridgeClearErrors());

    final preimageData = await _getPreimageData();
    final preimageError = _parsePreimageError(preimageData);

    if (preimageError != null) {
      _add(BridgeSetError(preimageError));
      return false;
    }

    _add(BridgeSetPreimage(preimageData));
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

  DataFromService<TradePreimage, BaseError>? get _cachedPreimage {
    final preimageData = _state.preimageData;
    if (preimageData == null) return null;

    final request = preimageData.data?.request;
    if (_state.sellCoin?.abbr != request?.base) return null;
    if (_state.bestOrder?.coin != request?.rel) return null;
    if (_state.bestOrder?.price != request?.price) return null;
    if (_state.sellAmount != request?.volume) return null;

    return preimageData;
  }

  Future<DataFromService<TradePreimage, BaseError>> _getPreimageData() async {
    final cached = _cachedPreimage;
    if (cached != null) return cached;

    try {
      return await _dexRepo.getTradePreimage(
        _state.sellCoin!.abbr,
        _state.bestOrder!.coin,
        _state.bestOrder!.price,
        'sell',
        _state.sellAmount,
      );
    } catch (e, s) {
      log(
        e.toString(),
        trace: s,
        path: 'bridge_validator::_getPreimageData',
        isError: true,
      );
      return DataFromService(
        error: TextError(error: 'Failed to request trade preimage'),
      );
    }
  }

  Future<bool> validateForm() async {
    _add(const BridgeClearErrors());

    if (!_isSellCoinSelected) {
      _add(BridgeSetError(_selectSourceProtocolError()));
      return false;
    }

    if (!_isOrderSelected) {
      _add(BridgeSetError(_selectTargetProtocolError()));
      return false;
    }

    if (!await _validateCoinAndParent(_state.sellCoin!.abbr)) return false;
    if (!await _validateCoinAndParent(_state.bestOrder!.coin)) return false;

    if (!_validateAmount()) return false;

    return true;
  }

  bool _validateAmount() {
    if (!_validateMinAmount()) return false;
    if (!_validateMaxAmount()) return false;

    return true;
  }

  bool _validateMaxAmount() {
    final Rational? availableBalance = _state.maxSellAmount;
    if (availableBalance == null) return true; // validated on preimage side

    final Rational? maxOrderVolume = _state.bestOrder?.maxVolume;
    if (maxOrderVolume == null) {
      _add(BridgeSetError(_selectTargetProtocolError()));
      return false;
    }

    final Rational? sellAmount = _state.sellAmount;
    if (sellAmount == null || sellAmount == Rational.zero) {
      _add(BridgeSetError(_enterSellAmountError()));
      return false;
    }

    if (maxOrderVolume <= availableBalance && sellAmount > maxOrderVolume) {
      _add(BridgeSetError(_setOrderMaxError(maxOrderVolume)));
      return false;
    }

    if (availableBalance < maxOrderVolume && sellAmount > availableBalance) {
      final Rational minAmount = maxRational([
        _state.minSellAmount ?? Rational.zero,
        _state.bestOrder!.minVolume,
      ])!;

      if (availableBalance < minAmount) {
        _add(
          BridgeSetError(
            _insufficientBalanceError(minAmount, _state.sellCoin!.abbr),
          ),
        );
      } else {
        _add(BridgeSetError(_setMaxError(availableBalance)));
      }

      return false;
    }

    return true;
  }

  bool _validateMinAmount() {
    final Rational minTradingVolume = _state.minSellAmount ?? Rational.zero;
    final Rational minOrderVolume =
        _state.bestOrder?.minVolume ?? Rational.zero;

    final Rational minAmount =
        maxRational([minTradingVolume, minOrderVolume]) ?? Rational.zero;
    final Rational sellAmount = _state.sellAmount ?? Rational.zero;

    if (sellAmount < minAmount) {
      final Rational available = _state.maxSellAmount ?? Rational.zero;
      if (available < minAmount) {
        _add(
          BridgeSetError(
            _insufficientBalanceError(minAmount, _state.sellCoin!.abbr),
          ),
        );
      } else {
        _add(BridgeSetError(_setMinError(minAmount)));
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
      _add(BridgeSetError(_coinNotActiveError(coin.id.id)));
      return false;
    }

    if (parentId != null && !activatedAssetIds.contains(parentId)) {
      _add(BridgeSetError(_coinNotActiveError(parentId.id)));
      return false;
    }

    return true;
  }

  Future<bool> _checkTradeWithSelf() async {
    _add(const BridgeClearErrors());

    final BestOrder? selectedOrder = _state.bestOrder;
    if (selectedOrder == null) return false;

    final selectedOrderAddress = selectedOrder.address;
    final asset = _sdk.getSdkAsset(selectedOrder.coin);
    final cached = _sdk.pubkeys.lastKnown(asset.id);
    final ownPubkeys = cached ?? await _sdk.pubkeys.getPubkeys(asset);
    final ownAddresses = ownPubkeys.keys
        .where((pubkeyInfo) => pubkeyInfo.isActiveForSwap)
        .map((e) => e.address)
        .toSet();

    if (ownAddresses.contains(selectedOrderAddress.addressData)) {
      _add(BridgeSetError(_tradingWithSelfError()));
      return true;
    }
    return false;
  }

  void verifyOrderVolume() {
    final Coin? sellCoin = _state.sellCoin;
    final BestOrder? selectedOrder = _state.bestOrder;
    final Rational? sellAmount = _state.sellAmount;

    if (sellCoin == null) return;
    if (selectedOrder == null) return;
    if (sellAmount == null) return;

    _add(const BridgeClearErrors());
    if (sellAmount > selectedOrder.maxVolume) {
      _add(BridgeSetError(_setOrderMaxError(selectedOrder.maxVolume)));
      return;
    }
  }

  DexFormError _coinNotActiveError(String abbr) {
    return DexFormError(error: LocaleKeys.coinIsNotActive.tr(args: [abbr]));
  }

  DexFormError _selectSourceProtocolError() =>
      DexFormError(error: LocaleKeys.bridgeSelectSendProtocolError.tr());
  DexFormError _selectTargetProtocolError() =>
      DexFormError(error: LocaleKeys.bridgeSelectReceiveCoinError.tr());
  DexFormError _enterSellAmountError() =>
      DexFormError(error: LocaleKeys.dexEnterSellAmountError.tr());

  DexFormError _setOrderMaxError(Rational maxAmount) {
    return DexFormError(
      error: LocaleKeys.dexMaxOrderVolume.tr(
        args: [formatDexAmt(maxAmount), _state.sellCoin!.abbr],
      ),
      type: DexFormErrorType.largerMaxSellVolume,
      action: DexFormErrorAction(
        text: LocaleKeys.setMax.tr(),
        callback: () async {
          _add(BridgeSetSellAmount(maxAmount));
        },
      ),
    );
  }

  DexFormError _insufficientBalanceError(Rational required, String abbr) {
    return DexFormError(
      error: LocaleKeys.dexBalanceNotSufficientError.tr(
        args: [abbr, formatDexAmt(required), abbr],
      ),
    );
  }

  DexFormError _setMaxError(Rational available) {
    return DexFormError(
      error: LocaleKeys.dexInsufficientFundsError.tr(
        args: [formatDexAmt(available), _state.sellCoin!.abbr],
      ),
      type: DexFormErrorType.largerMaxSellVolume,
      action: DexFormErrorAction(
        text: LocaleKeys.setMax.tr(),
        callback: () async {
          _add(BridgeSetSellAmount(available));
        },
      ),
    );
  }

  DexFormError _setMinError(Rational minAmount) {
    return DexFormError(
      type: DexFormErrorType.lessMinVolume,
      error: LocaleKeys.dexMinSellAmountError.tr(
        args: [formatDexAmt(minAmount), _state.sellCoin!.abbr],
      ),
      action: DexFormErrorAction(
        text: LocaleKeys.setMin.tr(),
        callback: () async {
          _add(BridgeSetSellAmount(minAmount));
        },
      ),
    );
  }

  DexFormError _tradingWithSelfError() {
    return DexFormError(error: LocaleKeys.dexTradingWithSelfError.tr());
  }

  bool get _isSellCoinSelected => _state.sellCoin != null;

  bool get _isOrderSelected => _state.bestOrder != null;

  bool get canRequestPreimage {
    // used to fetch the coin balance via the new balance function
    final sdk = GetIt.I<KomodoDefiSdk>();

    final Coin? sellCoin = _state.sellCoin;
    if (sellCoin == null) return false;
    if (sellCoin.isSuspended) return false;

    final Rational? sellAmount = _state.sellAmount;
    if (sellAmount == null) return false;
    if (sellAmount == Rational.zero) return false;
    final Rational? minSellAmount = _state.minSellAmount;
    if (minSellAmount != null && sellAmount < minSellAmount) return false;
    final Rational? maxSellAmount = _state.maxSellAmount;
    if (maxSellAmount != null && sellAmount > maxSellAmount) return false;

    final Coin? parentSell = sellCoin.parentCoin;
    if (parentSell != null) {
      if (parentSell.isSuspended) return false;
      if (parentSell.balance(sdk) == 0.00) return false;
    }

    final BestOrder? bestOrder = _state.bestOrder;
    if (bestOrder == null) return false;
    final Coin? buyCoin = _coinsRepo.getCoin(bestOrder.coin);
    if (buyCoin == null) return false;

    final Coin? parentBuy = buyCoin.parentCoin;
    if (parentBuy != null) {
      if (parentBuy.isSuspended) return false;

      if (parentBuy.balance(sdk) == 0.00) return false;
    }

    return true;
  }
}

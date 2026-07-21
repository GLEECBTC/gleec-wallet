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
  int _validationGeneration = 0;

  _TakerValidationScope _beginValidation() => _TakerValidationScope(
    walletId: state.walletId,
    formRevision: state.formRevision,
    generation: ++_validationGeneration,
  );

  bool _isCurrent(_TakerValidationScope scope) =>
      scope.generation == _validationGeneration &&
      scope.walletId == state.walletId &&
      scope.formRevision == state.formRevision;

  void _emit(_TakerValidationScope scope, TakerEvent event) {
    if (!_isCurrent(scope)) return;
    if (event is TakerAddError) {
      add(
        TakerAddError(
          event.error,
          walletId: scope.walletId,
          formRevision: scope.formRevision,
        ),
      );
    } else if (event is TakerClearErrors) {
      add(
        TakerClearErrors(
          walletId: scope.walletId,
          formRevision: scope.formRevision,
        ),
      );
    } else {
      add(event);
    }
  }

  Future<bool> validate() async {
    return await validateAndGetPreimage() != null;
  }

  /// Validates the current revision and returns the exact preimage that was
  /// validated. The caller must still verify its wallet/revision before use.
  Future<TradePreimage?> validateAndGetPreimage() async {
    final scope = _beginValidation();
    try {
      final bool isFormValid = await _validateForm(scope);
      if (!isFormValid || !_isCurrent(scope)) return null;

      final bool tradingWithSelf = await _checkTradeWithSelf(scope);
      if (tradingWithSelf || !_isCurrent(scope)) return null;

      return _validatePreimage(scope);
    } catch (_) {
      if (_isCurrent(scope)) {
        _emit(
          scope,
          TakerAddError(DexFormError(error: LocaleKeys.somethingWrong.tr())),
        );
      }
      return null;
    }
  }

  Future<TradePreimage?> _validatePreimage(_TakerValidationScope scope) async {
    _emit(scope, TakerClearErrors());

    final sellCoin = state.sellCoin;
    final selectedOrder = state.selectedOrder;
    final sellAmount = state.sellAmount;
    if (sellCoin == null || selectedOrder == null || sellAmount == null) {
      return null;
    }

    final preimageData = await _getPreimageData(
      base: sellCoin.abbr,
      rel: selectedOrder.coin,
      price: selectedOrder.price,
      volume: sellAmount,
    );
    if (!_isCurrent(scope)) return null;
    final preimageError = _parsePreimageError(preimageData);

    if (preimageError != null) {
      _emit(scope, TakerAddError(preimageError));
      return null;
    }

    return preimageData.data;
  }

  DexFormError? _parsePreimageError(
    DataFromService<TradePreimage, BaseError> preimageData,
  ) {
    final BaseError? error = preimageData.error;

    if (error is TradePreimageNotSufficientBalanceError) {
      final required = _parseBoundedPositiveRational(error.required);
      if (required == null) {
        return DexFormError(error: LocaleKeys.somethingWrong.tr());
      }
      return _insufficientBalanceError(required, _safeAssetLabel(error.coin));
    } else if (error is TradePreimageNotSufficientBaseCoinBalanceError) {
      final required = _parseBoundedPositiveRational(error.required);
      if (required == null) {
        return DexFormError(error: LocaleKeys.somethingWrong.tr());
      }
      return _insufficientBalanceError(required, _safeAssetLabel(error.coin));
    } else if (error is TradePreimageTransportError) {
      return DexFormError(error: LocaleKeys.notEnoughBalanceForGasError.tr());
    } else if (error is TradePreimageNoSuchCoinError) {
      return DexFormError(
        error: LocaleKeys.connectionToServersFailing.tr(
          args: [_safeAssetLabel(error.coin)],
        ),
      );
    } else if (error is TradePreimageVolumeTooLowError) {
      final threshold = _parseBoundedPositiveRational(error.threshold);
      if (threshold == null) {
        return DexFormError(error: LocaleKeys.somethingWrong.tr());
      }
      return DexFormError(
        error: LocaleKeys.lowTradeVolumeError.tr(
          args: [formatDexAmt(threshold), _safeAssetLabel(error.coin)],
        ),
      );
    } else if (error != null) {
      // Daemon-provided error strings may contain raw payloads or be
      // attacker-sized. Known conditions are mapped above; everything else
      // stays generic at this user-facing boundary.
      return DexFormError(error: LocaleKeys.somethingWrong.tr());
    } else if (preimageData.data == null) {
      return DexFormError(error: LocaleKeys.somethingWrong.tr());
    }

    return null;
  }

  Future<bool> validateForm() async {
    final scope = _beginValidation();
    try {
      return await _validateForm(scope);
    } catch (_) {
      if (_isCurrent(scope)) {
        _emit(
          scope,
          TakerAddError(DexFormError(error: LocaleKeys.somethingWrong.tr())),
        );
      }
      return false;
    }
  }

  Future<bool> _validateForm(_TakerValidationScope scope) async {
    _emit(scope, TakerClearErrors());

    if (!_isSellCoinSelected) {
      _emit(scope, TakerAddError(_selectSellCoinError()));
      return false;
    }

    if (!_isOrderSelected) {
      _emit(scope, TakerAddError(_selectOrderError()));
      return false;
    }

    if (!await _validateCoinAndParent(state.sellCoin!.abbr, scope)) {
      return false;
    }
    if (!_isCurrent(scope)) return false;
    if (!await _validateCoinAndParent(state.selectedOrder!.coin, scope)) {
      return false;
    }
    if (!_isCurrent(scope)) return false;

    if (!_validateAmount(scope)) return false;

    return true;
  }

  bool _validateAmount(_TakerValidationScope scope) {
    if (!_validateMinAmount(scope)) return false;
    if (!_validateMaxAmount(scope)) return false;

    return true;
  }

  Future<bool> _checkTradeWithSelf(_TakerValidationScope scope) async {
    _emit(scope, TakerClearErrors());

    if (state.selectedOrder == null) return false;
    final BestOrder selectedOrder = state.selectedOrder!;

    try {
      final selectedOrderAddress = selectedOrder.address;
      final asset = _sdk.getSdkAsset(selectedOrder.coin);
      final cached = _sdk.pubkeys.lastKnown(asset.id);
      final ownPubkeys = cached ?? await _sdk.pubkeys.getPubkeys(asset);
      if (!_isCurrent(scope)) return true;
      final ownAddresses = ownPubkeys.keys
          .where((pubkeyInfo) => pubkeyInfo.isActiveForSwap)
          .map((e) => e.address)
          .toSet();

      if (ownAddresses.contains(selectedOrderAddress.addressData)) {
        _emit(scope, TakerAddError(_tradingWithSelfError()));
        return true;
      }
      return false;
    } catch (_) {
      if (_isCurrent(scope)) {
        _emit(
          scope,
          TakerAddError(DexFormError(error: LocaleKeys.somethingWrong.tr())),
        );
      }
      // Ownership uncertainty must fail closed.
      return true;
    }
  }

  bool _validateMaxAmount(_TakerValidationScope scope) {
    final Rational? availableBalance = state.maxSellAmount;
    if (availableBalance == null) return true; // validated on preimage side

    final Rational? maxOrderVolume = state.selectedOrder?.maxVolume;
    if (maxOrderVolume == null) {
      _emit(scope, TakerAddError(_selectOrderError()));
      return false;
    }

    final Rational? sellAmount = state.sellAmount;
    if (sellAmount == null || sellAmount == Rational.zero) {
      _emit(scope, TakerAddError(_enterSellAmountError()));
      return false;
    }

    if (maxOrderVolume <= availableBalance && sellAmount > maxOrderVolume) {
      _emit(scope, TakerAddError(_setOrderMaxError(maxOrderVolume)));
      return false;
    }

    if (availableBalance < maxOrderVolume && sellAmount > availableBalance) {
      final Rational minAmount = maxRational([
        state.minSellAmount ?? Rational.zero,
        state.selectedOrder!.minVolume,
      ])!;

      if (availableBalance < minAmount) {
        _emit(
          scope,
          TakerAddError(
            _insufficientBalanceError(minAmount, state.sellCoin!.abbr),
          ),
        );
      } else {
        _emit(scope, TakerAddError(_setMaxError(availableBalance)));
      }

      return false;
    }

    return true;
  }

  bool _validateMinAmount(_TakerValidationScope scope) {
    final Rational minTradingVolume = state.minSellAmount ?? Rational.zero;
    final Rational minOrderVolume =
        state.selectedOrder?.minVolume ?? Rational.zero;

    final Rational minAmount =
        maxRational([minTradingVolume, minOrderVolume]) ?? Rational.zero;
    final Rational sellAmount = state.sellAmount ?? Rational.zero;

    if (sellAmount < minAmount) {
      final Rational available = state.maxSellAmount ?? Rational.zero;
      if (available < minAmount) {
        _emit(
          scope,
          TakerAddError(
            _insufficientBalanceError(minAmount, state.sellCoin!.abbr),
          ),
        );
      } else {
        _emit(scope, TakerAddError(_setMinError(minAmount)));
      }

      return false;
    }

    return true;
  }

  Future<bool> _validateCoinAndParent(
    String abbr,
    _TakerValidationScope scope,
  ) async {
    try {
      final coin = _sdk.getSdkAsset(abbr);
      final activatedAssetIds = await _coinsRepo.getActivatedAssetIds();
      if (!_isCurrent(scope)) return false;
      final parentId = coin.id.parentId;

      if (!activatedAssetIds.contains(coin.id)) {
        _emit(scope, TakerAddError(_coinNotActiveError(coin.id.id)));
        return false;
      }

      if (parentId != null && !activatedAssetIds.contains(parentId)) {
        _emit(scope, TakerAddError(_coinNotActiveError(parentId.id)));
        return false;
      }

      return true;
    } catch (_) {
      if (_isCurrent(scope)) {
        _emit(
          scope,
          TakerAddError(DexFormError(error: LocaleKeys.somethingWrong.tr())),
        );
      }
      return false;
    }
  }

  bool get _isSellCoinSelected => state.sellCoin != null;

  bool get _isOrderSelected => state.selectedOrder != null;

  bool get canRequestPreimage {
    try {
      // used to fetch the coin balance via the new balance function
      final sdk = GetIt.I<KomodoDefiSdk>();

      final Coin? sellCoin = state.sellCoin;
      if (sellCoin == null) return false;
      if (sellCoin.isSuspended) return false;

      final Rational? sellAmount = state.sellAmount;
      if (sellAmount == null || sellAmount <= Rational.zero) return false;
      final Rational? minSellAmount = state.minSellAmount;
      if (minSellAmount != null && sellAmount < minSellAmount) return false;
      final Rational? maxSellAmount = state.maxSellAmount;
      if (maxSellAmount != null && sellAmount > maxSellAmount) return false;

      final Coin? parentSell = sellCoin.parentCoin;
      if (parentSell != null) {
        if (parentSell.isSuspended) return false;
        final balance = parentSell.balance(sdk);
        if (balance == null || !balance.isFinite || balance <= 0) return false;
      }

      final BestOrder? selectedOrder = state.selectedOrder;
      if (selectedOrder == null) return false;
      final Coin? buyCoin = _coinsRepo.getCoin(selectedOrder.coin);
      if (buyCoin == null) return false;

      final Coin? parentBuy = buyCoin.parentCoin;
      if (parentBuy != null) {
        if (parentBuy.isSuspended) return false;
        final balance = parentBuy.balance(sdk);
        if (balance == null || !balance.isFinite || balance <= 0) return false;
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  void verifyOrderVolume() {
    final scope = _beginValidation();
    final Coin? sellCoin = state.sellCoin;
    final BestOrder? selectedOrder = state.selectedOrder;
    final Rational? sellAmount = state.sellAmount;

    if (sellCoin == null) return;
    if (selectedOrder == null) return;
    if (sellAmount == null) return;

    _emit(scope, TakerClearErrors());
    if (sellAmount > selectedOrder.maxVolume) {
      _emit(scope, TakerAddError(_setOrderMaxError(selectedOrder.maxVolume)));
      return;
    }
  }

  DataFromService<TradePreimage, BaseError>? _cachedPreimage({
    required String base,
    required String rel,
    required Rational price,
    required Rational volume,
  }) {
    final preimage = state.tradePreimage;
    if (preimage == null) return null;

    final request = preimage.request;
    if (base != request.base) return null;
    if (rel != request.rel) return null;
    if (price != request.price) return null;
    if (volume != request.volume) return null;

    return DataFromService(data: preimage);
  }

  Future<DataFromService<TradePreimage, BaseError>> _getPreimageData({
    required String base,
    required String rel,
    required Rational price,
    required Rational volume,
  }) async {
    final cached = _cachedPreimage(
      base: base,
      rel: rel,
      price: price,
      volume: volume,
    );
    if (cached != null) return cached;

    try {
      return await _dexRepo.getTradePreimage(base, rel, price, 'sell', volume);
    } catch (e, s) {
      log(
        'Unable to request a taker preimage',
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

  String _safeAssetLabel(String value) {
    final candidate = value.trim();
    if (candidate.isNotEmpty &&
        candidate.length <= 64 &&
        RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(candidate)) {
      return candidate;
    }
    return state.sellCoin?.abbr ?? '';
  }

  Rational? _parseBoundedPositiveRational(String value) {
    final candidate = value.trim();
    if (candidate.isEmpty || candidate.length > 128) return null;
    final parsed = Rational.tryParse(candidate);
    return parsed != null && parsed > Rational.zero ? parsed : null;
  }
}

class _TakerValidationScope {
  const _TakerValidationScope({
    required this.walletId,
    required this.formRevision,
    required this.generation,
  });

  final String? walletId;
  final int formRevision;
  final int generation;
}

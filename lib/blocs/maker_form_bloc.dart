import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/dex_repository.dart';
import 'package:web_dex/blocs/bloc_base.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:web_dex/mm2/mm2_api/rpc/setprice/setprice_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trade_preimage/trade_preimage_errors.dart';
import 'package:web_dex/model/available_balance_state.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/data_from_service.dart';
import 'package:web_dex/model/dex_form_error.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/model/trade_preimage.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/dex/dex_helpers.dart';
import 'package:web_dex/views/dex/simple/form/error_list/dex_form_error_with_action.dart';

class MakerFormBloc implements BlocBase {
  MakerFormBloc({
    required this.api,
    required this.kdfSdk,
    required this.coinsRepository,
    required this.dexRepository,
  });

  final Mm2Api api;
  final KomodoDefiSdk kdfSdk;
  final CoinsRepo coinsRepository;
  final DexRepository dexRepository;

  String currentEntityUuid = '';

  bool _showConfirmation = false;
  final StreamController<bool> _showConfirmationCtrl =
      StreamController.broadcast();
  Sink<bool> get _inShowConfirmation => _showConfirmationCtrl.sink;
  Stream<bool> get outShowConfirmation => _showConfirmationCtrl.stream;
  bool get showConfirmation => _showConfirmation;
  set showConfirmation(bool value) {
    _showConfirmation = value;
    _inShowConfirmation.add(_showConfirmation);
  }

  bool _showSellCoinSelect = false;
  final StreamController<bool> _showSellCoinSelectCtrl =
      StreamController.broadcast();
  Sink<bool> get _inShowSellCoinSelect => _showSellCoinSelectCtrl.sink;
  Stream<bool> get outShowSellCoinSelect => _showSellCoinSelectCtrl.stream;
  bool get showSellCoinSelect => _showSellCoinSelect;
  set showSellCoinSelect(bool value) {
    _showSellCoinSelect = value;
    _inShowSellCoinSelect.add(_showSellCoinSelect);
    if (_showSellCoinSelect) showBuyCoinSelect = false;
  }

  bool _showBuyCoinSelect = false;
  final StreamController<bool> _showBuyCoinSelectCtrl =
      StreamController.broadcast();
  Sink<bool> get _inShowBuyCoinSelect => _showBuyCoinSelectCtrl.sink;
  Stream<bool> get outShowBuyCoinSelect => _showBuyCoinSelectCtrl.stream;
  bool get showBuyCoinSelect => _showBuyCoinSelect;
  set showBuyCoinSelect(bool value) {
    _showBuyCoinSelect = value;
    _inShowBuyCoinSelect.add(_showBuyCoinSelect);
    if (_showBuyCoinSelect) showSellCoinSelect = false;
  }

  bool _inProgress = false;
  final StreamController<bool> _inProgressCtrl = StreamController.broadcast();
  Sink<bool> get _inInProgress => _inProgressCtrl.sink;
  Stream<bool> get outInProgress => _inProgressCtrl.stream;
  bool get inProgress => _inProgress;
  set inProgress(bool value) {
    _inProgress = value;
    _inInProgress.add(_inProgress);
  }

  bool _isMaxActive = false;
  final StreamController<bool> _isMaxActiveCtrl = StreamController.broadcast();
  Sink<bool> get _inIsMaxActive => _isMaxActiveCtrl.sink;
  Stream<bool> get outIsMaxActive => _isMaxActiveCtrl.stream;
  bool get isMaxActive => _isMaxActive;
  set isMaxActive(bool value) {
    _isMaxActive = value;
    _inIsMaxActive.add(_isMaxActive);
  }

  Coin? _sellCoin;
  final StreamController<Coin?> _sellCoinCtrl = StreamController.broadcast();
  Sink<Coin?> get _inSellCoin => _sellCoinCtrl.sink;
  Stream<Coin?> get outSellCoin => _sellCoinCtrl.stream;
  Coin? get sellCoin => _sellCoin;
  set sellCoin(Coin? coin) {
    // Wallet-only assets (e.g. TRX/TRC-20) are excluded from the DEX pickers;
    // ignore programmatic/deep-link selections too.
    if (coin != null && coin.walletOnly) return;
    if (coin?.abbr != sellCoin?.abbr) {
      setSellAmount(null);
      setBuyAmount(null);
      setPriceValue(null);
      maxSellAmount = null;
      availableBalanceState = AvailableBalanceState.initial;
    }

    _sellCoin = coin;
    _inSellCoin.add(_sellCoin);
    if (coin == buyCoin) buyCoin = null;

    _autoActivate(sellCoin)
        .then((_) async => await _updateMaxSellAmountListener())
        .then((_) => _updatePreimage())
        .then((_) => _reValidate());
  }

  Coin? _buyCoin;
  final StreamController<Coin?> _buyCoinCtrl = StreamController.broadcast();
  Sink<Coin?> get _inBuyCoin => _buyCoinCtrl.sink;
  Stream<Coin?> get outBuyCoin => _buyCoinCtrl.stream;
  Coin? get buyCoin => _buyCoin;
  set buyCoin(Coin? coin) {
    // Match the sell-side guard: wallet-only/custody assets must not be
    // introduced through deep links or programmatic quote selection.
    if (coin != null && coin.walletOnly) return;
    if (coin?.abbr != buyCoin?.abbr) {
      setBuyAmount(null);
      setPriceValue(null);
    }

    _buyCoin = coin;
    _inBuyCoin.add(_buyCoin);
    if (coin == sellCoin && coin != null) sellCoin = null;

    _autoActivate(
      buyCoin,
    ).then((_) => _updatePreimage()).then((_) => _reValidate());
  }

  Rational? _sellAmount;
  final StreamController<Rational?> _sellAmountCtrl =
      StreamController<Rational?>.broadcast();
  Sink<Rational?> get _inSellAmount => _sellAmountCtrl.sink;
  Stream<Rational?> get outSellAmount => _sellAmountCtrl.stream;
  Rational? get sellAmount => _sellAmount;
  set sellAmount(Rational? amount) {
    _sellAmount = amount;
    _inSellAmount.add(_sellAmount);

    _updatePreimage().then((_) => _reValidate());
  }

  Rational? _buyAmount;
  final StreamController<Rational?> _buyAmountCtrl =
      StreamController<Rational?>.broadcast();
  Sink<Rational?> get _inBuyAmount => _buyAmountCtrl.sink;
  Stream<Rational?> get outBuyAmount => _buyAmountCtrl.stream;
  Rational? get buyAmount => _buyAmount;
  set buyAmount(Rational? amount) {
    _buyAmount = amount;
    _inBuyAmount.add(_buyAmount);

    _updatePreimage().then((_) => _reValidate());
  }

  Rational? _price;
  final StreamController<Rational?> _priceCtrl =
      StreamController<Rational?>.broadcast();
  Sink<Rational?> get _inPrice => _priceCtrl.sink;
  Stream<Rational?> get outPrice => _priceCtrl.stream;
  Rational? get price => _price;
  set price(Rational? price) {
    _price = price;
    _inPrice.add(_price);

    _updatePreimage().then((_) => _reValidate());
  }

  Rational? _maxSellAmount;
  final StreamController<Rational?> _maxSellAmountCtrl =
      StreamController<Rational?>.broadcast();
  Sink<Rational?> get _inMaxSellAmount => _maxSellAmountCtrl.sink;
  Stream<Rational?> get outMaxSellAmount => _maxSellAmountCtrl.stream;
  Rational? get maxSellAmount => _maxSellAmount;
  set maxSellAmount(Rational? amount) {
    _maxSellAmount = amount;
    _inMaxSellAmount.add(_maxSellAmount);
  }

  AvailableBalanceState _availableBalanceState =
      AvailableBalanceState.unavailable;
  final StreamController<AvailableBalanceState> _availableBalanceStateCtrl =
      StreamController<AvailableBalanceState>.broadcast();
  Sink<AvailableBalanceState> get _inAvailableBalanceState =>
      _availableBalanceStateCtrl.sink;
  Stream<AvailableBalanceState> get outAvailableBalanceState =>
      _availableBalanceStateCtrl.stream;
  AvailableBalanceState get availableBalanceState => _availableBalanceState;
  set availableBalanceState(AvailableBalanceState state) {
    _availableBalanceState = state;
    _inAvailableBalanceState.add(_availableBalanceState);
  }

  TradePreimage? _preimage;
  final StreamController<TradePreimage?> _preimageCtrl =
      StreamController<TradePreimage?>.broadcast();
  Sink<TradePreimage?> get _inPreimage => _preimageCtrl.sink;
  Stream<TradePreimage?> get outPreimage => _preimageCtrl.stream;
  TradePreimage? get preimage => _preimage;
  set preimage(TradePreimage? tradePreimage) {
    _preimage = tradePreimage;
    _inPreimage.add(_preimage);
  }

  final List<DexFormError> _formErrors = [];
  final StreamController<List<DexFormError>> _formErrorsCtrl =
      StreamController.broadcast();
  Sink<List<DexFormError>> get _inFormErrors => _formErrorsCtrl.sink;
  Stream<List<DexFormError>> get outFormErrors => _formErrorsCtrl.stream;
  List<DexFormError> getFormErrors() => _formErrors;
  void _setFormErrors(List<DexFormError>? errors) {
    errors ??= [];
    _formErrors.clear();
    _formErrors.addAll(errors);
    _inFormErrors.add(_formErrors);
  }

  @override
  void dispose() {
    _inProgressCtrl.close();
    _showConfirmationCtrl.close();
    _sellCoinCtrl.close();
    _buyCoinCtrl.close();
    _sellAmountCtrl.close();
    _buyAmountCtrl.close();
    _priceCtrl.close();
    _isMaxActiveCtrl.close();
    _showSellCoinSelectCtrl.close();
    _showBuyCoinSelectCtrl.close();
    _formErrorsCtrl.close();
    _availableBalanceStateCtrl.close();
  }

  Timer? _maxSellAmountTimer;
  Future<void> _updateMaxSellAmountListener() async {
    _maxSellAmountTimer?.cancel();
    maxSellAmount = null;
    // Only show loading spinner when signed in
    final bool isSignedIn = await kdfSdk.auth.isSignedIn();
    availableBalanceState = isSignedIn
        ? AvailableBalanceState.loading
        : AvailableBalanceState.unavailable;
    isMaxActive = false;

    await _updateMaxSellAmount();
    _maxSellAmountTimer = Timer.periodic(const Duration(seconds: 10), (
      _,
    ) async {
      await _updateMaxSellAmount();
    });
  }

  Future<void> _updateMaxSellAmount() async {
    final Coin? coin = sellCoin;
    final bool isSignedIn = await kdfSdk.auth.isSignedIn();
    if (!isSignedIn) {
      maxSellAmount = null;
      availableBalanceState = AvailableBalanceState.unavailable;
      return;
    }

    if (availableBalanceState == AvailableBalanceState.initial) {
      availableBalanceState = AvailableBalanceState.loading;
    }

    if (coin == null) {
      maxSellAmount = null;
      availableBalanceState = AvailableBalanceState.unavailable;
      return;
    }

    final isAssetActive = await coinsRepository.isAssetActivated(coin.id);
    if (!isAssetActive) {
      // Intentionally leave in the loading state to avoid showing a "0.00" balance
      // while the asset is activating.
      maxSellAmount = null;
      availableBalanceState = AvailableBalanceState.loading;
      return;
    }

    Rational? amount = await dexRepository.getMaxMakerVolume(coin.abbr);
    if (amount != null) {
      maxSellAmount = amount;
      availableBalanceState = AvailableBalanceState.success;
    } else {
      amount = await _retryGetMaxMakerVolume(coin.abbr);
      maxSellAmount = amount;
      availableBalanceState = amount == null
          ? AvailableBalanceState.failure
          : AvailableBalanceState.success;
    }
  }

  Future<Rational?> _retryGetMaxMakerVolume(
    String coinTicker, {
    int maxAttempts = 5,
  }) async {
    try {
      return await retry(
        () => dexRepository.getMaxMakerVolume(coinTicker),
        maxAttempts: maxAttempts,
        backoffStrategy: const LinearBackoff(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> setMaxSellAmount() async {
    if (sellAmount == maxSellAmount) return;

    sellAmount = maxSellAmount;
    isMaxActive = maxSellAmount != null;
    _onSellAmountUpdated();
  }

  Future<void> setHalfSellAmount() async {
    if (maxSellAmount == null) return;

    final Rational halfAmount = maxSellAmount! / Rational.fromInt(2);
    if (sellAmount == halfAmount) return;

    sellAmount = halfAmount;
    isMaxActive = false;
    _onSellAmountUpdated();
  }

  Future<bool> validate() async {
    _setFormErrors(null);
    inProgress = true;

    if (!(await _validateFormFields())) {
      inProgress = false;
      return false;
    }

    if (!(await _validatePreimage())) {
      inProgress = false;
      return false;
    }

    inProgress = false;
    return true;
  }

  Future<bool> _validateFormFields() async {
    final DexFormError? sellItemError = await _validateSellFields();
    if (sellItemError != null) {
      _setFormErrors([sellItemError]);
      return false;
    }

    final DexFormError? buyItemError = await _validateBuyFields();
    if (buyItemError != null) {
      _setFormErrors([buyItemError]);
      return false;
    }

    final DexFormError? priceItemError = await _validatePriceField();
    if (priceItemError != null) {
      _setFormErrors([priceItemError]);
      return false;
    }

    return true;
  }

  Future<bool> _validatePreimage() async {
    inProgress = true;
    final tradePreimageData = await _getPreimageData();
    preimage = tradePreimageData?.data;
    inProgress = false;

    if (tradePreimageData == null) return false;

    final BaseError? error = tradePreimageData.error;
    if (error == null) return true;

    if (error is TradePreimageNotSufficientBalanceError) {
      _setFormErrors([
        DexFormError(
          error: LocaleKeys.dexBalanceNotSufficientError.tr(
            args: [
              error.coin,
              formatAmt(double.parse(error.required)),
              error.coin,
            ],
          ),
        ),
      ]);
    } else if (error is TradePreimageNotSufficientBaseCoinBalanceError) {
      _setFormErrors([
        DexFormError(
          error: LocaleKeys.dexBalanceNotSufficientError.tr(
            args: [
              error.coin,
              formatAmt(double.parse(error.required)),
              error.coin,
            ],
          ),
        ),
      ]);
    } else if (error is TradePreimageTransportError) {
      _setFormErrors([
        DexFormError(error: LocaleKeys.notEnoughBalanceForGasError.tr()),
      ]);
    } else {
      _setFormErrors([DexFormError(error: error.message)]);
    }

    return false;
  }

  Future<DexFormError?> _validatePriceField() async {
    final Rational? price = this.price;

    if (price == null) {
      return DexFormError(error: LocaleKeys.dexEnterPriceError.tr());
    } else if (price == Rational.zero) {
      return DexFormError(error: LocaleKeys.dexZeroPriceError.tr());
    }

    return null;
  }

  Future<DexFormError?> _validateBuyFields() async {
    final Coin? buyCoin = this.buyCoin;

    if (buyCoin == null) {
      return DexFormError(error: LocaleKeys.dexSelectBuyCoinError.tr());
    } else if (buyCoin.isSuspended) {
      return DexFormError(
        error: LocaleKeys.dexCoinSuspendedError.tr(args: [buyCoin.abbr]),
      );
    } else {
      final Coin? parentCoin = buyCoin.parentCoin;
      if (parentCoin != null && parentCoin.isSuspended) {
        return DexFormError(
          error: LocaleKeys.dexCoinSuspendedError.tr(args: [parentCoin.abbr]),
        );
      }
    }

    final Rational? buyAmount = this.buyAmount;
    if (buyAmount == null) {
      return DexFormError(error: LocaleKeys.dexEnterBuyAmountError.tr());
    } else {
      if (buyAmount.toDouble() == 0) {
        return DexFormError(error: LocaleKeys.dexZeroBuyAmountError.tr());
      }
    }

    return null;
  }

  Future<DexFormError?> _validateSellFields() async {
    final Coin? sellCoin = this.sellCoin;

    if (sellCoin == null) {
      return DexFormError(error: LocaleKeys.dexSelectSellCoinError.tr());
    } else if (sellCoin.isSuspended) {
      return DexFormError(
        error: LocaleKeys.dexCoinSuspendedError.tr(args: [sellCoin.abbr]),
      );
    }

    final Coin? parentCoin = sellCoin.parentCoin;
    if (parentCoin != null && parentCoin.isSuspended) {
      return DexFormError(
        error: LocaleKeys.dexCoinSuspendedError.tr(args: [parentCoin.abbr]),
      );
    }

    final Rational? sellAmount = this.sellAmount;

    if (sellAmount == null) {
      return DexFormError(error: LocaleKeys.dexEnterSellAmountError.tr());
    } else {
      if (sellAmount == Rational.zero) {
        return DexFormError(error: LocaleKeys.dexZeroSellAmountError.tr());
      } else {
        final Rational maxAmount = maxSellAmount ?? Rational.zero;
        if (maxAmount == Rational.zero) {
          return DexFormError(error: LocaleKeys.notEnoughFundsError.tr());
        } else if (sellAmount > maxAmount) {
          return DexFormError(
            error: LocaleKeys.dexMaxSellAmountError.tr(
              args: [formatAmt(maxAmount.toDouble()), sellCoin.abbr],
            ),
            type: DexFormErrorType.largerMaxSellVolume,
            action: DexFormErrorAction(
              text: LocaleKeys.setMax.tr(),
              callback: () async {
                await setMaxSellAmount();
              },
            ),
          );
        }
      }
    }

    return null;
  }

  Future<void> _autoActivate(Coin? coin) async {
    if (coin == null || !await kdfSdk.auth.isSignedIn()) return;
    inProgress = true;
    final List<DexFormError> activationErrors = await activateCoinIfNeeded(
      coin.abbr,
      coinsRepository,
    );
    inProgress = false;
    if (activationErrors.isNotEmpty) {
      _setFormErrors(activationErrors);
    }
  }

  Future<TextError?> makeOrder() async {
    if ((sellCoin?.walletOnly ?? true) || (buyCoin?.walletOnly ?? true)) {
      return TextError(error: LocaleKeys.dexUnableToStartSwap.tr());
    }

    final Map<String, dynamic>? response = await api.setprice(
      SetPriceRequest(
        base: sellCoin!.abbr,
        rel: buyCoin!.abbr,
        volume: sellAmount!,
        price: price!,
        max: isMaxActive,
      ),
    );

    if (response == null) {
      return TextError(error: LocaleKeys.somethingWrong.tr());
    }

    if (response['error'] != null) {
      return TextError(error: response['error']);
    }

    currentEntityUuid = response['result']['uuid'];

    return null;
  }

  void clear() {
    sellCoin = null;
    sellAmount = null;
    buyCoin = null;
    buyAmount = null;
    price = null;
    inProgress = false;
    showBuyCoinSelect = false;
    showSellCoinSelect = false;
    showConfirmation = false;
    isMaxActive = false;
    availableBalanceState = AvailableBalanceState.unavailable;
    _setFormErrors(null);
  }

  void setSellAmount(String? amountStr) {
    amountStr ??= '';
    Rational? amount;

    if (amountStr.isEmpty) {
      amount = null;
    } else {
      try {
        amount = parseLocaleAwareRational(amountStr);
      } catch (_) {
        amount = null;
      }
    }

    isMaxActive = false;

    if (amount == sellAmount) return;
    sellAmount = amount;

    _onSellAmountUpdated();
  }

  void setBuyAmount(String? amountStr) {
    amountStr ??= '';
    Rational? amount;

    if (amountStr.isEmpty) {
      amount = null;
    } else {
      try {
        amount = parseLocaleAwareRational(amountStr);
      } catch (_) {
        amount = null;
      }
    }

    if (amount == buyAmount) return;
    buyAmount = amount;
    _onBuyAmountUpdated();
  }

  void setPriceValue(String? priceStr) {
    priceStr ??= '';
    Rational? priceValue;

    if (priceStr.isEmpty) {
      priceValue = null;
    } else {
      priceValue = parseLocaleAwareRational(priceStr);
    }

    if (priceValue == price) return;
    price = priceValue;
    _onPriceUpdated();
  }

  void _onSellAmountUpdated() {
    final res = processBuyAmountAndPrice(sellAmount, price, buyAmount);
    if (res != null) {
      buyAmount = res.$1;
      price = res.$2;
    }
  }

  void _onBuyAmountUpdated() {
    if (buyAmount == null) return;
    if (price == null && sellAmount == null) return;
    try {
      price = buyAmount! / sellAmount!;
    } catch (_) {
      price = null;
    }
  }

  void _onPriceUpdated() {
    if (price == null) return;
    if (sellAmount == null && buyAmount == null) return;
    if (sellAmount != null) {
      buyAmount = sellAmount! * price!;
    } else if (buyAmount != null) {
      try {
        sellAmount = buyAmount! / price!;
      } catch (_) {
        sellAmount = null;
      }
    }
  }

  bool _fetchingPreimageData = false;
  Future<DataFromService<TradePreimage, BaseError>?> _getPreimageData() async {
    await pauseWhile(() => _fetchingPreimageData);

    await activateCoinIfNeeded(sellCoin?.abbr, coinsRepository);
    await activateCoinIfNeeded(buyCoin?.abbr, coinsRepository);

    final String? base = sellCoin?.abbr;
    final String? rel = buyCoin?.abbr;
    final Rational? price = this.price;
    final Rational? volume = sellAmount;

    if (base == null || rel == null || price == null || volume == null) {
      return null;
    }

    _fetchingPreimageData = true;
    final preimageData = await dexRepository.getTradePreimage(
      base,
      rel,
      price,
      'setprice',
      volume,
      isMaxActive,
    );
    _fetchingPreimageData = false;

    return preimageData;
  }

  Timer? _preimageDebounceTimer;
  Future<void> _updatePreimage() async {
    _preimageDebounceTimer?.cancel();

    _preimageDebounceTimer = Timer(const Duration(milliseconds: 300), () async {
      final tradePreimageData = await _getPreimageData();
      preimage = tradePreimageData?.data;
    });
  }

  int? _updateTimer;
  Future<void> _reValidate() async {
    if (_updateTimer != null) return;
    _updateTimer = DateTime.now().millisecondsSinceEpoch;

    while (inProgress &&
        DateTime.now().millisecondsSinceEpoch - _updateTimer! < 3000) {
      await Future<dynamic>.delayed(const Duration(milliseconds: 50));
    }

    await Future<dynamic>.delayed(const Duration(milliseconds: 200));
    _updateTimer = null;

    if (getFormErrors().isNotEmpty) {
      _setFormErrors(null);
      await _validateFormFields();
    }
  }

  Future<void> reInitForm() async {
    if (sellCoin != null) {
      sellCoin = coinsRepository.getCoin(sellCoin!.abbr);
    }
    if (buyCoin != null) buyCoin = coinsRepository.getCoin(buyCoin!.abbr);
  }

  void setDefaultSellCoin() {
    if (sellCoin != null) return;

    final Coin? defaultSellCoin = coinsRepository.getCoin(defaultDexCoin);
    if (defaultSellCoin == null) return;

    sellCoin = defaultSellCoin;
  }
}

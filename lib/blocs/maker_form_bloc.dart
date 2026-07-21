import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/analytics/events/advanced_trading_events.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/dex_repository.dart';
import 'package:web_dex/bloc/trading_status/trading_status_service.dart';
import 'package:web_dex/blocs/bloc_base.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trade_preimage/trade_preimage_errors.dart';
import 'package:web_dex/model/advanced_trade_preparation.dart';
import 'package:web_dex/model/available_balance_state.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/data_from_service.dart';
import 'package:web_dex/model/dex_form_error.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/model/trade_preimage.dart';
import 'package:web_dex/model/trading_entity_id.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/shared/utils/kdf_wallet_authority.dart';
import 'package:web_dex/views/dex/dex_helpers.dart';
import 'package:web_dex/views/dex/simple/form/error_list/dex_form_error_with_action.dart';

class MakerFormBloc implements BlocBase {
  static const int _maximumNumericInputLength = 128;
  static const Duration _preimageRequestDeadline = Duration(seconds: 15);

  MakerFormBloc({
    required this.api,
    required this.kdfSdk,
    required this.coinsRepository,
    required this.dexRepository,
    required this.analyticsBloc,
    this.tradingStatusService,
    this.finalSystemClockCheck,
    this.maxPreparedAge = const Duration(minutes: 2),
  }) {
    _authSubscription = kdfSdk.auth.watchCurrentUser().listen(
      (user) {
        if (_disposed) return;
        _authObservationEpoch++;
        _synchronizeWallet(user?.walletId.compoundId, forceSessionChange: true);
      },
      onError: (_) {
        if (_disposed) return;
        _authObservationEpoch++;
        _synchronizeWallet(null, forceSessionChange: true);
      },
      onDone: () {
        if (_disposed) return;
        _authObservationEpoch++;
        _synchronizeWallet(null, forceSessionChange: true);
      },
    );
    unawaited(_initializeWalletScope());
  }

  final Mm2Api api;
  final KomodoDefiSdk kdfSdk;
  final CoinsRepo coinsRepository;
  final DexRepository dexRepository;
  final AnalyticsBloc analyticsBloc;
  final TradingStatusService? tradingStatusService;
  final Future<bool> Function()? finalSystemClockCheck;
  final Duration maxPreparedAge;

  StreamSubscription<KdfUser?>? _authSubscription;
  bool _disposed = false;
  String? _walletId;
  int _walletGeneration = 0;
  int _authObservationEpoch = 0;
  int _submissionGeneration = 0;
  final Set<String> _walletsRequiringSubmissionReconciliation = {};
  int _formRevision = 0;
  Future<bool>? _validationInFlight;
  int _validationGeneration = 0;
  Future<TextError?>? _submissionInFlight;

  String currentEntityUuid = '';

  PreparedMakerOrder? _preparedOrder;
  final StreamController<PreparedMakerOrder?> _preparedOrderCtrl =
      StreamController<PreparedMakerOrder?>.broadcast();
  PreparedMakerOrder? get preparedOrder => _preparedOrder;
  Stream<PreparedMakerOrder?> get outPreparedOrder => _preparedOrderCtrl.stream;

  AdvancedTradeSubmissionStatus _submissionStatus =
      AdvancedTradeSubmissionStatus.idle;
  final StreamController<AdvancedTradeSubmissionStatus> _submissionStatusCtrl =
      StreamController<AdvancedTradeSubmissionStatus>.broadcast();
  AdvancedTradeSubmissionStatus get submissionStatus => _submissionStatus;
  Stream<AdvancedTradeSubmissionStatus> get outSubmissionStatus =>
      _submissionStatusCtrl.stream;

  AdvancedTradeSubmissionFailure? _submissionFailure;
  final StreamController<AdvancedTradeSubmissionFailure?>
  _submissionFailureCtrl =
      StreamController<AdvancedTradeSubmissionFailure?>.broadcast();
  AdvancedTradeSubmissionFailure? get submissionFailure => _submissionFailure;
  Stream<AdvancedTradeSubmissionFailure?> get outSubmissionFailure =>
      _submissionFailureCtrl.stream;

  String? get walletId => _walletId;
  int get formRevision => _formRevision;

  Future<void> _initializeWalletScope() async {
    final observationEpoch = _authObservationEpoch;
    try {
      final user = await kdfSdk.auth.currentUser;
      if (!_disposed && observationEpoch == _authObservationEpoch) {
        _synchronizeWallet(user?.walletId.compoundId);
      }
    } catch (_) {
      if (!_disposed && observationEpoch == _authObservationEpoch) {
        _synchronizeWallet(null);
      }
    }
  }

  void _synchronizeWallet(String? walletId, {bool forceSessionChange = false}) {
    if (_disposed || (!forceSessionChange && walletId == _walletId)) return;
    final previousWalletId = _walletId;
    if (previousWalletId != null &&
        (_submissionStatus == AdvancedTradeSubmissionStatus.uncertain ||
            _submissionStatus == AdvancedTradeSubmissionStatus.submitting)) {
      _walletsRequiringSubmissionReconciliation.add(previousWalletId);
    }
    _walletId = walletId;
    _walletGeneration++;
    _submissionGeneration++;
    _formRevision++;
    _maxSellAmountTimer?.cancel();
    _preimageDebounceTimer?.cancel();
    _revalidationDebounceTimer?.cancel();
    _resetFormState(
      preserveUncertain: false,
      balanceState: walletId == null
          ? AvailableBalanceState.unavailable
          : AvailableBalanceState.initial,
    );
    if (walletId != null &&
        _walletsRequiringSubmissionReconciliation.contains(walletId)) {
      _setSubmissionState(
        AdvancedTradeSubmissionStatus.uncertain,
        AdvancedTradeSubmissionFailure.uncertain,
      );
    }
  }

  void _invalidatePreparation() {
    if (_disposed) return;
    _formRevision++;
    if (_validationInFlight != null && _inProgress) {
      _inProgress = false;
      _inProgressCtrl.add(false);
    }
    _preparedOrder = null;
    _preparedOrderCtrl.add(null);
    if (_submissionStatus == AdvancedTradeSubmissionStatus.submitting) {
      if (_walletId != null) {
        _walletsRequiringSubmissionReconciliation.add(_walletId!);
      }
      _submissionStatus = AdvancedTradeSubmissionStatus.uncertain;
      _submissionFailure = AdvancedTradeSubmissionFailure.uncertain;
      _submissionStatusCtrl.add(_submissionStatus);
      _submissionFailureCtrl.add(_submissionFailure);
    } else if (_submissionStatus != AdvancedTradeSubmissionStatus.uncertain) {
      _submissionStatus = AdvancedTradeSubmissionStatus.idle;
      _submissionFailure = null;
      _submissionStatusCtrl.add(_submissionStatus);
      _submissionFailureCtrl.add(null);
    }
  }

  void _setPreparedOrder(PreparedMakerOrder? value) {
    if (_disposed) return;
    _preparedOrder = value;
    _preparedOrderCtrl.add(value);
  }

  void _setSubmissionState(
    AdvancedTradeSubmissionStatus status,
    AdvancedTradeSubmissionFailure? failure,
  ) {
    if (_disposed) return;
    if (status == AdvancedTradeSubmissionStatus.uncertain &&
        _walletId != null) {
      _walletsRequiringSubmissionReconciliation.add(_walletId!);
    } else if (status == AdvancedTradeSubmissionStatus.accepted &&
        _walletId != null) {
      _walletsRequiringSubmissionReconciliation.remove(_walletId!);
    }
    _submissionStatus = status;
    _submissionFailure = failure;
    _submissionStatusCtrl.add(status);
    _submissionFailureCtrl.add(failure);
  }

  void _resetFormState({
    required bool preserveUncertain,
    required AvailableBalanceState balanceState,
  }) {
    if (_disposed) return;
    final wasUncertain =
        preserveUncertain &&
        (_submissionStatus == AdvancedTradeSubmissionStatus.uncertain ||
            _submissionStatus == AdvancedTradeSubmissionStatus.submitting);
    _sellCoin = null;
    _buyCoin = null;
    _sellAmount = null;
    _buyAmount = null;
    _price = null;
    _maxSellAmount = null;
    _preimage = null;
    _isMaxActive = false;
    _inProgress = false;
    _showConfirmation = false;
    _showSellCoinSelect = false;
    _showBuyCoinSelect = false;
    _availableBalanceState = balanceState;
    _preparedOrder = null;
    currentEntityUuid = '';
    _formErrors.clear();

    _sellCoinCtrl.add(null);
    _buyCoinCtrl.add(null);
    _sellAmountCtrl.add(null);
    _buyAmountCtrl.add(null);
    _priceCtrl.add(null);
    _maxSellAmountCtrl.add(null);
    _preimageCtrl.add(null);
    _isMaxActiveCtrl.add(false);
    _inProgressCtrl.add(false);
    _showConfirmationCtrl.add(false);
    _showSellCoinSelectCtrl.add(false);
    _showBuyCoinSelectCtrl.add(false);
    _availableBalanceStateCtrl.add(balanceState);
    _preparedOrderCtrl.add(null);
    _formErrorsCtrl.add(const []);
    _setSubmissionState(
      wasUncertain
          ? AdvancedTradeSubmissionStatus.uncertain
          : AdvancedTradeSubmissionStatus.idle,
      wasUncertain ? AdvancedTradeSubmissionFailure.uncertain : null,
    );
  }

  bool _showConfirmation = false;
  final StreamController<bool> _showConfirmationCtrl =
      StreamController.broadcast();
  Sink<bool> get _inShowConfirmation => _showConfirmationCtrl.sink;
  Stream<bool> get outShowConfirmation => _showConfirmationCtrl.stream;
  bool get showConfirmation => _showConfirmation;
  set showConfirmation(bool value) {
    if (_disposed) return;
    if (value && _preparedOrder == null) return;
    if (!value && _showConfirmation) _invalidatePreparation();
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
    if (_disposed) return;
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
    if (_disposed) return;
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
    if (_disposed) return;
    _inProgress = value;
    _inInProgress.add(_inProgress);
  }

  bool _isMaxActive = false;
  final StreamController<bool> _isMaxActiveCtrl = StreamController.broadcast();
  Sink<bool> get _inIsMaxActive => _isMaxActiveCtrl.sink;
  Stream<bool> get outIsMaxActive => _isMaxActiveCtrl.stream;
  bool get isMaxActive => _isMaxActive;
  set isMaxActive(bool value) {
    if (_disposed || value == _isMaxActive) return;
    _invalidatePreparation();
    _isMaxActive = value;
    _inIsMaxActive.add(_isMaxActive);
  }

  Coin? _sellCoin;
  final StreamController<Coin?> _sellCoinCtrl = StreamController.broadcast();
  Sink<Coin?> get _inSellCoin => _sellCoinCtrl.sink;
  Stream<Coin?> get outSellCoin => _sellCoinCtrl.stream;
  Coin? get sellCoin => _sellCoin;
  set sellCoin(Coin? coin) {
    if (_disposed) return;
    if (coin?.id != _sellCoin?.id) _invalidatePreparation();
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
    if (_disposed) return;
    if (coin?.id != _buyCoin?.id) _invalidatePreparation();
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
    if (_disposed || amount == _sellAmount) return;
    _invalidatePreparation();
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
    if (_disposed || amount == _buyAmount) return;
    _invalidatePreparation();
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
    if (_disposed || price == _price) return;
    _invalidatePreparation();
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
    if (_disposed) return;
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
    if (_disposed) return;
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
    if (_disposed) return;
    _preimage = tradePreimage;
    _inPreimage.add(_preimage);
  }

  final List<DexFormError> _formErrors = [];
  final StreamController<List<DexFormError>> _formErrorsCtrl =
      StreamController.broadcast();
  Sink<List<DexFormError>> get _inFormErrors => _formErrorsCtrl.sink;
  Stream<List<DexFormError>> get outFormErrors => _formErrorsCtrl.stream;
  List<DexFormError> getFormErrors() =>
      List<DexFormError>.unmodifiable(_formErrors);
  void _setFormErrors(List<DexFormError>? errors) {
    if (_disposed) return;
    errors ??= [];
    _formErrors.clear();
    _formErrors.addAll(errors);
    _inFormErrors.add(List<DexFormError>.unmodifiable(_formErrors));
  }

  bool _matchesValidationScope(_MakerValidationScope scope) {
    return !_disposed &&
        scope.validationGeneration == _validationGeneration &&
        scope.walletId == _walletId &&
        scope.walletGeneration == _walletGeneration &&
        scope.formRevision == _formRevision &&
        scope.sellCoinId == sellCoin?.id &&
        scope.buyCoinId == buyCoin?.id &&
        scope.volume == sellAmount &&
        scope.price == price &&
        scope.max == isMaxActive;
  }

  void _setFormErrorsFor(
    _MakerValidationScope scope,
    List<DexFormError>? errors,
  ) {
    if (_matchesValidationScope(scope)) _setFormErrors(errors);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _walletGeneration++;
    _maxSellAmountTimer?.cancel();
    _preimageDebounceTimer?.cancel();
    _revalidationDebounceTimer?.cancel();
    unawaited(_authSubscription?.cancel());
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
    _maxSellAmountCtrl.close();
    _preimageCtrl.close();
    _preparedOrderCtrl.close();
    _submissionStatusCtrl.close();
    _submissionFailureCtrl.close();
  }

  Timer? _maxSellAmountTimer;
  Future<void> _updateMaxSellAmountListener() async {
    if (_disposed) return;
    final walletId = _walletId;
    final generation = _walletGeneration;
    final coinId = sellCoin?.id;
    _maxSellAmountTimer?.cancel();
    maxSellAmount = null;
    // Only show loading spinner when signed in. Authentication uncertainty is
    // represented as unavailable rather than escaping an unhandled Future.
    bool isSignedIn;
    try {
      isSignedIn = await kdfSdk.auth.isSignedIn();
    } catch (_) {
      isSignedIn = false;
    }
    if (!_matchesScope(walletId, generation, coinId)) return;
    availableBalanceState = isSignedIn
        ? AvailableBalanceState.loading
        : AvailableBalanceState.unavailable;
    isMaxActive = false;

    await _updateMaxSellAmount();
    if (!_matchesScope(walletId, generation, coinId)) return;
    _maxSellAmountTimer = Timer.periodic(const Duration(seconds: 10), (
      _,
    ) async {
      await _updateMaxSellAmount();
    });
  }

  Future<void> _updateMaxSellAmount() async {
    if (_disposed) return;
    final Coin? coin = sellCoin;
    final walletId = _walletId;
    final generation = _walletGeneration;
    try {
      final bool isSignedIn = await kdfSdk.auth.isSignedIn();
      if (!_matchesScope(walletId, generation, coin?.id)) return;
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
      if (!_matchesScope(walletId, generation, coin.id)) return;
      if (!isAssetActive) {
        // Intentionally leave in the loading state to avoid showing a "0.00"
        // balance while the asset is activating.
        maxSellAmount = null;
        availableBalanceState = AvailableBalanceState.loading;
        return;
      }

      Rational? amount = await dexRepository.getMaxMakerVolume(coin.abbr);
      if (!_matchesScope(walletId, generation, coin.id)) return;
      if (amount != null && amount >= Rational.zero) {
        maxSellAmount = amount;
        availableBalanceState = AvailableBalanceState.success;
      } else {
        amount = await _retryGetMaxMakerVolume(coin.abbr);
        if (!_matchesScope(walletId, generation, coin.id)) return;
        final validAmount = amount != null && amount >= Rational.zero
            ? amount
            : null;
        maxSellAmount = validAmount;
        availableBalanceState = validAmount == null
            ? AvailableBalanceState.failure
            : AvailableBalanceState.success;
      }
    } catch (_) {
      if (_matchesScope(walletId, generation, coin?.id)) {
        maxSellAmount = null;
        availableBalanceState = AvailableBalanceState.failure;
      }
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

  Future<bool> validate() {
    if (_disposed ||
        _submissionStatus == AdvancedTradeSubmissionStatus.uncertain) {
      return Future.value(false);
    }
    final existing = _validationInFlight;
    if (existing != null) return existing;

    final operation = _validateAndPrepare();
    _validationInFlight = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(_validationInFlight, operation)) {
          _validationInFlight = null;
        }
      }),
    );
    return operation;
  }

  Future<bool> _validateAndPrepare() async {
    final walletId = _walletId;
    final walletGeneration = _walletGeneration;
    final revision = _formRevision;
    final capturedSellCoin = sellCoin;
    final capturedBuyCoin = buyCoin;
    final capturedVolume = sellAmount;
    final capturedPrice = price;
    final capturedMax = isMaxActive;
    final scope = _MakerValidationScope(
      walletId: walletId,
      walletGeneration: walletGeneration,
      formRevision: revision,
      validationGeneration: ++_validationGeneration,
      sellCoinId: capturedSellCoin?.id,
      buyCoinId: capturedBuyCoin?.id,
      volume: capturedVolume,
      price: capturedPrice,
      max: capturedMax,
    );

    _setFormErrorsFor(scope, null);
    inProgress = true;
    try {
      if (walletId == null || !(await _validateFormFields(scope))) return false;

      final validatedPreimage = await _validatePreimage(scope);
      if (validatedPreimage == null) return false;

      final user = await kdfSdk.auth.currentUser;
      final isCurrent =
          _matchesValidationScope(scope) &&
          user?.walletId.compoundId == walletId;
      if (!isCurrent ||
          capturedSellCoin == null ||
          capturedBuyCoin == null ||
          capturedVolume == null ||
          capturedPrice == null) {
        return false;
      }

      try {
        final prepared = PreparedMakerOrder(
          walletId: walletId,
          formRevision: revision,
          baseAssetId: capturedSellCoin.id,
          relAssetId: capturedBuyCoin.id,
          base: capturedSellCoin.abbr,
          rel: capturedBuyCoin.abbr,
          volume: capturedVolume,
          price: capturedPrice,
          max: capturedMax,
          preimage: validatedPreimage,
        );
        _setPreparedOrder(prepared);
        _setSubmissionState(AdvancedTradeSubmissionStatus.prepared, null);
        preimage = prepared.preimage;
        return true;
      } on ArgumentError {
        if (_matchesValidationScope(scope)) {
          _setSubmissionState(
            AdvancedTradeSubmissionStatus.failed,
            AdvancedTradeSubmissionFailure.preparationInvalid,
          );
        }
        return false;
      }
    } catch (_) {
      if (_matchesValidationScope(scope)) {
        _setSubmissionState(
          AdvancedTradeSubmissionStatus.failed,
          AdvancedTradeSubmissionFailure.unknown,
        );
      }
      return false;
    } finally {
      if (_matchesValidationScope(scope)) {
        inProgress = false;
      }
    }
  }

  Future<bool> _validateFormFields(_MakerValidationScope scope) async {
    if (!_matchesValidationScope(scope)) return false;
    final DexFormError? sellItemError = await _validateSellFields();
    if (!_matchesValidationScope(scope)) return false;
    if (sellItemError != null) {
      _setFormErrorsFor(scope, [sellItemError]);
      return false;
    }

    final DexFormError? buyItemError = await _validateBuyFields();
    if (!_matchesValidationScope(scope)) return false;
    if (buyItemError != null) {
      _setFormErrorsFor(scope, [buyItemError]);
      return false;
    }

    final DexFormError? priceItemError = await _validatePriceField();
    if (!_matchesValidationScope(scope)) return false;
    if (priceItemError != null) {
      _setFormErrorsFor(scope, [priceItemError]);
      return false;
    }

    return true;
  }

  Future<TradePreimage?> _validatePreimage(_MakerValidationScope scope) async {
    if (!_matchesValidationScope(scope)) return null;
    inProgress = true;
    final tradePreimageData = await _getPreimageData();
    if (!_matchesValidationScope(scope)) return null;
    preimage = tradePreimageData?.data;

    if (tradePreimageData == null) {
      _setFormErrorsFor(scope, [
        DexFormError(error: LocaleKeys.somethingWrong.tr()),
      ]);
      return null;
    }

    final BaseError? error = tradePreimageData.error;
    if (error == null) return tradePreimageData.data;

    if (error is TradePreimageNotSufficientBalanceError) {
      _setFormErrorsFor(scope, [
        _insufficientPreimageBalanceError(error.coin, error.required),
      ]);
    } else if (error is TradePreimageNotSufficientBaseCoinBalanceError) {
      _setFormErrorsFor(scope, [
        _insufficientPreimageBalanceError(error.coin, error.required),
      ]);
    } else if (error is TradePreimageTransportError) {
      _setFormErrorsFor(scope, [
        DexFormError(error: LocaleKeys.notEnoughBalanceForGasError.tr()),
      ]);
    } else {
      _setFormErrorsFor(scope, [
        DexFormError(error: LocaleKeys.somethingWrong.tr()),
      ]);
    }

    return null;
  }

  Future<DexFormError?> _validatePriceField() async {
    final Rational? price = this.price;

    if (price == null) {
      return DexFormError(error: LocaleKeys.dexEnterPriceError.tr());
    } else if (price <= Rational.zero) {
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
    } else if (buyAmount <= Rational.zero) {
      return DexFormError(error: LocaleKeys.dexZeroBuyAmountError.tr());
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
      if (sellAmount <= Rational.zero) {
        return DexFormError(error: LocaleKeys.dexZeroSellAmountError.tr());
      } else {
        final Rational maxAmount = maxSellAmount ?? Rational.zero;
        if (maxAmount == Rational.zero) {
          return DexFormError(error: LocaleKeys.notEnoughFundsError.tr());
        } else if (sellAmount > maxAmount) {
          return DexFormError(
            error: LocaleKeys.dexMaxSellAmountError.tr(
              args: [formatDexAmt(maxAmount), sellCoin.abbr],
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
    if (_disposed || coin == null) return;
    final walletId = _walletId;
    final generation = _walletGeneration;
    if (walletId == null) return;
    List<DexFormError> activationErrors = const [];
    try {
      await _requireAssetActivationScope(walletId, generation, coin.id);
      inProgress = true;
      activationErrors = await activateCoinIfNeeded(
        coin.abbr,
        coinsRepository,
        activationScopeKey: 'maker:$walletId:$generation:${coin.id}',
        beforeActivationMutation: () =>
            _requireAssetActivationScope(walletId, generation, coin.id),
      );
      await _requireAssetActivationScope(walletId, generation, coin.id);
    } catch (_) {
      return;
    } finally {
      if (_matchesAssetScope(walletId, generation, coin.id)) inProgress = false;
    }
    if (_matchesAssetScope(walletId, generation, coin.id) &&
        activationErrors.isNotEmpty) {
      _setFormErrors(activationErrors);
    }
  }

  Future<void> _requireAssetActivationScope(
    String walletId,
    int generation,
    Object coinId,
  ) async {
    if (!_matchesAssetScope(walletId, generation, coinId)) {
      throw const KdfWalletAuthorityUnavailable();
    }
    final currentWalletId = await freshKdfCurrentWalletId(kdfSdk);
    if (currentWalletId != walletId ||
        !_matchesAssetScope(walletId, generation, coinId)) {
      throw const KdfWalletAuthorityUnavailable();
    }
  }

  Future<TextError?> makeOrder() {
    final existing = _submissionInFlight;
    if (existing != null) return existing;

    final operation = _makePreparedOrder();
    _submissionInFlight = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(_submissionInFlight, operation)) {
          _submissionInFlight = null;
        }
      }),
    );
    return operation;
  }

  Future<TextError?> _makePreparedOrder() async {
    final prepared = _preparedOrder;
    final submissionGeneration = _submissionGeneration;
    if (_disposed ||
        prepared == null ||
        _submissionStatus == AdvancedTradeSubmissionStatus.uncertain ||
        _submissionStatus == AdvancedTradeSubmissionStatus.accepted) {
      return TextError(error: LocaleKeys.somethingWrong.tr());
    }

    final gateFailure = await _submissionGateFailure(prepared);
    if (!_isCurrentPreparedSubmission(prepared, submissionGeneration)) {
      return TextError(error: LocaleKeys.somethingWrong.tr());
    }
    if (gateFailure != null) {
      if (gateFailure == AdvancedTradeSubmissionFailure.walletChanged ||
          gateFailure == AdvancedTradeSubmissionFailure.preparationExpired ||
          gateFailure == AdvancedTradeSubmissionFailure.preparationInvalid) {
        _setPreparedOrder(null);
      }
      _setSubmissionState(AdvancedTradeSubmissionStatus.failed, gateFailure);
      return TextError(error: LocaleKeys.somethingWrong.tr());
    }

    final preRpcWalletId = await _currentWalletId();
    if (preRpcWalletId != prepared.walletId ||
        !_isCurrentPreparedSubmission(prepared, submissionGeneration)) {
      return TextError(error: LocaleKeys.somethingWrong.tr());
    }

    _setSubmissionState(AdvancedTradeSubmissionStatus.submitting, null);
    inProgress = true;
    analyticsBloc.add(
      AnalyticsAdvancedTradeLifecycleEvent(
        kind: AdvancedTradeKind.makerOrder,
        outcome: AdvancedTradeOutcome.initiated,
      ),
    );
    final submissionClock = Stopwatch()..start();
    try {
      final Map<String, dynamic>? response = await api.setprice(
        prepared.toRequest(),
        beforeMutation: () async {
          if (!_isCurrentPreparedSubmission(prepared, submissionGeneration) ||
              await freshKdfCurrentWalletId(kdfSdk) != prepared.walletId ||
              !_isCurrentPreparedSubmission(prepared, submissionGeneration)) {
            throw const KdfWalletAuthorityUnavailable();
          }
        },
      );
      final result = response?['result'];
      final uuid = result is Map<String, dynamic>
          ? normalizeTradingEntityUuid(result['uuid'])
          : null;
      final postRpcWalletId = await _currentWalletId();
      if (!_isCurrentPreparedSubmission(prepared, submissionGeneration)) {
        return TextError(error: LocaleKeys.somethingWrong.tr());
      }
      if (postRpcWalletId != prepared.walletId) {
        _setPreparedOrder(null);
        _markMakerSubmissionUncertain(submissionClock.elapsed);
        return TextError(error: LocaleKeys.somethingWrong.tr());
      }
      if (response == null ||
          response['error'] != null ||
          uuid == null ||
          uuid.isEmpty) {
        _setPreparedOrder(null);
        _markMakerSubmissionUncertain(submissionClock.elapsed);
        return TextError(error: LocaleKeys.somethingWrong.tr());
      }

      currentEntityUuid = uuid;
      _setSubmissionState(AdvancedTradeSubmissionStatus.accepted, null);
      return null;
    } on KdfWalletAuthorityUnavailable {
      if (_isCurrentPreparedSubmission(prepared, submissionGeneration)) {
        _setPreparedOrder(null);
        _setSubmissionState(
          AdvancedTradeSubmissionStatus.failed,
          AdvancedTradeSubmissionFailure.walletChanged,
        );
      }
      return TextError(error: LocaleKeys.somethingWrong.tr());
    } catch (_) {
      final postRpcWalletId = await _currentWalletId();
      if (!_isCurrentPreparedSubmission(prepared, submissionGeneration)) {
        return TextError(error: LocaleKeys.somethingWrong.tr());
      }
      if (postRpcWalletId != prepared.walletId) {
        _setPreparedOrder(null);
        _markMakerSubmissionUncertain(submissionClock.elapsed);
        return TextError(error: LocaleKeys.somethingWrong.tr());
      }
      _setPreparedOrder(null);
      _markMakerSubmissionUncertain(submissionClock.elapsed);
      return TextError(error: LocaleKeys.somethingWrong.tr());
    } finally {
      if (!_disposed &&
          submissionGeneration == _submissionGeneration &&
          prepared.walletId == _walletId) {
        inProgress = false;
      }
    }
  }

  void _markMakerSubmissionUncertain(Duration duration) {
    _setSubmissionState(
      AdvancedTradeSubmissionStatus.uncertain,
      AdvancedTradeSubmissionFailure.uncertain,
    );
    analyticsBloc.add(
      AnalyticsAdvancedTradeLifecycleEvent(
        kind: AdvancedTradeKind.makerOrder,
        outcome: AdvancedTradeOutcome.uncertain,
        durationBucket: advancedTradeDurationBucket(duration),
      ),
    );
  }

  bool _isCurrentPreparedSubmission(
    PreparedMakerOrder prepared,
    int submissionGeneration,
  ) {
    return !_disposed &&
        submissionGeneration == _submissionGeneration &&
        prepared == _preparedOrder &&
        prepared.walletId == _walletId &&
        prepared.formRevision == _formRevision;
  }

  Future<String?> _currentWalletId() async {
    try {
      return await freshKdfCurrentWalletId(kdfSdk);
    } catch (_) {
      return null;
    }
  }

  Future<AdvancedTradeSubmissionFailure?> _submissionGateFailure(
    PreparedMakerOrder prepared,
  ) async {
    if (!prepared.isFreshAt(DateTime.timestamp(), maxAge: maxPreparedAge)) {
      return AdvancedTradeSubmissionFailure.preparationExpired;
    }
    if (prepared != _preparedOrder ||
        prepared.walletId != _walletId ||
        prepared.formRevision != _formRevision) {
      return AdvancedTradeSubmissionFailure.preparationInvalid;
    }
    final currentWalletId = await _currentWalletId();
    if (currentWalletId != prepared.walletId) {
      return AdvancedTradeSubmissionFailure.walletChanged;
    }

    final service = tradingStatusService;
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

    final clockCheck = finalSystemClockCheck;
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
    if (_disposed ||
        prepared != _preparedOrder ||
        prepared.walletId != _walletId ||
        prepared.formRevision != _formRevision) {
      return AdvancedTradeSubmissionFailure.preparationInvalid;
    }
    if (!prepared.isFreshAt(DateTime.timestamp(), maxAge: maxPreparedAge)) {
      return AdvancedTradeSubmissionFailure.preparationExpired;
    }
    return null;
  }

  void clear() {
    if (_disposed) return;
    _formRevision++;
    _maxSellAmountTimer?.cancel();
    _preimageDebounceTimer?.cancel();
    _revalidationDebounceTimer?.cancel();
    _resetFormState(
      preserveUncertain: true,
      balanceState: AvailableBalanceState.unavailable,
    );
  }

  void setSellAmount(String? amountStr) {
    amountStr ??= '';
    Rational? amount;

    if (amountStr.isEmpty) {
      amount = null;
    } else if (amountStr.length > _maximumNumericInputLength) {
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
    } else if (amountStr.length > _maximumNumericInputLength) {
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
    } else if (priceStr.length > _maximumNumericInputLength) {
      priceValue = null;
    } else {
      try {
        priceValue = parseLocaleAwareRational(priceStr);
      } catch (_) {
        priceValue = null;
      }
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

  Future<DataFromService<TradePreimage, BaseError>?> _getPreimageData() async {
    final String? base = sellCoin?.abbr;
    final String? rel = buyCoin?.abbr;
    final Rational? price = this.price;
    final Rational? volume = sellAmount;
    final max = isMaxActive;
    final walletId = _walletId;
    final generation = _walletGeneration;
    final revision = _formRevision;

    if (_disposed ||
        walletId == null ||
        base == null ||
        rel == null ||
        price == null ||
        volume == null) {
      return null;
    }

    try {
      final preimageData = await (() async {
        await _requirePreparationActivationScope(
          walletId,
          generation,
          revision,
          base,
          rel,
          price,
          volume,
          max,
        );
        final baseErrors = await activateCoinIfNeeded(
          base,
          coinsRepository,
          activationScopeKey:
              'maker-preimage:$walletId:$generation:$revision:$base',
          beforeActivationMutation: () => _requirePreparationActivationScope(
            walletId,
            generation,
            revision,
            base,
            rel,
            price,
            volume,
            max,
          ),
        );
        await _requirePreparationActivationScope(
          walletId,
          generation,
          revision,
          base,
          rel,
          price,
          volume,
          max,
        );
        if (baseErrors.isNotEmpty) return null;
        final relErrors = await activateCoinIfNeeded(
          rel,
          coinsRepository,
          activationScopeKey:
              'maker-preimage:$walletId:$generation:$revision:$rel',
          beforeActivationMutation: () => _requirePreparationActivationScope(
            walletId,
            generation,
            revision,
            base,
            rel,
            price,
            volume,
            max,
          ),
        );
        await _requirePreparationActivationScope(
          walletId,
          generation,
          revision,
          base,
          rel,
          price,
          volume,
          max,
        );
        if (relErrors.isNotEmpty) {
          return null;
        }
        return dexRepository.getTradePreimage(
          base,
          rel,
          price,
          'setprice',
          volume,
          max,
        );
      })().timeout(_preimageRequestDeadline);
      return _matchesPreparation(
            walletId,
            generation,
            revision,
            base,
            rel,
            price,
            volume,
            max,
          )
          ? preimageData
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _requirePreparationActivationScope(
    String walletId,
    int generation,
    int revision,
    String base,
    String rel,
    Rational price,
    Rational volume,
    bool max,
  ) async {
    if (!_matchesPreparation(
      walletId,
      generation,
      revision,
      base,
      rel,
      price,
      volume,
      max,
    )) {
      throw const KdfWalletAuthorityUnavailable();
    }
    final currentWalletId = await freshKdfCurrentWalletId(kdfSdk);
    if (currentWalletId != walletId ||
        !_matchesPreparation(
          walletId,
          generation,
          revision,
          base,
          rel,
          price,
          volume,
          max,
        )) {
      throw const KdfWalletAuthorityUnavailable();
    }
  }

  bool _matchesScope(String? walletId, int generation, Object? coinId) {
    return !_disposed &&
        walletId == _walletId &&
        generation == _walletGeneration &&
        coinId == sellCoin?.id;
  }

  bool _matchesAssetScope(String? walletId, int generation, Object? coinId) {
    return !_disposed &&
        walletId == _walletId &&
        generation == _walletGeneration &&
        (coinId == sellCoin?.id || coinId == buyCoin?.id);
  }

  bool _matchesPreparation(
    String walletId,
    int generation,
    int revision,
    String base,
    String rel,
    Rational price,
    Rational volume,
    bool max,
  ) {
    return !_disposed &&
        walletId == _walletId &&
        generation == _walletGeneration &&
        revision == _formRevision &&
        base == sellCoin?.abbr &&
        rel == buyCoin?.abbr &&
        price == this.price &&
        volume == sellAmount &&
        max == isMaxActive;
  }

  Timer? _preimageDebounceTimer;
  Future<void> _updatePreimage() async {
    if (_disposed) return;
    _preimageDebounceTimer?.cancel();

    _preimageDebounceTimer = Timer(const Duration(milliseconds: 300), () async {
      final tradePreimageData = await _getPreimageData();
      if (!_disposed && tradePreimageData != null) {
        preimage = tradePreimageData.data;
      }
    });
  }

  Timer? _revalidationDebounceTimer;
  int _revalidationRequestGeneration = 0;

  Future<void> _reValidate() async {
    if (_disposed) return;
    final requestGeneration = ++_revalidationRequestGeneration;
    _revalidationDebounceTimer?.cancel();
    _revalidationDebounceTimer = Timer(const Duration(milliseconds: 200), () {
      unawaited(_runRevalidation(requestGeneration));
    });
  }

  Future<void> _runRevalidation(int requestGeneration) async {
    final wait = Stopwatch()..start();
    while (!_disposed &&
        requestGeneration == _revalidationRequestGeneration &&
        inProgress &&
        wait.elapsed < const Duration(seconds: 3)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (_disposed || requestGeneration != _revalidationRequestGeneration) {
      return;
    }

    if (_validationInFlight == null && getFormErrors().isNotEmpty) {
      _setFormErrors(null);
      final scope = _MakerValidationScope(
        walletId: _walletId,
        walletGeneration: _walletGeneration,
        formRevision: _formRevision,
        validationGeneration: ++_validationGeneration,
        sellCoinId: sellCoin?.id,
        buyCoinId: buyCoin?.id,
        volume: sellAmount,
        price: price,
        max: isMaxActive,
      );
      try {
        await _validateFormFields(scope);
      } catch (_) {
        if (_matchesValidationScope(scope)) {
          _setFormErrorsFor(scope, [
            DexFormError(error: LocaleKeys.somethingWrong.tr()),
          ]);
        }
      }
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

  String _safeAssetLabel(String value) {
    final candidate = value.trim();
    if (candidate.isNotEmpty &&
        candidate.length <= 64 &&
        RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(candidate)) {
      return candidate;
    }
    return sellCoin?.abbr ?? '';
  }

  DexFormError _insufficientPreimageBalanceError(
    String coin,
    String requiredValue,
  ) {
    final required = _boundedPositiveRational(requiredValue);
    if (required == null) {
      return DexFormError(error: LocaleKeys.somethingWrong.tr());
    }
    final asset = _safeAssetLabel(coin);
    return DexFormError(
      error: LocaleKeys.dexBalanceNotSufficientError.tr(
        args: [asset, formatDexAmt(required), asset],
      ),
    );
  }

  Rational? _boundedPositiveRational(String value) {
    final candidate = value.trim();
    if (candidate.isEmpty || candidate.length > _maximumNumericInputLength) {
      return null;
    }
    final parsed = Rational.tryParse(candidate);
    return parsed != null && parsed > Rational.zero ? parsed : null;
  }
}

class _MakerValidationScope {
  const _MakerValidationScope({
    required this.walletId,
    required this.walletGeneration,
    required this.formRevision,
    required this.validationGeneration,
    required this.sellCoinId,
    required this.buyCoinId,
    required this.volume,
    required this.price,
    required this.max,
  });

  final String? walletId;
  final int walletGeneration;
  final int formRevision;
  final int validationGeneration;
  final AssetId? sellCoinId;
  final AssetId? buyCoinId;
  final Rational? volume;
  final Rational? price;
  final bool max;
}

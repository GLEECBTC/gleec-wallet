import 'dart:convert';
import 'dart:io' show Platform;

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:collection/collection.dart';
import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:formz/formz.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart' show KomodoDefiSdk;
import 'package:komodo_defi_types/komodo_defi_type_utils.dart'
    show ConstantBackoff, retry;
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/fiat/base_fiat_provider.dart';
import 'package:web_dex/bloc/fiat/fiat_order_status.dart';
import 'package:web_dex/bloc/fiat/fiat_repository.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/fiat/models/models.dart';
import 'package:web_dex/bloc/fiat/payment_status_type.dart';
import 'package:web_dex/model/forms/fiat/currency_input.dart';
import 'package:web_dex/model/forms/fiat/fiat_amount_input.dart';
import 'package:web_dex/model/kdf_auth_metadata_extension.dart';
import 'package:web_dex/shared/utils/extensions/string_extensions.dart';
import 'package:web_dex/views/fiat/webview_dialog.dart' show WebViewDialogMode;

part 'fiat_form_event.dart';
part 'fiat_form_state.dart';

class FiatFormBloc extends Bloc<FiatFormEvent, FiatFormState> {
  FiatFormBloc({
    required FiatRepository repository,
    required CoinsRepo coinsRepo,
    required KomodoDefiSdk sdk,
    int pubkeysMaxRetryAttempts = 20,
    Duration pubkeysRetryDelay = const Duration(milliseconds: 500),
  }) : _fiatRepository = repository,
       _coinsRepo = coinsRepo,
       _sdk = sdk,
       _pubkeysMaxRetryAttempts = pubkeysMaxRetryAttempts,
       _pubkeysRetryDelay = pubkeysRetryDelay,
       super(FiatFormState.initial()) {
    on<FiatFormFiatSelected>(_onFiatSelected);
    // Use restartable here since this is called for auth changes, which
    // can happen frequently and we want to avoid race conditions.
    on<FiatFormCoinSelected>(_onCoinSelected, transformer: restartable());
    on<FiatFormPaymentMethodSelected>(_onPaymentMethodSelected);
    // Use droppable here to prevent multiple simultaneous submissions
    on<FiatFormSubmitted>(_onFormSubmitted, transformer: droppable());
    on<FiatFormPaymentStatusMessageReceived>(_onPaymentStatusMessage);
    on<FiatFormModeUpdated>(_onModeUpdated);
    on<FiatFormResetRequested>(_onAccountCleared);
    on<FiatFormCoinAddressSelected>(_onCoinAddressSelected);
    on<FiatFormWebViewClosed>(_onWebViewClosed);
    on<FiatFormAssetAddressUpdated>(_onAssetAddressUpdated);

    // Use restartable for these events to ensure that the latest
    // user inputs are reflected and that those latest inputs are
    // used to update the state. This prevents race conditions that
    // could occur if the user changes inputs rapidly, resulting in
    // outdated (unexptected) state updates.
    on<FiatFormAmountUpdated>(_onAmountUpdated, transformer: restartable());
    on<FiatFormPaymentMethodsRefreshRequested>(
      _onPaymentMethodsChanged,
      transformer: restartable(),
    );
    on<FiatFormCurrenciesRefreshRequested>(
      _onCurrenciesFetched,
      transformer: restartable(),
    );
    on<FiatFormOrderStatusWatchStarted>(
      _onOrderStatusWatchStarted,
      transformer: restartable(),
    );
  }

  final FiatRepository _fiatRepository;
  final CoinsRepo _coinsRepo;
  final KomodoDefiSdk _sdk;
  final int _pubkeysMaxRetryAttempts;
  final Duration _pubkeysRetryDelay;
  final _log = Logger('FiatFormBloc');

  Future<void> _onFiatSelected(
    FiatFormFiatSelected event,
    Emitter<FiatFormState> emit,
  ) async {
    emit(
      state.copyWith(
        selectedFiat: CurrencyInput.dirty(event.selectedFiat),
        // Show the loading indicator for payment methods
        // after switching fiat currency since there is no
        // other indicator, and the payment methods have to be
        // updated before the user can proceed
        status: FiatFormStatus.loading,
      ),
    );
  }

  Future<void> _onCoinSelected(
    FiatFormCoinSelected event,
    Emitter<FiatFormState> emit,
  ) async {
    emit(
      state.copyWith(
        selectedAsset: CurrencyInput.dirty(event.selectedCoin),
        selectedAssetAddress: () => null,
        // Necessary since payment methods are dependent on the asset
        // and can change drastically. E.g. A provider might be added
        // or removed based on whether they support the selected asset.
        status: FiatFormStatus.loading,
      ),
    );

    try {
      if (!await _sdk.auth.isSignedIn()) {
        return emit(state.copyWith(selectedAssetAddress: () => null));
      }

      // Activate the asset via CoinsRepo to ensure broadcasts reach CoinsBloc
      final asset = event.selectedCoin.toAsset(_sdk);
      // Gate until initial activation completes to avoid duplicate tasks
      await _coinsRepo.waitForInitialActivationToComplete(
        timeout: const Duration(seconds: 30),
      );
      await _coinsRepo.activateAssetsSync([asset]);
      // TODO: increase the max delay in the SDK or make it adjustable
      AssetPubkeys? assetPubkeys = _sdk.pubkeys.lastKnown(asset.id);
      if (assetPubkeys == null) {
        assetPubkeys = await retry<AssetPubkeys>(
          () async => _sdk.pubkeys.getPubkeys(asset),
          maxAttempts: _pubkeysMaxRetryAttempts,
          backoffStrategy: ConstantBackoff(delay: _pubkeysRetryDelay),
        );
      }
      final address = assetPubkeys.keys.firstOrNull;

      emit(
        state.copyWith(
          selectedAssetAddress: address != null ? () => address : null,
          selectedCoinPubkeys: () => assetPubkeys,
        ),
      );
    } catch (e, s) {
      _log.shout('Error getting pubkeys for selected coin', e, s);
      emit(state.copyWith(selectedAssetAddress: () => null));
    }
  }

  Future<void> _onAmountUpdated(
    FiatFormAmountUpdated event,
    Emitter<FiatFormState> emit,
  ) async {
    emit(
      state.copyWith(fiatAmount: _getFiatAmountInputBounds(event.fiatAmount)),
    );
  }

  void _onPaymentMethodSelected(
    FiatFormPaymentMethodSelected event,
    Emitter<FiatFormState> emit,
  ) {
    emit(
      state.copyWith(
        selectedPaymentMethod: event.paymentMethod,
        fiatAmount: _getFiatAmountInputBounds(
          state.fiatAmount.value,
          selectedPaymentMethod: event.paymentMethod,
        ),
        fiatOrderStatus: FiatOrderStatus.initial,
        status: FiatFormStatus.initial,
      ),
    );
  }

  Future<void> _onFormSubmitted(
    FiatFormSubmitted event,
    Emitter<FiatFormState> emit,
  ) async {
    final formValidationError = _getFormIssue();
    if (formValidationError != null || !state.isValid) {
      _log.warning('Form validation failed. Validation: ${state.isValid}');
      return;
    }

    emit(
      state.copyWith(
        fiatOrderStatus: FiatOrderStatus.submitting,
        checkoutUrl: '',
      ),
    );

    try {
      final newOrder = await _fiatRepository.buyCoin(
        accountReference: state.selectedAssetAddress!.address,
        source: state.selectedFiat.value!.getAbbr(),
        target: state.selectedAsset.value!,
        walletAddress: state.selectedAssetAddress!.address,
        paymentMethod: state.selectedPaymentMethod,
        sourceAmount: state.fiatAmount.value,
        returnUrlOnSuccess: BaseFiatProvider.successUrl(
          state.selectedAssetAddress!.address,
        ),
      );

      if (!newOrder.error.isNone) {
        _log.warning('Order creation returned an error: ${newOrder.error}');
        return emit(_parseOrderError(newOrder.error));
      }

      var checkoutUrl = newOrder.checkoutUrl as String? ?? '';
      if (checkoutUrl.isEmpty) {
        _log.severe('Invalid checkout URL received.');
        return emit(state.copyWith(fiatOrderStatus: FiatOrderStatus.failed));
      }

      // Only Ramp on web requires the intermediate html page to satisfy cors
      // rules and allow for console.log and postMessage events to be handled.
      // Banxa does not use `postMessage` and does not require this.
      checkoutUrl = BaseFiatProvider.fiatWrapperPageUrl(checkoutUrl);
      final webViewMode = _determineWebViewMode();

      emit(
        state.copyWith(
          checkoutUrl: checkoutUrl,
          orderId: newOrder.id,
          status: FiatFormStatus.success,
          fiatOrderStatus: FiatOrderStatus.submitted,
          webViewMode: webViewMode,
        ),
      );
    } catch (e, s) {
      _log.shout('Error submitting fiat form', e, s);
      emit(state.copyWith(status: FiatFormStatus.failure, checkoutUrl: ''));
    }
  }

  /// Determines the appropriate WebViewDialogMode based on platform and
  /// environment
  WebViewDialogMode _determineWebViewMode() {
    final bool isLinux = !kIsWeb && !kIsWasm && Platform.isLinux;
    const bool isWeb = kIsWeb || kIsWasm;

    // Banxa "Return to Komodo" button attempts to navigate the top window to
    // the return URL, which is not supported in a dialog. So we need to open
    // it in a new tab.
    if (isLinux || (isWeb && state.isBanxaSelected)) {
      return WebViewDialogMode.newTab;
    } else if (isWeb) {
      return WebViewDialogMode.dialog;
    } else {
      return WebViewDialogMode.fullscreen;
    }
  }

  Future<void> _onPaymentMethodsChanged(
    FiatFormPaymentMethodsRefreshRequested event,
    Emitter<FiatFormState> emit,
  ) async {
    final refreshPaymentMethodsStream = _refreshPaymentMethods();
    await emit.forEach(
      refreshPaymentMethodsStream,
      onData: (newState) => newState,
    );
  }

  void _onAccountCleared(
    FiatFormResetRequested event,
    Emitter<FiatFormState> emit,
  ) {
    final initialStateWithLists = FiatFormState.initial().copyWith(
      fiatList: state.fiatList,
      coinList: state.coinList,
    );
    emit(_defaultPaymentMethods(initialStateWithLists));
  }

  void _onPaymentStatusMessage(
    FiatFormPaymentStatusMessageReceived event,
    Emitter<FiatFormState> emit,
  ) {
    if (!event.message.isJson()) {
      _log.severe('Invalid json console message received');
      return;
    }

    try {
      String message = event.message;
      if (jsonDecode(event.message) is String) {
        message = jsonDecode(message) as String;
      }
      final data = jsonDecode(message) as Map<String, dynamic>;
      final eventType = PaymentStatusType.fromJson(data);
      FiatOrderStatus updatedStatus = state.fiatOrderStatus;

      switch (eventType) {
        case PaymentStatusType.widgetCloseRequestConfirmed:
        case PaymentStatusType.widgetClose:
        case PaymentStatusType.widgetCloseRequest:
          updatedStatus = FiatOrderStatus.windowCloseRequested;
        case PaymentStatusType.purchaseCreated:
          updatedStatus = FiatOrderStatus.inProgress;
        case PaymentStatusType.paymentStatus:
          final status = data['status'] as String? ?? 'declined';
          updatedStatus = FiatOrderStatus.fromString(status);
        case PaymentStatusType.widgetConfigFailed:
        case PaymentStatusType.widgetConfigDone:
        case PaymentStatusType.widgetCloseRequestCancelled:
        case PaymentStatusType.offrampSaleCreated:
          break;
      }

      if (updatedStatus != state.fiatOrderStatus) {
        emit(state.copyWith(fiatOrderStatus: updatedStatus));
      }
    } catch (e, s) {
      _log.shout('Error parsing payment status message', e, s);
    }
  }

  void _onCoinAddressSelected(
    FiatFormCoinAddressSelected event,
    Emitter<FiatFormState> emit,
  ) {
    emit(state.copyWith(selectedAssetAddress: () => event.address));
  }

  void _onModeUpdated(FiatFormModeUpdated event, Emitter<FiatFormState> emit) {
    emit(state.copyWith(fiatMode: event.mode));
  }

  Future<void> _onCurrenciesFetched(
    FiatFormCurrenciesRefreshRequested event,
    Emitter<FiatFormState> emit,
  ) async {
    try {
      final fiatList = await _fiatRepository.getFiatList();
      final coinList = await _fiatRepository.getCoinList();
      coinList.removeWhere(
        (coin) => excludedAssetList.contains(coin.getAbbr()),
      );
      emit(state.copyWith(fiatList: fiatList, coinList: coinList));
    } catch (e, s) {
      _log.shout('Error loading currency list', e, s);
      emit(
        state.copyWith(
          fiatList: [],
          coinList: [],
          status: FiatFormStatus.failure,
        ),
      );
    }
  }

  Future<void> _onOrderStatusWatchStarted(
    FiatFormOrderStatusWatchStarted event,
    Emitter<FiatFormState> emit,
  ) async {
    // banxa implementation monitors status using their API, so watch the order
    // status via the existing repository methods
    if (state.selectedPaymentMethod.providerId != 'Banxa') {
      return;
    }

    try {
      final orderStatusStream = _fiatRepository.watchOrderStatus(
        state.selectedPaymentMethod,
        state.orderId,
      );

      return await emit.forEach(
        orderStatusStream,
        onData: (data) => state.copyWith(fiatOrderStatus: data),
        onError: (error, stackTrace) {
          _log.shout('Error watching order status', error, stackTrace);
          return state.copyWith(fiatOrderStatus: FiatOrderStatus.failed);
        },
      );
    } catch (e, s) {
      _log.shout('Error setting up order status watch', e, s);
      emit(state.copyWith(fiatOrderStatus: FiatOrderStatus.failed));
    }
  }

  void _onWebViewClosed(
    FiatFormWebViewClosed event,
    Emitter<FiatFormState> emit,
  ) {
    // If the order is not in progress, reset the status to pending
    // to allow the user to submit another order
    if (state.fiatOrderStatus != FiatOrderStatus.inProgress) {
      _log.info('WebView closed, resetting order status to pending');
      emit(
        state.copyWith(
          fiatOrderStatus: FiatOrderStatus.initial,
          checkoutUrl: '',
        ),
      );
    } else {
      _log.info(
        'WebView closed, but order is in progress. Keeping current status.',
      );
    }
  }

  void _onAssetAddressUpdated(
    FiatFormAssetAddressUpdated event,
    Emitter<FiatFormState> emit,
  ) {
    emit(
      state.copyWith(selectedAssetAddress: () => event.selectedAssetAddress),
    );
  }

  FiatFormState _parseOrderError(FiatBuyOrderError error) {
    // TODO? banxa can return an error indicating that a higher fiat amount is
    // required, which could be indicated to the user. The only issue is that
    // it is text-based and does not match the value returned in their payment
    // method list
    return state.copyWith(
      checkoutUrl: '',
      status: FiatFormStatus.failure,
      fiatOrderStatus: FiatOrderStatus.failed,
      providerError: () => error.title,
    );
  }

  @Deprecated(
    'Validation is handled by formz in dedicated inputs like [FiatAmountInput]'
    'This function should be removed once the cases are confirmed to be '
    'covered by formz inputs',
  )
  String? _getFormIssue() {
    // TODO: ? show on the UI and localise? These are currently used as more of
    // a boolean "is there an error?" rather than "what is the error?"
    if (state.paymentMethods.isEmpty) {
      return 'No payment method for this pair';
    }
    if (state.selectedAssetAddress == null) {
      return 'No wallet, or coin/network might not be supported';
    }

    return null;
  }

  FiatAmountInput _getFiatAmountInputBounds(
    String amount, {
    FiatPaymentMethod? selectedPaymentMethod,
  }) {
    Decimal? minAmount;
    Decimal? maxAmount;
    final paymentMethod = selectedPaymentMethod ?? state.selectedPaymentMethod;
    final firstLimit = paymentMethod.transactionLimits.firstOrNull;
    if (firstLimit != null) {
      minAmount = Decimal.tryParse(firstLimit.min.toString());
      maxAmount = Decimal.tryParse(firstLimit.max.toString());
    }

    // Use the minimum transaction amount provided by Ramp and Banxa per coin
    // to determine the minimum amount that can be purchased. The payment
    // method list provides a minimum amount for the fiat currency, but this is
    // not always the same as the minimum amount for the coin.
    final coinAmount = paymentMethod.priceInfo.coinAmount;
    final fiatAmount = paymentMethod.priceInfo.fiatAmount;
    final minPurchaseAmount =
        state.selectedAsset.value?.minPurchaseAmount ?? Decimal.zero;
    if (coinAmount < minPurchaseAmount && coinAmount > Decimal.zero) {
      final minFiatAmount = ((minPurchaseAmount * fiatAmount) / coinAmount)
          .toDecimal(scaleOnInfinitePrecision: 18);
      minAmount = minAmount != null && minAmount > minFiatAmount
          ? minAmount
          : minFiatAmount;
    }

    return FiatAmountInput.dirty(
      amount,
      minValue: minAmount,
      maxValue: maxAmount,
    );
  }

  Stream<FiatFormState> _refreshPaymentMethods() async* {
    yield state.copyWith(
      fiatAmount: _getFiatAmountInputBounds(state.fiatAmount.value),
      providerError: () => null,
    );

    if (!_hasValidFiatAmount()) {
      yield _defaultPaymentMethods(state);
    }

    try {
      final methodsStream = _fiatRepository.getPaymentMethodsList(
        state.selectedFiat.value!.getAbbr(),
        state.selectedAsset.value!,
        _getSourceAmount(),
      );

      await for (final methods in methodsStream) {
        yield _updatePaymentMethods(methods);
      }
    } on Exception catch (error, stacktrace) {
      _log.shout('Error refreshing payment methods', error, stacktrace);
      yield state.copyWith(
        paymentMethods: [],
        status: FiatFormStatus.failure,
        providerError: () => null,
      );
    }
  }

  String _getSourceAmount() {
    return _hasValidFiatAmount() ? state.fiatAmount.value : '10000';
  }

  bool _hasValidFiatAmount() {
    return state.fiatAmount.valueAsDecimal != null &&
        state.fiatAmount.valueAsDecimal != Decimal.zero;
  }

  FiatFormState _updatePaymentMethods(List<FiatPaymentMethod> methods) {
    if (methods.isEmpty) {
      final selectedAsset = state.selectedAsset.value;
      _log.severe('No payment methods found for $selectedAsset');
      throw ArgumentError.value(
        methods,
        'methods',
        'No payment methods found for ${state.selectedAsset.value?.getAbbr()}',
      );
    }

    try {
      final method = state.selectedPaymentMethod.isNone
          ? methods.first
          : methods.firstWhere(
              (method) => method.id == state.selectedPaymentMethod.id,
              orElse: () => methods.first,
            );

      return state.copyWith(
        paymentMethods: methods,
        selectedPaymentMethod: method,
        status: FiatFormStatus.success,
        providerError: () => null,
        fiatAmount: _getFiatAmountInputBounds(
          state.fiatAmount.value,
          selectedPaymentMethod: method,
        ),
      );
    } catch (e, s) {
      _log.shout('Error updating payment methods', e, s);
      return state.copyWith(paymentMethods: [], providerError: () => null);
    }
  }

  FiatFormState _defaultPaymentMethods(FiatFormState currentState) {
    return currentState.copyWith(
      paymentMethods: defaultFiatPaymentMethods,
      selectedPaymentMethod: defaultFiatPaymentMethods.first,
      status: FiatFormStatus.initial,
      fiatOrderStatus: FiatOrderStatus.initial,
      providerError: () => null,
    );
  }
}

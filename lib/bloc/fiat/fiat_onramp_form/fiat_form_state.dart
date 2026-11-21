part of 'fiat_form_bloc.dart';

enum FiatFormStatus { initial, loading, success, failure }

/// Represents the state of the fiat onramp/offramp form.
///
/// Contains all the user selections, available options, and the current
/// status of the form. Implements [FormzMixin] to manage form validation.
final class FiatFormState extends Equatable with FormzMixin {
  const FiatFormState({
    required this.selectedFiat,
    required this.selectedAsset,
    required this.fiatAmount,
    required this.paymentMethods,
    required this.selectedPaymentMethod,
    required this.checkoutUrl,
    required this.orderId,
    required this.fiatList,
    required this.coinList,
    this.status = FiatFormStatus.initial,
    this.fiatOrderStatus = FiatOrderStatus.initial,
    this.fiatMode = FiatMode.onramp,
    this.selectedAssetAddress,
    this.selectedCoinPubkeys,
    this.webViewMode = WebViewDialogMode.fullscreen,
    this.providerError,
    this.currenciesStatus = FiatFormStatus.initial,
    this.providerUnavailable = false,
  });

  /// Creates an initial state with default values.
  FiatFormState.initial({FiatCurrency? selectedFiat})
    : selectedFiat = CurrencyInput.dirty(selectedFiat ?? FiatCurrency.usd()),
      selectedAsset = CurrencyInput.dirty(CryptoCurrency.bitcoin()),
      fiatAmount = const FiatAmountInput.pure(),
      selectedAssetAddress = null,
      selectedPaymentMethod = FiatPaymentMethod.none,
      checkoutUrl = '',
      orderId = '',
      status = FiatFormStatus.initial,
      paymentMethods = const [],
      fiatList = const [],
      coinList = const [],
      fiatOrderStatus = FiatOrderStatus.initial,
      fiatMode = FiatMode.onramp,
      selectedCoinPubkeys = null,
      webViewMode = WebViewDialogMode.fullscreen,
      providerError = null,
      currenciesStatus = FiatFormStatus.initial,
      providerUnavailable = false;

  /// The selected fiat currency to use to purchase [selectedAsset].
  final CurrencyInput<FiatCurrency> selectedFiat;

  /// The selected crypto currency to purchase.
  final CurrencyInput<CryptoCurrency> selectedAsset;

  /// The amount of [selectedFiat] to use to purchase [selectedAsset].
  final FiatAmountInput fiatAmount;

  /// The selected payment method to use to purchase [selectedAsset].
  final FiatPaymentMethod selectedPaymentMethod;

  /// The crypto receive address to use to purchase [selectedAsset].
  final PubkeyInfo? selectedAssetAddress;

  /// The public keys associated with the selected crypto currency.
  final AssetPubkeys? selectedCoinPubkeys;

  /// The callback url to return to once checkout is completed.
  final String checkoutUrl;

  /// The order id for the fiat purchase (Only supported by Banxa).
  final String orderId;

  /// The current status of the form (loading, success, failure).
  final FiatFormStatus status;

  /// The list of payment methods available for the [selectedFiat],
  /// [selectedAsset], and [fiatAmount].
  final Iterable<FiatPaymentMethod> paymentMethods;

  /// The list of fiat currencies that can be used to purchase [selectedAsset].
  final Iterable<FiatCurrency> fiatList;

  /// The list of crypto currencies that can be purchased.
  final Iterable<CryptoCurrency> coinList;

  /// The current status of the fiat order.
  final FiatOrderStatus fiatOrderStatus;

  /// The current mode of the fiat form (onramp, offramp). This is currently
  /// used to determine the tab to show. The implementation will likely change
  /// once the order history tab is implemented
  final FiatMode fiatMode;

  /// The mode to use for displaying the WebView dialog
  final WebViewDialogMode webViewMode;

  /// Raw error message from the provider when there is an order error
  final String? providerError;

  /// Catalog requests finish even when the provider returns no currencies.
  final FiatFormStatus currenciesStatus;
  final bool providerUnavailable;

  /// Gets the transaction limit from the selected payment method
  FiatTransactionLimit? get transactionLimit =>
      selectedPaymentMethod.transactionLimits.firstOrNull;

  /// The minimum fiat amount that is allowed for the selected payment method
  Decimal? get minFiatAmount => fiatAmount.minValue ?? transactionLimit?.min;

  /// The maximum fiat amount that is allowed for the selected payment method
  Decimal? get maxFiatAmount => fiatAmount.maxValue ?? transactionLimit?.max;

  /// Whether currencies are still being loaded
  bool get isLoadingCurrencies =>
      currenciesStatus == FiatFormStatus.loading ||
      (currenciesStatus == FiatFormStatus.initial &&
          (fiatList.isEmpty || coinList.isEmpty));

  /// Whether the form is in a loading state
  bool get isLoading =>
      currenciesStatus == FiatFormStatus.loading ||
      (status != FiatFormStatus.failure &&
          (isLoadingCurrencies || status == FiatFormStatus.loading));

  /// Whether the form can be submitted
  bool get canSubmit =>
      !isLoading &&
      currenciesStatus != FiatFormStatus.failure &&
      !providerUnavailable &&
      paymentMethods.isNotEmpty &&
      !selectedPaymentMethod.isNone &&
      selectedPaymentMethod.priceInfo.coinAmount > Decimal.zero &&
      selectedAssetAddress != null &&
      status != FiatFormStatus.failure &&
      !fiatOrderStatus.isSubmitting &&
      isValid;

  /// Whether the selected payment method is from the Banxa provider
  bool get isBanxaSelected => selectedPaymentMethod.providerId == 'Banxa';

  FiatFormState copyWith({
    CurrencyInput<FiatCurrency>? selectedFiat,
    CurrencyInput<CryptoCurrency>? selectedAsset,
    FiatAmountInput? fiatAmount,
    FiatPaymentMethod? selectedPaymentMethod,
    ValueGetter<PubkeyInfo?>? selectedAssetAddress,
    String? checkoutUrl,
    String? orderId,
    FiatFormStatus? status,
    Iterable<FiatPaymentMethod>? paymentMethods,
    Iterable<FiatCurrency>? fiatList,
    Iterable<CryptoCurrency>? coinList,
    FiatOrderStatus? fiatOrderStatus,
    FiatMode? fiatMode,
    ValueGetter<AssetPubkeys?>? selectedCoinPubkeys,
    WebViewDialogMode? webViewMode,
    ValueGetter<String?>? providerError,
    FiatFormStatus? currenciesStatus,
    bool? providerUnavailable,
  }) {
    return FiatFormState(
      selectedFiat: selectedFiat ?? this.selectedFiat,
      selectedAsset: selectedAsset ?? this.selectedAsset,
      selectedPaymentMethod:
          selectedPaymentMethod ?? this.selectedPaymentMethod,
      selectedAssetAddress: selectedAssetAddress != null
          ? selectedAssetAddress()
          : this.selectedAssetAddress,
      checkoutUrl: checkoutUrl ?? this.checkoutUrl,
      orderId: orderId ?? this.orderId,
      fiatAmount: fiatAmount ?? this.fiatAmount,
      status: status ?? this.status,
      paymentMethods: paymentMethods ?? this.paymentMethods,
      fiatList: fiatList ?? this.fiatList,
      coinList: coinList ?? this.coinList,
      fiatOrderStatus: fiatOrderStatus ?? this.fiatOrderStatus,
      fiatMode: fiatMode ?? this.fiatMode,
      selectedCoinPubkeys: selectedCoinPubkeys != null
          ? selectedCoinPubkeys()
          : this.selectedCoinPubkeys,
      webViewMode: webViewMode ?? this.webViewMode,
      providerError: providerError != null
          ? providerError()
          : this.providerError,
      currenciesStatus: currenciesStatus ?? this.currenciesStatus,
      providerUnavailable: providerUnavailable ?? this.providerUnavailable,
    );
  }

  @override
  List<FormzInput<dynamic, dynamic>> get inputs => [
    selectedFiat,
    selectedAsset,
    fiatAmount,
  ];

  @override
  List<Object?> get props => [
    selectedFiat,
    selectedAsset,
    selectedPaymentMethod,
    selectedAssetAddress,
    checkoutUrl,
    orderId,
    fiatAmount,
    status,
    paymentMethods,
    fiatList,
    coinList,
    fiatOrderStatus,
    fiatMode,
    selectedCoinPubkeys,
    webViewMode,
    providerError,
    currenciesStatus,
    providerUnavailable,
  ];
}

part of 'fiat_form_bloc.dart';

/// Base class for all events related to the Fiat Form.
sealed class FiatFormEvent extends Equatable {
  const FiatFormEvent();

  @override
  List<Object?> get props => [];
}

final class FiatFormDefaultFiatHydrationRequested extends FiatFormEvent {
  const FiatFormDefaultFiatHydrationRequested();
}

/// Event emitted when a payment status message is received from the on-ramp provider.
final class FiatFormPaymentStatusMessageReceived extends FiatFormEvent {
  const FiatFormPaymentStatusMessageReceived(this.message);

  final String message;

  @override
  List<Object> get props => [message];
}

/// Event emitted when a fiat currency is selected in the form.
final class FiatFormFiatSelected extends FiatFormEvent {
  const FiatFormFiatSelected(this.selectedFiat);

  final FiatCurrency selectedFiat;

  @override
  List<Object> get props => [selectedFiat];
}

/// Event emitted when a cryptocurrency is selected in the form.
final class FiatFormCoinSelected extends FiatFormEvent {
  const FiatFormCoinSelected(this.selectedCoin);

  final CryptoCurrency selectedCoin;

  @override
  List<Object> get props => [selectedCoin];
}

/// Event emitted when the fiat amount to be used for purchase is updated.
final class FiatFormAmountUpdated extends FiatFormEvent {
  const FiatFormAmountUpdated(this.fiatAmount);

  final String fiatAmount;

  @override
  List<Object> get props => [fiatAmount];
}

/// Event emitted when a payment method is selected.
final class FiatFormPaymentMethodSelected extends FiatFormEvent {
  const FiatFormPaymentMethodSelected(this.paymentMethod);

  final FiatPaymentMethod paymentMethod;

  @override
  List<Object> get props => [paymentMethod];
}

/// Event emitted when the form is submitted to initiate a purchase.
final class FiatFormSubmitted extends FiatFormEvent {
  const FiatFormSubmitted();
}

/// Event emitted when the form mode (on-ramp/off-ramp) is updated.
final class FiatFormModeUpdated extends FiatFormEvent {
  const FiatFormModeUpdated(this.mode);

  /// Constructor that creates a mode update event from a tab index.
  FiatFormModeUpdated.fromTabIndex(int tabIndex)
    : mode = FiatMode.fromTabIndex(tabIndex);

  final FiatMode mode;

  @override
  List<Object> get props => [mode];
}

/// Event emitted to clear the payment status.
final class FiatFormPaymentStatusCleared extends FiatFormEvent {
  const FiatFormPaymentStatusCleared();
}

/// Event emitted to clear the current account data.
final class FiatFormResetRequested extends FiatFormEvent {
  const FiatFormResetRequested();
}

/// Event emitted to refresh the form data.
final class FiatFormPaymentMethodsRefreshRequested extends FiatFormEvent {
  const FiatFormPaymentMethodsRefreshRequested();
}

/// Event emitted to fetch available fiat and crypto currencies.
final class FiatFormCurrenciesRefreshRequested extends FiatFormEvent {
  const FiatFormCurrenciesRefreshRequested();
}

/// Event emitted to start watching the status of a fiat order.
final class FiatFormOrderStatusWatchStarted extends FiatFormEvent {
  const FiatFormOrderStatusWatchStarted();
}

/// Event emitted when a cryptocurrency address is selected for receiving funds.
final class FiatFormCoinAddressSelected extends FiatFormEvent {
  const FiatFormCoinAddressSelected(this.address);

  final PubkeyInfo address;

  @override
  List<Object> get props => [address];
}

/// Event emitted when the WebView is closed by the user.
final class FiatFormWebViewClosed extends FiatFormEvent {
  const FiatFormWebViewClosed();
}

/// Event emitted when the selected asset address is updated.
final class FiatFormAssetAddressUpdated extends FiatFormEvent {
  const FiatFormAssetAddressUpdated(this.selectedAssetAddress);

  final PubkeyInfo? selectedAssetAddress;

  @override
  List<Object?> get props => [selectedAssetAddress];
}

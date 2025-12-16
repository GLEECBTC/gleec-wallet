part of 'bitrefill_bloc.dart';

sealed class BitrefillState extends Equatable {
  const BitrefillState();

  @override
  List<Object> get props => [];
}

final class BitrefillInitial extends BitrefillState {}

/// Payment intent was recieved from Bitrefill and is in progress
final class BitrefillPaymentInProgress extends BitrefillState {
  const BitrefillPaymentInProgress(this.paymentIntent);

  /// This contains the payment details required to make the payment.
  final BitrefillPaymentIntentEvent paymentIntent;

  @override
  List<Object> get props => [paymentIntent];
}

/// The payment was successful from Gleec Wallet to the Bitrefill address.
final class BitrefillPaymentSuccess extends BitrefillState {
  const BitrefillPaymentSuccess({required this.invoiceId});

  /// The Bitrefill invoice ID. This is used to track the payment.
  final String invoiceId;

  @override
  List<Object> get props => [];
}

/// The payment failed from Gleec Wallet to the Bitrefill address.
final class BitrefillPaymentFailure extends BitrefillState {
  const BitrefillPaymentFailure(this.message);

  /// The error message or message to be displayed to the user.
  final String message;

  @override
  List<Object> get props => [message];
}

/// Bitrefill state loading is in progress to get the url and supported coins.
final class BitrefillLoadInProgress extends BitrefillState {
  const BitrefillLoadInProgress();

  @override
  List<Object> get props => [];
}

/// Bitrefill state was successfully loaded with the url and supported coins
/// from the bitrefill provider.
final class BitrefillLoadSuccess extends BitrefillState {
  const BitrefillLoadSuccess(this.url, this.supportedCoins);

  /// The Bitrefill url to load the Embedded Bitrefill widget.
  final String url;

  /// The list of coins supported as payment methods by Bitrefill.
  final List<String> supportedCoins;

  @override
  List<Object> get props => [url, supportedCoins];
}

/// Bitrefill state failed to load with the given [message].
final class BitrefillLoadFailure extends BitrefillState {
  const BitrefillLoadFailure(this.message);

  /// The error message or message to be displayed to the user.
  final String message;

  @override
  List<Object> get props => [message];
}

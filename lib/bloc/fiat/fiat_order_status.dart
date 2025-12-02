// TODO: Differentiate between different error and in-progress statuses
import 'package:logging/logging.dart';

enum FiatOrderStatus {
  /// Initial status: User has not yet started the payment process
  initial,

  /// Form is being submitted: Order is being created with the provider.
  /// This is the transitional state while waiting for the provider API
  /// response with the checkout URL.
  submitting,

  /// Order successfully created and checkout URL received from provider.
  /// The webview dialog is ready to be opened/is opening with the provider's
  /// payment page (e.g., Ramp or Banxa). This state triggers the webview
  /// display and starts the order status monitoring.
  submitted,

  /// Payment is awaiting user action (e.g., user needs to complete payment)
  pendingPayment,

  /// Payment has been submitted with the provider, and is being processed
  inProgress,

  /// Payment has been completed successfully
  success,

  /// Payment has been cancelled, declined, expired or refunded
  failed,

  /// The user closed the payment window using the provider close button
  /// or "return to Gleec Wallet" button
  windowCloseRequested;

  bool get isTerminal =>
      this == FiatOrderStatus.success || this == FiatOrderStatus.failed;
  bool get isSubmitting =>
      this == FiatOrderStatus.inProgress ||
      this == FiatOrderStatus.submitted ||
      this == FiatOrderStatus.submitting ||
      this == FiatOrderStatus.pendingPayment;
  bool get isFailed => this == FiatOrderStatus.failed;
  bool get isSuccess => this == FiatOrderStatus.success;

  /// Parses the fiat order status form string
  /// Throws [Exception] if the string is not a valid status
  static FiatOrderStatus fromString(String status) {
    // The case statements are references to Banxa's order statuses. See the
    // docs link here for more info: https://docs.banxa.com/docs/order-status
    final normalized = status.toLowerCase();
    switch (normalized) {
      case 'complete':
        return FiatOrderStatus.success;

      case 'cancelled':
      case 'declined':
      case 'expired':
      case 'refunded':
        return FiatOrderStatus.failed;

      case 'extraverification':
      case 'pendingpayment':
      case 'waitingpayment':
        return FiatOrderStatus.pendingPayment;

      case 'paymentreceived':
      case 'inprogress':
      case 'cointransferred':
      case 'cryptotransferred':
        return FiatOrderStatus.inProgress;

      default:
        // Default to in progress if the status is not recognized
        // to avoid alarming users with "Payment failed" popup messages
        // unless we are sure that the payment has failed.
        // Ideally, this section should not be reached.
        Logger(
          'FiatOrderStatus',
        ).warning('Unknown status: $status, defaulting to in progress');
        return FiatOrderStatus.inProgress;
    }
  }
}

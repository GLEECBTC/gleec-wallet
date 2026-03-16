/// Legacy RPC error type enum.
///
/// This enum is deprecated. Use the typed error type enums from
/// `package:komodo_defi_rpc_methods` instead. These are auto-generated
/// from the KDF source and provide comprehensive coverage of all error types.
///
/// For example:
/// - [AccountRpcErrorType] for account-related errors
/// - [WithdrawErrorType] for withdrawal errors
/// - [SwapStartErrorType] for swap errors
///
/// See [KdfErrorRegistry] for automatic error parsing into typed exceptions.
@Deprecated(
  'Use typed error type enums from package:komodo_defi_rpc_methods instead. '
  'See mm2_rpc_exceptions.dart for available error types.',
)
enum RpcErrorType {
  alreadyStarted,
  alreadyStopped,
  alreadyStopping,
  cannotStartFromStopping,
  invalidRequest;

  @override
  String toString() {
    switch (this) {
      case RpcErrorType.alreadyStarted:
        return 'AlreadyStarted';
      case RpcErrorType.alreadyStopped:
        return 'AlreadyStopped';
      case RpcErrorType.alreadyStopping:
        return 'AlreadyStopping';
      case RpcErrorType.cannotStartFromStopping:
        return 'CannotStartFromStopping';
      case RpcErrorType.invalidRequest:
        return 'InvalidRequest';
    }
  }

  static RpcErrorType? fromString(String value) {
    switch (value) {
      case 'AlreadyStarted':
        return RpcErrorType.alreadyStarted;
      case 'AlreadyStopped':
        return RpcErrorType.alreadyStopped;
      case 'AlreadyStopping':
        return RpcErrorType.alreadyStopping;
      case 'CannotStartFromStopping':
        return RpcErrorType.cannotStartFromStopping;
      case 'InvalidRequest':
        return RpcErrorType.invalidRequest;
      default:
        return null;
    }
  }
}

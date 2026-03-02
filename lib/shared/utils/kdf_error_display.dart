import 'package:easy_localization/easy_localization.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';

/// Extension on [MmRpcException] providing localized user-friendly messages.
///
/// This extension integrates the SDK's error message mapping with the app's
/// localization system (easy_localization).
///
/// ## Example
///
/// ```dart
/// try {
///   await withdraw(...);
/// } on MmRpcException catch (e) {
///   // Get localized message with automatic fallback
///   showErrorDialog(e.localizedMessage);
/// }
/// ```
extension KdfErrorLocalizedMessage on MmRpcException {
  /// Returns the localized user-friendly message for this exception.
  ///
  /// Resolution order:
  /// 1. If a locale key mapping exists and has a translation, returns the
  ///    translated message
  /// 2. If a locale key mapping exists but no translation, returns the
  ///    English fallback message
  /// 3. If no mapping exists, returns the technical error message
  /// 4. As a last resort, returns a generic error message
  String get localizedMessage {
    final msg = userMessage;
    if (msg == null) {
      // No mapping - use technical message or default
      return message ?? KdfErrorMessages.defaultError.fallbackMessage;
    }

    // Try to get translation
    final translated = msg.localeKey.tr();

    // If translation equals the key, it wasn't found - use fallback
    if (translated == msg.localeKey) {
      return msg.fallbackMessage;
    }

    return translated;
  }
}

/// Extension on [GeneralErrorResponse] providing localized user-friendly
/// messages.
///
/// This is useful when catching the fallback error type before it's converted
/// to a typed exception.
extension GeneralErrorLocalizedMessage on GeneralErrorResponse {
  /// Returns the localized user-friendly message for this error.
  ///
  /// First attempts to look up a message based on [errorType], then falls
  /// back to the raw error message.
  String get localizedMessage {
    final msg = KdfErrorMessages.forErrorType(errorType);
    if (msg == null) {
      return error ?? KdfErrorMessages.defaultError.fallbackMessage;
    }

    final translated = msg.localeKey.tr();
    if (translated == msg.localeKey) {
      return msg.fallbackMessage;
    }

    return translated;
  }
}

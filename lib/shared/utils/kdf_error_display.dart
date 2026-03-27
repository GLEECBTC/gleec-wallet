import 'package:easy_localization/easy_localization.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
// ignore: implementation_imports -- not exported from komodo_defi_sdk public API
import 'package:komodo_defi_sdk/src/activation/activation_exceptions.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

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

/// Resolves [error] to a single user-facing string using the same mapping as
/// [KdfErrorLocalizedMessage] / [GeneralErrorLocalizedMessage] where applicable,
/// plus [SdkError] locale keys and a few common wrapper types.
String formatKdfUserFacingError(Object error) {
  if (error is MmRpcException) {
    return error.localizedMessage;
  }
  if (error is GeneralErrorResponse) {
    return error.localizedMessage;
  }
  if (error is SdkError) {
    final localized = error.messageKey.tr(args: error.messageArgs);
    return localized == error.messageKey ? error.fallbackMessage : localized;
  }
  if (error is WithdrawalException) {
    return error.message;
  }
  if (error is ActivationFailedException) {
    final original = error.originalError;
    if (original != null) {
      return formatKdfUserFacingError(original);
    }
    return error.message;
  }

  final raw = error.toString().trim();
  if (raw.isEmpty) {
    return LocaleKeys.somethingWrong.tr();
  }

  const exceptionPrefix = 'Exception: ';
  if (raw.startsWith(exceptionPrefix)) {
    final message = raw.substring(exceptionPrefix.length).trim();
    if (message.isNotEmpty) {
      return message;
    }
  }

  return raw;
}

/// Technical detail string for expandable error UI (mirrors withdraw-form logic).
String extractKdfTechnicalDetails(Object error) {
  if (error is SdkError) {
    return error.fallbackMessage;
  }
  if (error is MmRpcException) {
    return error.message ?? error.toString();
  }
  if (error is GeneralErrorResponse) {
    return error.error ?? error.toString();
  }
  if (error is WithdrawalException) {
    return error.message;
  }
  return error.toString();
}

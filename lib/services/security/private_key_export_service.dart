import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

enum PrivateKeyExportError { incorrectPassword, sessionChanged, unavailable }

class PrivateKeyExportException implements Exception {
  const PrivateKeyExportException(this.reason);

  final PrivateKeyExportError reason;

  @override
  String toString() => 'PrivateKeyExportException(${reason.name})';
}

/// A screen-local authorization handle. The SDK token is never serialized.
class PrivateKeyExportAccess {
  const PrivateKeyExportAccess({required this.walletName, required this.token});

  final String walletName;
  final Object token;

  @override
  String toString() => 'PrivateKeyExportAccess(redacted)';
}

abstract class PrivateKeyExportService {
  Stream<void> get sessionChanges;

  Future<PrivateKeyExportAccess> begin();

  Future<void> ensureCurrent(PrivateKeyExportAccess access);

  void ensureCurrentSync(PrivateKeyExportAccess access);

  Future<PrivateKeyExportResult> authenticateAndExport(
    PrivateKeyExportAccess access,
    SensitiveString password,
  );
}

class SdkPrivateKeyExportService implements PrivateKeyExportService {
  SdkPrivateKeyExportService(this._sdk);

  final KomodoDefiSdk _sdk;

  @override
  Stream<void> get sessionChanges =>
      _sdk.auth.authGenerationChanges.map((_) {});

  @override
  Future<PrivateKeyExportAccess> begin() async {
    try {
      final session = await _sdk.security.captureExportSession();
      return PrivateKeyExportAccess(
        walletName: session.walletId.name,
        token: session,
      );
    } catch (_) {
      throw const PrivateKeyExportException(PrivateKeyExportError.unavailable);
    }
  }

  @override
  void ensureCurrentSync(PrivateKeyExportAccess access) {
    try {
      _sdk.security.ensureExportSessionCurrentSync(
        access.token as PrivateKeyExportSession,
      );
    } catch (_) {
      throw const PrivateKeyExportException(
        PrivateKeyExportError.sessionChanged,
      );
    }
  }

  @override
  Future<void> ensureCurrent(PrivateKeyExportAccess access) async {
    try {
      await _sdk.security.ensureExportSessionCurrent(
        access.token as PrivateKeyExportSession,
      );
    } catch (_) {
      throw const PrivateKeyExportException(
        PrivateKeyExportError.sessionChanged,
      );
    }
  }

  @override
  Future<PrivateKeyExportResult> authenticateAndExport(
    PrivateKeyExportAccess access,
    SensitiveString password,
  ) async {
    await ensureCurrent(access);
    try {
      // The SDK currently verifies the password by decrypting the mnemonic.
      // Keep that result local; it never reaches BLoC state or diagnostics.
      final mnemonic = await _sdk.auth.getMnemonicPlainText(password.value);
      await ensureCurrent(access);
      if (mnemonic.plaintextMnemonic?.isNotEmpty != true) {
        throw const PrivateKeyExportException(
          PrivateKeyExportError.incorrectPassword,
        );
      }
    } on PrivateKeyExportException {
      rethrow;
    } on AuthException catch (error) {
      await ensureCurrent(access);
      throw PrivateKeyExportException(
        error.type == AuthExceptionType.incorrectPassword
            ? PrivateKeyExportError.incorrectPassword
            : PrivateKeyExportError.unavailable,
      );
    } catch (_) {
      // A wallet transition takes precedence over a password error.
      await ensureCurrent(access);
      throw const PrivateKeyExportException(PrivateKeyExportError.unavailable);
    }

    try {
      final result = await _sdk.security.exportPrivateKeys(
        request: const PrivateKeyExportRequest(),
        session: access.token as PrivateKeyExportSession,
      );
      await ensureCurrent(access);
      return result;
    } on PrivateKeyExportException {
      rethrow;
    } catch (_) {
      await ensureCurrent(access);
      throw const PrivateKeyExportException(PrivateKeyExportError.unavailable);
    }
  }
}

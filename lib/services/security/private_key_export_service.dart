import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:web_dex/services/wallet_access/wallet_operation_gate.dart';

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
    SensitiveString password, {
    void Function()? ensureAuthorized,
  });
}

class SdkPrivateKeyExportService implements PrivateKeyExportService {
  SdkPrivateKeyExportService(this._sdk, {WalletOperationGate? operationGate})
    : _operationGate = operationGate ?? WalletOperationGate.instance;

  final KomodoDefiSdk _sdk;
  final WalletOperationGate _operationGate;

  @override
  Stream<void> get sessionChanges =>
      _sdk.auth.authGenerationChanges.map((_) {});

  @override
  Future<PrivateKeyExportAccess> begin() async {
    try {
      final session = await _sdk.security.captureExportSession();
      return PrivateKeyExportAccess(
        walletName: session.walletId.name,
        token: _ExportAccessScope(session),
      );
    } catch (_) {
      throw const PrivateKeyExportException(PrivateKeyExportError.unavailable);
    }
  }

  @override
  void ensureCurrentSync(PrivateKeyExportAccess access) {
    try {
      _sdk.security.ensureExportSessionCurrentSync(
        (access.token as _ExportAccessScope).session,
      );
      (access.token as _ExportAccessScope).ensureAuthorized?.call();
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
        (access.token as _ExportAccessScope).session,
      );
      (access.token as _ExportAccessScope).ensureAuthorized?.call();
    } catch (_) {
      throw const PrivateKeyExportException(
        PrivateKeyExportError.sessionChanged,
      );
    }
  }

  @override
  Future<PrivateKeyExportResult> authenticateAndExport(
    PrivateKeyExportAccess access,
    SensitiveString password, {
    void Function()? ensureAuthorized,
  }) async {
    if (_operationGate.isInstalled && ensureAuthorized == null) {
      throw const PrivateKeyExportException(
        PrivateKeyExportError.sessionChanged,
      );
    }
    final scope = access.token as _ExportAccessScope;
    final generation = ++scope.generation;
    // Bind the post-authorization permit to this one screen-local result. All
    // later reveal/copy/save checks retain the same app-lock generation.
    scope.ensureAuthorized = ensureAuthorized;
    void ensureOperation() {
      if (scope.generation != generation) {
        throw const PrivateKeyExportException(
          PrivateKeyExportError.sessionChanged,
        );
      }
      ensureCurrentSync(access);
    }

    Future<void> ensureOperationCurrent() async {
      ensureOperation();
      await ensureCurrent(access);
      ensureOperation();
    }

    await ensureOperationCurrent();
    try {
      // The SDK currently verifies the password by decrypting the mnemonic.
      // Keep that result local; it never reaches BLoC state or diagnostics.
      final mnemonic = await RpcDispatchGuard.run(
        ensureOperation,
        () => _sdk.auth.getMnemonicPlainText(password.value),
        methods: const {'get_mnemonic'},
      );
      await ensureOperationCurrent();
      if (mnemonic.plaintextMnemonic?.isNotEmpty != true) {
        throw const PrivateKeyExportException(
          PrivateKeyExportError.incorrectPassword,
        );
      }
    } on PrivateKeyExportException {
      rethrow;
    } on AuthException catch (error) {
      await ensureOperationCurrent();
      throw PrivateKeyExportException(
        error.type == AuthExceptionType.incorrectPassword
            ? PrivateKeyExportError.incorrectPassword
            : PrivateKeyExportError.unavailable,
      );
    } catch (_) {
      // A wallet transition takes precedence over a password error.
      await ensureOperationCurrent();
      throw const PrivateKeyExportException(PrivateKeyExportError.unavailable);
    }

    try {
      final result = await RpcDispatchGuard.run(
        ensureOperation,
        () => _sdk.security.exportPrivateKeys(
          request: const PrivateKeyExportRequest(),
          session: scope.session,
        ),
        methods: const {'get_private_keys', 'show_priv_key'},
      );
      await ensureOperationCurrent();
      return result;
    } on PrivateKeyExportException {
      rethrow;
    } catch (_) {
      await ensureOperationCurrent();
      throw const PrivateKeyExportException(PrivateKeyExportError.unavailable);
    }
  }
}

class _ExportAccessScope {
  _ExportAccessScope(this.session);

  final PrivateKeyExportSession session;
  int generation = 0;
  void Function()? ensureAuthorized;
}

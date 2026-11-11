// Synthetic adapters for cross-process persisted-reader compatibility tests.
// These model engine/vault contracts, not operating-system security guarantees.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_session.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/services/storage/base_storage.dart';
import 'package:web_dex/services/wallet_access/platform/credential_backend.dart';
import 'package:web_dex/services/wallet_access/unlock_coordinator.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/services/wallet_access/wallet_operation_gate.dart';

const rollbackOptions = AuthOptions(
  derivationMethod: DerivationMethod.hdWallet,
);
const rollbackNewPassword = 'Synthetic-new-pass-456!';

class RollbackStorage extends BaseStorage {
  RollbackStorage([Map<String, dynamic>? initial])
    : values = initial ?? <String, dynamic>{};
  final Map<String, dynamic> values;
  @override
  Future<dynamic> read(String key) async =>
      values[key] == null ? null : jsonDecode(jsonEncode(values[key]));
  @override
  Future<bool> write(String key, dynamic value) async {
    values[key] = jsonDecode(jsonEncode(value));
    return true;
  }

  @override
  Future<bool> delete(String key) async {
    values.remove(key);
    return true;
  }
}

class RollbackBackend extends CredentialBackend {
  final values = <String, String>{};
  final infos = <String, CredentialRecordInfo>{};
  int authorizations = 0;
  bool failWrite = false;
  @override
  Future<CredentialCapabilities> capabilities() async =>
      const CredentialCapabilities(
        available: true,
        protection: CredentialProtection.appLocal,
        deviceAuthentication: true,
        passkeyCandidate: true,
      );
  @override
  Future<CredentialRecordInfo?> metadata(String key) async => infos[key];
  @override
  Future<void> write(
    String key,
    String value, {
    required bool requireAuthentication,
  }) async {
    if (failWrite) {
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
    values[key] = value;
    infos[key] = CredentialRecordInfo(
      protection: requireAuthentication
          ? CredentialProtection.authenticationBound
          : CredentialProtection.appLocal,
      enrolled: requireAuthentication,
      revision: (infos[key]?.revision ?? 0) + 1,
    );
  }

  @override
  Future<void> enrollPasskey(
    String key,
    String value, {
    required String label,
  }) async {
    values[key] = value;
    infos[key] = CredentialRecordInfo(
      protection: CredentialProtection.passkey,
      enrolled: true,
      revision: (infos[key]?.revision ?? 0) + 1,
    );
  }

  @override
  Future<String?> read(
    String key, {
    required String reason,
    bool requireAuthentication = false,
    bool automatic = false,
    String? purpose,
  }) async {
    // Enforce stored policy even when the caller passes false.
    if (infos[key]?.enrolled == true) authorizations++;
    return values[key];
  }

  @override
  Future<String?> prepareDelete(String key, {required String reason}) async {
    authorizations++;
    return 'synthetic-delete:${infos[key]?.revision}';
  }

  @override
  Future<void> delete(String key, {String? authorization}) async {
    if (infos[key]?.enrolled == true &&
        authorization != 'synthetic-delete:${infos[key]?.revision}') {
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
    values.remove(key);
    infos.remove(key);
  }

  @override
  Future<void> cancel() async {}
  @override
  Future<PasswordManagerOutcome> savePassword({
    required String username,
    required String password,
    required String title,
  }) async => PasswordManagerOutcome.unknown;
}

class RollbackAuth extends Fake implements KomodoDefiLocalAuth {
  final sessions = AuthSessionTracker();
  final users = <KdfUser>[];
  final passwords = <String, String>{};
  KdfUser? active;
  String? creationFailure;
  String? rotationFailure;
  int registrations = 0;
  void activate(KdfUser user) {
    active = user;
    sessions.observe(user);
  }

  @override
  Future<KdfUser?> get currentUser async => active;
  @override
  Future<List<KdfUser>> getUsers() async => List.of(users);
  @override
  void onWalletDeletion(Future<void> Function(WalletId) hook) {}
  @override
  Future<AuthSessionContext> captureSessionContext() async {
    sessions.observe(active);
    return sessions.current ?? (throw const AuthSessionChangedException());
  }

  @override
  void ensureSessionContextCurrent(AuthSessionContext context) {
    if (!sessions.isCurrent(context)) throw const AuthSessionChangedException();
  }

  @override
  Future<void> verifyPassword({
    required String password,
    required WalletId expectedWalletId,
    AuthSessionContext? expectedSession,
  }) async {
    RpcDispatchGuard.ensureCurrent('get_mnemonic');
    if (expectedSession != null) ensureSessionContextCurrent(expectedSession);
    if (active?.walletId != expectedWalletId) {
      throw const AuthSessionChangedException();
    }
    if (passwords[WalletAccessService.entryId(active!)] != password) {
      throw AuthException(
        'Incorrect password',
        type: AuthExceptionType.incorrectPassword,
      );
    }
  }

  @override
  Future<KdfUser> register({
    required String walletName,
    required String password,
    AuthOptions options = rollbackOptions,
    Mnemonic? mnemonic,
    Map<String, dynamic> initialMetadata = const {},
    String? provisioningId,
  }) async {
    final failure = creationFailure;
    creationFailure = null;
    if (failure == 'before') {
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
    final existing = users.where(
      (user) => WalletAccessService.entryId(user) == provisioningId,
    );
    if (existing.isNotEmpty) {
      activate(existing.single);
      return existing.single;
    }
    registrations++;
    final user = KdfUser(
      walletId: WalletId.withPubkeyHash(
        walletName,
        options,
        sha256
            .convert(utf8.encode(provisioningId!))
            .toString()
            .substring(0, 40),
      ),
      isBip39Seed: true,
      metadata: {'_wallet_entry_id': provisioningId, ...initialMetadata},
    );
    users.add(user);
    passwords[provisioningId] = password;
    activate(user);
    if (failure == 'after') {
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
    return user;
  }

  @override
  Future<KdfUser> signIn({
    required String walletName,
    required String password,
    AuthOptions options = rollbackOptions,
  }) async {
    final user = users.firstWhere((user) => user.walletId.name == walletName);
    activate(user);
    // Intentionally preserve the SDK's same-wallet fast path. The service must
    // still call fresh verification, including in the rollback build.
    return user;
  }

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
    WalletId? expectedWalletId,
    AuthSessionContext? expectedSession,
  }) async {
    RpcDispatchGuard.ensureCurrent('change_mnemonic_password');
    await verifyPassword(
      password: currentPassword,
      expectedWalletId: expectedWalletId!,
      expectedSession: expectedSession,
    );
    final failure = rotationFailure;
    rotationFailure = null;
    if (failure == 'before') {
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
    passwords[WalletAccessService.entryId(active!)] = newPassword;
    if (failure == 'after') {
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
  }

  @override
  Future<Mnemonic> getMnemonicEncrypted() async => Mnemonic.encrypted(
    EncryptedMnemonicData.fromJson(EncryptedMnemonicData.encryptedDataExample),
  );

  @override
  Future<KdfUser> updateMetadataForSession(
    AuthSessionContext context,
    Map<String, dynamic> updates,
  ) async {
    ensureSessionContextCurrent(context);
    final current = active!;
    final updated = current.copyWith(
      metadata: {...current.metadata, ...updates},
    );
    users[users.indexOf(current)] = updated;
    activate(updated);
    return updated;
  }
}

class RollbackSdk extends Fake implements KomodoDefiSdk {
  RollbackSdk(this.auth);
  @override
  final RollbackAuth auth;
}

class RollbackFixture {
  RollbackFixture() {
    service = WalletAccessService(
      sdk: RollbackSdk(auth),
      storage: storage,
      backend: backend,
      unlockCoordinator: WalletUnlockCoordinator(
        operationGate: WalletOperationGate(),
      ),
    );
  }
  final storage = RollbackStorage();
  final backend = RollbackBackend();
  final auth = RollbackAuth();
  late final WalletAccessService service;

  Map<String, Object?> toJson() => {
    'syntheticRollbackFixture': 1,
    'storage': storage.values,
    'credentialValues': backend.values,
    'credentialInfo': backend.infos.map(
      (key, info) => MapEntry(key, {
        'protection': info.protection.name,
        'enrolled': info.enrolled,
        'revision': info.revision,
      }),
    ),
    'users': auth.users.map((user) => user.toJson()).toList(),
    'enginePasswords': auth.passwords,
    'registrations': auth.registrations,
  };

  void restore(Map<String, dynamic> json) {
    if (json['syntheticRollbackFixture'] != 1) {
      throw StateError('Only synthetic rollback fixtures are accepted');
    }
    storage.values.addAll(Map<String, dynamic>.from(json['storage'] as Map));
    backend.values.addAll(
      Map<String, String>.from(json['credentialValues'] as Map),
    );
    for (final entry in (json['credentialInfo'] as Map).entries) {
      final info = entry.value as Map;
      backend.infos[entry.key as String] = CredentialRecordInfo(
        protection: CredentialProtection.parse(info['protection']),
        enrolled: info['enrolled'] == true,
        revision: info['revision'] as int,
      );
    }
    auth.users.addAll(
      (json['users'] as List).map(
        (user) => KdfUser.fromJson(Map<String, dynamic>.from(user as Map)),
      ),
    );
    auth.passwords.addAll(
      Map<String, String>.from(json['enginePasswords'] as Map),
    );
    auth.registrations = json['registrations'] as int;
  }
}

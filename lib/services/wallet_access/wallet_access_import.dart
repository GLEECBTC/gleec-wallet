part of 'wallet_access_service.dart';

/// An import in flight, so a retry with the same wallet can finish it and a
/// different wallet never adopts it. Kept apart from creation's claim so
/// neither cancels the other's resume.
typedef _PendingImport = ({String entryId, String walletName, bool isHd});

extension _ManagedImport on WalletAccessService {
  static const _pendingImportKey = 'wallet_access_pending_import_v1';

  /// Generates and stores the password for a new managed wallet, protected
  /// where the user chose that. Nothing refers to [id] yet, so a failure
  /// removes the item; declining protection keeps it unattended instead.
  Future<({String password, CredentialRecordInfo info})> _provisionCredential(
    String id, {
    required bool useDeviceProtection,
    required _AccessRevision revision,
  }) async {
    final capability = await _backend.capabilities();
    if (!capability.available) {
      throw const WalletAccessException(WalletAccessFailure.unavailable);
    }
    final password = SecurityUtils.generatePasswordSecure(32);
    var protected =
        WalletAccessService.deviceEnrollmentEnabled &&
        useDeviceProtection &&
        capability.deviceAuthentication;
    final key = WalletAccessRecord.credentialKeyFor(id);
    _ensureRevision(revision);
    try {
      await unlockCoordinator.runSystemPrompt(
        () => _backend.write(key, password, requireAuthentication: protected),
      );
      if (await unlockCoordinator.runSystemPrompt(
            () => _backend.read(
              key,
              reason: 'Confirm wallet protection',
              purpose: 'verifyWrite',
              requireAuthentication: protected,
            ),
          ) !=
          password) {
        throw const WalletAccessException(WalletAccessFailure.storageFailed);
      }
    } on WalletAccessException catch (error) {
      final declinedProtection =
          protected &&
          error.failure == WalletAccessFailure.canceled &&
          _isRevisionCurrent(revision);
      if (!declinedProtection) {
        // The write may have landed before its confirmation failed. No
        // record or engine wallet refers to this new key yet, so nothing
        // else would ever remove it.
        try {
          await unlockCoordinator.runSystemPrompt(() => _backend.delete(key));
        } on Object {
          // The failure being reported is the one that matters.
        }
        _ensureRevision(revision);
        rethrow;
      }
      // This is an explicitly new wallet with no previous protection.
      // Cancellation never downgrades a persisted/protected wallet.
      // Nothing has been registered with KDF yet. Remove only this new
      // scratch item before honoring the choice to set protection later.
      await _backend.delete(key);
      if (await _backend.metadata(key) != null) rethrow;
      protected = false;
      await _backend.write(key, password, requireAuthentication: false);
      if (await _backend.read(key, reason: 'Confirm wallet storage') !=
          password) {
        throw const WalletAccessException(WalletAccessFailure.storageFailed);
      }
    }
    final info = await _backend.metadata(key);
    if (info == null) {
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
    return (password: password, info: info);
  }

  Future<KdfUser> _importWallet({
    required String walletName,
    required WalletType walletType,
    required String mnemonic,
    required Map<String, dynamic> initialMetadata,
    required bool useDeviceProtection,
    required _AccessRevision revision,
  }) async {
    final isHd = walletType == WalletType.hdwallet;
    String? id;
    String? password;
    final claim = await _readPendingImport();
    if (claim != null) {
      // Another wallet's claim is released unread: reading it would ask the
      // user to unlock a wallet they are not importing.
      final sameWallet = claim.walletName == walletName && claim.isHd == isHd;
      final record =
          !sameWallet || _completedProvisioning.contains(claim.entryId)
          ? null
          : (await _records())[claim.entryId];
      final resumed = record == null
          ? null
          : await _resumeProvisioningCredential(record, revision);
      if (resumed != null) {
        id = claim.entryId;
        password = resumed;
      } else {
        // Its record stays for any wallet the engine did create; only the
        // claim on the next import is released.
        await _clearPendingImport(claim.entryId);
      }
    }
    if (id == null || password == null) {
      id = const Uuid().v4();
      final provisioned = await _provisionCredential(
        id,
        useDeviceProtection: useDeviceProtection,
        revision: revision,
      );
      password = provisioned.password;
      await _saveRecord(
        WalletAccessRecord(
          entryId: id,
          walletName: walletName,
          isHd: isHd,
          protection: provisioned.info.protection,
          requiresAuthentication: provisioned.info.enrolled,
        ),
      );
      await _writeChecked(
        _pendingImportKey,
        jsonEncode({'entryId': id, 'walletName': walletName, 'isHd': isHd}),
      );
    }
    _ensureRevision(revision);
    final KdfUser user;
    try {
      user = await _sdk.auth.register(
        walletName: walletName,
        password: password,
        provisioningId: id,
        mnemonic: Mnemonic.plaintext(mnemonic),
        options: AuthOptions(
          derivationMethod: isHd
              ? DerivationMethod.hdWallet
              : DerivationMethod.iguana,
        ),
        initialMetadata: {...initialMetadata, 'type': walletType.name},
      );
    } on AuthException catch (error) {
      // A taken name is the user's to resolve, never renamed silently. When
      // nothing was reserved under it, nothing refers to this credential.
      if (error.type == AuthExceptionType.walletAlreadyExists &&
          error.details?['canRetryWithDifferentName'] == true) {
        await _abandonImport(id);
      }
      rethrow;
    }
    _ensureRevision(revision);
    if (WalletAccessService.entryId(user) != id ||
        !user.walletId.hasFullIdentity) {
      throw const WalletAccessException(WalletAccessFailure.invalidResponse);
    }
    // A resumed engine wallet keeps the derivation it was created with.
    // Another one would show addresses other than the moved wallet's.
    if (user.walletId.isHd != isHd) await _refuseOpenedWallet();
    await _sdk.auth.verifyPassword(
      password: password,
      expectedWalletId: user.walletId,
    );
    // A retry may resume an engine wallet that an earlier attempt created.
    // Only the seed handed over now may open, or the user would fund a
    // wallet other than the one they moved.
    final opened = await RpcDispatchGuard.run(
      () => _ensureRevision(revision),
      () => _sdk.auth.getMnemonicPlainText(password!),
      methods: const {'get_mnemonic'},
    );
    if (!_sameSeed(opened.plaintextMnemonic, mnemonic)) {
      await _refuseOpenedWallet();
    }
    final encrypted = await _sdk.auth.getMnemonicEncrypted();
    if (encrypted.isEncrypted != true) {
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
    final record = await _recordFor(id);
    if (record == null) {
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
    await _saveRecord(
      record.copyWith(phase: 'ready', pubkeyHash: user.walletId.pubkeyHash),
    );
    await _didAuthenticate(user, expectedRevision: revision);
    await _clearPendingImport(id);
    return user;
  }

  /// Closes an engine wallet that is not the one being imported, so the user
  /// never funds it by mistake.
  Future<Never> _refuseOpenedWallet() async {
    try {
      await _sdk.auth.signOut();
    } on Object {
      // The mismatch is what must be reported.
    }
    throw const WalletAccessException(WalletAccessFailure.invalidResponse);
  }

  /// Removes a credential no engine wallet refers to, with its record and
  /// claim. Best effort: the failure being reported is the one that matters.
  Future<void> _abandonImport(String id) async {
    try {
      await unlockCoordinator.runSystemPrompt(
        () => _backend.delete(WalletAccessRecord.credentialKeyFor(id)),
      );
      await _deleteRecord(id);
      await _clearPendingImport(id);
    } on Object {
      // Left for the next import, which releases a claim it cannot resume.
    }
  }

  Future<_PendingImport?> _readPendingImport() async {
    final raw = await _storage.read(_pendingImportKey);
    if (raw is! String) return null;
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic> &&
          json['entryId'] is String &&
          json['walletName'] is String &&
          json['isHd'] is bool) {
        return (
          entryId: json['entryId'] as String,
          walletName: json['walletName'] as String,
          isHd: json['isHd'] as bool,
        );
      }
    } on FormatException {
      // Unreadable: treated as no claim, and replaced by the next import.
    }
    return null;
  }

  Future<void> _clearPendingImport(String id) async {
    if (await _storage.read(_pendingImportKey) == null) return;
    final claim = await _readPendingImport();
    // Another import's claim is not this one's to release.
    if (claim != null && claim.entryId != id) return;
    await _storage.delete(_pendingImportKey);
  }

  Future<void> _deleteRecord(String id) => withWalletAccessRecordLock(() async {
    final stored = await _storedRecords();
    if (stored == null || stored.remove(id) == null) return;
    await _writeChecked(WalletAccessService._recordsKey, stored);
    _changes.add(null);
  });

  static bool _sameSeed(String? opened, String expected) {
    if (opened == null) return false;
    final a = utf8.encode(opened);
    final b = utf8.encode(expected);
    var diff = a.length ^ b.length;
    for (var i = 0; i < a.length && i < b.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

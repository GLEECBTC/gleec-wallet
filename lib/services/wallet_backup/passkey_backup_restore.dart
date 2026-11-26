part of 'passkey_backup_service.dart';

/// Opening, checking and removing backups, and finding them in a store.
extension _Restore on PasskeyBackupService {
  /// One prompt, for the passkey the record names.
  Future<WalletTransferSecret> _open(String raw, int token) async {
    final rpId = _rpId;
    final record = PasskeyBackupRecord.decode(raw, expectedRpId: rpId);
    final Uint8List prf;
    try {
      prf = await _assertKey(
        rpId,
        record.credentialId,
        record.userHandle,
        token,
        PasskeyBackupFailure.wrongPasskey,
      );
    } on WalletAccessException catch (error, stack) {
      Error.throwWithStackTrace(
        PasskeyBackupService._backupFailure(error, restoring: true),
        stack,
      );
    }
    try {
      return record.open(prf);
    } finally {
      prf.fillRange(0, prf.length, 0);
    }
  }

  /// Opens the copy a restore would read, and forgets what it held.
  Future<DateTime> _check(PasskeyBackupEntry entry, int token) async {
    await _open(await _storedCopy(entry), token);
    final checked = _clock().toUtc();
    await _index.markChecked(entry.id, checked);
    return checked;
  }

  /// The store's copy, or for a file this device's: a check must fail when
  /// the store no longer holds the backup.
  Future<String> _storedCopy(PasskeyBackupEntry entry) async {
    final String? raw;
    if (entry.store == BackupStoreKind.file) {
      raw = await _index.record(entry.id);
    } else {
      final listed = await (await _store(entry.store)).list();
      raw = listed.where((item) => item.id == entry.id).firstOrNull?.raw;
    }
    if (raw == null) {
      throw const PasskeyBackupException(PasskeyBackupFailure.noBackupFound);
    }
    return raw;
  }

  Future<void> _remove(PasskeyBackupEntry entry) async {
    final rpId = _rpId;
    final credentialId = await _credentialOf(entry, rpId);
    if (entry.store != BackupStoreKind.file) {
      await (await _store(entry.store)).delete(entry.id);
    }
    await _index.remove(entry.id);
    if (credentialId != null) await _reportRemoved(credentialId);
  }

  /// The passkey [entry] was sealed to, from this device's copy or else the
  /// store's. Null leaves the passkey unreported.
  Future<Uint8List?> _credentialOf(
    PasskeyBackupEntry entry,
    String rpId,
  ) async {
    for (final copy in [
      () => _index.record(entry.id),
      () => _storedCopy(entry),
    ]) {
      try {
        final raw = await copy();
        if (raw == null) continue;
        final record = PasskeyBackupRecord.decode(raw, expectedRpId: rpId);
        if (record.id == entry.id) return record.credentialId;
      } on Object {
        // The next copy, or none.
      }
    }
    return null;
  }

  /// This device's copy is the record as created; the store's is read only
  /// when that is missing, so saving a file asks for no sign-in.
  Future<String> _export(PasskeyBackupEntry entry) async {
    final rpId = _rpId;
    bool readable(String raw) {
      try {
        return PasskeyBackupRecord.decode(raw, expectedRpId: rpId).id ==
            entry.id;
      } on Object {
        return false;
      }
    }

    final local = await _index.record(entry.id);
    if (local != null && readable(local)) return local;
    if (entry.store != BackupStoreKind.file) {
      final stored = await _storedCopy(entry);
      if (readable(stored)) return stored;
    } else if (local == null) {
      throw const PasskeyBackupException(PasskeyBackupFailure.noBackupFound);
    }
    throw const PasskeyBackupException(PasskeyBackupFailure.damaged);
  }

  /// Newest first. Records for another relying party, and damaged ones,
  /// are not this build's to offer.
  Future<List<StoredBackup>> _find(BackupStoreKind kind) async {
    final rpId = _rpId;
    final store = await _store(kind);
    final found = <String, StoredBackup>{};
    var newer = false;
    for (final stored in await store.list()) {
      try {
        final record = PasskeyBackupRecord.decode(
          stored.raw,
          expectedRpId: rpId,
        );
        if (record.id != stored.id) continue;
        found.putIfAbsent(
          record.id,
          () => StoredBackup(
            id: record.id,
            store: kind,
            created: record.created,
            raw: stored.raw,
          ),
        );
      } on Exception catch (error) {
        newer =
            newer ||
            (error is PasskeyBackupException &&
                error.failure == PasskeyBackupFailure.newerVersion);
      }
    }
    // Only a newer app can read them: that beats "none found".
    if (found.isEmpty && newer) {
      throw const PasskeyBackupException(PasskeyBackupFailure.newerVersion);
    }
    return found.values.toList()
      ..sort((a, b) => b.created.compareTo(a.created));
  }
}

part of 'wallet_access_service.dart';

/// The non-secret journal of access records, read one entry at a time.
extension _AccessRecords on WalletAccessService {
  /// Null when the journal as a whole cannot be read.
  Future<Map<String, dynamic>?> _storedRecords() async {
    final raw = await _storage.read(WalletAccessService._recordsKey);
    if (raw == null) return {};
    try {
      final map = raw is String ? jsonDecode(raw) : raw;
      return map is Map ? Map<String, dynamic>.from(map) : null;
    } on Object {
      return null;
    }
  }

  /// Every record this build can read. One it cannot read is skipped and left
  /// in place: it must not cost unrelated wallets their sign-in.
  Future<Map<String, WalletAccessRecord>> _records() async {
    final stored = await _storedRecords() ?? const <String, dynamic>{};
    final records = <String, WalletAccessRecord>{};
    for (final entry in stored.entries) {
      final record = WalletAccessRecord.tryParse(entry.key, entry.value);
      if (record != null) records[entry.key] = record;
    }
    return records;
  }

  /// The record of one wallet. Throws when something is stored for it that
  /// this build cannot read, so that is never mistaken for having no record.
  Future<WalletAccessRecord?> _recordFor(String id) async {
    final stored = await _storedRecords();
    if (stored == null) {
      throw const WalletAccessException(WalletAccessFailure.invalidResponse);
    }
    if (!stored.containsKey(id)) return null;
    return WalletAccessRecord.tryParse(id, stored[id]) ??
        (throw const WalletAccessException(
          WalletAccessFailure.invalidResponse,
        ));
  }

  Future<void> _saveRecord(WalletAccessRecord record) =>
      _updateRecord(record.entryId, (_) => record);

  /// Replaces one entry and leaves every other, readable or not, as stored.
  /// [update] returns null to leave the entry as it is.
  Future<void> _updateRecord(
    String id,
    WalletAccessRecord? Function(WalletAccessRecord? current) update,
  ) => withWalletAccessRecordLock(() async {
    final stored = await _storedRecords();
    if (stored == null) {
      throw const WalletAccessException(WalletAccessFailure.invalidResponse);
    }
    final next = update(
      stored.containsKey(id)
          ? WalletAccessRecord.tryParse(id, stored[id])
          : null,
    );
    if (next == null) return;
    stored[id] = next.toJson();
    await _writeChecked(WalletAccessService._recordsKey, stored);
    _changes.add(null);
  });

  /// The engine reports a different identity for each derivation mode of one
  /// wallet. Once it has verified the password for this session, the record
  /// follows the identity now in use, and so does its stored credential.
  Future<void> _followVerifiedIdentity(KdfUser user) async {
    final hash = user.walletId.pubkeyHash;
    if (hash == null) return;
    try {
      await _updateRecord(
        WalletAccessService.entryId(user),
        (current) =>
            current == null ||
                current.pubkeyHash == null ||
                current.pubkeyHash == hash
            ? null
            : current.copyWith(pubkeyHash: hash),
      );
    } on WalletAccessException {
      // The status then reports the password alone, which is still true.
    }
  }
}

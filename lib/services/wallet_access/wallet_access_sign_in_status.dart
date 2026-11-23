part of 'wallet_access_service.dart';

/// Sign-in status. A restore or a new device can return a wallet and its
/// journal without a usable stored unlock.
extension _SignInStatus on WalletAccessService {
  Future<WalletAccessStatus> _signInStatus(KdfUser user) async {
    final id = WalletAccessService.entryId(user);
    final WalletAccessStatus status;
    try {
      status = await _status(user);
    } on WalletAccessException catch (error) {
      final record = switch (error.failure) {
        WalletAccessFailure.missingCredential ||
        WalletAccessFailure.invalidated => await _recordFor(id),
        _ => null,
      };
      if (record == null) rethrow;
      return _unlockLostStatus(id, record);
    }
    if (user.wallet.isHW) return status;
    final orphan = await _orphanedRecordFor(user);
    return orphan != null && orphan.managed && await _storedUnlockGone(orphan)
        ? _unlockLostStatus(id, orphan)
        : status;
  }

  WalletAccessStatus _unlockLostStatus(String id, WalletAccessRecord record) =>
      WalletAccessStatus(
        entryId: id,
        protection: CredentialProtection.password,
        hasManagedCredential: false,
        requiresAuthentication: true,
        generatedPassword: record.passwordUnseen,
        passwordManager: record.manager,
        lostProtection: record.protection,
      );

  /// Other vault failures leave the wallet's status as it was.
  Future<bool> _storedUnlockGone(WalletAccessRecord record) async {
    try {
      final actual = await _backend.metadata(record.credentialKey);
      return actual == null ||
          (record.requiresAuthentication && !actual.enrolled);
    } on WalletAccessException catch (error) {
      // A restored entry this device cannot decrypt (DPAPI).
      return error.failure == WalletAccessFailure.invalidated;
    }
  }

  /// The record under the wallet's former entry ID, after the SDK rebuilt its
  /// catalog entry from the engine's wallet names with a new one.
  Future<WalletAccessRecord?> _orphanedRecordFor(KdfUser user) async {
    // A verified entry is the wallet's own: any other record under its name
    // belonged to a wallet removed since.
    if (user.walletId.hasFullIdentity) return null;
    try {
      final records = await _records();
      if (records.containsKey(WalletAccessService.entryId(user))) return null;
      final claimed = {
        for (final other in await _sdk.auth.getUsers())
          WalletAccessService.entryId(other),
      };
      final removing = await _cleanup.intentEntryIds;
      final candidates = [
        for (final record in records.values)
          if (record.walletName == user.walletId.name &&
              record.phase == 'ready' &&
              !claimed.contains(record.entryId) &&
              !removing.contains(record.entryId))
            record,
      ];
      return candidates.length == 1 ? candidates.single : null;
    } on Object {
      // Unmatched, the wallet keeps the status it had without this lookup.
      return null;
    }
  }
}

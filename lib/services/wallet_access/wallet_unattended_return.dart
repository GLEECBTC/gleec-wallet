part of 'wallet_access_service.dart';

/// Linux keeps an unattended wallet's password in the Secret Service keyring
/// or an app-local file and has no protected tier. Without this way back, a
/// wallet whose password the app generated could leave a working passkey
/// only through its recovery phrase.
extension _UnattendedReturn on WalletAccessService {
  Future<void> _returnToUnattended(WalletId walletId) => _runAccessOperation((
    revision,
  ) async {
    if (!(await _backend.capabilities()).unattendedReturn) {
      throw const WalletAccessException(WalletAccessFailure.unavailable);
    }
    final user = await _resolve(walletId);
    final session = await _sdk.auth.captureSessionContext();
    // The passkey's assertion is the authorization, and the engine checks
    // the password it opens before anything changes.
    final password = await _authorize(
      walletId,
      reason: 'Open this wallet without the passkey',
      revision: revision,
    );
    final ensureCurrent = captureSensitiveOperation(walletId);
    await _ensureUserCurrent(user, session, revision);
    final record = await _recordFor(WalletAccessService.entryId(user));
    if (record == null || !record.managed) {
      throw const WalletAccessException(WalletAccessFailure.missingCredential);
    }
    final actual = await _backend.metadata(record.credentialKey);
    if (actual == null ||
        actual.protection != CredentialProtection.passkey ||
        actual.revision < 1) {
      throw const WalletAccessException(WalletAccessFailure.unavailable);
    }
    ensureCurrent();
    _ensureSensitiveForeground();
    await unlockCoordinator.runSystemPrompt(
      () => _backend.replacePasskeyWithUnattended(
        record.credentialKey,
        password,
        expectedRevision: actual.revision,
      ),
      waitForForeground: true,
    );
    _ensureRevision(revision);
    final info = await _backend.metadata(record.credentialKey);
    final stored = await _backend.read(
      record.credentialKey,
      reason: 'Confirm wallet storage',
    );
    if (info == null ||
        info.protection == CredentialProtection.passkey ||
        info.enrolled ||
        stored != password) {
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
    ensureCurrent();
    await _saveRecord(
      record.copyWith(
        phase: 'ready',
        managed: true,
        requiresAuthentication: false,
        protection: info.protection,
        clearRotation: true,
      ),
    );
    await _didAuthenticate(
      user,
      expectedRevision: revision,
      ensureAuthorized: ensureCurrent,
    );
    _changes.add(null);
  });
}

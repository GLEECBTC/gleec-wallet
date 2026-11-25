import '../wallet_access_types.dart';

/// Implementations enforce the *stored* policy; passing false must never
/// bypass a previously enrolled record's authentication requirement.
abstract class CredentialBackend {
  Future<CredentialCapabilities> capabilities();
  Future<CredentialRecordInfo?> metadata(String key);
  Future<void> write(
    String key,
    String value, {
    required bool requireAuthentication,
  });
  Future<String?> read(
    String key, {
    required String reason,
    bool requireAuthentication = false,
    bool automatic = false,
    String? purpose,
  });

  /// Preauthorizes one deletion without leaving a secret in the caller.
  /// Protected implementations bind this token to the stored record revision.
  Future<String?> prepareDelete(String key, {required String reason}) async {
    if (await metadata(key) == null) return null;
    throw const WalletAccessException(WalletAccessFailure.unavailable);
  }

  Future<void> delete(String key, {String? authorization});
  Future<void> cancel();

  /// Replaces only an OS-proven invalidated wrapper after the caller has
  /// freshly verified this password with the wallet engine. Always protected.
  Future<void> repairInvalidated(String key, String value) async =>
      throw const WalletAccessException(WalletAccessFailure.unavailable);

  /// Creates a passkey and verifies a subsequent user-verified PRF assertion.
  /// Before returning, authenticate-decrypt both the staged and promoted
  /// envelope with that ceremony's key and compare with [value]. Only verified
  /// staged material may replace unattended access. Callers must not unlock to
  /// repeat this proof. Cancellation/failure must never downgrade protection.
  Future<void> enrollPasskey(
    String key,
    String value, {
    required String label,
  }) async =>
      throw const WalletAccessException(WalletAccessFailure.unavailable);

  /// Binds a passkey the user already holds for the wallet's site, chosen in
  /// one user-verified PRF assertion, and switches the record to it. The
  /// envelope is verified with that ceremony's key before the previous record
  /// is removed; until then the previous protection stays in force. Callers
  /// should first read the credential with purpose `delete` so removing a
  /// protected record needs no second prompt.
  Future<void> bindExistingPasskey(String key, String value) async =>
      throw const WalletAccessException(WalletAccessFailure.unavailable);

  /// Replaces passkey protection with device protection after the
  /// coordinator has verified [value] with the engine, without needing the
  /// passkey. Creating the device record is itself OS-authorized.
  Future<void> replacePasskeyWithDevice(
    String key,
    String value, {
    required int expectedRevision,
  }) async =>
      throw const WalletAccessException(WalletAccessFailure.unavailable);

  /// Where the vault has no protected tier, replaces passkey protection with
  /// the vault's unattended record. The caller authorized it with the
  /// passkey; the envelope is inert from the moment that record exists.
  Future<void> replacePasskeyWithUnattended(
    String key,
    String value, {
    required int expectedRevision,
  }) async =>
      throw const WalletAccessException(WalletAccessFailure.unavailable);

  /// Explicit recovery after the coordinator has freshly verified the supplied
  /// password with the same wallet engine/session. This never decrypts the old
  /// envelope: it stages new verified PRF protection and atomically replaces
  /// only the expected revision. Cancellation must retain the old record.
  /// Where passkeys cannot be created, the new protection is another passkey
  /// the user already holds, bound as [bindExistingPasskey] does.
  Future<void> replacePasskeyAfterPasswordVerification(
    String key,
    String value, {
    required int expectedRevision,
    required String label,
  }) async =>
      throw const WalletAccessException(WalletAccessFailure.unavailable);

  /// Destructive authorization after genuine wallet-password verification by
  /// the coordinator, without releasing the unavailable old PRF secret.
  Future<String?> prepareDeleteAfterPasswordVerification(
    String key, {
    required int expectedRevision,
  }) async =>
      throw const WalletAccessException(WalletAccessFailure.unavailable);
  Future<PasswordManagerOutcome> savePassword({
    required String username,
    required String password,
    required String title,
  });
  Stream<void> get deviceLocked => const Stream.empty();

  /// A change made outside this process, with the credential key it concerns
  /// or null when the source cannot say.
  Stream<String?> get protectionChanged => const Stream.empty();
}

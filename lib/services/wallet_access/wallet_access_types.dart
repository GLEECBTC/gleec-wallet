/// Actual protection of a locally retained wallet credential. This is not a
/// statement about recovery, malware resistance, or the running wallet engine.
enum CredentialProtection {
  authenticationBound,
  recentDeviceAuthenticationBound,
  osAccountProtected,
  browserLocal,
  appLocal,
  passkey,
  password;

  static CredentialProtection parse(Object? value) => values.firstWhere(
    (item) => item.name == value,
    orElse: () =>
        throw const WalletAccessException(WalletAccessFailure.invalidResponse),
  );
}

enum WalletAccessFailure {
  canceled,
  unavailable,
  invalidated,
  lockedOut,
  storageFailed,
  busy,
  invalidResponse,
  missingCredential,
  staleOperation,
  incorrectPassword,
  walletUnavailable,
  prfUnavailable,
  envelopeCorrupt,
  invalidName,
  nameAlreadyUsed,
  walletMustBeUnlocked,
}

/// Deliberately carries no raw platform exception or credential data.
class WalletAccessException implements Exception {
  const WalletAccessException(this.failure);
  final WalletAccessFailure failure;
  @override
  String toString() => 'WalletAccessException(${failure.name})';
}

enum PasswordManagerOutcome {
  offered,
  accepted,
  unknown,
  declined,
  failed,
  unavailable,
}

class CredentialCapabilities {
  const CredentialCapabilities({
    required this.available,
    required this.protection,
    this.deviceAuthentication = false,
    this.passkeyCandidate = false,
  });
  final bool available;
  final CredentialProtection protection;
  final bool deviceAuthentication;
  final bool passkeyCandidate;
}

class CredentialRecordInfo {
  const CredentialRecordInfo({
    required this.protection,
    required this.enrolled,
    this.revision = 0,
  });
  final CredentialProtection protection;
  final bool enrolled;
  final int revision;
}

class WalletAccessStatus {
  const WalletAccessStatus({
    required this.entryId,
    required this.protection,
    required this.hasManagedCredential,
    required this.requiresAuthentication,
    this.generatedPassword = false,
    this.passwordManager = PasswordManagerOutcome.unavailable,
  });
  final String entryId;
  final CredentialProtection protection;
  final bool hasManagedCredential;
  final bool requiresAuthentication;
  final bool generatedPassword;
  final PasswordManagerOutcome passwordManager;
}

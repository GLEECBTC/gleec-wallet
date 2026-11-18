part of 'wallet_protection_bloc.dart';

final class WalletProtectionState extends Equatable {
  const WalletProtectionState({
    this.status,
    this.capabilities,
    this.loading = true,
    this.busy = false,
    this.waitingForPasswordManager = false,
    this.graceSeconds = 30,
    this.failure,
    this.failedAction,
    this.checkFailure,
    this.completed,
    this.activeAction,
  });
  final WalletAccessStatus? status;
  final CredentialCapabilities? capabilities;
  final bool loading;
  final bool busy;
  final bool waitingForPasswordManager;
  final int graceSeconds;

  /// Why the last requested change did not finish, and which change it was.
  /// Both stay until the next request so the user can read the outcome.
  final WalletAccessFailure? failure;
  final WalletProtectionAction? failedAction;

  /// Why the latest status check failed. The next successful check clears it,
  /// so a transient read error never outlives its cause.
  final WalletAccessFailure? checkFailure;
  final WalletProtectionAction? completed;
  final WalletProtectionAction? activeAction;

  bool get canCreatePasskey =>
      capabilities?.available == true &&
      capabilities?.passkeyCandidate == true &&
      status?.protection != CredentialProtection.passkey;
  bool get canEnableDevice =>
      capabilities?.available == true &&
      capabilities?.deviceAuthentication == true &&
      (status?.requiresAuthentication == false ||
          status?.protection == CredentialProtection.password);

  /// A passkey the user already holds can protect this wallet instead of its
  /// current lock. Browsers create passkeys instead, so this is native only.
  bool get canUseExistingPasskey =>
      capabilities?.available == true &&
      capabilities?.existingPasskeyCandidate == true &&
      status?.protection != CredentialProtection.passkey;

  /// A native passkey-protected wallet can return to device unlock.
  bool get canSwitchToDevice =>
      capabilities?.available == true &&
      capabilities?.deviceAuthentication == true &&
      status?.protection == CredentialProtection.passkey;

  /// A native passkey wallet can return to unattended storage where the
  /// device has no device unlock to return to.
  bool get canUseDeviceStorage =>
      capabilities?.available == true &&
      capabilities?.unattendedReturn == true &&
      status?.protection == CredentialProtection.passkey;

  /// Another passkey can replace a lost one after password verification.
  bool get canReplacePasskey =>
      status?.protection == CredentialProtection.passkey &&
      (capabilities?.passkeyCandidate == true ||
          capabilities?.existingPasskeyCandidate == true);

  /// A native passkey wallet can always fall back to its password alone.
  bool get canUsePasswordOnly =>
      status?.protection == CredentialProtection.passkey &&
      capabilities?.available == true &&
      capabilities?.protection != CredentialProtection.browserLocal;

  WalletProtectionState copyWith({
    WalletAccessStatus? status,
    CredentialCapabilities? capabilities,
    bool? loading,
    bool? busy,
    bool? waitingForPasswordManager,
    int? graceSeconds,
    WalletAccessFailure? failure,
    WalletProtectionAction? failedAction,
    WalletAccessFailure? checkFailure,
    WalletProtectionAction? completed,
    WalletProtectionAction? activeAction,
    bool clearNotice = false,
    bool clearFailure = false,
    bool clearCheckFailure = false,
  }) {
    final dropFailure = clearNotice || clearFailure;
    return WalletProtectionState(
      status: status ?? this.status,
      capabilities: capabilities ?? this.capabilities,
      loading: loading ?? this.loading,
      busy: busy ?? this.busy,
      waitingForPasswordManager:
          waitingForPasswordManager ?? this.waitingForPasswordManager,
      graceSeconds: graceSeconds ?? this.graceSeconds,
      failure: dropFailure ? null : failure ?? this.failure,
      failedAction: dropFailure ? null : failedAction ?? this.failedAction,
      checkFailure: clearCheckFailure
          ? null
          : checkFailure ?? this.checkFailure,
      completed: clearNotice ? null : completed ?? this.completed,
      activeAction: (busy ?? this.busy)
          ? activeAction ?? this.activeAction
          : null,
    );
  }

  @override
  List<Object?> get props => [
    status,
    capabilities,
    loading,
    busy,
    waitingForPasswordManager,
    graceSeconds,
    failure,
    failedAction,
    checkFailure,
    completed,
    activeAction,
  ];
}

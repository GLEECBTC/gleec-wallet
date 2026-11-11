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
    this.completed,
  });
  final WalletAccessStatus? status;
  final CredentialCapabilities? capabilities;
  final bool loading;
  final bool busy;
  final bool waitingForPasswordManager;
  final int graceSeconds;
  final WalletAccessFailure? failure;
  final WalletProtectionAction? completed;

  bool get canCreatePasskey =>
      capabilities?.available == true &&
      capabilities?.passkeyCandidate == true &&
      status?.protection != CredentialProtection.passkey;
  bool get canEnableDevice =>
      capabilities?.available == true &&
      capabilities?.deviceAuthentication == true &&
      (status?.requiresAuthentication == false ||
          status?.protection == CredentialProtection.password);

  WalletProtectionState copyWith({
    WalletAccessStatus? status,
    CredentialCapabilities? capabilities,
    bool? loading,
    bool? busy,
    bool? waitingForPasswordManager,
    int? graceSeconds,
    WalletAccessFailure? failure,
    WalletProtectionAction? completed,
    bool clearNotice = false,
    bool clearFailure = false,
  }) => WalletProtectionState(
    status: status ?? this.status,
    capabilities: capabilities ?? this.capabilities,
    loading: loading ?? this.loading,
    busy: busy ?? this.busy,
    waitingForPasswordManager:
        waitingForPasswordManager ?? this.waitingForPasswordManager,
    graceSeconds: graceSeconds ?? this.graceSeconds,
    failure: clearNotice || clearFailure ? null : failure ?? this.failure,
    completed: clearNotice ? null : completed ?? this.completed,
  );

  @override
  List<Object?> get props => [
    status,
    capabilities,
    loading,
    busy,
    waitingForPasswordManager,
    graceSeconds,
    failure,
    completed,
  ];
}

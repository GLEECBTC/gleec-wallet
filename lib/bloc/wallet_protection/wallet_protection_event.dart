part of 'wallet_protection_bloc.dart';

sealed class WalletProtectionEvent extends Equatable {
  const WalletProtectionEvent();
  @override
  List<Object?> get props => const [];
}

final class WalletProtectionRefreshed extends WalletProtectionEvent {
  const WalletProtectionRefreshed({this.manual = false});

  /// The user asked for it, so the check is shown while it runs.
  final bool manual;
  @override
  List<Object?> get props => [manual];
}

enum WalletProtectionAction {
  passkey,

  /// Bind a passkey the user already holds for the web wallet (native apps).
  existingPasskey,
  device,
  replacePasskey,

  /// Remove a lost native passkey so the wallet opens with its password.
  passwordOnly,
  grace,
}

final class WalletProtectionRequested extends WalletProtectionEvent {
  const WalletProtectionRequested(
    this.action, {
    this.password,
    this.graceSeconds,
  });
  final WalletProtectionAction action;
  // Short-lived input only; never copied into state or diagnostic props.
  final String? password;
  final int? graceSeconds;
  @override
  List<Object?> get props => [action, graceSeconds];
}

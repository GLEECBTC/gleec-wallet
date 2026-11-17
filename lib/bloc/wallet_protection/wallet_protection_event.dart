part of 'wallet_protection_bloc.dart';

sealed class WalletProtectionEvent extends Equatable {
  const WalletProtectionEvent();
  @override
  List<Object?> get props => const [];
}

final class WalletProtectionRefreshed extends WalletProtectionEvent {
  const WalletProtectionRefreshed();
}

enum WalletProtectionAction { passkey, device, replacePasskey, grace }

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

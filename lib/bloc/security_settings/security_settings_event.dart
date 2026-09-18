import 'package:equatable/equatable.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';

/// Base class for all security settings events.
abstract class SecuritySettingsEvent extends Equatable {
  const SecuritySettingsEvent();

  @override
  List<Object> get props => [];
}

/// Event to reset the security settings to the initial state.
class ResetEvent extends SecuritySettingsEvent {
  const ResetEvent();
}

/// Event to show the seed phrase backup screen.
class ShowSeedEvent extends SecuritySettingsEvent {
  const ShowSeedEvent();
}

/// Event to proceed to seed phrase confirmation.
class SeedConfirmEvent extends SecuritySettingsEvent {
  const SeedConfirmEvent();
}

/// Event when the user has confirmed they saved their seed phrase.
class SeedConfirmedEvent extends SecuritySettingsEvent {
  const SeedConfirmedEvent();
}

/// Event to toggle visibility of seed words in the UI.
class ShowSeedWordsEvent extends SecuritySettingsEvent {
  const ShowSeedWordsEvent(this.isShow);
  final bool isShow;
}

/// Event when seed phrase has been copied to clipboard.
class ShowSeedCopiedEvent extends SecuritySettingsEvent {
  const ShowSeedCopiedEvent();
}

/// Event to show the password update screen.
class PasswordUpdateEvent extends SecuritySettingsEvent {
  const PasswordUpdateEvent();
}

/// Legacy sign-in presence check for compatibility navigation.
/// The current export BLoC independently verifies the password and session.
class AuthenticateForPrivateKeysEvent extends SecuritySettingsEvent {
  const AuthenticateForPrivateKeysEvent();
}

/// Selects the export result screen. The export BLoC retains the result.
class ShowPrivateKeysEvent extends SecuritySettingsEvent {
  const ShowPrivateKeysEvent();
}

/// Event to toggle visibility of private keys in the UI.
///
/// **Security Note**: This only controls UI visibility state.
/// This legacy visibility flag is not used by the current export flow.
class ShowPrivateKeysWordsEvent extends SecuritySettingsEvent {
  const ShowPrivateKeysWordsEvent(this.isShow);
  final bool isShow;

  @override
  List<Object> get props => [isShow];
}

/// Event when private keys have been copied to clipboard.
class ShowPrivateKeysCopiedEvent extends SecuritySettingsEvent {
  const ShowPrivateKeysCopiedEvent();
}

/// Event to download private keys to a file.
class PrivateKeysDownloadRequestedEvent extends SecuritySettingsEvent {
  const PrivateKeysDownloadRequestedEvent();
}

/// Event to clear any authentication errors.
class ClearAuthenticationErrorEvent extends SecuritySettingsEvent {
  const ClearAuthenticationErrorEvent();
}

/// Event to trigger unbanning of all banned public keys.
///
/// This operation does not require password authentication as it's considered
/// a non-destructive action that improves wallet functionality.
class UnbanPubkeysEvent extends SecuritySettingsEvent {
  const UnbanPubkeysEvent();
}

/// Event when pubkey unbanning completes successfully.
class UnbanPubkeysCompletedEvent extends SecuritySettingsEvent {
  const UnbanPubkeysCompletedEvent(this.result);

  final UnbanPubkeysResult result;

  @override
  List<Object> get props => [result];
}

/// Event when pubkey unbanning fails.
class UnbanPubkeysFailedEvent extends SecuritySettingsEvent {
  const UnbanPubkeysFailedEvent(this.error);

  final String error;

  @override
  List<Object> get props => [error];
}

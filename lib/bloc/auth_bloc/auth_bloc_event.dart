part of 'auth_bloc.dart';

abstract class AuthBlocEvent {
  const AuthBlocEvent();
}

class AuthModeChanged extends AuthBlocEvent {
  const AuthModeChanged({required this.mode, required this.currentUser});

  final AuthorizeMode mode;
  final KdfUser? currentUser;
}

class AuthStateClearRequested extends AuthBlocEvent {
  const AuthStateClearRequested();
}

class AuthSignOutRequested extends AuthBlocEvent {
  const AuthSignOutRequested();
}

class AuthSignInRequested extends AuthBlocEvent {
  const AuthSignInRequested({required this.wallet, required this.password});

  final Wallet wallet;
  final String password;
}

class AuthErrorReported extends AuthBlocEvent {
  const AuthErrorReported(this.error);

  final AuthException error;
}

class AuthRegisterRequested extends AuthBlocEvent {
  const AuthRegisterRequested({required this.wallet, required this.password});

  final Wallet wallet;
  final String password;
}

class AuthRestoreRequested extends AuthBlocEvent {
  const AuthRestoreRequested({
    required this.wallet,
    required this.password,
    required this.seed,
    this.legacyNativeSecrets,
  });

  final Wallet wallet;
  final String password;
  final String seed;
  final LegacyWalletSecrets? legacyNativeSecrets;
}

/// A user-initiated seed import.
///
/// Split from [AuthRestoreRequested] because the two want opposite behaviour on
/// a wallet-name collision. Restore falls back to signing into the existing
/// wallet, which is what the debug auto-login path relies on. For a real
/// import that fallback is destructive to intent: the seed the user just typed
/// is discarded and they are signed into a *different* wallet, with only a log
/// line to say so. This event fails loudly instead.
class AuthImportRequested extends AuthBlocEvent {
  const AuthImportRequested({
    required this.wallet,
    required this.password,
    required this.seed,
  });

  final Wallet wallet;
  final String password;
  final String seed;
}

class AuthLegacyMigrationRequested extends AuthBlocEvent {
  const AuthLegacyMigrationRequested({
    required this.sourceWallet,
    required this.legacyPassword,
    required this.kdfPassword,
    required this.targetWalletName,
    required this.seedPhrase,
    this.requestedZhtlcCoinIds = const <String>[],
    this.zhtlcSyncPolicy,
    this.legacyWalletExtras = const <String, dynamic>{},
    this.legacyNativeSecrets,
  });

  final Wallet sourceWallet;
  final String legacyPassword;
  final String kdfPassword;
  final String targetWalletName;
  final String seedPhrase;
  final List<String> requestedZhtlcCoinIds;
  final ZhtlcRecurringSyncPolicy? zhtlcSyncPolicy;
  final Map<String, dynamic> legacyWalletExtras;
  final LegacyWalletSecrets? legacyNativeSecrets;
}

class AuthSeedBackupConfirmed extends AuthBlocEvent {
  const AuthSeedBackupConfirmed({required this.expectedWalletId});

  /// The wallet whose recovery phrase was confirmed.
  final WalletId expectedWalletId;
}

class AuthWalletDownloadRequested extends AuthBlocEvent {
  const AuthWalletDownloadRequested({
    required this.password,
    required this.expectedWalletId,
  });
  final String password;
  final WalletId expectedWalletId;
}

/// Dispatched to restore authentication state after the SDK has been
/// initialized. If a user session exists, the bloc will emit the
/// appropriate [AuthBlocState].
class AuthStateRestoreRequested extends AuthBlocEvent {
  const AuthStateRestoreRequested();
}

class AuthTrezorInitAndAuthStarted extends AuthBlocEvent {
  const AuthTrezorInitAndAuthStarted();
}

class AuthTrezorPinProvided extends AuthBlocEvent {
  const AuthTrezorPinProvided(this.pin);

  final String pin;
}

class AuthTrezorPassphraseProvided extends AuthBlocEvent {
  const AuthTrezorPassphraseProvided(this.passphrase);

  final String passphrase;
}

class AuthTrezorCancelled extends AuthBlocEvent {
  const AuthTrezorCancelled();
}

/// Event emitted on app lifecycle changes to check if a user is already signed
/// in and restore the auth state.
class AuthLifecycleCheckRequested extends AuthBlocEvent {
  const AuthLifecycleCheckRequested();
}

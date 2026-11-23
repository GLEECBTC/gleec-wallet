part of 'auth_bloc.dart';

abstract class AuthBlocEvent {
  const AuthBlocEvent();
}

class AuthModeChanged extends AuthBlocEvent {
  const AuthModeChanged({required this.mode, required this.currentUser});

  final AuthorizeMode mode;
  final KdfUser? currentUser;
}

/// A watcher result is only applicable to the auth flow that subscribed.
class _AuthUserObserved extends AuthModeChanged {
  const _AuthUserObserved({
    required super.mode,
    required super.currentUser,
    required this.revision,
  });
  final int revision;
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

class AuthQuickCreateRequested extends AuthBlocEvent {
  const AuthQuickCreateRequested({
    this.walletType = WalletType.hdwallet,
    this.useDeviceProtection = true,
  });
  final WalletType walletType;
  final bool useDeviceProtection;
}

/// Where a wallet opened by [AuthManagedImportRequested] came from.
enum ManagedImportSource { movedFromDevice, passkeyBackup }

/// Opens a wallet moved from another device or restored from a passkey
/// backup. Like quick create, this device keeps a generated password, so
/// nothing is typed. The wallet's own name is used; a name already taken
/// here fails with `walletAlreadyExists` instead of being changed silently.
class AuthManagedImportRequested extends AuthBlocEvent {
  const AuthManagedImportRequested({
    required this.secret,
    required this.walletName,
    required this.source,
    this.useDeviceProtection = true,
  });

  final WalletTransferSecret secret;

  /// The name to save it under: the secret's own, or one the user chose
  /// because that one is taken here.
  final String walletName;
  final ManagedImportSource source;
  final bool useDeviceProtection;
}

class AuthManagedSignInRequested extends AuthBlocEvent {
  const AuthManagedSignInRequested({
    required this.wallet,
    this.automatic = false,
    this.generatedPassword = false,
  });
  final Wallet wallet;
  final bool automatic;

  /// The wallet's password was created for it and never shown, so a failure
  /// must not advise typing it.
  final bool generatedPassword;
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
/// Creation and restoration all reject wallet-name collisions in the SDK.
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
    this.ensureAuthorized,
    this.selectDestination,
    this.onFinished,
  });
  final String password;
  final WalletId expectedWalletId;
  final void Function()? ensureAuthorized;
  final GuardedDestinationSelector? selectDestination;

  /// Called once the request ends, however it ends.
  final void Function()? onFinished;
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

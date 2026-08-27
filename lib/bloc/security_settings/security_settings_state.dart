import 'package:equatable/equatable.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';

/// Represents the different steps in the security settings flow.
/// Each step corresponds to a different screen or phase of the user journey.
enum SecuritySettingsStep {
  /// The main security settings screen with backup options.
  securityMain,

  /// The screen showing the seed words for backup.
  seedShow,

  /// The screen confirming that the seed words have been written down.
  seedConfirm,

  /// The screen showing that the seed words have been successfully confirmed.
  seedSuccess,

  /// The screen showing the private keys for export.
  /// Note: Actual private key data is NOT stored in state for security reasons.
  privateKeyShow,

  /// The screen for updating the wallet password.
  passwordUpdate,
}

/// State for the security settings flow.
///
/// **Security Note**: This state intentionally does NOT contain actual private
/// key data. Private keys are handled directly in the UI layer to minimize
/// their memory lifetime and exposure. Only authentication status and flow
/// control state is managed here.
class SecuritySettingsState extends Equatable {
  const SecuritySettingsState({
    required this.step,
    required this.showSeedWords,
    required this.isSeedSaved,
    required this.showPrivateKeys,
    required this.arePrivateKeysSaved,
    required this.isAuthenticating,
    required this.privateKeyAuthenticationSuccess,
    required this.authError,
    required this.isUnbanningPubkeys,
    this.unbanResult,
    this.unbanError,
    this.backupStartedAt,
  });

  factory SecuritySettingsState.initialState() {
    return const SecuritySettingsState(
      step: SecuritySettingsStep.securityMain,
      showSeedWords: false,
      isSeedSaved: false,
      showPrivateKeys: false,
      arePrivateKeysSaved: false,
      isAuthenticating: false,
      privateKeyAuthenticationSuccess: false,
      authError: null,
      isUnbanningPubkeys: false,
      unbanResult: null,
      unbanError: null,
    );
  }

  /// The current step of the security settings flow.
  final SecuritySettingsStep step;

  /// Whether the seed words are currently being shown.
  final bool showSeedWords;

  /// Whether the seed words have been written down or saved somewhere by the user.
  final bool isSeedSaved;

  /// Whether the private keys are currently being shown.
  /// Note: This only controls UI visibility, not the actual private key data.
  final bool showPrivateKeys;

  /// Whether the private keys have been written down or saved somewhere by the user.
  final bool arePrivateKeysSaved;

  /// Whether authentication is currently in progress for private key access.
  final bool isAuthenticating;

  /// Whether authentication for private key access was successful.
  /// This triggers the UI to fetch private keys from the SDK.
  final bool privateKeyAuthenticationSuccess;

  /// Any authentication error that occurred during private key access.
  final String? authError;

  /// Whether pubkey unbanning is currently in progress.
  final bool isUnbanningPubkeys;

  /// Result of the last unban operation, if any.
  final UnbanPubkeysResult? unbanResult;

  /// Error message if the last unban operation failed.
  final String? unbanError;

  /// When the user entered a backup flow (seed reveal or private-key export).
  ///
  /// The anchor for `backup_complete`'s `backup_time`, which was previously
  /// hardcoded to 0 and so measured nothing. Null outside a backup flow, which
  /// is why the event falls back to 0 rather than inventing a duration.
  final DateTime? backupStartedAt;

  /// How long the current backup flow has been open, or null outside one.
  Duration? get backupElapsed => backupStartedAt == null
      ? null
      : DateTime.now().difference(backupStartedAt!);

  @override
  List<Object?> get props => [
    step,
    showSeedWords,
    isSeedSaved,
    showPrivateKeys,
    arePrivateKeysSaved,
    isAuthenticating,
    privateKeyAuthenticationSuccess,
    authError,
    isUnbanningPubkeys,
    unbanResult,
    unbanError,
    backupStartedAt,
  ];

  /// Creates a copy of this state with the given fields replaced with new values.
  SecuritySettingsState copyWith({
    SecuritySettingsStep? step,
    bool? showSeedWords,
    bool? isSeedSaved,
    bool? showPrivateKeys,
    bool? arePrivateKeysSaved,
    bool? isAuthenticating,
    bool? privateKeyAuthenticationSuccess,
    String? authError,
    bool clearAuthError = false,
    bool? isUnbanningPubkeys,
    UnbanPubkeysResult? unbanResult,
    String? unbanError,
    bool clearUnbanError = false,
    DateTime? backupStartedAt,
    bool clearBackupStartedAt = false,
  }) {
    return SecuritySettingsState(
      step: step ?? this.step,
      showSeedWords: showSeedWords ?? this.showSeedWords,
      isSeedSaved: isSeedSaved ?? this.isSeedSaved,
      showPrivateKeys: showPrivateKeys ?? this.showPrivateKeys,
      arePrivateKeysSaved: arePrivateKeysSaved ?? this.arePrivateKeysSaved,
      isAuthenticating: isAuthenticating ?? this.isAuthenticating,
      privateKeyAuthenticationSuccess:
          privateKeyAuthenticationSuccess ??
          this.privateKeyAuthenticationSuccess,
      authError: clearAuthError ? null : (authError ?? this.authError),
      isUnbanningPubkeys: isUnbanningPubkeys ?? this.isUnbanningPubkeys,
      unbanResult: unbanResult ?? this.unbanResult,
      unbanError: clearUnbanError ? null : (unbanError ?? this.unbanError),
      backupStartedAt: clearBackupStartedAt
          ? null
          : (backupStartedAt ?? this.backupStartedAt),
    );
  }
}

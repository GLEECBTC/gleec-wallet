part of 'wallet_protection_panel.dart';

/// What the wallet lock looks like right now: the words and icons both
/// presentations of [WalletProtectionPanel] share.
class _ProtectionView {
  const _ProtectionView({
    required this.state,
    required this.collectingInput,
    required this.typedPassword,
    required this.providerPending,
  });

  final WalletProtectionState state;
  final bool collectingInput;
  final bool typedPassword;
  final bool providerPending;

  WalletAccessStatus? get status => state.status;
  bool get passkey => status?.protection == CredentialProtection.passkey;
  bool get protected => status?.requiresAuthentication == true;

  /// Neither a passkey nor device unlock can be turned on here.
  bool get unavailable =>
      !protected && !state.canCreatePasskey && !state.canEnableDevice;

  /// A request cannot start yet. The buttons are disabled for this, but not
  /// while their own request runs: a disabled button drops keyboard focus,
  /// and the user would lose their place when the system prompt closes.
  bool get blocked =>
      state.loading || state.waitingForPasswordManager || providerPending;

  bool get showsProgress =>
      state.busy || collectingInput || state.waitingForPasswordManager;

  /// The one-step way to turn the lock on, when this device offers one. An
  /// existing passkey is never it: most people have none for the web wallet,
  /// so it stays an alternative beside this.
  WalletProtectionAction? get setupAction => state.canCreatePasskey
      ? WalletProtectionAction.passkey
      : state.canEnableDevice
      ? WalletProtectionAction.device
      : null;

  /// Names the lock that stopped working. Native apps can lose either kind,
  /// and what is offered in its place may be the other one.
  bool get _lostPasskey => _storedInBrowser
      ? setupAction == WalletProtectionAction.passkey
      : status?.lostProtection == CredentialProtection.passkey;

  /// The wallet fell back to a password it created itself: the passkey or
  /// device unlock it had stopped working, and can be set up again.
  bool get lockMethodLost =>
      protected &&
      status?.protection == CredentialProtection.password &&
      status?.generatedPassword == true &&
      setupAction != null;

  /// The lock that is on, for the checklist's finished step.
  String get readyTitle =>
      (passkey
              ? 'authPasskeyReadyTitle'
              : status?.protection == CredentialProtection.password
              ? 'authPasswordReadyTitle'
              : 'authDeviceReadyTitle')
          .tr();

  String get title =>
      (lockMethodLost
              ? _lostPasskey
                    ? 'authPasskeyOffTitle'
                    : 'authDeviceUnlockOffTitle'
              : passkey
              ? 'authPasskeyReadyTitle'
              : protected
              ? status?.protection == CredentialProtection.password
                    ? 'authPasswordReadyTitle'
                    : 'authDeviceReadyTitle'
              : state.canCreatePasskey
              ? 'authPasskeySetupTitle'
              : state.canEnableDevice
              ? 'authDeviceSetupTitle'
              : 'authUnprotectedTitle')
          .tr();

  /// One sentence for the settings section.
  String get description =>
      (lockMethodLost
              ? !_lostPasskey
                    ? 'authDeviceUnlockOffDescription'
                    : _storedInBrowser
                    ? 'authPasskeyOffDescription'
                    : 'authExistingPasskeyOffDescription'
              : passkey
              ? _storedInBrowser
                    ? 'authPasskeyProtected'
                    : 'authPasskeyProtectedDevice'
              : protected
              ? status?.protection == CredentialProtection.password
                    ? 'authPasswordProtected'
                    : status?.protection ==
                          CredentialProtection.osAccountProtected
                    ? 'authOsAccountProtected'
                    : 'authDeviceProtected'
              : setupAction != null
              // The wording covers a passkey and device unlock alike.
              ? 'authPasskeySetupDescription'
              : _storedInBrowser
              ? 'authBrowserUnprotected'
              : 'authDeviceUnprotected')
          .tr();

  /// The single supporting line of the settings section: how far the lock
  /// reaches, or why it cannot be turned on in one step.
  String? get supportingLine => protected
      ? null
      : state.canCreatePasskey
      ? 'authPasskeyLocalScopeCompact'.tr()
      : state.canEnableDevice
      ? 'authDeviceLocalScope'.tr()
      : unavailableReason;

  /// One line for the checklist step on the wallet page.
  String get stepDescription => state.canCreatePasskey
      ? 'authPasskeyStepDescription'.tr()
      : state.canEnableDevice
      ? 'authDeviceStepDescription'.tr()
      : unavailableReason;

  bool get _storedInBrowser =>
      kIsWeb ||
      (state.capabilities?.protection ?? status?.protection) ==
          CredentialProtection.browserLocal;

  bool get _securityKeys =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  String get unavailableReason {
    if (_storedInBrowser) {
      return (WalletAccessService.passkeyEnrollmentEnabled
              ? 'authLockUnavailablePasskeys'
              : 'authLockUnavailablePlatform')
          .tr();
    }
    final phone =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    // A phone or tablet always has device unlock unless no screen lock is set.
    return (phone && WalletAccessService.deviceEnrollmentEnabled
            ? 'authLockUnavailableScreenLock'
            : 'authLockUnavailablePlatform')
        .tr();
  }

  Widget icon({double? size}) => passkey || state.canCreatePasskey
      ? WalletPasskeyIcon(size: size ?? 24)
      : Icon(
          protected
              ? Icons.lock_outline
              : state.canEnableDevice
              ? Icons.fingerprint
              : Icons.lock_open_outlined,
        );

  Widget actionIcon(WalletProtectionAction action) =>
      action == WalletProtectionAction.device
      ? const Icon(Icons.fingerprint)
      : const WalletPasskeyIcon();

  String actionLabel(WalletProtectionAction action) =>
      (action == WalletProtectionAction.device
              ? 'authEnableDeviceUnlock'
              : 'authCreatePasskey')
          .tr();

  /// The passkey is chosen from those the user holds rather than created.
  bool _choosesPasskey(WalletProtectionAction? action) =>
      action == WalletProtectionAction.existingPasskey ||
      (action == WalletProtectionAction.replacePasskey && !_storedInBrowser);

  String get pendingMessage =>
      (state.waitingForPasswordManager
              ? 'authPasswordManagerPending'
              : _choosesPasskey(state.activeAction)
              ? 'authExistingPasskeyPending'
              : state.activeAction == WalletProtectionAction.passwordOnly
              ? 'authPasskeyRemoving'
              : state.activeAction == WalletProtectionAction.deviceStorage
              ? 'authOpenWithoutPasskeyPending'
              : state.activeAction == WalletProtectionAction.passkey ||
                    state.activeAction == WalletProtectionAction.replacePasskey
              ? 'authPasskeySetupPending'
              : 'authProtectionPending')
          .tr();

  /// Why the last request did not finish, in the words of what was asked.
  String? get failureText {
    final failure = state.failure;
    if (failure == null) return null;
    final action = state.failedAction;
    if (action == WalletProtectionAction.grace) {
      return walletAccessFailureText(
        WalletAccessException(failure),
        passwordEntered: typedPassword,
        unlocking: false,
      );
    }
    final aboutPasskey =
        action == WalletProtectionAction.passkey ||
        action == WalletProtectionAction.replacePasskey;
    final chosen = _choosesPasskey(action);
    return switch (failure) {
      WalletAccessFailure.busy => 'authProtectionBusy',
      WalletAccessFailure.staleOperation => 'authProtectionStale',
      WalletAccessFailure.canceled => 'authProtectionCanceled',
      // Linux reaches passkeys on security keys only.
      WalletAccessFailure.passkeyNotFound when _securityKeys =>
        'authSecurityKeyPasskeyNotFound',
      WalletAccessFailure.passkeyNotFound => 'authExistingPasskeyNotFound',
      WalletAccessFailure.prfUnavailable || WalletAccessFailure.unavailable
          when chosen && _securityKeys =>
        'authSecurityKeyUnsupported',
      WalletAccessFailure.prfUnavailable when chosen =>
        'authExistingPasskeyUnsupported',
      WalletAccessFailure.unavailable when chosen =>
        'authExistingPasskeyProviderError',
      WalletAccessFailure.prfUnavailable || WalletAccessFailure.unavailable
          when aboutPasskey =>
        'authPasskeyUnsupported',
      _ => 'authProtectionFailed',
    }.tr();
  }

  WalletAccessTone get failureTone =>
      state.failure == WalletAccessFailure.canceled ||
          state.failure == WalletAccessFailure.busy
      ? WalletAccessTone.info
      : WalletAccessTone.error;

  String? get completedText => switch (state.completed) {
    null => null,
    WalletProtectionAction.existingPasskey => 'authExistingPasskeyReady'.tr(),
    WalletProtectionAction.replacePasskey =>
      (_storedInBrowser ? 'authPasskeyReplaced' : 'authPasskeyChosen').tr(),
    WalletProtectionAction.grace => 'authLockPreferenceSaved'.tr(),
    WalletProtectionAction.passwordOnly => 'authPasskeyRemoved'.tr(),
    WalletProtectionAction.deviceStorage => 'authOpenedWithoutPasskey'.tr(),
    _ => 'authProtectionEnabled'.tr(),
  };

  String get checkFailureText =>
      (state.checkFailure == WalletAccessFailure.staleOperation
              ? 'authProtectionStale'
              : 'authProtectionCheckFailed')
          .tr();

  /// A password nobody chose and no password manager holds: worth saying,
  /// because the wallet's password prompts cannot be answered from memory.
  bool get generatedPasswordUnsaved =>
      status?.generatedPassword == true &&
      (status?.passwordManager == PasswordManagerOutcome.declined ||
          status?.passwordManager == PasswordManagerOutcome.failed);
}

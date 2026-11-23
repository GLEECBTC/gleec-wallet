part of 'wallet_protection_panel.dart';

typedef _ProtectionRequest = Future<void> Function(
  WalletProtectionAction action, {
  int? grace,
  bool withPassword,
});

extension on _WalletProtectionPanelState {
  /// The full section in Security settings: a sibling of the other plates.
  Widget _buildSettings(BuildContext context, _ProtectionView view) {
    if (view.status == null) {
      return SecuritySectionCard(
        child: view.state.loading
            ? WalletAccessProgress(
                label: 'authProtectionChecking'.tr(),
                showLabel: true,
              )
            : _CheckFailed(view: view, onRetry: _retryCheck),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = SecurityActionPlate.isWide(context, constraints);
        final supporting = view.supportingLine;
        final details = <Widget>[
          ?_feedback(view, withOutcome: true),
          if (view.protected) _LockTiming(view: view, onRequest: _request),
          if (view.passkey &&
              (view.state.canReplacePasskey ||
                  view.state.canSwitchToDevice ||
                  view.state.canUsePasswordOnly))
            _ReplacePasskey(view: view, wide: wide, onRequest: _request),
          if (view.generatedPasswordUnsaved)
            WalletAccessNotice(
              text: 'authGeneratedPasswordNotSaved'.tr(),
              announce: false,
            ),
        ];
        return SecurityActionPlate(
          icon: view.icon(size: 50),
          title: view.title,
          description: view.description,
          status: supporting == null
              ? null
              : Text(
                  supporting,
                  style: SecuritySectionText.supporting(context),
                  textAlign: wide ? TextAlign.start : TextAlign.center,
                ),
          trailingWidget: _actions(view, wide),
          details: details.isEmpty
              ? null
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 20,
                  children: details,
                ),
        );
      },
    );
  }

  /// The primary way to turn the lock on, and the quieter alternatives: device
  /// unlock where a passkey leads, and the other native lock either way.
  Widget? _actions(_ProtectionView view, bool wide) {
    final state = view.state;
    final setUp = view.setupAction;
    final setPassword = widget.onSetPassword;
    final width = wide ? SecurityActionPlate.actionWidth : double.infinity;
    Widget? primary;
    if (setUp != null) {
      primary = UiPrimaryButton(
        key: Key(
          setUp == WalletProtectionAction.passkey
              ? 'enable-passkey-unlock'
              : 'enable-device-unlock',
        ),
        expandForText: true,
        width: width,
        onPressed: view.blocked ? null : () => _request(setUp),
        prefix: Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: view.actionIcon(setUp),
        ),
        text: view.actionLabel(setUp),
      );
    } else if (view.unavailable && setPassword != null) {
      primary = UiPrimaryButton(
        key: const Key('set-wallet-password'),
        expandForText: true,
        width: width,
        onPressed: setPassword,
        text: 'authSetWalletPassword'.tr(),
      );
    }
    final alternatives = <Widget>[
      if (state.canCreatePasskey && state.canEnableDevice)
        SecuritySecondaryButton(
          key: const Key('enable-device-unlock'),
          icon: const Icon(Icons.fingerprint),
          text: 'authEnableDeviceUnlock'.tr(),
          onPressed: view.blocked
              ? null
              : () => _request(WalletProtectionAction.device),
        ),
      if (state.canUseExistingPasskey)
        SecuritySecondaryButton(
          key: const Key('use-existing-passkey'),
          icon: const WalletPasskeyIcon(size: 20),
          text: 'authUseExistingPasskey'.tr(),
          onPressed: view.blocked
              ? null
              : () => _request(WalletProtectionAction.existingPasskey),
        ),
      if (state.canSwitchToDevice)
        SecuritySecondaryButton(
          key: const Key('switch-to-device-unlock'),
          icon: const Icon(Icons.fingerprint),
          text: 'authUseDeviceUnlockInstead'.tr(),
          onPressed: view.blocked
              ? null
              : () => _request(WalletProtectionAction.device),
        ),
    ];
    if (primary == null && alternatives.isEmpty) return null;
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [?primary, ...alternatives],
      ),
    );
  }
}

/// When the wallet locks after the app is left.
class _LockTiming extends StatelessWidget {
  const _LockTiming({required this.view, required this.onRequest});

  final _ProtectionView view;
  final _ProtectionRequest onRequest;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        header: true,
        child: Text(
          'authLockAfterTitle'.tr(),
          style: SecuritySectionText.label(context),
        ),
      ),
      const SizedBox(height: 4),
      // A build that must lock at once would ignore any other choice.
      if (WalletAccessService.immediateLockRequired)
        WalletAccessNotice(
          text: 'authLockAlwaysImmediate'.tr(),
          announce: false,
        )
      else ...[
        WalletLockTimingChoice(
          selectedSeconds: view.state.graceSeconds,
          onSelected: (seconds) =>
              onRequest(WalletProtectionAction.grace, grace: seconds),
        ),
        const SizedBox(height: 4),
        Text(
          'authLockGraceDescription'.tr(),
          style: SecuritySectionText.supporting(context),
        ),
      ],
    ],
  );
}

/// The way back in when the passkey itself is gone: a new or another passkey,
/// and on native apps device unlock or the password alone, each authorized
/// by the wallet password.
class _ReplacePasskey extends StatelessWidget {
  const _ReplacePasskey({
    required this.view,
    required this.wide,
    required this.onRequest,
  });

  final _ProtectionView view;
  final bool wide;
  final _ProtectionRequest onRequest;

  @override
  Widget build(BuildContext context) {
    final generated = view.status?.generatedPassword == true;
    final description = Text(
      // A password the wallet created is not one the user can recall, so say
      // where it may be and what to do while the passkey still works.
      (view._storedInBrowser
              ? generated
                    ? 'authReplacePasskeyGeneratedDescription'
                    : 'authReplacePasskeyDescription'
              : generated
              ? 'authPasskeyLostDeviceGeneratedDescription'
              : 'authPasskeyLostDeviceDescription')
          .tr(),
      style: SecuritySectionText.body(context),
    );
    final buttons = [
      if (view.state.canReplacePasskey)
        SecuritySecondaryButton(
          key: const Key('replace-passkey-using-password'),
          icon: const WalletPasskeyIcon(size: 20),
          text:
              (view._storedInBrowser
                      ? 'authReplacePasskeyUsingPassword'
                      : 'authChooseAnotherPasskeyWithPassword')
                  .tr(),
          onPressed: view.blocked
              ? null
              : () => onRequest(WalletProtectionAction.replacePasskey),
        ),
      if (view.state.canSwitchToDevice)
        SecuritySecondaryButton(
          key: const Key('device-unlock-using-password'),
          icon: const Icon(Icons.fingerprint),
          text: 'authUseDeviceUnlockWithPassword'.tr(),
          onPressed: view.blocked
              ? null
              : () => onRequest(
                  WalletProtectionAction.device,
                  withPassword: true,
                ),
        ),
      if (view.state.canUsePasswordOnly)
        SecuritySecondaryButton(
          key: const Key('stop-using-passkey'),
          icon: const Icon(Icons.password),
          text: 'authStopUsingPasskey'.tr(),
          onPressed: view.blocked
              ? null
              : () => onRequest(WalletProtectionAction.passwordOnly),
        ),
    ];
    // Stacked at every width: the explanation is several sentences long
    // and reads badly squeezed beside its buttons.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        description,
        const SizedBox(height: 12),
        for (final (index, button) in buttons.indexed) ...[
          if (index > 0) const SizedBox(height: 8),
          if (wide)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: SizedBox(width: 300, child: button),
            )
          else
            button,
        ],
      ],
    );
  }
}

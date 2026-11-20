part of 'wallet_protection_panel.dart';

typedef _ProtectionRequest = Future<void> Function(
  WalletProtectionAction action, {
  int? grace,
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
          if (view.passkey && view.state.capabilities?.passkeyCandidate == true)
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

  /// The primary way to turn the lock on, and device unlock as the quieter
  /// alternative where a passkey leads.
  Widget? _actions(_ProtectionView view, bool wide) {
    final state = view.state;
    final setUp = view.setupAction;
    final setPassword = widget.onSetPassword;
    final width = wide ? SecurityActionPlate.actionWidth : double.infinity;
    final Widget primary;
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
    } else {
      return null;
    }
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          primary,
          if (state.canCreatePasskey && state.canEnableDevice)
            SecuritySecondaryButton(
              key: const Key('enable-device-unlock'),
              icon: const Icon(Icons.fingerprint),
              text: 'authEnableDeviceUnlock'.tr(),
              onPressed: view.blocked
                  ? null
                  : () => _request(WalletProtectionAction.device),
            ),
        ],
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

/// The way back in when the passkey itself is gone.
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
    final description = Text(
      // A password the wallet created is not one the user can recall, so say
      // where it may be and what to do while the passkey still works.
      (view.status?.generatedPassword == true
              ? 'authReplacePasskeyGeneratedDescription'
              : 'authReplacePasskeyDescription')
          .tr(),
      style: SecuritySectionText.body(context),
    );
    final button = SecuritySecondaryButton(
      key: const Key('replace-passkey-using-password'),
      icon: const WalletPasskeyIcon(size: 20),
      text: 'authReplacePasskeyUsingPassword'.tr(),
      onPressed: view.blocked
          ? null
          : () => onRequest(WalletProtectionAction.replacePasskey),
    );
    // Stacked at every width: the explanation is several sentences long
    // and reads badly squeezed beside its button.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        description,
        const SizedBox(height: 12),
        if (wide)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox(width: 300, child: button),
          )
        else
          button,
      ],
    );
  }
}

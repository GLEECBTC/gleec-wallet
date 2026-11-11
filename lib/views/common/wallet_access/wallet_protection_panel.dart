import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/wallet_protection/wallet_protection_bloc.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/views/common/wallet_access/wallet_passkey_icon.dart';
import 'package:web_dex/views/common/wallet_password_dialog/wallet_password_dialog.dart';

/// Shared enrollment handoff for the wallet and settings. No credential is
/// rendered here; password-only fallback stays in the existing authorization UI.
class WalletProtectionPanel extends StatefulWidget {
  const WalletProtectionPanel({
    this.showLockSettings = false,
    this.onOpenSettings,
    super.key,
  });
  final bool showLockSettings;
  final VoidCallback? onOpenSettings;
  @override
  State<WalletProtectionPanel> createState() => _WalletProtectionPanelState();
}

class _WalletProtectionPanelState extends State<WalletProtectionPanel> {
  bool _collectingInput = false;

  Future<void> _request(WalletProtectionAction action, {int? grace}) async {
    final bloc = context.read<WalletProtectionBloc>();
    final state = bloc.state;
    if (_collectingInput ||
        state.loading ||
        state.busy ||
        state.status == null) {
      return;
    }
    final user = context.read<AuthBloc>().state.currentUser;
    final currentEntry = user?.metadata['_wallet_entry_id'];
    if (user != null &&
        (user.walletId != bloc.walletId ||
            (currentEntry is String &&
                currentEntry != state.status!.entryId))) {
      return;
    }
    final needsPassword =
        !state.status!.hasManagedCredential ||
        action == WalletProtectionAction.replacePasskey ||
        action == WalletProtectionAction.grace;
    String? password;
    if (needsPassword) {
      setState(() => _collectingInput = true);
      try {
        password = await walletPasswordDialog(
          context,
          passwordOnly: action == WalletProtectionAction.replacePasskey,
        );
      } finally {
        if (mounted) setState(() => _collectingInput = false);
      }
      if (password == null) return;
    }
    if (!mounted || bloc.isClosed) return;
    bloc.add(
      WalletProtectionRequested(
        action,
        password: password,
        graceSeconds: grace,
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<WalletProtectionBloc, WalletProtectionState>(
    builder: (context, state) {
      final theme = Theme.of(context);
      final supportingStyle = theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurface,
      );
      final status = state.status;
      final passkey = status?.protection == CredentialProtection.passkey;
      final protected = status?.requiresAuthentication == true;
      final busy = state.busy || _collectingInput;
      if (state.loading) {
        return Semantics(
          liveRegion: true,
          child: Text('authProtectionChecking'.tr()),
        );
      }
      if (status == null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('authProtectionCheckFailed'.tr()),
            TextButton(
              onPressed: () => context.read<WalletProtectionBloc>().add(
                const WalletProtectionRefreshed(),
              ),
              child: Text('tryAgain'.tr()),
            ),
          ],
        );
      }
      final title = passkey
          ? 'authPasskeyReadyTitle'
          : protected
          ? status.protection == CredentialProtection.password
                ? 'authPasswordReadyTitle'
                : 'authDeviceReadyTitle'
          : state.canCreatePasskey
          ? 'authPasskeySetupTitle'
          : state.canEnableDevice
          ? 'authDeviceSetupTitle'
          : 'authUnprotectedTitle';
      final description = passkey
          ? 'authPasskeyProtected'
          : protected
          ? status.protection == CredentialProtection.password
                ? 'authPasswordProtected'
                : status.protection == CredentialProtection.osAccountProtected
                ? 'authOsAccountProtected'
                : 'authDeviceProtected'
          : state.canCreatePasskey
          ? 'authPasskeySetupDescription'
          : state.canEnableDevice
          ? 'authDeviceSetupDescription'
          : status.protection == CredentialProtection.browserLocal
          ? 'authBrowserUnprotected'
          : 'authDeviceUnprotected';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: passkey || state.canCreatePasskey
                    ? WalletPasskeyIcon(color: theme.colorScheme.primary)
                    : Icon(
                        protected
                            ? Icons.lock_outline
                            : Icons.lock_open_outlined,
                        color: theme.colorScheme.primary,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title.tr(), style: theme.textTheme.titleMedium),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            (!widget.showLockSettings && (passkey || state.canCreatePasskey)
                    ? passkey
                          ? 'authPasskeyReadyCompactDescription'
                          : 'authPasskeySetupCompactDescription'
                    : description)
                .tr(),
          ),
          if (widget.showLockSettings && state.canCreatePasskey) ...[
            const SizedBox(height: 8),
            Text('authPasskeyLocalScope'.tr(), style: supportingStyle),
          ],
          if (widget.showLockSettings && state.canCreatePasskey) ...[
            const SizedBox(height: 8),
            Text('authPasskeySetupConfirmations'.tr(), style: supportingStyle),
          ],
          if (state.canCreatePasskey || state.canEnableDevice) ...[
            const SizedBox(height: 16),
            UiPrimaryButton(
              key: Key(
                widget.showLockSettings
                    ? state.canCreatePasskey
                          ? 'enable-passkey-unlock'
                          : 'enable-device-unlock'
                    : 'wallet-setup-protect',
              ),
              expandForText: true,
              onPressed: busy
                  ? null
                  : () => _request(
                      state.canCreatePasskey
                          ? WalletProtectionAction.passkey
                          : WalletProtectionAction.device,
                    ),
              prefix: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: state.canCreatePasskey
                    ? const WalletPasskeyIcon()
                    : const Icon(Icons.fingerprint),
              ),
              text:
                  (state.canCreatePasskey
                          ? 'authCreatePasskey'
                          : 'authEnableDeviceUnlock')
                      .tr(),
            ),
          ],
          if (!protected &&
              !state.canCreatePasskey &&
              !state.canEnableDevice &&
              widget.onOpenSettings != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('wallet-setup-protect'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
                foregroundColor: theme.colorScheme.onSurface,
              ),
              onPressed: busy ? null : widget.onOpenSettings,
              child: Text('authReviewProtection'.tr()),
            ),
          ],
          if (widget.showLockSettings &&
              state.canCreatePasskey &&
              state.canEnableDevice) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('enable-device-unlock'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
                foregroundColor: theme.colorScheme.onSurface,
              ),
              onPressed: busy
                  ? null
                  : () => _request(WalletProtectionAction.device),
              icon: const Icon(Icons.fingerprint),
              label: Text('authEnableDeviceUnlock'.tr()),
            ),
          ],
          if (widget.showLockSettings &&
              passkey &&
              state.capabilities?.passkeyCandidate == true) ...[
            const SizedBox(height: 16),
            Text('authReplacePasskeyDescription'.tr()),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('replace-passkey-using-password'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
                foregroundColor: theme.colorScheme.onSurface,
              ),
              onPressed: busy
                  ? null
                  : () => _request(WalletProtectionAction.replacePasskey),
              icon: const WalletPasskeyIcon(),
              label: Text('authReplacePasskeyUsingPassword'.tr()),
            ),
          ],
          if (widget.showLockSettings && protected) ...[
            const SizedBox(height: 20),
            Text('authLockAfterTitle'.tr(), style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final seconds in [0, 30])
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: ChoiceChip(
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      visualDensity: VisualDensity.standard,
                      label: Text(
                        (seconds == 0
                                ? 'authLockImmediately'
                                : 'authLockThirtySeconds')
                            .tr(),
                      ),
                      selected: state.graceSeconds == seconds,
                      onSelected: busy
                          ? null
                          : (_) => _request(
                              WalletProtectionAction.grace,
                              grace: seconds,
                            ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('authLockGraceDescription'.tr(), style: supportingStyle),
          ],
          if (busy) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              label: 'pleaseWait'.tr(),
              child: TickerMode(
                enabled: !MediaQuery.disableAnimationsOf(context),
                child: const LinearProgressIndicator(),
              ),
            ),
          ],
          if (state.failure != null ||
              (widget.showLockSettings && state.completed != null)) ...[
            const SizedBox(height: 12),
            Semantics(liveRegion: true, child: Text(_message(state).tr())),
          ],
          if (widget.showLockSettings) ...[
            const SizedBox(height: 16),
            Text('authPasswordManagerAutomatic'.tr(), style: supportingStyle),
            const SizedBox(height: 8),
            Text(switch (status.passwordManager) {
              PasswordManagerOutcome.accepted =>
                'authPasswordManagerAccepted'.tr(),
              PasswordManagerOutcome.declined =>
                'authPasswordManagerDeclined'.tr(),
              PasswordManagerOutcome.failed => 'authPasswordManagerFailed'.tr(),
              PasswordManagerOutcome.unavailable =>
                'authPasswordManagerUnavailable'.tr(),
              PasswordManagerOutcome.offered ||
              PasswordManagerOutcome.unknown =>
                'authPasswordManagerUnknown'.tr(),
            }, style: supportingStyle),
          ],
        ],
      );
    },
  );

  String _message(WalletProtectionState state) {
    if (state.failure == WalletAccessFailure.busy) return 'authProtectionBusy';
    if (state.failure == WalletAccessFailure.staleOperation) {
      return 'authProtectionStale';
    }
    if (state.failure == WalletAccessFailure.canceled) {
      return 'authProtectionCanceled';
    }
    if (state.failure == WalletAccessFailure.prfUnavailable ||
        (state.failure == WalletAccessFailure.unavailable &&
            state.capabilities?.passkeyCandidate == true)) {
      return 'authPasskeyUnsupported';
    }
    if (state.failure != null) return 'authProtectionFailed';
    return state.completed == WalletProtectionAction.replacePasskey
        ? 'authPasskeyReplaced'
        : state.completed == WalletProtectionAction.grace
        ? 'authLockPreferenceSaved'
        : 'authProtectionEnabled';
  }
}

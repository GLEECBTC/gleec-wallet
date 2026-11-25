import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/wallet_protection/wallet_protection_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_feedback.dart';
import 'package:web_dex/views/common/wallet_access/wallet_passkey_icon.dart';
import 'package:web_dex/views/common/wallet_access/wallet_setup_card.dart';
import 'package:web_dex/views/common/wallet_password_dialog/wallet_password_dialog.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_action_plate.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_section_card.dart';
import 'package:web_dex/views/settings/widgets/security_settings/wallet_lock_timing.dart';

part 'wallet_protection_panel_settings.dart';
part 'wallet_protection_view.dart';

/// The wallet lock of one wallet: its state, the way to turn it on, and in
/// settings its timing. On the wallet page it is one step of the setup
/// checklist; in Security settings it is a full section.
///
/// No credential is rendered here; the password fallback stays in the
/// existing authorization dialog.
class WalletProtectionPanel extends StatefulWidget {
  const WalletProtectionPanel({
    this.showLockSettings = false,
    this.onOpenSettings,
    this.onSetPassword,
    super.key,
  });

  /// The full Security settings section rather than the checklist step.
  final bool showLockSettings;
  final VoidCallback? onOpenSettings;

  /// Starts setting a wallet password, the lock that works where neither a
  /// passkey nor device unlock is available.
  final VoidCallback? onSetPassword;

  @override
  State<WalletProtectionPanel> createState() => _WalletProtectionPanelState();
}

class _WalletProtectionPanelState extends State<WalletProtectionPanel> {
  bool _collectingInput = false;
  bool _typedPassword = false;

  /// [withPassword] asks for the wallet password even where a stored
  /// credential could authorize the change: the way back from a lost passkey.
  Future<void> _request(
    WalletProtectionAction action, {
    int? grace,
    bool withPassword = false,
  }) async {
    final bloc = context.read<WalletProtectionBloc>();
    final state = bloc.state;
    if (_collectingInput ||
        state.loading ||
        state.busy ||
        state.waitingForPasswordManager ||
        bloc.access.isPasswordManagerPending ||
        state.status == null) {
      return;
    }
    // Nothing would change, so nothing is worth authenticating for.
    if (action == WalletProtectionAction.grace && grace == state.graceSeconds) {
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
    final passwordOnly =
        withPassword ||
        action == WalletProtectionAction.replacePasskey ||
        action == WalletProtectionAction.passwordOnly;
    final needsPassword =
        !state.status!.hasManagedCredential ||
        passwordOnly ||
        action == WalletProtectionAction.grace;
    String? password;
    if (needsPassword) {
      setState(() => _collectingInput = true);
      try {
        password = await walletPasswordDialog(
          context,
          passwordOnly: passwordOnly,
        );
      } finally {
        if (mounted) setState(() => _collectingInput = false);
      }
      if (password == null) return;
    }
    if (!mounted || bloc.isClosed) return;
    _typedPassword = !state.status!.hasManagedCredential || passwordOnly;
    bloc.add(
      WalletProtectionRequested(
        action,
        password: password,
        graceSeconds: grace,
      ),
    );
  }

  void _retryCheck() => context.read<WalletProtectionBloc>().add(
    const WalletProtectionRefreshed(manual: true),
  );

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<WalletProtectionBloc, WalletProtectionState>(
        builder: (context, state) {
          final view = _ProtectionView(
            state: state,
            collectingInput: _collectingInput,
            typedPassword: _typedPassword,
            providerPending: context
                .read<WalletProtectionBloc>()
                .access
                .isPasswordManagerPending,
          );
          return widget.showLockSettings
              ? _buildSettings(context, view)
              : _buildStep(context, view);
        },
      );

  /// The checklist step on the wallet page.
  Widget _buildStep(BuildContext context, _ProtectionView view) {
    final state = view.state;
    if (state.status == null) {
      return state.loading
          ? WalletAccessProgress(
              label: 'authProtectionChecking'.tr(),
              showLabel: true,
            )
          : _CheckFailed(view: view, onRetry: _retryCheck);
    }
    if (view.protected) return WalletSetupDone(label: view.readyTitle);
    final setUp = view.setupAction;
    final fallback = widget.onSetPassword ?? widget.onOpenSettings;
    return WalletSetupTask(
      icon: view.icon(),
      title: view.title,
      description: view.stepDescription,
      action: setUp != null
          ? WalletSetupAction(
              key: const Key('wallet-setup-protect'),
              icon: view.actionIcon(setUp),
              text: view.actionLabel(setUp),
              onPressed: view.blocked ? null : () => _request(setUp),
            )
          : fallback == null
          ? null
          : WalletSetupAction(
              key: const Key('wallet-setup-protect'),
              primary: false,
              text: 'authSetWalletPassword'.tr(),
              onPressed: fallback,
            ),
      footer: _feedback(view),
    );
  }

  /// What is happening or what came of the last request: never both.
  Widget? _feedback(_ProtectionView view, {bool withOutcome = false}) {
    final children = <Widget>[
      if (view.showsProgress)
        _LabelledProgress(label: view.pendingMessage)
      else if (view.failureText case final text?)
        WalletAccessNotice(text: text, tone: view.failureTone)
      else if (withOutcome && view.completedText != null)
        WalletAccessNotice(
          text: view.completedText!,
          tone: WalletAccessTone.success,
        ),
      if (view.state.checkFailure != null)
        _CheckFailed(view: view, onRetry: _retryCheck),
    ];
    if (children.isEmpty) return null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: children,
    );
  }
}

class _LabelledProgress extends StatelessWidget {
  const _LabelledProgress({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) =>
      WalletAccessProgress(label: label, linear: true, showLabel: true);
}

/// The lock state could not be read; the user can ask again.
class _CheckFailed extends StatelessWidget {
  const _CheckFailed({required this.view, required this.onRetry});

  final _ProtectionView view;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (view.state.loading)
        WalletAccessProgress(
          label: 'authProtectionChecking'.tr(),
          showLabel: true,
        )
      else ...[
        WalletAccessNotice(
          text: view.checkFailureText,
          tone: WalletAccessTone.warning,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: SecuritySecondaryButton(
            key: const Key('wallet-protection-retry'),
            width: SecurityActionPlate.actionWidth,
            text: LocaleKeys.tryAgain.tr(),
            onPressed: onRetry,
          ),
        ),
      ],
    ],
  );
}

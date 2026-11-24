import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/model/wallets_manager_models.dart';
import 'package:web_dex/services/wallet_access/unlock_coordinator.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/services/wallet_access/wallet_lock_policy.dart';
import 'package:web_dex/shared/widgets/app_dialog.dart';
import 'package:web_dex/shared/widgets/logout_popup.dart';
import 'package:web_dex/views/common/wallet_access/app_lock_boundary.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_feedback.dart';
import 'package:web_dex/views/common/wallet_password_dialog/wallet_access_actions.dart';
import 'package:web_dex/views/common/wallet_password_dialog/wallet_password_input.dart';
import 'package:web_dex/views/wallets_manager/wallets_manager_events_factory.dart';
import 'package:web_dex/views/wallets_manager/wallets_manager_wrapper.dart';

/// Application host above the Navigator. Authentication and logout confirmation
/// are intentionally rendered in the cover, where they remain interactive.
class WalletAccessBoundary extends StatefulWidget {
  const WalletAccessBoundary({required this.child, super.key});
  final Widget child;
  @override
  State<WalletAccessBoundary> createState() => _WalletAccessBoundaryState();
}

class _WalletAccessBoundaryState extends State<WalletAccessBoundary>
    with WidgetsBindingObserver {
  final _password = TextEditingController();
  final _passwordFocus = FocusNode(debugLabel: 'wallet lock password');
  WalletAccessService? _access;
  StreamSubscription<void>? _changes;
  WalletId? _walletId;
  Future<WalletAccessStatus?>? _status;
  bool _usePassword = false;
  bool _confirmExit = false;
  bool _recover = false;
  bool _waitingForSignOut = false;
  Object? _previousSignOutError;
  int? _automaticGeneration;
  String? _error;
  WalletAccessTone _errorTone = WalletAccessTone.error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final access = context.read<WalletAccessService?>();
    if (identical(_access, access)) return;
    _changes?.cancel();
    _access = access;
    _changes = access?.changes.listen((_) {
      if (mounted && _walletId != null) {
        // A block body: an arrow would hand setState the Future it assigns.
        setState(() {
          _status = access.status(walletId: _walletId);
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (lifecycleLeavesApp(state)) _password.clear();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _changes?.cancel();
    _password.clear();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final access = context.read<WalletAccessService?>();
    if (access == null) return widget.child;
    return BlocBuilder<AuthBloc, AuthBlocState>(
      builder: (context, auth) {
        final id = auth.currentUser?.walletId;
        if (_walletId != id) {
          _walletId = id;
          _password.clear();
          _error = null;
          _usePassword = false;
          _status = id == null ? null : access.status(walletId: id);
        }
        if (_waitingForSignOut &&
            auth.authError != null &&
            !identical(auth.authError, _previousSignOutError)) {
          _waitingForSignOut = false;
          _errorTone = WalletAccessTone.error;
          _error = 'authSignOutFailed'.tr();
        }
        if (_waitingForSignOut &&
            !auth.isLoading &&
            !auth.isSignedIn &&
            !auth.isError) {
          _waitingForSignOut = false;
          WidgetsBinding.instance.addPostFrameCallback((_) => _openManager());
        }
        final walletName = auth.currentUser?.wallet.displayName;
        return StreamBuilder<WalletUnlockState>(
          stream: access.unlockCoordinator.changes,
          initialData: access.unlockCoordinator.state,
          builder: (context, snapshot) {
            final state = snapshot.data ?? access.unlockCoordinator.state;
            return FutureBuilder<WalletAccessStatus?>(
              future: _status,
              builder: (context, details) {
                final status = details.data;
                final managed = status?.hasManagedCredential == true;
                // A refresh keeps the last answer on screen, so the face in
                // use (and what is typed in it) does not blink away.
                final resolved =
                    details.connectionState == ConnectionState.done ||
                    details.hasData ||
                    details.hasError;
                if (id != null &&
                    managed &&
                    state.canStartUnlock &&
                    !_usePassword &&
                    !_confirmExit &&
                    !_waitingForSignOut &&
                    _automaticGeneration != state.generation) {
                  _automaticGeneration = state.generation;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) unawaited(_unlock(access, automatic: true));
                  });
                }
                final title = walletUnlockTitle(walletName);
                final message = walletName == null || walletName.isEmpty
                    ? 'authUnlockDescription'.tr()
                    : null;
                Widget? authentication;
                if (_waitingForSignOut) {
                  authentication = Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: WalletAccessProgress(
                        label: 'authSigningOut'.tr(),
                        showLabel: true,
                      ),
                    ),
                  );
                } else if (_confirmExit) {
                  authentication = _ExitConfirmation(
                    recover: _recover,
                    walletName: walletName,
                    onCancel: () => setState(() => _confirmExit = false),
                    onConfirm: () => setState(() {
                      _confirmExit = false;
                      _previousSignOutError = context
                          .read<AuthBloc>()
                          .state
                          .authError;
                      _waitingForSignOut = true;
                    }),
                  );
                } else if (id == null || !resolved) {
                  // Neither face is known to apply yet; showing one would
                  // flash the wrong method.
                  authentication = WalletLockPanel(
                    title: title,
                    message: message,
                    children: [
                      Center(
                        child: WalletAccessProgress(
                          label: 'authProtectionChecking'.tr(),
                          showLabel: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _LockExits(
                        onSwitchWallet: () => _exit(recover: false),
                        onRecover: () => _exit(recover: true),
                      ),
                    ],
                  );
                } else if (_usePassword || !managed) {
                  authentication = _PasswordFace(
                    title: title,
                    message: message,
                    loginName: id.name,
                    details: details,
                    controller: _password,
                    focusNode: _passwordFocus,
                    busy: state.unlockInProgress,
                    error: _error,
                    errorTone: _errorTone,
                    onSubmit: () => _unlock(access, password: true),
                    onUseEnrolled: () => setState(() {
                      _password.clear();
                      _usePassword = false;
                      _error = null;
                    }),
                    onSwitchWallet: () => _exit(recover: false),
                    onRecover: () => _exit(recover: true),
                  );
                }
                return AppLockBoundary(
                  coordinator: access.unlockCoordinator,
                  onUnlock: () => _unlock(access),
                  onUsePassword: () => setState(() {
                    _usePassword = true;
                    _error = null;
                  }),
                  onSwitchWallet: () => _exit(recover: false),
                  onRecoverWallet: () => _exit(recover: true),
                  authenticationContent: authentication,
                  errorMessage: _error,
                  errorTone: _errorTone,
                  labels: WalletLockLabels(
                    title: title,
                    message: message,
                    unlock: walletUnlockMethodLabel(status),
                    unlocking: LocaleKeys.pleaseWait.tr(),
                    usePassword: 'authUsePassword'.tr(),
                    switchWallet: 'authSwitchWallet'.tr(),
                    recoverWallet: 'authRecoverWallet'.tr(),
                    privacy: 'authPrivacyCover'.tr(),
                  ),
                  child: widget.child,
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _unlock(
    WalletAccessService access, {
    bool password = false,
    bool automatic = false,
  }) async {
    final expected = _walletId;
    if (expected == null || _confirmExit || _waitingForSignOut) return;
    final entered = password ? _password.text : null;
    if (password && (entered?.isEmpty ?? true)) {
      _passwordFocus.requestFocus();
      return;
    }
    _password.clear();
    if (mounted && !automatic) setState(() => _error = null);
    try {
      final unlocked = await access.unlockCurrent(
        password: entered,
        automatic: automatic,
      );
      if (!mounted || _walletId != expected) return;
      if (unlocked) {
        setState(() {
          _usePassword = false;
          _error = null;
        });
      }
    } catch (error) {
      if (!mounted || _walletId != expected) return;
      setState(() {
        _errorTone = walletAccessFailureTone(error);
        _error = walletAccessFailureText(error, passwordEntered: password);
      });
      // Submitting takes focus off the field; hand it back for the retry.
      if (password) _passwordFocus.requestFocus();
    }
  }

  void _exit({required bool recover}) {
    context.read<WalletAccessService?>()?.lockWalletSession();
    setState(() {
      _password.clear();
      _recover = recover;
      _confirmExit = true;
      _error = null;
    });
  }

  Future<void> _openManager() async {
    if (!mounted) return;
    final target = scaffoldKey.currentContext;
    if (target == null || !target.mounted) return;
    await AppDialog.showWithCallback<void>(
      context: target,
      width: 320,
      barrierDismissible: false,
      useRootNavigator: true,
      childBuilder: (close) => WalletsManagerWrapper(
        eventType: WalletsManagerEventType.header,
        initialAction: _recover
            ? WalletsManagerAction.import
            : WalletsManagerAction.none,
        onCancel: close,
        onSuccess: (_) => close(),
      ),
    );
  }
}

class _AccessPanel extends StatelessWidget {
  const _AccessPanel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: child,
      ),
    ),
  );
}

/// Leaving the locked wallet signs it out first, so say what for and what it
/// costs before it happens.
class _ExitConfirmation extends StatelessWidget {
  const _ExitConfirmation({
    required this.recover,
    required this.walletName,
    required this.onCancel,
    required this.onConfirm,
  });

  final bool recover;
  final String? walletName;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final name = walletName;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): onCancel},
      // Escape needs focus inside the panel. It rests on no button, so Enter
      // cannot sign out by accident.
      child: Focus(
        autofocus: true,
        skipTraversal: true,
        child: _AccessPanel(
          child: LogOutPopup(
            title:
                (recover
                        ? 'authRecoverWalletConfirmTitle'
                        : 'authSwitchWalletConfirmTitle')
                    .tr(),
            description: name == null || name.isEmpty
                ? null
                : (recover
                          ? 'authRecoverWalletConfirmBody'
                          : 'authSwitchWalletConfirmBody')
                      .tr(args: [name]),
            confirmLabel:
                (recover ? 'authSignOutAndRecover' : 'authSignOutAndSwitch')
                    .tr(),
            onCancel: onCancel,
            onConfirm: onConfirm,
          ),
        ),
      ),
    );
  }
}

class _LockExits extends StatelessWidget {
  const _LockExits({
    required this.onSwitchWallet,
    required this.onRecover,
    this.showRecover = true,
  });

  final VoidCallback onSwitchWallet;
  final VoidCallback onRecover;
  final bool showRecover;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      WalletAccessTertiaryButton(
        key: const Key('wallet-lock-switch-wallet'),
        text: 'authSwitchWallet'.tr(),
        onPressed: onSwitchWallet,
      ),
      if (showRecover)
        WalletAccessTertiaryButton(
          key: const Key('wallet-lock-recover-wallet'),
          text: 'authRecoverWallet'.tr(),
          onPressed: onRecover,
        ),
    ],
  );
}

class _PasswordFace extends StatelessWidget {
  const _PasswordFace({
    required this.title,
    required this.message,
    required this.loginName,
    required this.details,
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.error,
    required this.errorTone,
    required this.onSubmit,
    required this.onUseEnrolled,
    required this.onSwitchWallet,
    required this.onRecover,
  });

  final String title;
  final String? message;
  final String loginName;
  final AsyncSnapshot<WalletAccessStatus?> details;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final String? error;
  final WalletAccessTone errorTone;
  final VoidCallback onSubmit;
  final VoidCallback onUseEnrolled;
  final VoidCallback onSwitchWallet;
  final VoidCallback onRecover;

  @override
  Widget build(BuildContext context) {
    final status = details.data;
    final enrolled = status?.hasManagedCredential == true;
    final guidance = WalletPasswordGuidance.of(details);
    // Without another way in, a user who never chose this password needs the
    // recovery phrase more than a list of exits.
    final recoverFirst = !enrolled && guidance.passwordMayBeUnknown;
    return AutofillGroup(
      onDisposeAction: AutofillContextAction.cancel,
      child: WalletLockPanel(
        title: title,
        message: message,
        children: [
          guidance,
          WalletPasswordInput(
            fieldKey: const Key('wallet-lock-password'),
            controller: controller,
            focusNode: focusNode,
            walletName: loginName,
            busy: busy,
            onSubmitted: onSubmit,
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            WalletAccessNotice(text: error!, tone: errorTone),
          ],
          const SizedBox(height: 24),
          WalletAccessPrimaryButton(
            buttonKey: const Key('wallet-lock-password-submit'),
            text: 'authUnlock'.tr(),
            busy: busy,
            onPressed: onSubmit,
          ),
          if (enrolled) ...[
            const SizedBox(height: 8),
            WalletAccessSecondaryButton(
              key: const Key('wallet-lock-use-enrolled'),
              text: walletUnlockMethodLabel(status),
              onPressed: onUseEnrolled,
            ),
          ] else if (recoverFirst) ...[
            const SizedBox(height: 8),
            WalletAccessSecondaryButton(
              key: const Key('wallet-lock-recover-wallet'),
              text: 'authRecoverWallet'.tr(),
              onPressed: onRecover,
            ),
          ],
          const SizedBox(height: 16),
          _LockExits(
            onSwitchWallet: onSwitchWallet,
            onRecover: onRecover,
            showRecover: !recoverFirst,
          ),
        ],
      ),
    );
  }
}

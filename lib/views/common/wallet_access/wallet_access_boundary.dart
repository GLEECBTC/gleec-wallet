import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallets_manager_models.dart';
import 'package:web_dex/services/wallet_access/unlock_coordinator.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/shared/widgets/app_dialog.dart';
import 'package:web_dex/shared/widgets/logout_popup.dart';
import 'package:web_dex/views/common/wallet_access/app_lock_boundary.dart';
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
        setState(() => _status = access.status(walletId: _walletId));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _password.clear();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _changes?.cancel();
    _password.clear();
    _password.dispose();
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
          _error = 'authSignOutFailed'.tr();
        }
        if (_waitingForSignOut &&
            !auth.isLoading &&
            !auth.isSignedIn &&
            !auth.isError) {
          _waitingForSignOut = false;
          WidgetsBinding.instance.addPostFrameCallback((_) => _openManager());
        }
        return StreamBuilder<WalletUnlockState>(
          stream: access.unlockCoordinator.changes,
          initialData: access.unlockCoordinator.state,
          builder: (context, snapshot) {
            final state = snapshot.data ?? access.unlockCoordinator.state;
            return FutureBuilder<WalletAccessStatus?>(
              future: _status,
              builder: (context, details) {
                final managed = details.data?.hasManagedCredential == true;
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
                Widget? authentication;
                if (_waitingForSignOut) {
                  authentication = Center(
                    child: Semantics(
                      liveRegion: true,
                      label: LocaleKeys.pleaseWait.tr(),
                      child: TickerMode(
                        enabled: !MediaQuery.disableAnimationsOf(context),
                        child: const CircularProgressIndicator(),
                      ),
                    ),
                  );
                } else if (_confirmExit) {
                  authentication = _AccessPanel(
                    child: LogOutPopup(
                      onCancel: () => setState(() {
                        _confirmExit = false;
                      }),
                      onConfirm: () => setState(() {
                        _confirmExit = false;
                        _previousSignOutError = context
                            .read<AuthBloc>()
                            .state
                            .authError;
                        _waitingForSignOut = true;
                      }),
                    ),
                  );
                } else if (_usePassword ||
                    (details.connectionState == ConnectionState.done &&
                        !managed)) {
                  authentication = _AccessPanel(
                    child: AutofillGroup(
                      onDisposeAction: AutofillContextAction.cancel,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(
                              'authUnlockTitle'.tr(),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            key: const Key('wallet-lock-password'),
                            controller: _password,
                            autofocus: true,
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            autofillHints: const [AutofillHints.password],
                            enabled: !state.unlockInProgress,
                            decoration: InputDecoration(
                              labelText: LocaleKeys.enterThePassword.tr(),
                            ),
                            onSubmitted: (_) => _unlock(access, password: true),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Semantics(liveRegion: true, child: Text(_error!)),
                          ],
                          const SizedBox(height: 20),
                          UiPrimaryButton(
                            expandForText: true,
                            key: const Key('wallet-lock-password-submit'),
                            text: 'authUnlock'.tr(),
                            onPressed: state.unlockInProgress
                                ? null
                                : () => _unlock(access, password: true),
                          ),
                          if (managed)
                            TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.onSurface,
                              ),
                              onPressed: state.unlockInProgress
                                  ? null
                                  : () => setState(() {
                                      _password.clear();
                                      _usePassword = false;
                                    }),
                              child: Text('authUseDeviceUnlock'.tr()),
                            ),
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onSurface,
                            ),
                            onPressed: () => _exit(recover: false),
                            child: Text('authSwitchWallet'.tr()),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onSurface,
                            ),
                            onPressed: () => _exit(recover: true),
                            child: Text('authRecoverWallet'.tr()),
                          ),
                        ],
                      ),
                    ),
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
                  labels: WalletLockLabels(
                    title: 'authUnlockTitle'.tr(),
                    message: 'authUnlockDescription'.tr(),
                    unlock: 'authUnlock'.tr(),
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
    if (password && (entered?.isEmpty ?? true)) return;
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
      setState(
        () => _error =
            error is WalletAccessException &&
                error.failure == WalletAccessFailure.canceled
            ? 'authUnlockCanceled'.tr()
            : LocaleKeys.passwordNotAccepted.tr(),
      );
    }
  }

  void _exit({required bool recover}) {
    context.read<WalletAccessService?>()?.unlockCoordinator.lock();
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

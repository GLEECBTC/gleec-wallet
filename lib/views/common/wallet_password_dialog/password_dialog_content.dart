import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/services/wallet_access/wallet_operation_gate.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/widgets/password_visibility_control.dart';

/// A purpose-specific authorization prompt. The credential is only passed to
/// the existing operation callback, never placed in an ordinary BLoC state.
class PasswordDialogContent extends StatelessWidget {
  const PasswordDialogContent({
    required this.onSuccess,
    required this.onCancel,
    super.key,
    this.wallet,
    this.passwordOnly = false,
  });
  final ValueChanged<String> onSuccess;
  final VoidCallback onCancel;
  final Wallet? wallet;
  final bool passwordOnly;

  @override
  Widget build(BuildContext context) => _AuthorizationContent(
    wallet: wallet,
    passwordOnly: passwordOnly,
    onCancel: onCancel,
    onAuthorized: (password) async {
      onSuccess(password);
      return true;
    },
    onComplete: (_) {},
    passwordFieldKey: 'confirmation-showing-seed-phrase',
  );
}

class PasswordDialogContentWithLoading extends StatelessWidget {
  const PasswordDialogContentWithLoading({
    required this.onPasswordValidated,
    required this.onComplete,
    required this.onCancel,
    super.key,
    this.wallet,
    this.loadingTitle,
    this.loadingMessage,
    this.operationFailedMessage,
    this.passwordFieldKey = 'confirmation-showing-operation',
  });
  final Future<bool> Function(String password) onPasswordValidated;
  final ValueChanged<bool> onComplete;
  final VoidCallback onCancel;
  final Wallet? wallet;
  final String? loadingTitle;
  final String? loadingMessage;
  final String? operationFailedMessage;
  final String passwordFieldKey;

  @override
  Widget build(BuildContext context) => _AuthorizationContent(
    wallet: wallet,
    onCancel: onCancel,
    onAuthorized: onPasswordValidated,
    onComplete: onComplete,
    passwordFieldKey: passwordFieldKey,
    loadingTitle: loadingTitle,
    loadingMessage: loadingMessage,
    operationFailedMessage: operationFailedMessage,
  );
}

class _AuthorizationContent extends StatefulWidget {
  const _AuthorizationContent({
    required this.wallet,
    required this.onCancel,
    required this.onAuthorized,
    required this.onComplete,
    required this.passwordFieldKey,
    this.passwordOnly = false,
    this.loadingTitle,
    this.loadingMessage,
    this.operationFailedMessage,
  });
  final Wallet? wallet;
  final VoidCallback onCancel;
  final Future<bool> Function(String password) onAuthorized;
  final ValueChanged<bool> onComplete;
  final String passwordFieldKey;
  final bool passwordOnly;
  final String? loadingTitle;
  final String? loadingMessage;
  final String? operationFailedMessage;

  @override
  State<_AuthorizationContent> createState() => _AuthorizationContentState();
}

class _AuthorizationContentState extends State<_AuthorizationContent>
    with WidgetsBindingObserver {
  final _passwordController = TextEditingController();
  WalletAccessService? _access;
  WalletId? _targetWalletId;
  Future<WalletAccessStatus?>? _status;
  bool _manual = false;
  bool _obscured = true;
  bool _busy = false;
  bool _cancelled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_status != null) return;
    _access = context.read<WalletAccessService?>();
    _targetWalletId = context.read<AuthBloc>().state.currentUser?.walletId;
    final wallet =
        widget.wallet ?? context.read<AuthBloc>().state.currentUser?.wallet;
    _status = wallet == null || _access == null
        ? Future<WalletAccessStatus?>.value()
        : _access!.statusForWallet(wallet);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _passwordController.clear();
    // Native authorization temporarily obscures the app. Let its coordinator
    // own cancellation; closing here would cancel our own system prompt.
    if (!_busy &&
        (state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused)) {
      _cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _passwordController.clear();
    _passwordController.dispose();
    TextInput.finishAutofillContext(shouldSave: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<WalletAccessStatus?>(
    future: _status,
    builder: (context, snapshot) {
      final managed = snapshot.data?.hasManagedCredential == true;
      final manual = widget.passwordOnly || _manual || !managed;
      final waiting = snapshot.connectionState != ConnectionState.done;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 362),
          child: AutofillGroup(
            onDisposeAction: AutofillContextAction.cancel,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _busy && widget.loadingTitle != null
                      ? widget.loadingTitle!
                      : managed
                      ? 'authAuthorizationTitle'.tr()
                      : LocaleKeys.confirmationForShowingSeedPhraseTitle.tr(),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 20),
                if (waiting)
                  TickerMode(
                    enabled: !MediaQuery.disableAnimationsOf(context),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                if (!waiting && !manual)
                  Text(
                    snapshot.data!.requiresAuthentication
                        ? 'authConfirmWithDevice'.tr()
                        : 'authUnprotectedConfirmation'.tr(),
                    textAlign: TextAlign.center,
                  ),
                if (!waiting && manual) ...[
                  Offstage(
                    child: ExcludeFocus(
                      child: UiTextFormField(
                        initialValue: widget.wallet?.name ?? '',
                        autofillHints: const [AutofillHints.username],
                        readOnly: true,
                      ),
                    ),
                  ),
                  UiTextFormField(
                    key: Key(widget.passwordFieldKey),
                    controller: _passwordController,
                    autofocus: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    obscureText: _obscured,
                    enabled: !_busy,
                    maxLength: passwordMaxLength,
                    counterText: '',
                    hintText: LocaleKeys.enterThePassword.tr(),
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    suffixIcon: PasswordVisibilityControl(
                      onVisibilityChange: (value) =>
                          setState(() => _obscured = value),
                    ),
                    onFieldSubmitted: (_) => _authorize(manual: manual),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                UiPrimaryButton(
                  expandForText: true,
                  onPressed: _busy || waiting
                      ? null
                      : () => _authorize(manual: manual),
                  text: _busy
                      ? LocaleKeys.pleaseWait.tr()
                      : LocaleKeys.continueText.tr(),
                  prefix: _busy
                      ? TickerMode(
                          enabled: !MediaQuery.disableAnimationsOf(context),
                          child: const UiSpinner(),
                        )
                      : null,
                ),
                if (managed && !widget.passwordOnly) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                    ),
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _manual = !_manual;
                            _error = null;
                          }),
                    child: Text(
                      _manual
                          ? 'authUseDeviceUnlock'.tr()
                          : 'authUsePassword'.tr(),
                    ),
                  ),
                ],
                if (_busy && widget.loadingMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(widget.loadingMessage!, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 12),
                UiUnderlineTextButton(
                  text: LocaleKeys.cancel.tr(),
                  onPressed: _cancel,
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Future<void> _authorize({required bool manual}) async {
    if (_busy || _cancelled) return;
    final route = ModalRoute.of(context);
    bool routeIsCurrent() =>
        route == null || (route.isActive && route.isCurrent);
    final auth = context.read<AuthBloc>();
    final expected = _targetWalletId;
    final target = widget.wallet;
    if (expected == null ||
        auth.state.currentUser?.walletId != expected ||
        (target != null && expected.name != target.name)) {
      return;
    }
    final entered = manual ? _passwordController.text : null;
    if (manual && (entered?.isEmpty ?? true)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    _passwordController.clear();
    try {
      final String credential;
      if (_access != null) {
        credential = await _access!.authorize(
          walletId: expected,
          password: entered,
          reason: 'authSensitiveAuthorizationReason'.tr(),
        );
      } else {
        // Compatibility for existing hosts which have not installed the access
        // service. This is the pre-existing password-dependent verification.
        credential = entered!;
        await context.read<KomodoDefiSdk>().auth.getMnemonicPlainText(
          credential,
        );
      }
      if (!mounted ||
          _cancelled ||
          !routeIsCurrent() ||
          auth.state.currentUser?.walletId != expected) {
        return;
      }
      final ensureAccess =
          _access?.captureSensitiveOperation(expected) ??
          WalletOperationGate.instance.capture().ensureCurrent;
      void ensureCurrent() {
        final lifecycle = WidgetsBinding.instance.lifecycleState;
        if (!mounted ||
            _cancelled ||
            !routeIsCurrent() ||
            auth.state.currentUser?.walletId != expected ||
            (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
          throw const WalletAccessException(WalletAccessFailure.staleOperation);
        }
        ensureAccess();
      }

      ensureCurrent();
      final success = await RpcDispatchGuard.run(
        ensureCurrent,
        () => widget.onAuthorized(credential),
        methods: const {'get_mnemonic', 'show_priv_key', 'get_private_keys'},
      );
      if (!mounted ||
          _cancelled ||
          !routeIsCurrent() ||
          auth.state.currentUser?.walletId != expected) {
        return;
      }
      ensureCurrent();
      if (success) {
        widget.onComplete(true);
      } else {
        setState(
          () => _error =
              widget.operationFailedMessage ?? LocaleKeys.somethingWrong.tr(),
        );
      }
    } catch (error) {
      if (!mounted || _cancelled || !routeIsCurrent()) return;
      if (error is WalletOperationDenied ||
          error is RpcDispatchRejected ||
          (error is WalletAccessException &&
              error.failure == WalletAccessFailure.staleOperation)) {
        _cancel();
        return;
      }
      setState(
        () => _error =
            error is WalletAccessException &&
                error.failure == WalletAccessFailure.canceled
            ? 'authUnlockCanceled'.tr()
            : LocaleKeys.passwordNotAccepted.tr(),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _passwordController.clear();
    widget.onCancel();
  }
}

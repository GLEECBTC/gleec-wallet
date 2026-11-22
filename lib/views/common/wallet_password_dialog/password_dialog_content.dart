import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/services/wallet_access/wallet_operation_gate.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_feedback.dart';
import 'package:web_dex/views/common/wallet_password_dialog/wallet_access_actions.dart';
import 'package:web_dex/views/common/wallet_password_dialog/wallet_authorization_form.dart';

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
  WalletAccessService? _access;
  WalletId? _targetWalletId;
  // Null when there is nothing to look up: the form then asks for the
  // password at once instead of waiting a frame on an empty answer.
  Future<WalletAccessStatus?>? _status;
  bool _statusRequested = false;
  String _walletName = '';
  bool _busy = false;
  bool _cancelled = false;
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
    if (_statusRequested) return;
    _statusRequested = true;
    _access = context.read<WalletAccessService?>();
    _targetWalletId = context.read<AuthBloc>().state.currentUser?.walletId;
    final wallet =
        widget.wallet ?? context.read<AuthBloc>().state.currentUser?.wallet;
    _walletName = wallet?.name ?? '';
    _status = wallet == null ? null : _access?.statusForWallet(wallet);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WalletAuthorizationForm(
    status: _status,
    walletName: _walletName,
    passwordOnly: widget.passwordOnly,
    busy: _busy,
    closing: _cancelled,
    error: _error,
    errorTone: _errorTone,
    busyTitle: widget.loadingTitle,
    busyMessage: widget.loadingMessage,
    passwordFieldKey: Key(widget.passwordFieldKey),
    onConfirm: _authorize,
    onCancel: _cancel,
  );

  Future<void> _authorize(String? entered) async {
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
    setState(() {
      _busy = true;
      _error = null;
    });
    // Once access is confirmed, a later failure belongs to the operation.
    var accessConfirmed = false;
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
        if (entered == null) {
          throw const WalletAccessException(
            WalletAccessFailure.missingCredential,
          );
        }
        credential = entered;
        await context.read<KomodoDefiSdk>().auth.getMnemonicPlainText(
          credential,
        );
      }
      accessConfirmed = true;
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
        setState(() {
          _errorTone = WalletAccessTone.error;
          _error =
              widget.operationFailedMessage ?? LocaleKeys.somethingWrong.tr();
        });
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
      final operationFailed =
          accessConfirmed &&
          error is! WalletAccessException &&
          !(error is AuthException &&
              error.type == AuthExceptionType.incorrectPassword);
      setState(() {
        _errorTone = walletAccessFailureTone(error);
        _error = operationFailed
            ? widget.operationFailedMessage ?? LocaleKeys.somethingWrong.tr()
            : walletAccessFailureText(
                error,
                passwordEntered: entered != null,
                unlocking: false,
              );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _cancel() {
    if (_cancelled) return;
    // The owner may leave this widget mounted while its route closes.
    if (mounted) {
      setState(() => _cancelled = true);
    } else {
      _cancelled = true;
    }
    widget.onCancel();
  }
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/services/wallet_access/wallet_operation_gate.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_feedback.dart';
import 'package:web_dex/views/common/wallet_password_dialog/wallet_access_actions.dart';
import 'package:web_dex/views/common/wallet_password_dialog/wallet_authorization_form.dart';

/// Password input for the private-key export flow.
///
/// The owning flow performs authentication and controls this dialog's lifetime.
class PrivateKeyExportPasswordDialog extends StatefulWidget {
  const PrivateKeyExportPasswordDialog({
    required this.walletName,
    required this.isLoading,
    required this.onSubmit,
    required this.onCancel,
    this.errorText,
    super.key,
  });

  final String walletName;
  final bool isLoading;
  final String? errorText;
  final ValueChanged<SensitiveString> onSubmit;
  final VoidCallback onCancel;

  @override
  State<PrivateKeyExportPasswordDialog> createState() =>
      _PrivateKeyExportPasswordDialogState();
}

class _PrivateKeyExportPasswordDialogState
    extends State<PrivateKeyExportPasswordDialog> {
  bool _submissionPending = false;
  bool _cancelled = false;
  String? _managedError;
  WalletAccessTone _managedErrorTone = WalletAccessTone.error;
  // Null when there is nothing to look up, so the form asks for the password
  // at once.
  Future<WalletAccessStatus?>? _accessStatus;
  bool _statusRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadAccessStatus();
  }

  void _loadAccessStatus() {
    if (_statusRequested) return;
    _statusRequested = true;
    final id = context.read<AuthBloc?>()?.state.currentUser?.walletId;
    _accessStatus = id == null || id.name != widget.walletName
        ? null
        : context.read<WalletAccessService?>()?.status(walletId: id);
  }

  bool get _isBusy => widget.isLoading || _submissionPending;

  @override
  void didUpdateWidget(covariant PrivateKeyExportPasswordDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.walletName != oldWidget.walletName) {
      _statusRequested = false;
      _loadAccessStatus();
      _managedError = null;
    }
    if (!widget.isLoading &&
        (oldWidget.isLoading || widget.errorText != oldWidget.errorText)) {
      _submissionPending = false;
    }
  }

  @override
  Widget build(BuildContext context) => ScreenshotSensitive(
    child: WalletAuthorizationForm(
      status: _accessStatus,
      walletName: widget.walletName,
      padding: const EdgeInsets.all(24),
      busy: _isBusy,
      closing: _cancelled,
      error: _managedError ?? widget.errorText,
      errorTone: _managedError == null
          ? WalletAccessTone.error
          : _managedErrorTone,
      busyTitle: LocaleKeys.fetchingPrivateKeysTitle.tr(),
      busyMessage: LocaleKeys.fetchingPrivateKeysMessage.tr(),
      passwordFieldKey: const Key('private-key-export-password'),
      confirmKey: const Key('private-key-export-password-submit'),
      cancelKey: const Key('private-key-export-password-cancel'),
      onConfirm: (password) =>
          password == null ? _submitManaged() : _submit(password),
      onCancel: _cancel,
    ),
  );

  Future<void> _submitManaged() async {
    if (_isBusy || _cancelled) return;
    final auth = context.read<AuthBloc?>();
    final access = context.read<WalletAccessService?>();
    final id = auth?.state.currentUser?.walletId;
    if (id == null || access == null || id.name != widget.walletName) return;
    setState(() {
      _submissionPending = true;
      _managedError = null;
    });
    try {
      final password = await access.authorize(
        walletId: id,
        reason: 'authSensitiveAuthorizationReason'.tr(),
      );
      if (!mounted ||
          _cancelled ||
          auth?.state.currentUser?.walletId != id ||
          widget.walletName != id.name) {
        return;
      }
      access.captureSensitiveOperation(id)();
      _ensureForeground();
      widget.onSubmit(SensitiveString(password));
    } catch (error) {
      if (mounted && !_cancelled) {
        setState(() {
          _submissionPending = false;
          _managedErrorTone = walletAccessFailureTone(error);
          _managedError = walletAccessFailureText(
            error,
            passwordEntered: false,
            unlocking: false,
          );
        });
      }
    }
  }

  void _submit(String entered) {
    if (_isBusy || _cancelled) return;
    try {
      _ensureForeground();
      final access = context.read<WalletAccessService?>();
      final id = context.read<AuthBloc?>()?.state.currentUser?.walletId;
      if (access != null) {
        if (id == null || id.name != widget.walletName) {
          throw const WalletAccessException(WalletAccessFailure.staleOperation);
        }
        access.captureSensitiveOperation(id)();
      } else {
        WalletOperationGate.instance.capture().ensureCurrent();
      }
    } on Object {
      _cancel();
      return;
    }
    setState(() {
      _submissionPending = true;
      _managedError = null;
    });
    widget.onSubmit(SensitiveString(entered));
  }

  void _ensureForeground() {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (!mounted ||
        _cancelled ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
      throw const WalletAccessException(WalletAccessFailure.staleOperation);
    }
  }

  void _cancel() {
    if (_cancelled) return;
    setState(() => _cancelled = true);
    widget.onCancel();
  }
}

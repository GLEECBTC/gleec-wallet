import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/services/wallet_access/wallet_operation_gate.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';
import 'package:web_dex/shared/widgets/password_visibility_control.dart';

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
  final _passwordController = TextEditingController();
  bool _isObscured = true;
  bool _submissionPending = false;
  bool _cancelled = false;
  bool _manualPassword = false;
  String? _managedError;
  Future<WalletAccessStatus?>? _accessStatus;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadAccessStatus();
  }

  void _loadAccessStatus() {
    final id = context.read<AuthBloc?>()?.state.currentUser?.walletId;
    _accessStatus ??= id == null || id.name != widget.walletName
        ? Future<WalletAccessStatus?>.value()
        : context.read<WalletAccessService?>()?.status(walletId: id) ??
              Future<WalletAccessStatus?>.value();
  }

  bool get _isBusy => widget.isLoading || _submissionPending;

  @override
  void didUpdateWidget(covariant PrivateKeyExportPasswordDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.walletName != oldWidget.walletName) {
      _passwordController.clear();
      _isObscured = true;
      _accessStatus = null;
      _loadAccessStatus();
      _manualPassword = false;
      _managedError = null;
    }
    if (!widget.isLoading &&
        (oldWidget.isLoading || widget.errorText != oldWidget.errorText)) {
      _submissionPending = false;
    }
  }

  @override
  void dispose() {
    _passwordController.clear();
    _passwordController.dispose();
    TextInput.finishAutofillContext(shouldSave: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WalletAccessStatus?>(
      future: _accessStatus,
      builder: (context, snapshot) {
        final managed =
            snapshot.data?.hasManagedCredential == true && !_manualPassword;
        return ScreenshotSensitive(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 362),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: AutofillGroup(
                onDisposeAction: AutofillContextAction.cancel,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _isBusy
                          ? LocaleKeys.fetchingPrivateKeysTitle.tr()
                          : managed
                          ? 'authAuthorizationTitle'.tr()
                          : LocaleKeys.confirmationForShowingSeedPhraseTitle
                                .tr(),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Offstage(
                      child: UiTextFormField(
                        initialValue: widget.walletName,
                        autofillHints: const [AutofillHints.username],
                        readOnly: true,
                      ),
                    ),
                    if (managed) ...[
                      Text(
                        snapshot.data!.requiresAuthentication
                            ? 'authConfirmWithDevice'.tr()
                            : 'authUnprotectedConfirmation'.tr(),
                      ),
                      TextButton(
                        onPressed: _isBusy
                            ? null
                            : () => setState(() => _manualPassword = true),
                        child: Text('authUsePassword'.tr()),
                      ),
                    ] else
                      UiTextFormField(
                        key: const Key('private-key-export-password'),
                        controller: _passwordController,
                        autofocus: true,
                        autocorrect: false,
                        obscureText: _isObscured,
                        enabled: !_isBusy && !_cancelled,
                        maxLength: passwordMaxLength,
                        counterText: '',
                        errorMaxLines: 6,
                        errorText: _isBusy ? null : widget.errorText,
                        hintText: LocaleKeys.enterThePassword.tr(),
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        suffixIcon: _isBusy || _cancelled
                            ? null
                            : PasswordVisibilityControl(
                                onVisibilityChange: (isObscured) {
                                  setState(() => _isObscured = isObscured);
                                },
                              ),
                        onFieldSubmitted: (_) => _submit(),
                      ),
                    if (_managedError != null) ...[
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _managedError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (_isBusy) ...[
                      const Center(child: CircularProgressIndicator()),
                      const SizedBox(height: 16),
                      Text(
                        LocaleKeys.fetchingPrivateKeysMessage.tr(),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                    ],
                    UiPrimaryButton(
                      expandForText: true,
                      key: const Key('private-key-export-password-submit'),
                      text: LocaleKeys.continueText.tr(),
                      onPressed: _isBusy || _cancelled
                          ? null
                          : managed
                          ? _submitManaged
                          : _submit,
                    ),
                    const SizedBox(height: 20),
                    UiUnderlineTextButton(
                      key: const Key('private-key-export-password-cancel'),
                      text: LocaleKeys.cancel.tr(),
                      onPressed: _cancelled ? null : _cancel,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

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
          _managedError =
              error is WalletAccessException &&
                  error.failure == WalletAccessFailure.canceled
              ? 'authUnlockCanceled'.tr()
              : LocaleKeys.passwordNotAccepted.tr();
        });
      }
    }
  }

  void _submit() {
    if (_isBusy || _cancelled || _passwordController.text.isEmpty) return;
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
    final password = SensitiveString(_passwordController.text);
    setState(() {
      _submissionPending = true;
      _isObscured = true;
    });
    _clearInput();
    widget.onSubmit(password);
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
    _clearInput();
    widget.onCancel();
  }

  void _clearInput() {
    _passwordController.clear();
    FocusScope.of(context).unfocus();
    TextInput.finishAutofillContext(shouldSave: false);
  }
}

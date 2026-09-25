import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  bool get _isBusy => widget.isLoading || _submissionPending;

  @override
  void didUpdateWidget(covariant PrivateKeyExportPasswordDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.walletName != oldWidget.walletName) {
      _passwordController.clear();
      _isObscured = true;
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
                      : LocaleKeys.confirmationForShowingSeedPhraseTitle.tr(),
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 24),
                Offstage(
                  child: UiTextFormField(
                    initialValue: widget.walletName,
                    autofillHints: const [AutofillHints.username],
                    readOnly: true,
                  ),
                ),
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
                  key: const Key('private-key-export-password-submit'),
                  text: LocaleKeys.continueText.tr(),
                  onPressed: _isBusy || _cancelled ? null : _submit,
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
  }

  void _submit() {
    if (_isBusy || _cancelled || _passwordController.text.isEmpty) return;

    final password = SensitiveString(_passwordController.text);
    setState(() {
      _submissionPending = true;
      _isObscured = true;
    });
    _clearInput();
    widget.onSubmit(password);
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

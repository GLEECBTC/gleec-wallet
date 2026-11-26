import 'dart:convert';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/security_key/security_key_prompts.dart';
import 'package:web_dex/shared/widgets/password_visibility_control.dart';
import 'package:web_dex/views/common/wallet_access/security_key/security_key_prompt_sheet.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_feedback.dart';
import 'package:web_dex/views/common/wallet_password_dialog/wallet_access_actions.dart';

/// Asks for the security key's PIN. The PIN leaves here once, as bytes, and
/// the field is cleared as it does. A malformed PIN never reaches the key,
/// where it would spend one of its tries.
class SecurityKeyPinForm extends StatefulWidget {
  const SecurityKeyPinForm({
    required this.prompt,
    required this.onSubmit,
    required this.onCancel,
    super.key,
  });

  final SecurityKeyPrompt prompt;
  final ValueChanged<Uint8List> onSubmit;
  final VoidCallback onCancel;

  @override
  State<SecurityKeyPinForm> createState() => _SecurityKeyPinFormState();
}

class _SecurityKeyPinFormState extends State<SecurityKeyPinForm> {
  final _pin = TextEditingController();
  bool _obscured = true;
  String? _problem;

  @override
  void didUpdateWidget(SecurityKeyPinForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.prompt != oldWidget.prompt) {
      _pin.clear();
      _obscured = true;
      _problem = null;
    }
  }

  @override
  void dispose() {
    _pin
      ..clear()
      ..dispose();
    super.dispose();
  }

  void _submit() {
    final text = _pin.text;
    final pin = utf8.encode(text);
    // CTAP's limits: at least 4 code points, at most 63 bytes of UTF-8.
    final problem = text.runes.length < 4
        ? 'authSecurityKeyPinTooShort'
        : pin.length > 63
        ? 'authSecurityKeyPinTooLong'
        : null;
    if (problem != null) {
      pin.fillRange(0, pin.length, 0);
      setState(() => _problem = problem);
      return;
    }
    _pin.clear();
    widget.onSubmit(pin);
  }

  @override
  Widget build(BuildContext context) {
    final retries = widget.prompt.retriesLeft;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SecurityKeyStepHeader(
          icon: Icons.pin_outlined,
          title: 'authSecurityKeyPinTitle'.tr(),
          product: widget.prompt.product,
        ),
        const SizedBox(height: 24),
        if (widget.prompt.wrongPin) ...[
          WalletAccessNotice(
            key: const Key('security-key-pin-wrong'),
            text: 'authSecurityKeyPinWrong'.tr(),
            tone: WalletAccessTone.error,
          ),
          const SizedBox(height: 12),
        ],
        if (retries == 1) ...[
          WalletAccessNotice(
            key: const Key('security-key-pin-last-try'),
            text: 'authSecurityKeyPinLastTry'.tr(),
            tone: WalletAccessTone.warning,
          ),
          const SizedBox(height: 12),
        ] else if (retries != null && retries <= 3) ...[
          WalletAccessNotice(
            key: const Key('security-key-pin-tries'),
            text: 'authSecurityKeyPinTries'.tr(args: ['$retries']),
            tone: WalletAccessTone.warning,
          ),
          const SizedBox(height: 12),
        ],
        UiTextFormField(
          key: const Key('security-key-pin'),
          controller: _pin,
          autofocus: true,
          obscureText: _obscured,
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
          // A PIN is not a password to save.
          autofillHints: const [],
          keyboardType: TextInputType.visiblePassword,
          textInputAction: TextInputAction.done,
          maxLength: 63,
          counterText: '',
          labelText: 'authSecurityKeyPinLabel'.tr(),
          suffixIcon: PasswordVisibilityControl(
            isObscured: _obscured,
            onVisibilityChange: (obscured) =>
                setState(() => _obscured = obscured),
          ),
          onChanged: (_) {
            if (_problem != null) setState(() => _problem = null);
          },
          onFieldSubmitted: (_) => _submit(),
        ),
        if (_problem != null) ...[
          const SizedBox(height: 12),
          WalletAccessNotice(
            key: const Key('security-key-pin-problem'),
            text: _problem!.tr(),
            tone: WalletAccessTone.error,
          ),
        ],
        const SizedBox(height: 24),
        WalletAccessPrimaryButton(
          buttonKey: const Key('security-key-pin-submit'),
          text: LocaleKeys.continueText.tr(),
          onPressed: _submit,
        ),
        const SizedBox(height: 8),
        WalletAccessTertiaryButton(
          key: const Key('security-key-cancel'),
          text: LocaleKeys.cancel.tr(),
          onPressed: widget.onCancel,
        ),
      ],
    );
  }
}

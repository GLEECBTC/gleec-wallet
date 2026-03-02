import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';
import 'package:web_dex/shared/widgets/password_visibility_control.dart';

class TrezorDialogSelectWallet extends StatelessWidget {
  const TrezorDialogSelectWallet({Key? key, required this.onComplete})
    : super(key: key);

  final Function(String) onComplete;

  @override
  Widget build(BuildContext context) {
    return ScreenshotSensitive(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            LocaleKeys.selectWalletType.tr(),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 18),
          _TrezorStandardWallet(onTap: () => onComplete('')),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6.0),
            child: UiDivider(),
          ),
          _TrezorHiddenWallet(
            onSubmit: (String passphrase) => onComplete(passphrase),
          ),
        ],
      ),
    );
  }
}

class _TrezorStandardWallet extends StatelessWidget {
  const _TrezorStandardWallet({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _TrezorWalletItem(
      icon: Icons.account_balance_wallet_outlined,
      title: LocaleKeys.standardWallet.tr(),
      description: LocaleKeys.noPassphrase.tr(),
      isIconShown: true,
      onTap: onTap,
    );
  }
}

class _TrezorHiddenWallet extends StatefulWidget {
  const _TrezorHiddenWallet({required this.onSubmit});
  final Function(String) onSubmit;

  @override
  State<_TrezorHiddenWallet> createState() => _TrezorHiddenWalletState();
}

class _TrezorHiddenWalletState extends State<_TrezorHiddenWallet> {
  final TextEditingController _passphraseController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final FocusNode _passphraseFieldFocusNode = FocusNode();
  bool _isObscured = true;

  @override
  void initState() {
    _passphraseController.addListener(() => setState(() {}));
    super.initState();
  }

  @override
  void dispose() {
    _passphraseController.dispose();
    _passphraseFieldFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TrezorWalletItem(
          title: LocaleKeys.hiddenWallet.tr(),
          description: LocaleKeys.passphraseRequired.tr(),
          icon: Icons.lock_outline,
          isIconShown: _isSendAllowed,
          onTap: _isSendAllowed ? _onSubmit : null,
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 30),
          child: AutofillGroup(child: _buildObscuredPassphrase()),
        ),
      ],
    );
  }

  Widget _buildObscuredPassphrase() {
    return Form(
      key: _formKey,
      child: UiTextFormField(
        controller: _passphraseController,
        autofocus: true,
        hintText: LocaleKeys.passphrase.tr(),
        keyboardType: TextInputType.text,
        autofillHints: const [AutofillHints.password],
        obscureText: _isObscured,
        maxLength: passwordMaxLength,
        counterText: '',
        focusNode: _passphraseFieldFocusNode,
        suffixIcon: PasswordVisibilityControl(
          onVisibilityChange: (bool isObscured) {
            setState(() {
              _isObscured = isObscured;
            });
          },
        ),
        onFieldSubmitted: (_) => _onSubmit(),
        validator: (String? text) {
          if (text == null || text.isEmpty) {
            return LocaleKeys.passphraseIsEmpty.tr();
          }

          return null;
        },
      ),
    );
  }

  void _onSubmit() {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      _passphraseFieldFocusNode.requestFocus();
      return;
    }
    // We deliberately do not save passphrases
    TextInput.finishAutofillContext(shouldSave: false);
    widget.onSubmit(_passphraseController.text);
  }

  bool get _isSendAllowed => _passphraseController.text.isNotEmpty;
}

class _TrezorWalletItem extends StatelessWidget {
  const _TrezorWalletItem({
    required this.title,
    required this.description,
    required this.icon,
    required this.isIconShown,
    required this.onTap,
  });
  final String title;
  final String description;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isIconShown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(18.0),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 36.0),
            const SizedBox(width: 24),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                ),
              ],
            ),
            const Spacer(),
            if (isIconShown) const Icon(Icons.keyboard_arrow_right_rounded),
          ],
        ),
      ),
    );
  }
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/services/wallet_access/wallet_lock_policy.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/widgets/password_visibility_control.dart';

/// The wallet-password field of an unlock or authorization form.
///
/// Password managers match a saved login by the wallet name, which rides along
/// as a hidden, unfocusable username. Place it inside an [AutofillGroup].
class WalletPasswordInput extends StatefulWidget {
  const WalletPasswordInput({
    required this.controller,
    required this.walletName,
    required this.onSubmitted,
    this.fieldKey,
    this.focusNode,
    this.busy = false,
    this.autofocus = true,
    super.key,
  });

  final TextEditingController controller;
  final String walletName;
  final VoidCallback onSubmitted;
  final Key? fieldKey;
  final FocusNode? focusNode;

  /// Keeps the field focused but not editable while the password is checked.
  final bool busy;
  final bool autofocus;

  @override
  State<WalletPasswordInput> createState() => _WalletPasswordInputState();
}

class _WalletPasswordInputState extends State<WalletPasswordInput>
    with WidgetsBindingObserver {
  bool _obscured = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (lifecycleLeavesApp(state) && !_obscured && mounted) {
      setState(() => _obscured = true);
    }
  }

  @override
  void didUpdateWidget(WalletPasswordInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A submitted password is never left readable behind the busy state.
    if (widget.busy && !oldWidget.busy) _obscured = true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Offstage(
        child: ExcludeFocus(
          child: UiTextFormField(
            key: const Key('wallet-field'),
            initialValue: widget.walletName,
            readOnly: true,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            autofillHints: const [AutofillHints.username],
          ),
        ),
      ),
      UiTextFormField(
        key: widget.fieldKey,
        controller: widget.controller,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
        obscureText: _obscured,
        // Read-only rather than disabled: a disabled field drops keyboard
        // focus, and the user would have to click it again to retry.
        readOnly: widget.busy,
        maxLength: passwordMaxLength,
        counterText: '',
        // A label alone: the kit repeats a hint as the label above it.
        labelText: LocaleKeys.walletCreationPasswordHint.tr(),
        autofillHints: const [AutofillHints.password],
        textInputAction: TextInputAction.done,
        suffixIcon: PasswordVisibilityControl(
          isObscured: _obscured,
          onVisibilityChange: (obscured) =>
              setState(() => _obscured = obscured),
        ),
        onFieldSubmitted: (_) => widget.onSubmitted(),
      ),
    ],
  );
}

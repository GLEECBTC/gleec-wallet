import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/services/wallet_access/wallet_lock_policy.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/widgets/password_visibility_control.dart';

/// The password field never submits on its own.
///
/// It used to: any burst of 3+ characters scheduled an auto-submit 300ms later,
/// and to tell an autofill apart from a human paste it read the system
/// clipboard on every such burst. That reads whatever the user last copied -
/// including a seed phrase or someone else's password - to decide a UI timing
/// question, and it fired on fast typing too. Submission is now only ever the
/// user pressing done or the login button.
class PasswordTextField extends StatefulWidget {
  const PasswordTextField({
    required this.onFieldSubmitted,
    required this.controller,
    super.key,
    this.errorText,
    this.autofillHints,
    this.focusNode,
  });

  final String? errorText;
  final TextEditingController controller;
  final void Function()? onFieldSubmitted;
  final Iterable<String>? autofillHints;

  /// Lets the owner hand focus back after a failed attempt.
  final FocusNode? focusNode;

  @override
  State<PasswordTextField> createState() => _PasswordTextFieldState();
}

class _PasswordTextFieldState extends State<PasswordTextField>
    with WidgetsBindingObserver {
  bool _isPasswordObscured = true;
  FocusNode? _ownFocusNode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.focusNode == null) _ownFocusNode = FocusNode();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (lifecycleLeavesApp(state) && mounted) {
      setState(() => _isPasswordObscured = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ownFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        UiTextFormField(
          key: const Key('create-password-field'),
          autofocus: true,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
          controller: widget.controller,
          obscureText: _isPasswordObscured,
          errorText: widget.errorText,
          autofillHints: widget.autofillHints ?? const [AutofillHints.password],
          maxLength: passwordMaxLength,
          counterText: '',
          labelText: LocaleKeys.walletCreationPasswordHint.tr(),
          suffixIcon: PasswordVisibilityControl(
            isObscured: _isPasswordObscured,
            onVisibilityChange: onVisibilityChange,
          ),
          onFieldSubmitted: (_) => widget.onFieldSubmitted?.call(),
          focusNode: widget.focusNode ?? _ownFocusNode,
        ),
      ],
    );
  }

  // ignore: avoid_positional_boolean_parameters
  void onVisibilityChange(bool isPasswordObscured) {
    setState(() {
      _isPasswordObscured = isPasswordObscured;
    });
  }
}

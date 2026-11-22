import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/utils/validators.dart';
import 'package:web_dex/shared/widgets/password_visibility_control.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

class CreationPasswordFields extends StatefulWidget {
  const CreationPasswordFields({
    super.key,
    required this.passwordController,
    this.onValidityChanged,
    this.onFieldSubmitted,
    this.enforceStrongPassword = false,
    this.autofocus = false,
  });

  final TextEditingController passwordController;
  final void Function(bool isValid)? onValidityChanged;
  final void Function(String)? onFieldSubmitted;

  /// When true, weak passwords are never allowed regardless of settings.
  final bool enforceStrongPassword;

  /// Whether the first field takes focus as the step opens.
  final bool autofocus;

  @override
  State<CreationPasswordFields> createState() => _CreationPasswordFieldsState();
}

class _CreationPasswordFieldsState extends State<CreationPasswordFields>
    with WidgetsBindingObserver {
  final TextEditingController _confirmPasswordController =
      TextEditingController(text: '');
  final FocusNode _passwordFocus = FocusNode(debugLabel: 'new password');
  final FocusNode _confirmFocus = FocusNode(debugLabel: 'confirm password');
  bool _isObscured = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPasswordField(),
        if (!_weakPasswordAllowed) ...[
          const SizedBox(height: 8),
          // The rules up front, so they are not discovered one error at a
          // time.
          Text(
            'authPasswordRequirementsHint'.tr(),
            key: const Key('create-password-requirements'),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
          ),
        ],
        const SizedBox(height: 20),
        _buildPasswordConfirmationField(),
      ],
    );
  }

  bool get _weakPasswordAllowed =>
      !widget.enforceStrongPassword &&
      context.watch<SettingsBloc>().state.weakPasswordsAllowed;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _confirmPasswordController.clear();
    _confirmPasswordController.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  @override
  void initState() {
    if (widget.passwordController.text.isNotEmpty) {
      widget.passwordController.text = '';
    }
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.autofocus) {
      // Requested, not `autofocus`: the field this step replaces still holds
      // the scope's focus while this one is built, which cancels an autofocus.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _passwordFocus.requestFocus();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted) {
      setState(() => _isObscured = true);
    }
  }

  Widget _buildPasswordConfirmationField() {
    return UiTextFormField(
      key: const Key('create-password-field-confirm'),
      controller: _confirmPasswordController,
      focusNode: _confirmFocus,
      textInputAction: TextInputAction.done,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      obscureText: _isObscured,
      enableInteractiveSelection: true,
      validationMode: InputValidationMode.passive,
      maxLength: passwordMaxLength,
      validator: _validateConfirmPasswordField,
      onChanged: (_) => _notifyValidityChanged(),
      onFieldSubmitted: widget.onFieldSubmitted,
      counterText: '',
      errorMaxLines: 6,
      autofillHints: const [AutofillHints.newPassword],
      hintText: LocaleKeys.walletCreationConfirmPasswordHint.tr(),
    );
  }

  Widget _buildPasswordField() {
    return UiTextFormField(
      key: const Key('create-password-field'),
      controller: widget.passwordController,
      focusNode: _passwordFocus,
      textInputAction: TextInputAction.next,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      enableInteractiveSelection: true,
      obscureText: _isObscured,
      maxLength: passwordMaxLength,
      counterText: '',
      validator: _validatePasswordField,
      validationMode: InputValidationMode.passive,
      onChanged: (_) => _notifyValidityChanged(),
      // "Next" would otherwise stop on the show-password control.
      onFieldSubmitted: (_) => _confirmFocus.requestFocus(),
      errorMaxLines: 6,
      autofillHints: const [AutofillHints.newPassword],
      hintText: LocaleKeys.walletCreationPasswordHint.tr(),
      suffixIcon: PasswordVisibilityControl(
        isObscured: _isObscured,
        onVisibilityChange: (bool isPasswordObscured) {
          setState(() {
            _isObscured = isPasswordObscured;
          });
        },
      ),
    );
  }

  String? _validatePasswordField(String? passwordFieldInput) {
    final settingsBlocState = context.read<SettingsBloc>().state;
    final allowWeakPassword =
        !widget.enforceStrongPassword && settingsBlocState.weakPasswordsAllowed;
    final password = passwordFieldInput ?? '';

    if (allowWeakPassword) {
      return null;
    }

    return validatePassword(password);
  }

  String? _validateConfirmPasswordField(String? confirmPasswordFieldInput) {
    final originalPassword = widget.passwordController.text;

    return validateConfirmPassword(
      originalPassword,
      confirmPasswordFieldInput ?? '',
    );
  }

  void _notifyValidityChanged() {
    if (widget.onValidityChanged == null) return;

    final settingsBlocState = context.read<SettingsBloc>().state;
    final allowWeakPassword =
        !widget.enforceStrongPassword && settingsBlocState.weakPasswordsAllowed;

    final password = widget.passwordController.text;
    final confirm = _confirmPasswordController.text;

    final isPasswordValid =
        allowWeakPassword || validatePassword(password) == null;
    final isConfirmValid = validateConfirmPassword(password, confirm) == null;

    widget.onValidityChanged!.call(isPasswordValid && isConfirmValid);
  }
}

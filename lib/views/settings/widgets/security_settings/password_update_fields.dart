part of 'password_update_page.dart';

class _CurrentField extends StatelessWidget {
  const _CurrentField({
    required this.controller,
    required this.isObscured,
    required this.onVisibilityChange,
    required this.formKey,
  });

  final TextEditingController controller;
  final bool isObscured;
  final Function(bool) onVisibilityChange;
  final GlobalKey<FormState> formKey;

  @override
  Widget build(BuildContext context) {
    final currentWallet = context.read<AuthBloc>().state.currentUser?.wallet;
    return _PasswordField(
      hintText: LocaleKeys.currentPassword.tr(),
      controller: controller,
      isObscured: isObscured,
      autofillHints: const [AutofillHints.password],
      validator: (String? password) {
        if (password == null || password.isEmpty) {
          return LocaleKeys.passwordIsEmpty.tr();
        }

        if (currentWallet == null) return LocaleKeys.walletNotFound.tr();

        return null;
      },
      suffixIcon: PasswordVisibilityControl(
        isObscured: isObscured,
        onVisibilityChange: onVisibilityChange,
      ),
    );
  }
}

class _NewField extends StatelessWidget {
  const _NewField({
    required this.controller,
    required this.isObscured,
    required this.onVisibilityChange,
  });

  final TextEditingController controller;
  final bool isObscured;
  final void Function(bool) onVisibilityChange;

  @override
  Widget build(BuildContext context) {
    return _PasswordField(
      hintText: LocaleKeys.enterNewPassword.tr(),
      controller: controller,
      isObscured: isObscured,
      autofillHints: const [AutofillHints.newPassword],
      // Checked whatever the "allow weak passwords" setting says: the wallet
      // refuses a password that breaks these rules either way, and here the
      // user is shown which rule it was.
      validator: (password) => validatePassword(password ?? ''),
      suffixIcon: PasswordVisibilityControl(
        isObscured: isObscured,
        onVisibilityChange: onVisibilityChange,
      ),
    );
  }
}

class _ConfirmField extends StatelessWidget {
  const _ConfirmField({
    required this.confirmController,
    required this.newController,
    required this.isObscured,
    required this.onVisibilityChange,
    required this.onSubmitted,
  });

  final TextEditingController confirmController;
  final TextEditingController newController;
  final bool isObscured;
  final Function(bool) onVisibilityChange;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return _PasswordField(
      hintText: LocaleKeys.confirmNewPassword.tr(),
      controller: confirmController,
      isObscured: isObscured,
      autofillHints: const [AutofillHints.newPassword],
      // The last field of the form: Enter sends it.
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) => onSubmitted(),
      validator: (String? confirmPassword) =>
          validateConfirmPassword(newController.text, confirmPassword ?? ''),
      suffixIcon: PasswordVisibilityControl(
        isObscured: isObscured,
        onVisibilityChange: onVisibilityChange,
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.isObscured,
    required this.suffixIcon,
    required this.validator,
    required this.hintText,
    this.autofillHints,
    this.textInputAction = TextInputAction.next,
    this.onFieldSubmitted,
  });

  final TextEditingController controller;
  final bool isObscured;
  final PasswordVisibilityControl suffixIcon;
  final String? Function(String?)? validator;
  final String hintText;
  final Iterable<String>? autofillHints;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    return UiTextFormField(
      controller: controller,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      enableInteractiveSelection: true,
      obscureText: isObscured,
      maxLength: passwordMaxLength,
      counterText: '',
      autofillHints: autofillHints,
      validator: validator,
      errorMaxLines: 6,
      hintText: hintText,
      suffixIcon: suffixIcon,
    );
  }
}

/// The change is done: say so as a status, and offer the way back as its
/// own button rather than dressing the status up as one.
class _SuccessView extends StatelessWidget {
  const _SuccessView({
    required this.outcome,
    required this.back,
    this.passkey = false,
  });

  final PasswordChangeOutcome outcome;

  /// The wallet was protected by a passkey before the change.
  final bool passkey;
  final VoidCallback back;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        WalletAccessNotice(
          key: const Key('password-update-success'),
          text: LocaleKeys.passwordHasChanged.tr(),
          tone: WalletAccessTone.success,
        ),
        if (outcome == PasswordChangeOutcome.deviceUnlockNeedsSetup) ...[
          const SizedBox(height: 12),
          WalletAccessNotice(
            key: const Key('password-update-device-unlock-reset'),
            // The lock a browser wallet loses this way is its passkey.
            text:
                (kIsWeb
                        ? 'authPasswordChangedPasskeyOff'
                        : passkey
                        ? 'authPasswordChangedDevicePasskeyOff'
                        : 'authPasswordChangedDeviceUnlockOff')
                    .tr(),
            tone: WalletAccessTone.warning,
          ),
        ],
        const SizedBox(height: 24),
        UiPrimaryButton(
          key: const Key('password-update-done'),
          expandForText: true,
          autofocus: true,
          onPressed: back,
          text: 'authBackToSecurity'.tr(),
        ),
      ],
    );
  }
}

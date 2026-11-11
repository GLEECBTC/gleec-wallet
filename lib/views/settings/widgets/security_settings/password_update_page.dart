import 'dart:async';

import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_event.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/utils/validators.dart';
import 'package:web_dex/shared/widgets/password_visibility_control.dart';
import 'package:web_dex/views/common/page_header/page_header.dart';
import 'package:web_dex/views/common/wallet_password_dialog/password_manager_save.dart';

class PasswordUpdatePage extends StatefulWidget {
  const PasswordUpdatePage({super.key});

  @override
  State<PasswordUpdatePage> createState() => _PasswordUpdatePageState();
}

class _PasswordUpdatePageState extends State<PasswordUpdatePage> {
  bool _passwordUpdated = false;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<SecuritySettingsBloc>();
    const event = ResetEvent();
    gotoSecurityMain() => bloc.add(event);

    late Widget pageContent;
    if (_passwordUpdated) {
      pageContent = _SuccessView(back: gotoSecurityMain);
    } else {
      pageContent = _FormView(
        onSuccess: () {
          setState(() => _passwordUpdated = true);
        },
      );
    }
    final scrollController = ScrollController();
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: .3),
        borderRadius: BorderRadius.circular(18.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isNotMobile)
            PageHeader(
              onBackButtonPressed: gotoSecurityMain,
              backText: LocaleKeys.back.tr(),
              title: LocaleKeys.changingWalletPassword.tr(),
            ),
          const SizedBox(height: 28),
          Flexible(
            child: DexScrollbar(
              isMobile: isMobile,
              scrollController: scrollController,
              child: SingleChildScrollView(
                controller: ScrollController(),
                child: SizedBox(
                  width: 270,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (isMobile) ...{
                        Text(
                          '${LocaleKeys.changingWalletPassword.tr()} ',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 15),
                      },
                      Text(
                        LocaleKeys.changingWalletPasswordDescription.tr(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'authPasswordChangeDisclosure'.tr(),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 21),
                      pageContent,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormView extends StatefulWidget {
  const _FormView({required this.onSuccess});

  final VoidCallback onSuccess;

  @override
  State<_FormView> createState() => _FormViewState();
}

class _FormViewState extends State<_FormView> with WidgetsBindingObserver {
  bool _isObscured = true;
  final _oldController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  String? _error;
  bool _busy = false;
  bool _managed = false;
  WalletId? _walletId;
  Future<WalletAccessStatus?>? _accessStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    _oldController.clear();
    _newController.clear();
    _confirmController.clear();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _oldController.clear();
    _newController.clear();
    _confirmController.clear();
    _oldController.dispose();
    _newController.dispose();
    _confirmController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final walletId = context.read<AuthBloc>().state.currentUser?.walletId;
    if (_walletId != walletId || _accessStatus == null) {
      _walletId = walletId;
      _accessStatus =
          context.read<WalletAccessService?>()?.status(walletId: walletId) ??
          Future<WalletAccessStatus?>.value();
    }
    return FutureBuilder<WalletAccessStatus?>(
      future: _accessStatus,
      builder: (context, snapshot) {
        _managed = snapshot.data?.hasManagedCredential == true;
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        return AutofillGroup(
          onDisposeAction: AutofillContextAction.cancel,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_managed) ...[
                  Text('authPersonalPasswordOptional'.tr()),
                  const SizedBox(height: 16),
                ] else
                  _CurrentField(
                    controller: _oldController,
                    isObscured: _isObscured,
                    onVisibilityChange: _onVisibilityChange,
                    formKey: _formKey,
                  ),
                const SizedBox(height: 30),
                _NewField(
                  controller: _newController,
                  isObscured: _isObscured,
                  onVisibilityChange: _onVisibilityChange,
                ),
                const SizedBox(height: 20),
                _ConfirmField(
                  confirmController: _confirmController,
                  newController: _newController,
                  isObscured: _isObscured,
                  onVisibilityChange: _onVisibilityChange,
                ),
                const SizedBox(height: 30),
                if (_error != null) ...{
                  Text(
                    _error!,
                    style: TextStyle(
                      color: theme.currentGlobal.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 10),
                },
                UiPrimaryButton(
                  expandForText: true,
                  onPressed: _busy ? null : _onUpdate,
                  text: _busy
                      ? LocaleKeys.pleaseWait.tr()
                      : LocaleKeys.updatePassword.tr(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _onUpdate() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    final expected = _walletId;
    if (expected == null) return;
    final currentPassword = _managed ? null : _oldController.text;
    final newPassword = _newController.text;

    if (currentPassword == newPassword) {
      setState(() {
        _error = LocaleKeys.usedSamePassword.tr();
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final access = context.read<WalletAccessService?>();
      if (access != null) {
        await access.changePassword(
          walletId: expected,
          currentPassword: currentPassword,
          newPassword: newPassword,
        );
      } else {
        await context.read<KomodoDefiSdk>().auth.updatePassword(
          currentPassword: currentPassword!,
          newPassword: newPassword,
        );
      }
      if (!mounted ||
          context.read<AuthBloc>().state.currentUser?.walletId != expected) {
        return;
      }
      setState(() => _error = null);
      TextInput.finishAutofillContext(shouldSave: false);
      if (access != null) {
        final navigator = Navigator.of(context, rootNavigator: true);
        unawaited(
          offerWalletPasswordSave(
            navigator.context,
            access: access,
            walletId: expected,
          ),
        );
      }
      _newController.clear();
      _confirmController.clear();
      widget.onSuccess();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (e is WalletAccessException &&
            e.failure == WalletAccessFailure.canceled) {
          _error = 'authUnlockCanceled'.tr();
          return;
        }
        if (e is! AuthException) {
          _error = LocaleKeys.passwordNotAccepted.tr();
          return;
        }

        switch (e.type) {
          case AuthExceptionType.incorrectPassword:
            _error = LocaleKeys.incorrectPassword.tr();
            break;
          case AuthExceptionType.unauthorized:
            _error = LocaleKeys.noActiveWallet.tr();
            break;
          case AuthExceptionType.apiConnectionError:
            _error = LocaleKeys.activationFailedMessage.tr();
            break;
          default:
            _error = LocaleKeys.passwordNotAccepted.tr();
        }
      });
    } finally {
      _oldController.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onVisibilityChange(bool isPasswordObscured) {
    setState(() {
      _isObscured = isPasswordObscured;
    });
  }
}

class _CurrentField extends StatefulWidget {
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
  State<_CurrentField> createState() => _CurrentFieldState();
}

class _CurrentFieldState extends State<_CurrentField> {
  @override
  Widget build(BuildContext context) {
    final currentWallet = context.read<AuthBloc>().state.currentUser?.wallet;
    return _PasswordField(
      hintText: LocaleKeys.currentPassword.tr(),
      controller: widget.controller,
      isObscured: widget.isObscured,
      autofillHints: const [AutofillHints.password],
      validator: (String? password) {
        if (password == null || password.isEmpty) {
          return LocaleKeys.passwordIsEmpty.tr();
        }

        if (currentWallet == null) return LocaleKeys.walletNotFound.tr();

        return null;
      },
      suffixIcon: PasswordVisibilityControl(
        onVisibilityChange: widget.onVisibilityChange,
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
      validator: (password) => _validatePassword(password, context),
      suffixIcon: PasswordVisibilityControl(
        onVisibilityChange: onVisibilityChange,
      ),
    );
  }

  String? _validatePassword(String? passwordText, BuildContext context) {
    final settingsBlocState = context.read<SettingsBloc>().state;
    final allowWeakPassword = settingsBlocState.weakPasswordsAllowed;
    final password = passwordText ?? '';

    if (allowWeakPassword) {
      return null;
    }

    return validatePassword(password);
  }
}

class _ConfirmField extends StatelessWidget {
  const _ConfirmField({
    required this.confirmController,
    required this.newController,
    required this.isObscured,
    required this.onVisibilityChange,
  });

  final TextEditingController confirmController;
  final TextEditingController newController;
  final bool isObscured;
  final Function(bool) onVisibilityChange;

  @override
  Widget build(BuildContext context) {
    return _PasswordField(
      hintText: LocaleKeys.confirmNewPassword.tr(),
      controller: confirmController,
      isObscured: isObscured,
      autofillHints: const [AutofillHints.newPassword],
      validator: (String? confirmPassword) =>
          validateConfirmPassword(newController.text, confirmPassword ?? ''),
      suffixIcon: PasswordVisibilityControl(
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
  });

  final TextEditingController controller;
  final bool isObscured;
  final PasswordVisibilityControl suffixIcon;
  final String? Function(String?)? validator;
  final String hintText;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    return UiTextFormField(
      autofocus: true,
      controller: controller,
      // Use .next, rather than done or go, as this is a generic password field
      // that is not guaranteed to be the last field in the forms it is
      // referenced in
      textInputAction: TextInputAction.next,
      autocorrect: false,
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

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.back});

  final VoidCallback back;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.only(top: 30),
          child: UiPrimaryButton(
            expandForText: true,
            prefix: const Icon(Icons.check, color: Colors.white),
            backgroundColor: theme.custom.passwordButtonSuccessColor,
            onPressed: back,
            text: LocaleKeys.passwordHasChanged.tr(),
          ),
        ),
      ],
    );
  }
}

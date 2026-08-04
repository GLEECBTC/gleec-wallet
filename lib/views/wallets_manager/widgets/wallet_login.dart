import 'dart:async';

import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/shared/widgets/password_visibility_control.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/utils/hd_wallet_mode_preference.dart';
import 'package:web_dex/shared/widgets/quick_login_switch.dart';
import 'package:web_dex/views/wallets_manager/widgets/hdwallet_mode_switch.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';

class WalletLogIn extends StatefulWidget {
  const WalletLogIn({
    required this.wallet,
    required this.onLogin,
    required this.onCancel,
    this.initialHdMode = false,
    this.initialQuickLogin = false,
    super.key,
  });

  final Wallet wallet;
  final void Function(String, Wallet, bool) onLogin;
  final void Function() onCancel;
  final bool initialHdMode;
  final bool initialQuickLogin;

  @override
  State<WalletLogIn> createState() => _WalletLogInState();
}

class _WalletLogInState extends State<WalletLogIn> {
  final _backKeyButton = GlobalKey();
  final TextEditingController _passwordController = TextEditingController();
  late bool _isHdMode;
  bool _isQuickLoginEnabled = false;
  KdfUser? _user;
  bool? _storedHdPreference;

  @override
  void initState() {
    super.initState();
    _isHdMode =
        widget.initialHdMode ||
        widget.wallet.config.type == WalletType.hdwallet;
    _isQuickLoginEnabled = widget.initialQuickLogin;
    _loadHdModePreference();
    unawaited(_fetchKdfUser());
  }

  Future<void> _fetchKdfUser() async {
    final kdfSdk = RepositoryProvider.of<KomodoDefiSdk>(context);
    final users = await kdfSdk.auth.getUsers();
    final user = users.firstWhereOrNull(
      (user) => user.walletId.name == widget.wallet.name,
    );

    if (user != null) {
      final fallbackHdMode =
          widget.initialHdMode ||
          user.wallet.config.type == WalletType.hdwallet;
      setState(() {
        _user = user;
        _isHdMode = _storedHdPreference ?? fallbackHdMode;
      });
    }
  }

  Future<void> _loadHdModePreference() async {
    final storedPreference = await readHdWalletModePreference(widget.wallet.id);
    if (!mounted || storedPreference == null) return;
    setState(() {
      _storedHdPreference = storedPreference;
      _isHdMode = storedPreference;
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _submitLogin() {
    final authState = context.read<AuthBloc>().state;
    if (authState.isLoading) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final WalletType derivedType =
          _isHdMode && _user != null && _user!.isBip39Seed == true
          ? WalletType.hdwallet
          : WalletType.iguana;

      final Wallet walletToUse = widget.wallet.copyWith(
        config: widget.wallet.config.copyWith(type: derivedType),
      );

      widget.onLogin(
        _passwordController.text,
        walletToUse,
        _isQuickLoginEnabled,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthBlocState>(
      builder: (context, state) {
        final errorMessage =
            state.authError?.type == AuthExceptionType.incorrectPassword
            ? LocaleKeys.incorrectPassword.tr()
            : state.authError?.message;

        return AutofillGroup(
          child: ScreenshotSensitive(
            child: Column(
              mainAxisSize: isMobile ? MainAxisSize.max : MainAxisSize.min,
              children: [
                Text(
                  LocaleKeys.walletLogInTitle.tr(),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontSize: 18),
                ),
                const SizedBox(height: 24),
                UiTextFormField(
                  key: const Key('wallet-field'),
                  initialValue: widget.wallet.name,
                  readOnly: true,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.username],
                ),
                const SizedBox(height: 16),
                PasswordTextField(
                  onFieldSubmitted: state.isLoading ? null : _submitLogin,
                  controller: _passwordController,
                  errorText: errorMessage,
                  autofillHints: const [AutofillHints.password],
                ),
                const SizedBox(height: 32),
                QuickLoginSwitch(
                  value: _isQuickLoginEnabled,
                  onChanged: (value) {
                    setState(() => _isQuickLoginEnabled = value);
                  },
                ),
                const SizedBox(height: 16),
                if (_user != null && _user!.isBip39Seed == true) ...[
                  HDWalletModeSwitch(
                    value: _isHdMode,
                    onChanged: (value) {
                      setState(() => _isHdMode = value);
                      unawaited(
                        storeHdWalletModePreference(widget.wallet.id, value),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                ],
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.0),
                  child: UiPrimaryButton(
                    height: 50,
                    text: state.isLoading
                        ? '${LocaleKeys.pleaseWait.tr()}...'
                        : LocaleKeys.logIn.tr(),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    onPressed: state.isLoading ? null : _submitLogin,
                  ),
                ),
                const SizedBox(height: 8),
                UiUnderlineTextButton(
                  key: _backKeyButton,
                  onPressed: widget.onCancel,
                  text: LocaleKeys.cancel.tr(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

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
  });

  final String? errorText;
  final TextEditingController controller;
  final void Function()? onFieldSubmitted;
  final Iterable<String>? autofillHints;

  @override
  State<PasswordTextField> createState() => _PasswordTextFieldState();
}

class _PasswordTextFieldState extends State<PasswordTextField> {
  bool _isPasswordObscured = true;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
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
          controller: widget.controller,
          obscureText: _isPasswordObscured,
          errorText: widget.errorText,
          autofillHints: widget.autofillHints ?? const [AutofillHints.password],
          maxLength: passwordMaxLength,
          counterText: '',
          hintText: LocaleKeys.walletCreationPasswordHint.tr(),
          suffixIcon: PasswordVisibilityControl(
            onVisibilityChange: onVisibilityChange,
          ),
          onFieldSubmitted: (_) => widget.onFieldSubmitted?.call(),
          focusNode: _focusNode,
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

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/legal_agreement/legal_agreement_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';
import 'package:web_dex/shared/utils/hd_wallet_mode_preference.dart';
import 'package:web_dex/shared/widgets/disclaimer/terms_consent_text.dart';
import 'package:web_dex/shared/widgets/password_visibility_control.dart';
import 'package:web_dex/shared/widgets/quick_login_switch.dart';
import 'package:web_dex/views/common/wallet_access/wallet_passkey_icon.dart';
import 'package:web_dex/views/wallets_manager/widgets/hdwallet_mode_switch.dart';

class WalletLogIn extends StatefulWidget {
  const WalletLogIn({
    required this.wallet,
    required this.onLogin,
    required this.onCancel,
    this.onSwitchWallet,
    this.onRecover,
    this.initialHdMode = false,
    this.initialQuickLogin = false,
    super.key,
  });

  final Wallet wallet;
  final void Function(String, Wallet, bool) onLogin;
  final void Function() onCancel;
  final VoidCallback? onSwitchWallet;
  final VoidCallback? onRecover;
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
  bool _waitingForLegal = false;
  KdfUser? _user;
  bool? _storedHdPreference;
  Future<WalletAccessStatus?>? _accessStatus;
  bool _manualPassword = false;
  bool _automaticAttempted = false;

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _accessStatus ??=
        context.read<WalletAccessService?>()?.statusForWallet(widget.wallet) ??
        Future<WalletAccessStatus?>.value();
  }

  Future<void> _submitManaged({bool automatic = false}) async {
    if (!automatic) _automaticAttempted = true;
    if (_waitingForLegal || context.read<AuthBloc>().state.isLoading) return;
    _waitingForLegal = true;
    final agreement = await awaitLegalAgreement(context);
    _waitingForLegal = false;
    if (!mounted || agreement == null) return;
    // Reopening a wallet must not accept new legal terms on the user's behalf.
    if (automatic && agreement.status != LegalAgreementStatus.current) return;
    if (!automatic) {
      context.read<LegalAgreementBloc>().add(
        LegalAgreementSubmitted('wallet-login', snapshot: agreement.snapshot),
      );
    }
    context.read<AuthBloc>().add(
      AuthManagedSignInRequested(wallet: widget.wallet, automatic: automatic),
    );
  }

  Future<void> _fetchKdfUser() async {
    final kdfSdk = RepositoryProvider.of<KomodoDefiSdk>(context);
    final users = await kdfSdk.auth.getUsers();
    final user = users.firstWhereOrNull(
      (user) => user.walletId.name == widget.wallet.name,
    );

    if (mounted && user != null) {
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
    _passwordController.clear();
    _passwordController.dispose();
    TextInput.finishAutofillContext(shouldSave: false);
    super.dispose();
  }

  void _submitLogin() async {
    if (_waitingForLegal) return;
    _waitingForLegal = true;
    final agreement = await awaitLegalAgreement(context);
    _waitingForLegal = false;
    if (!mounted || agreement == null) return;
    final consentSnapshot = agreement.snapshot;
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

      if (!mounted || !context.read<LegalAgreementBloc>().canComplete) return;
      context.read<LegalAgreementBloc>().add(
        LegalAgreementSubmitted('wallet-login', snapshot: consentSnapshot),
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
    // Legal documents are published before the asynchronous acceptance lookup
    // finishes. Wait for current acceptance without consuming the launch attempt.
    final legalStatus = context.select(
      (LegalAgreementBloc bloc) => bloc.state.status,
    );
    return BlocBuilder<AuthBloc, AuthBlocState>(
      builder: (context, state) {
        final errorMessage =
            state.authError?.type == AuthExceptionType.incorrectPassword
            ? LocaleKeys.incorrectPassword.tr()
            : state.authError?.message;

        return FutureBuilder<WalletAccessStatus?>(
          future: _accessStatus,
          builder: (context, snapshot) {
            final status = snapshot.data;
            if (status?.hasManagedCredential == true && !_manualPassword) {
              if (widget.initialQuickLogin &&
                  !_automaticAttempted &&
                  legalStatus == LegalAgreementStatus.current) {
                _automaticAttempted = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _submitManaged(automatic: true);
                });
              }
              return _ManagedWalletUnlock(
                walletDisplayName: widget.wallet.displayName,
                status: status!,
                loading: state.isLoading,
                errorMessage: errorMessage,
                onUnlock: () => _submitManaged(),
                onPassword: () => setState(() {
                  _manualPassword = true;
                  _automaticAttempted = true;
                }),
                onSwitchWallet: widget.onSwitchWallet ?? widget.onCancel,
                onRecover: widget.onRecover,
                onCancel: widget.onCancel,
              );
            }
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            return AutofillGroup(
              onDisposeAction: AutofillContextAction.cancel,
              child: ScreenshotSensitive(
                child: Column(
                  mainAxisSize: isMobile ? MainAxisSize.max : MainAxisSize.min,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        LocaleKeys.walletLogInTitle.tr(),
                        style: Theme.of(
                          context,
                        ).textTheme.titleLarge?.copyWith(fontSize: 18),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      widget.wallet.displayName,
                      key: const Key('wallet-display-name'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Offstage(
                      child: ExcludeFocus(
                        child: UiTextFormField(
                          key: const Key('wallet-field'),
                          initialValue: widget.wallet.name,
                          readOnly: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          enableIMEPersonalizedLearning: false,
                          autofillHints: const [AutofillHints.username],
                        ),
                      ),
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
                            storeHdWalletModePreference(
                              widget.wallet.id,
                              value,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                    ],
                    TermsConsentText(actionLabel: LocaleKeys.logIn.tr()),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2.0),
                      child: LegalConsentAction(
                        builder: (allowed) => UiPrimaryButton(
                          expandForText: true,
                          height: 50,
                          text: state.isLoading
                              ? '${LocaleKeys.pleaseWait.tr()}...'
                              : LocaleKeys.logIn.tr(),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                          onPressed: !allowed || state.isLoading
                              ? null
                              : _submitLogin,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    UiUnderlineTextButton(
                      key: _backKeyButton,
                      onPressed: widget.onCancel,
                      text: LocaleKeys.cancel.tr(),
                    ),
                    if (status?.hasManagedCredential == true)
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onSurface,
                        ),
                        onPressed: state.isLoading
                            ? null
                            : () => setState(() => _manualPassword = false),
                        child: Text(
                          (snapshot.data?.protection ==
                                      CredentialProtection.passkey
                                  ? 'authUnlockWithPasskey'
                                  : 'authUseDeviceUnlock')
                              .tr(),
                        ),
                      ),
                    if (widget.onRecover != null)
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onSurface,
                        ),
                        onPressed: state.isLoading ? null : widget.onRecover,
                        child: Text('authRecoverWallet'.tr()),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ManagedWalletUnlock extends StatelessWidget {
  const _ManagedWalletUnlock({
    required this.walletDisplayName,
    required this.status,
    required this.loading,
    required this.errorMessage,
    required this.onUnlock,
    required this.onPassword,
    required this.onSwitchWallet,
    required this.onRecover,
    required this.onCancel,
  });
  final String walletDisplayName;
  final WalletAccessStatus status;
  final bool loading;
  final String? errorMessage;
  final VoidCallback onUnlock;
  final VoidCallback onPassword;
  final VoidCallback onSwitchWallet;
  final VoidCallback? onRecover;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (status.protection == CredentialProtection.passkey)
        const WalletPasskeyIcon(size: 36)
      else
        Icon(
          status.requiresAuthentication
              ? Icons.lock_outline
              : Icons.account_balance_wallet_outlined,
          size: 36,
        ),
      const SizedBox(height: 16),
      Semantics(
        header: true,
        child: Text(
          'authUnlockTitle'.tr(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        walletDisplayName,
        key: const Key('wallet-display-name'),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 12),
      Text(
        status.requiresAuthentication
            ? 'authUnlockDescription'.tr()
            : 'authUnprotectedLocalDescription'.tr(),
        textAlign: TextAlign.center,
      ),
      if (errorMessage != null) ...[
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: Text(
            errorMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
      const SizedBox(height: 24),
      TermsConsentText(actionLabel: 'authUnlock'.tr()),
      const SizedBox(height: 12),
      LegalConsentAction(
        builder: (allowed) => UiPrimaryButton(
          expandForText: true,
          key: const Key('managed-wallet-unlock'),
          height: 52,
          text: loading
              ? LocaleKeys.pleaseWait.tr()
              : status.protection == CredentialProtection.passkey
              ? 'authUnlockWithPasskey'.tr()
              : status.requiresAuthentication
              ? 'authUseDeviceUnlock'.tr()
              : 'authOpenWallet'.tr(),
          onPressed: loading || !allowed ? null : onUnlock,
        ),
      ),
      const SizedBox(height: 8),
      TextButton(
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.onSurface,
        ),
        onPressed: loading ? null : onPassword,
        child: Text('authUsePassword'.tr()),
      ),
      TextButton(
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.onSurface,
        ),
        onPressed: loading ? null : onSwitchWallet,
        child: Text('authSwitchWallet'.tr()),
      ),
      if (onRecover != null)
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.onSurface,
          ),
          onPressed: loading ? null : onRecover,
          child: Text('authRecoverWallet'.tr()),
        ),
      UiUnderlineTextButton(text: LocaleKeys.cancel.tr(), onPressed: onCancel),
    ],
  );
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

class _PasswordTextFieldState extends State<PasswordTextField>
    with WidgetsBindingObserver {
  bool _isPasswordObscured = true;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focusNode = FocusNode();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted) {
      setState(() => _isPasswordObscured = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
          controller: widget.controller,
          obscureText: _isPasswordObscured,
          errorText: widget.errorText,
          autofillHints: widget.autofillHints ?? const [AutofillHints.password],
          maxLength: passwordMaxLength,
          counterText: '',
          hintText: LocaleKeys.walletCreationPasswordHint.tr(),
          suffixIcon: PasswordVisibilityControl(
            isObscured: _isPasswordObscured,
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

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
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';
import 'package:web_dex/shared/utils/hd_wallet_mode_preference.dart';
import 'package:web_dex/shared/widgets/disclaimer/terms_consent_text.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_feedback.dart';
import 'package:web_dex/views/common/wallet_access/wallet_passkey_icon.dart';
import 'package:web_dex/views/common/wallet_password_dialog/password_text_field.dart';
import 'package:web_dex/views/common/wallet_password_dialog/wallet_access_actions.dart';
import 'package:web_dex/views/wallets_manager/widgets/hdwallet_mode_switch.dart';

export 'package:web_dex/views/common/wallet_password_dialog/password_text_field.dart';

part 'wallet_login_faces.dart';

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

  /// Opens the wallet list. Leave null when the sheet was reached from that
  /// list: Cancel already returns there, and two controls for one destination
  /// read as two different things.
  final VoidCallback? onSwitchWallet;
  final VoidCallback? onRecover;
  final bool initialHdMode;

  /// Whether this wallet was remembered, so its enrolled unlock may be offered
  /// once without a tap. Handed back unchanged through [onLogin].
  final bool initialQuickLogin;

  @override
  State<WalletLogIn> createState() => _WalletLogInState();
}

class _WalletLogInState extends State<WalletLogIn> {
  final TextEditingController _passwordController = TextEditingController();
  final _passwordFocus = FocusNode(debugLabel: 'wallet sign-in password');
  late bool _isHdMode;
  bool _waitingForLegal = false;
  KdfUser? _user;
  bool? _storedHdPreference;
  Future<WalletAccessStatus?>? _accessStatus;
  bool _manualPassword = false;
  bool _automaticAttempted = false;
  bool _managedAttempt = false;

  /// Some stored unlocks only show they no longer work when read.
  bool _unlockLost = false;

  /// The error on screen when the user changed method; it described the other
  /// method's attempt.
  AuthException? _dismissedError;

  @override
  void initState() {
    super.initState();
    _isHdMode =
        widget.initialHdMode ||
        widget.wallet.config.type == WalletType.hdwallet;
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

  Future<void> _submitManaged({
    bool automatic = false,
    bool generatedPassword = false,
  }) async {
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
    _managedAttempt = true;
    context.read<AuthBloc>().add(
      AuthManagedSignInRequested(
        wallet: widget.wallet,
        automatic: automatic,
        generatedPassword: generatedPassword,
      ),
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
    _passwordFocus.dispose();
    TextInput.finishAutofillContext(shouldSave: false);
    super.dispose();
  }

  void _submitLogin() async {
    if (_waitingForLegal) return;
    _managedAttempt = false;
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
        widget.initialQuickLogin,
      );
    });
  }

  void _showPasswordFace(bool manual) {
    setState(() {
      _manualPassword = manual;
      _automaticAttempted = true;
      _dismissedError = context.read<AuthBloc>().state.authError;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Legal documents are published before the asynchronous acceptance lookup
    // finishes. Wait for current acceptance without consuming the launch attempt.
    final legalStatus = context.select(
      (LegalAgreementBloc bloc) => bloc.state.status,
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
      },
      child: BlocConsumer<AuthBloc, AuthBlocState>(
        listenWhen: (previous, current) =>
            current.authError != null &&
            !identical(previous.authError, current.authError),
        // Submitting takes focus off the field; a failed attempt hands it back.
        listener: (_, state) {
          if (_passwordFocus.context?.mounted ?? false) {
            _passwordFocus.requestFocus();
          }
          if (_managedAttempt) {
            _managedAttempt = false;
            if (managedUnlockGone(state.authError)) {
              // The face that explains the loss replaces the failure's message.
              setState(() {
                _unlockLost = true;
                _dismissedError = state.authError;
              });
            }
          }
        },
        builder: (context, state) {
          final authError = identical(state.authError, _dismissedError)
              ? null
              : state.authError;
          final errorMessage =
              authError?.type == AuthExceptionType.incorrectPassword
              ? LocaleKeys.incorrectPassword.tr()
              : authError?.message;

          return FutureBuilder<WalletAccessStatus?>(
            future: _accessStatus,
            builder: (context, snapshot) {
              final status = snapshot.data;
              final unlockLost =
                  status?.lostProtection != null ||
                  (_unlockLost && status != null);
              final managed =
                  status?.hasManagedCredential == true && !unlockLost;
              if (managed && !_manualPassword) {
                final generated = status!.generatedPassword;
                if (widget.initialQuickLogin &&
                    !_automaticAttempted &&
                    legalStatus == LegalAgreementStatus.current) {
                  _automaticAttempted = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      _submitManaged(
                        automatic: true,
                        generatedPassword: generated,
                      );
                    }
                  });
                }
                return _ManagedWalletUnlock(
                  walletDisplayName: widget.wallet.displayName,
                  status: status,
                  loading: state.isLoading,
                  errorMessage: errorMessage,
                  onUnlock: () => _submitManaged(generatedPassword: generated),
                  onPassword: () => _showPasswordFace(true),
                  exits: _exits(state.isLoading),
                );
              }
              if (snapshot.connectionState != ConnectionState.done) {
                return Center(
                  child: WalletAccessProgress(
                    label: 'authProtectionChecking'.tr(),
                    showLabel: true,
                  ),
                );
              }
              final recover = widget.onRecover;
              if (unlockLost &&
                  status!.generatedPassword &&
                  !_manualPassword &&
                  recover != null) {
                return _UnlockLostRecovery(
                  walletDisplayName: widget.wallet.displayName,
                  passwordMayBeSaved: _passwordMayBeSaved(
                    status.passwordManager,
                  ),
                  onRecover: recover,
                  onPassword: () => _showPasswordFace(true),
                  exits: _exits(state.isLoading, showRecover: false),
                );
              }
              final guidance = WalletPasswordGuidance(
                unlockUnavailable: snapshot.hasError,
                generatedPassword: status?.generatedPassword ?? false,
                unlockLost: unlockLost,
              );
              // Without another way in, a user who never chose this password
              // needs the recovery phrase more than a list of exits.
              final recoverFirst =
                  !managed &&
                  guidance.passwordMayBeUnknown &&
                  widget.onRecover != null;
              return AutofillGroup(
                onDisposeAction: AutofillContextAction.cancel,
                child: ScreenshotSensitive(
                  child: Column(
                    mainAxisSize: isMobile
                        ? MainAxisSize.max
                        : MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SignInTitle(
                        walletDisplayName: widget.wallet.displayName,
                      ),
                      const SizedBox(height: 24),
                      guidance,
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
                      PasswordTextField(
                        onFieldSubmitted: state.isLoading ? null : _submitLogin,
                        controller: _passwordController,
                        focusNode: _passwordFocus,
                        autofillHints: const [AutofillHints.password],
                      ),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 12),
                        WalletAccessNotice(
                          text: errorMessage,
                          tone: WalletAccessTone.error,
                        ),
                      ],
                      if (_user != null && _user!.isBip39Seed == true) ...[
                        const SizedBox(height: 16),
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
                      ],
                      const SizedBox(height: 24),
                      TermsConsentText(actionLabel: 'authUnlock'.tr()),
                      const SizedBox(height: 12),
                      LegalConsentAction(
                        builder: (allowed) => WalletAccessPrimaryButton(
                          buttonKey: const Key('wallet-password-unlock'),
                          text: 'authUnlock'.tr(),
                          busy: state.isLoading,
                          onPressed: allowed ? _submitLogin : null,
                        ),
                      ),
                      if (managed) ...[
                        const SizedBox(height: 8),
                        WalletAccessSecondaryButton(
                          text: walletUnlockMethodLabel(status),
                          onPressed: state.isLoading
                              ? null
                              : () => _showPasswordFace(false),
                        ),
                      ] else if (recoverFirst) ...[
                        const SizedBox(height: 8),
                        WalletAccessSecondaryButton(
                          text: 'authRecoverWallet'.tr(),
                          onPressed: state.isLoading ? null : widget.onRecover,
                        ),
                      ],
                      const SizedBox(height: 16),
                      _exits(state.isLoading, showRecover: !recoverFirst),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// The same exits in the same order on both faces.
  Widget _exits(bool loading, {bool showRecover = true}) => _SignInExits(
    loading: loading,
    onSwitchWallet: widget.onSwitchWallet,
    onRecover: showRecover ? widget.onRecover : null,
    onCancel: widget.onCancel,
  );
}

class _SignInTitle extends StatelessWidget {
  const _SignInTitle({required this.walletDisplayName, this.locked = true});
  final String walletDisplayName;
  final bool locked;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      walletUnlockTitle(walletDisplayName, locked: locked),
      key: const Key('wallet-display-name'),
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleLarge,
    ),
  );
}

class _SignInExits extends StatelessWidget {
  const _SignInExits({
    required this.loading,
    required this.onSwitchWallet,
    required this.onRecover,
    required this.onCancel,
  });

  final bool loading;
  final VoidCallback? onSwitchWallet;
  final VoidCallback? onRecover;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (onSwitchWallet != null)
        WalletAccessTertiaryButton(
          text: 'authSwitchWallet'.tr(),
          onPressed: loading ? null : onSwitchWallet,
        ),
      if (onRecover != null)
        WalletAccessTertiaryButton(
          text: 'authRecoverWallet'.tr(),
          onPressed: loading ? null : onRecover,
        ),
      WalletAccessTertiaryButton(
        text: LocaleKeys.cancel.tr(),
        onPressed: onCancel,
      ),
    ],
  );
}

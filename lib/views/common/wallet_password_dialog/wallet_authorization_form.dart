import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/services/wallet_access/wallet_lock_policy.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_feedback.dart';
import 'package:web_dex/views/common/wallet_password_dialog/wallet_access_actions.dart';
import 'package:web_dex/views/common/wallet_password_dialog/wallet_password_input.dart';

/// The body of every "confirm it's you" dialog: the wallet's enrolled method
/// or its password, one primary action and Cancel.
///
/// The owner decides what a confirmation does and reports [busy] and [error];
/// this form owns the typed password, which it clears before handing it over.
class WalletAuthorizationForm extends StatefulWidget {
  const WalletAuthorizationForm({
    required this.status,
    required this.walletName,
    required this.busy,
    required this.onConfirm,
    required this.onCancel,
    this.error,
    this.errorTone = WalletAccessTone.error,
    this.busyTitle,
    this.busyMessage,
    this.passwordOnly = false,
    this.closing = false,
    this.padding = EdgeInsets.zero,
    this.passwordFieldKey,
    this.confirmKey,
    this.cancelKey,
    super.key,
  });

  /// How the wallet is protected. Null when there is nothing to look up, and
  /// the form asks for the password.
  final Future<WalletAccessStatus?>? status;
  final String walletName;
  final bool busy;

  /// Receives the typed password, or null to confirm with the enrolled method.
  final ValueChanged<String?> onConfirm;
  final VoidCallback onCancel;
  final String? error;
  final WalletAccessTone errorTone;
  final String? busyTitle;
  final String? busyMessage;

  /// Never offers the enrolled method, for example to replace a lost passkey.
  final bool passwordOnly;

  /// The owner is closing the dialog; nothing more can be submitted.
  final bool closing;
  final EdgeInsets padding;
  final Key? passwordFieldKey;
  final Key? confirmKey;
  final Key? cancelKey;

  @override
  State<WalletAuthorizationForm> createState() =>
      _WalletAuthorizationFormState();
}

class _WalletAuthorizationFormState extends State<WalletAuthorizationForm>
    with WidgetsBindingObserver {
  final _password = TextEditingController();
  final _passwordFocus = FocusNode(debugLabel: 'wallet authorization password');
  final _confirmFocus = FocusNode(debugLabel: 'wallet authorization confirm');
  bool _usePassword = false;
  bool _showsPassword = false;
  // An error belongs to the method that produced it.
  bool _errorDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (lifecycleLeavesApp(state)) _password.clear();
  }

  @override
  void didUpdateWidget(WalletAuthorizationForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.status, oldWidget.status)) {
      _password.clear();
      _usePassword = false;
    }
    if (widget.busy || widget.error != oldWidget.error) {
      _errorDismissed = false;
    }
    // Submitting takes focus off the field; a failed attempt gives it back so
    // the user can retype at once.
    final failed =
        widget.error != null &&
        !widget.busy &&
        (oldWidget.busy || widget.error != oldWidget.error);
    if (failed && _showsPassword && !widget.closing) {
      _passwordFocus.requestFocus();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _password.clear();
    _password.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    TextInput.finishAutofillContext(shouldSave: false);
    super.dispose();
  }

  void _confirm({required bool withPassword}) {
    if (widget.busy || widget.closing) return;
    if (!withPassword) {
      widget.onConfirm(null);
      return;
    }
    final entered = _password.text;
    if (entered.isEmpty) {
      _passwordFocus.requestFocus();
      return;
    }
    _password.clear();
    // An unverified password must not be offered to the password manager.
    TextInput.finishAutofillContext(shouldSave: false);
    widget.onConfirm(entered);
  }

  void _cancel() {
    if (widget.closing) return;
    _password.clear();
    TextInput.finishAutofillContext(shouldSave: false);
    widget.onCancel();
  }

  void _switchMethod() {
    if (widget.busy || widget.closing) return;
    final toPassword = !_usePassword;
    setState(() {
      _password.clear();
      _usePassword = toPassword;
      _errorDismissed = true;
    });
    // The other control already holds focus, so autofocus alone would not
    // move it to the face that just appeared.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (toPassword ? _passwordFocus : _confirmFocus).requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<WalletAccessStatus?>(
    future: widget.status,
    builder: (context, snapshot) {
      final theme = Theme.of(context);
      // Until the lookup answers there is no telling which face applies;
      // showing either would flash the wrong one.
      final resolved =
          snapshot.connectionState != ConnectionState.waiting ||
          snapshot.hasData ||
          snapshot.hasError;
      final status = snapshot.data;
      final enrolled =
          status?.hasManagedCredential == true && !widget.passwordOnly;
      final withPassword = !enrolled || _usePassword;
      _showsPassword = resolved && withPassword;
      final error = widget.busy || _errorDismissed ? null : widget.error;
      final body = theme.textTheme.bodyMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: theme.colorScheme.onSurface,
      );
      return CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _cancel},
        child: SingleChildScrollView(
          padding: widget.padding,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 362),
            child: AutofillGroup(
              onDisposeAction: AutofillContextAction.cancel,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      widget.busy && widget.busyTitle != null
                          ? widget.busyTitle!
                          : 'authAuthorizationTitle'.tr(),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!resolved)
                    Center(
                      child: WalletAccessProgress(
                        label: 'authProtectionChecking'.tr(),
                        showLabel: true,
                      ),
                    )
                  else if (!withPassword)
                    Text(
                      (status!.requiresAuthentication
                              ? 'authConfirmWithDevice'
                              : 'authUnprotectedConfirmation')
                          .tr(),
                      textAlign: TextAlign.center,
                      style: body,
                    )
                  else ...[
                    WalletPasswordGuidance.of(snapshot),
                    WalletPasswordInput(
                      fieldKey: widget.passwordFieldKey,
                      controller: _password,
                      focusNode: _passwordFocus,
                      walletName: widget.walletName,
                      busy: widget.busy || widget.closing,
                      onSubmitted: () => _confirm(withPassword: true),
                    ),
                  ],
                  if (widget.busy && widget.busyMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      widget.busyMessage!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    WalletAccessNotice(text: error, tone: widget.errorTone),
                  ],
                  const SizedBox(height: 24),
                  if (resolved)
                    WalletAccessPrimaryButton(
                      buttonKey: widget.confirmKey,
                      focusNode: _confirmFocus,
                      autofocus: !withPassword,
                      text: LocaleKeys.continueText.tr(),
                      busy: widget.busy,
                      onPressed: widget.closing
                          ? null
                          : () => _confirm(withPassword: withPassword),
                    ),
                  if (resolved && enrolled) ...[
                    const SizedBox(height: 8),
                    WalletAccessSecondaryButton(
                      text: !_usePassword
                          ? 'authUsePassword'.tr()
                          : status!.protection == CredentialProtection.passkey
                          ? 'authUsePasskey'.tr()
                          : status.requiresAuthentication
                          ? 'authUseDeviceUnlock'.tr()
                          : LocaleKeys.back.tr(),
                      onPressed: widget.closing ? null : _switchMethod,
                    ),
                  ],
                  const SizedBox(height: 8),
                  WalletAccessTertiaryButton(
                    key: widget.cancelKey,
                    text: LocaleKeys.cancel.tr(),
                    onPressed: widget.closing ? null : _cancel,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

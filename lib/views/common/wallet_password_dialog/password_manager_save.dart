import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';
import 'package:web_dex/views/common/wallet_password_dialog/wallet_password_dialog.dart';

/// Native provider acceptance and compatibility autofill are separate outcomes.
/// Autofill can request a save, but cannot confirm that the provider saved it.
Future<PasswordManagerOutcome> saveWalletPassword(
  BuildContext context, {
  required WalletAccessService access,
  required WalletId walletId,
  String? password,
}) async {
  if (password == null) {
    final status = await access.status(walletId: walletId);
    if (!context.mounted) return PasswordManagerOutcome.declined;
    if (!status.hasManagedCredential) {
      password = await walletPasswordDialog(context);
      if (password == null || !context.mounted) {
        return PasswordManagerOutcome.declined;
      }
    }
  }
  final credential = await access.authorize(
    walletId: walletId,
    password: password,
    reason: 'authSensitiveAuthorizationReason'.tr(),
  );
  if (!context.mounted) return PasswordManagerOutcome.declined;
  final nativeOutcome = await access.saveToPasswordManager(
    walletId: walletId,
    password: credential,
  );
  if (nativeOutcome != PasswordManagerOutcome.unavailable || !context.mounted) {
    return nativeOutcome;
  }
  final outcome =
      await showDialog<PasswordManagerOutcome>(
        context: context,
        builder: (context) => _AutofillSaveDialog(
          walletName: walletId.name,
          password: credential,
          closeEvents: access.unlockCoordinator.sensitiveViewsMustClose,
        ),
      ) ??
      PasswordManagerOutcome.declined;
  await access.recordPasswordManagerOutcome(
    walletId: walletId,
    outcome: outcome,
  );
  return outcome;
}

/// Offer only after the wallet is committed. The optional action is serialized
/// after provisioning/device enrollment and never delays opening the wallet.
Future<void> offerWalletPasswordSave(
  BuildContext context, {
  required WalletAccessService access,
  required WalletId walletId,
}) async {
  try {
    await access.recordPasswordManagerOutcome(
      walletId: walletId,
      outcome: PasswordManagerOutcome.offered,
    );
  } catch (_) {
    // Failure to record an optional offer does not affect the committed wallet.
  }
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 12),
      showCloseIcon: true,
      content: Text('authPasswordManagerOffer'.tr()),
      action: SnackBarAction(
        label: 'authSavePassword'.tr(),
        onPressed: () async {
          try {
            final outcome = await saveWalletPassword(
              context,
              access: access,
              walletId: walletId,
            );
            if (!context.mounted) return;
            messenger.showSnackBar(
              SnackBar(content: Text(passwordManagerOutcomeMessage(outcome))),
            );
          } catch (_) {
            if (context.mounted) {
              messenger.showSnackBar(
                SnackBar(content: Text('authPasswordManagerFailed'.tr())),
              );
            }
          }
        },
      ),
    ),
  );
}

String passwordManagerOutcomeMessage(PasswordManagerOutcome outcome) =>
    switch (outcome) {
      PasswordManagerOutcome.accepted => 'authPasswordManagerAccepted'.tr(),
      PasswordManagerOutcome.declined => 'authPasswordManagerDeclined'.tr(),
      PasswordManagerOutcome.failed => 'authPasswordManagerFailed'.tr(),
      PasswordManagerOutcome.unavailable =>
        'authPasswordManagerUnavailable'.tr(),
      PasswordManagerOutcome.offered ||
      PasswordManagerOutcome.unknown => 'authPasswordManagerUnknown'.tr(),
    };

class _AutofillSaveDialog extends StatefulWidget {
  const _AutofillSaveDialog({
    required this.walletName,
    required this.password,
    required this.closeEvents,
  });
  final String walletName;
  final String password;
  final Stream<void> closeEvents;
  @override
  State<_AutofillSaveDialog> createState() => _AutofillSaveDialogState();
}

class _AutofillSaveDialogState extends State<_AutofillSaveDialog>
    with WidgetsBindingObserver {
  late final TextEditingController _password;
  late final TextEditingController _username;
  StreamSubscription<void>? _closeEvents;
  bool _obscured = true;
  bool _closed = false;
  @override
  void initState() {
    super.initState();
    _password = TextEditingController(text: widget.password);
    _username = TextEditingController(text: widget.walletName);
    WidgetsBinding.instance.addObserver(this);
    _closeEvents = widget.closeEvents.listen((_) {
      _password.clear();
      _close(PasswordManagerOutcome.declined);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _password.clear();
      _close(PasswordManagerOutcome.declined);
    }
  }

  void _close(PasswordManagerOutcome outcome) {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop(outcome);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _closeEvents?.cancel();
    _password.clear();
    _password.dispose();
    _username.dispose();
    TextInput.finishAutofillContext(shouldSave: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScreenshotSensitive(
    child: AlertDialog(
      scrollable: true,
      title: Text('authSavePassword'.tr()),
      content: SingleChildScrollView(
        child: AutofillGroup(
          onDisposeAction: AutofillContextAction.cancel,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('authPasswordManagerCompatibility'.tr()),
              const SizedBox(height: 16),
              TextField(
                readOnly: true,
                controller: _username,
                autofillHints: const [AutofillHints.username],
                decoration: InputDecoration(labelText: 'authWalletName'.tr()),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('password-manager-save-credential'),
                controller: _password,
                readOnly: true,
                obscureText: _obscured,
                autocorrect: false,
                enableSuggestions: false,
                enableInteractiveSelection: false,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'authPassword'.tr(),
                  suffixIcon: IconButton(
                    tooltip: _obscured
                        ? 'authShowPassword'.tr()
                        : 'authHidePassword'.tr(),
                    icon: Icon(
                      _obscured
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () => setState(() => _obscured = !_obscured),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('authPasswordManagerNotBackup'.tr()),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.onSurface,
          ),
          onPressed: () =>
              Navigator.of(context).pop(PasswordManagerOutcome.declined),
          child: Text(LocaleKeys.cancel.tr()),
        ),
        FilledButton(
          key: const Key('password-manager-save-submit'),
          onPressed: () {
            TextInput.finishAutofillContext();
            _close(PasswordManagerOutcome.unknown);
          },
          child: Text('authSavePassword'.tr()),
        ),
      ],
    ),
  );
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/security_key/security_key_prompts.dart';
import 'package:web_dex/views/common/wallet_access/security_key/security_key_pin_form.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_feedback.dart';
import 'package:web_dex/views/common/wallet_password_dialog/wallet_access_actions.dart';

/// One step of a security-key request: insert, choose, PIN, touch.
class SecurityKeyPromptSheet extends StatelessWidget {
  const SecurityKeyPromptSheet({
    required this.prompt,
    required this.prompts,
    super.key,
  });

  final SecurityKeyPrompt prompt;
  final SecurityKeyPrompts prompts;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const ModalBarrier(dismissible: false, color: Colors.black54),
      SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: FocusScope(autofocus: true, child: _content()),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _content() => switch (prompt.stage) {
    SecurityKeyStage.enterPin => SecurityKeyPinForm(
      prompt: prompt,
      onSubmit: prompts.answerPin,
      onCancel: prompts.cancel,
    ),
    SecurityKeyStage.chooseAccount => _AccountChoice(
      accounts: prompt.accounts,
      onChoose: prompts.answerAccount,
      onCancel: prompts.cancel,
    ),
    SecurityKeyStage.timedOut => _Step(
      icon: Icons.timer_off_outlined,
      title: 'authSecurityKeyTimedOutTitle'.tr(),
      body: 'authSecurityKeyTimedOut'.tr(),
      product: prompt.product,
      primary: LocaleKeys.tryAgain.tr(),
      onPrimary: prompts.retry,
      onCancel: prompts.cancel,
    ),
    SecurityKeyStage.noAccess => _Step(
      icon: Icons.block_outlined,
      title: 'authSecurityKeyNoAccessTitle'.tr(),
      body: 'authSecurityKeyNoAccess'.tr(),
      onCancel: prompts.cancel,
    ),
    final stage => _Step(
      icon:
          stage == SecurityKeyStage.touch || stage == SecurityKeyStage.chooseKey
          ? Icons.touch_app_outlined
          : Icons.usb,
      title: switch (stage) {
        SecurityKeyStage.touch => 'authSecurityKeyTouchTitle',
        SecurityKeyStage.chooseKey => 'authSecurityKeyChooseKeyTitle',
        SecurityKeyStage.reinsert => 'authSecurityKeyReinsertTitle',
        _ => 'authSecurityKeyInsertTitle',
      }.tr(),
      body: switch (stage) {
        SecurityKeyStage.touch => 'authSecurityKeyTouch',
        SecurityKeyStage.chooseKey => 'authSecurityKeyChooseKey',
        SecurityKeyStage.reinsert => 'authSecurityKeyReinsert',
        _ => 'authSecurityKeyInsert',
      }.tr(),
      product: prompt.product,
      waiting: true,
      onCancel: prompts.cancel,
    ),
  };
}

/// A heading for every step, so each reads on its own to a screen reader.
class SecurityKeyStepHeader extends StatelessWidget {
  const SecurityKeyStepHeader({
    required this.icon,
    required this.title,
    this.body,
    this.product,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? body;
  final String? product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Icon(icon, size: 40, color: theme.colorScheme.primary),
        ),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
        ),
        if (product != null) ...[
          const SizedBox(height: 4),
          Text(
            product!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (body != null) ...[
          const SizedBox(height: 8),
          Text(
            body!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 14,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.icon,
    required this.title,
    required this.body,
    required this.onCancel,
    this.product,
    this.waiting = false,
    this.primary,
    this.onPrimary,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? product;

  /// The app waits on the key, not on the user.
  final bool waiting;
  final String? primary;
  final VoidCallback? onPrimary;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SecurityKeyStepHeader(
        icon: icon,
        title: title,
        body: body,
        product: product,
      ),
      if (waiting) ...[
        const SizedBox(height: 16),
        Center(child: WalletAccessProgress(label: title)),
      ],
      const SizedBox(height: 24),
      if (primary != null) ...[
        WalletAccessPrimaryButton(
          buttonKey: const Key('security-key-primary'),
          autofocus: true,
          text: primary!,
          onPressed: onPrimary,
        ),
        const SizedBox(height: 8),
      ],
      WalletAccessSecondaryButton(
        key: const Key('security-key-cancel'),
        text: LocaleKeys.cancel.tr(),
        onPressed: onCancel,
      ),
    ],
  );
}

class _AccountChoice extends StatelessWidget {
  const _AccountChoice({
    required this.accounts,
    required this.onChoose,
    required this.onCancel,
  });

  final List<SecurityKeyAccount> accounts;
  final ValueChanged<int> onChoose;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SecurityKeyStepHeader(
        icon: Icons.key_outlined,
        title: 'authSecurityKeyChooseAccountTitle'.tr(),
        body: 'authSecurityKeyChooseAccount'.tr(),
      ),
      const SizedBox(height: 24),
      for (var i = 0; i < accounts.length; i++) ...[
        WalletAccessSecondaryButton(
          key: Key('security-key-account-$i'),
          text: _label(accounts[i]),
          onPressed: accounts[i].usable ? () => onChoose(i) : null,
        ),
        const SizedBox(height: 8),
      ],
      const SizedBox(height: 8),
      WalletAccessTertiaryButton(
        key: const Key('security-key-cancel'),
        text: LocaleKeys.cancel.tr(),
        onPressed: onCancel,
      ),
    ],
  );

  /// The web wallet names each passkey after its wallet plus a short ID.
  String _label(SecurityKeyAccount account) {
    final name =
        account.name ??
        account.displayName ??
        'authSecurityKeyUnnamedPasskey'.tr();
    return account.usable
        ? name
        : '$name\n${'authSecurityKeyPasskeyUnusable'.tr()}';
  }
}

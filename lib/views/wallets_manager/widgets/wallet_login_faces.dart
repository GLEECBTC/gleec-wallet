part of 'wallet_login.dart';

class _ManagedWalletUnlock extends StatelessWidget {
  const _ManagedWalletUnlock({
    required this.walletDisplayName,
    required this.status,
    required this.loading,
    required this.errorMessage,
    required this.onUnlock,
    required this.onPassword,
    required this.exits,
  });
  final String walletDisplayName;
  final WalletAccessStatus status;
  final bool loading;
  final String? errorMessage;
  final VoidCallback onUnlock;
  final VoidCallback onPassword;
  final Widget exits;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final method = walletUnlockMethodLabel(status);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: IconTheme.merge(
            data: IconThemeData(size: 36, color: theme.colorScheme.primary),
            child: status.protection == CredentialProtection.passkey
                ? const WalletPasskeyIcon(size: 36)
                : Icon(
                    status.requiresAuthentication
                        ? Icons.lock_outline
                        : Icons.account_balance_wallet_outlined,
                  ),
          ),
        ),
        const SizedBox(height: 16),
        _SignInTitle(
          walletDisplayName: walletDisplayName,
          locked: status.requiresAuthentication,
        ),
        if (!status.requiresAuthentication) ...[
          const SizedBox(height: 8),
          Text(
            'authUnprotectedLocalDescription'.tr(),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
        if (errorMessage != null) ...[
          const SizedBox(height: 16),
          WalletAccessNotice(text: errorMessage!, tone: WalletAccessTone.error),
        ],
        const SizedBox(height: 24),
        TermsConsentText(actionLabel: method),
        const SizedBox(height: 12),
        LegalConsentAction(
          builder: (allowed) => WalletAccessPrimaryButton(
            buttonKey: const Key('managed-wallet-unlock'),
            autofocus: true,
            text: method,
            busy: loading,
            onPressed: allowed ? onUnlock : null,
          ),
        ),
        const SizedBox(height: 8),
        WalletAccessSecondaryButton(
          text: 'authUsePassword'.tr(),
          onPressed: loading ? null : onPassword,
        ),
        const SizedBox(height: 16),
        exits,
      ],
    );
  }
}

/// Only an accepted or unreported save can hold a password nobody was shown.
bool _passwordMayBeSaved(PasswordManagerOutcome outcome) =>
    outcome == PasswordManagerOutcome.accepted ||
    outcome == PasswordManagerOutcome.unknown;

class _UnlockLostRecovery extends StatelessWidget {
  const _UnlockLostRecovery({
    required this.walletDisplayName,
    required this.passwordMayBeSaved,
    required this.onRecover,
    required this.onPassword,
    required this.exits,
  });

  final String walletDisplayName;
  final bool passwordMayBeSaved;
  final VoidCallback onRecover;
  final VoidCallback onPassword;
  final Widget exits;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ExcludeSemantics(
        child: Icon(
          Icons.key_off_outlined,
          size: 36,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      const SizedBox(height: 16),
      _SignInTitle(walletDisplayName: walletDisplayName),
      const SizedBox(height: 24),
      WalletAccessNotice(
        key: const Key('wallet-unlock-lost'),
        tone: WalletAccessTone.warning,
        text: walletUnlockLostMessage(),
      ),
      const SizedBox(height: 8),
      WalletAccessNotice(
        announce: false,
        text: 'authUnlockLostGeneratedHint'.tr(),
      ),
      const SizedBox(height: 24),
      WalletAccessPrimaryButton(
        buttonKey: const Key('wallet-unlock-lost-recover'),
        autofocus: true,
        text: 'authUseRecoveryPhrase'.tr(),
        onPressed: onRecover,
      ),
      if (passwordMayBeSaved) ...[
        const SizedBox(height: 8),
        WalletAccessSecondaryButton(
          key: const Key('wallet-unlock-lost-password'),
          text: 'authUseSavedPassword'.tr(),
          onPressed: onPassword,
        ),
      ],
      const SizedBox(height: 16),
      // A journal can be wrong about a password; the form stays reachable.
      if (!passwordMayBeSaved)
        WalletAccessTertiaryButton(
          key: const Key('wallet-unlock-lost-password'),
          text: 'authUsePassword'.tr(),
          onPressed: onPassword,
        ),
      exits,
    ],
  );
}

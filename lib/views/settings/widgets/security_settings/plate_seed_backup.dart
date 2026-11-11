import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/views/common/wallet_password_dialog/wallet_password_dialog.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_action_plate.dart';

class PlateSeedBackup extends StatelessWidget {
  const PlateSeedBackup({required this.onViewSeedPressed});
  final Function(BuildContext context) onViewSeedPressed;

  @override
  Widget build(BuildContext context) {
    final currentWallet = context.read<AuthBloc>().state.currentUser?.wallet;
    final hasBackup = currentWallet?.config.hasRecoveryPhrase ?? false;
    final authBloc = context.read<AuthBloc>();

    final text = hasBackup
        ? LocaleKeys.viewSeedPhrase.tr()
        : LocaleKeys.backupSeedPhrase.tr();

    final evidence = currentWallet?.config.recoveryEvidence;
    final recoveryStatus = evidence == RecoveryEvidence.phraseConfirmed
        ? 'authRecoveryReady'.tr()
        : evidence == RecoveryEvidence.phraseSupplied
        ? 'authRecoveryImported'.tr()
        : 'authRecoveryNotReady'.tr();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SecurityActionPlate(
          icon: const Icon(Icons.shield_outlined),
          title: 'authRecoveryPhraseTitle'.tr(),
          description:
              '$recoveryStatus\n${'authRecoveryPhraseDescription'.tr()}',
          actionText: text,
          onActionPressed: () => onViewSeedPressed(context),
        ),
        const SizedBox(height: 12),
        SecurityActionPlate(
          icon: const Icon(Icons.file_download_outlined),
          title: 'authEncryptedWalletFileTitle'.tr(),
          description: 'authEncryptedWalletFileDescription'.tr(),
          trailingWidget: _WalletFileExportAction(authBloc: authBloc),
        ),
      ],
    );
  }
}

class _WalletFileExportAction extends StatelessWidget {
  const _WalletFileExportAction({required this.authBloc});
  final AuthBloc authBloc;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 48),
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      icon: const Icon(Icons.file_download_outlined),
      onPressed: () async {
        final expectedWalletId = authBloc.state.currentUser?.walletId;
        if (expectedWalletId == null) return;
        final String? password = await walletPasswordDialog(context);
        if (password == null) return;

        if (!context.mounted ||
            authBloc.state.currentUser?.walletId != expectedWalletId) {
          return;
        }
        try {
          final access = context.read<WalletAccessService?>();
          final authorization = await access?.captureSensitiveExport(
            expectedWalletId,
          );
          if (!context.mounted ||
              authBloc.state.currentUser?.walletId != expectedWalletId) {
            return;
          }
          authorization?.ensureCurrent();
          authBloc.add(
            AuthWalletDownloadRequested(
              password: password,
              expectedWalletId: expectedWalletId,
              ensureAuthorized: authorization?.ensureCurrent,
              selectDestination: authorization?.selectDestination,
            ),
          );
        } on Object {
          // Locking, leaving or switching revokes this export request.
        }
      },
      label: Text(
        LocaleKeys.seedPhraseSettingControlsDownloadSeed.tr(),
        textAlign: TextAlign.center,
      ),
    );
  }
}

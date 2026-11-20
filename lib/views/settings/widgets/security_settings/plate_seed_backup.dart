import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_event.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_feedback.dart';
import 'package:web_dex/views/common/wallet_password_dialog/wallet_password_dialog.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_action_plate.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_section_card.dart';

/// What the wallet knows about its recovery phrase, as the user should read
/// it: a status, how sure it is, and the next step.
({String status, WalletAccessTone tone, String action}) recoveryPhraseStanding(
  RecoveryEvidence evidence,
) => switch (evidence) {
  RecoveryEvidence.phraseConfirmed => (
    status: 'authRecoveryReady'.tr(),
    tone: WalletAccessTone.success,
    action: LocaleKeys.viewSeedPhrase.tr(),
  ),
  RecoveryEvidence.phraseSupplied => (
    status: 'authRecoveryImported'.tr(),
    tone: WalletAccessTone.success,
    action: LocaleKeys.viewSeedPhrase.tr(),
  ),
  // Marked as backed up before confirmation existed: likely true, never
  // checked.
  RecoveryEvidence.legacyUnknown => (
    status: 'authRecoveryLegacyUnconfirmed'.tr(),
    tone: WalletAccessTone.warning,
    action: 'authConfirmRecoveryPhrase'.tr(),
  ),
  // A file needs its password to restore; it does not show the user holds
  // the words.
  RecoveryEvidence.encryptedFileExported => (
    status: 'authRecoveryFileOnly'.tr(),
    tone: WalletAccessTone.warning,
    action: 'authConfirmRecoveryPhrase'.tr(),
  ),
  // Short enough for the section's button; its title names the phrase.
  RecoveryEvidence.none => (
    status: 'authRecoveryNotBackedUp'.tr(),
    tone: WalletAccessTone.warning,
    action: LocaleKeys.seedBackupGateBackUpNow.tr(),
  ),
};

class PlateSeedBackup extends StatelessWidget {
  const PlateSeedBackup({required this.onViewSeedPressed});
  final Function(BuildContext context) onViewSeedPressed;

  @override
  Widget build(BuildContext context) => BlocBuilder<AuthBloc, AuthBlocState>(
    builder: (context, auth) {
      final config = auth.currentUser?.wallet.config;
      final standing = recoveryPhraseStanding(
        config?.recoveryEvidence ?? RecoveryEvidence.none,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SecurityActionPlate(
            icon: const Icon(Icons.shield_outlined),
            title: 'authRecoveryPhraseTitle'.tr(),
            description: 'authRecoveryPhraseDescription'.tr(),
            status: WalletAccessNotice(
              key: const Key('recovery-phrase-status'),
              text: standing.status,
              tone: standing.tone,
              announce: false,
            ),
            showWarningIndicator: !(config?.hasRecoveryPhrase ?? false),
            actionText: standing.action,
            onActionPressed: () => onViewSeedPressed(context),
          ),
          const SizedBox(height: 12),
          _EncryptedFilePlate(
            key: ValueKey(auth.currentUser?.walletId),
            walletId: auth.currentUser?.walletId,
          ),
        ],
      );
    },
  );
}

/// The encrypted wallet file, offered only when the user could open it again.
class _EncryptedFilePlate extends StatefulWidget {
  const _EncryptedFilePlate({required this.walletId, super.key});

  final WalletId? walletId;

  @override
  State<_EncryptedFilePlate> createState() => _EncryptedFilePlateState();
}

class _EncryptedFilePlateState extends State<_EncryptedFilePlate> {
  /// Whether the file would be locked with a password the user has no way
  /// to know: one created for them that no password manager took. Null until
  /// read.
  bool? _generatedPassword;

  @override
  void initState() {
    super.initState();
    _readPasswordOrigin();
  }

  Future<void> _readPasswordOrigin() async {
    final access = context.read<WalletAccessService?>();
    final id = widget.walletId;
    var generated = false;
    if (access != null && id != null) {
      try {
        final status = await access.status(walletId: id);
        generated =
            status.generatedPassword &&
            status.passwordManager != PasswordManagerOutcome.accepted;
      } on Object {
        // Unknown is treated as a password the user chose: the file stays
        // available and its description still says what restoring needs.
      }
    }
    if (mounted) setState(() => _generatedPassword = generated);
  }

  @override
  Widget build(BuildContext context) {
    final generated = _generatedPassword;
    final security = context.read<SecuritySettingsBloc?>();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = SecurityActionPlate.isWide(context, constraints)
            ? SecurityActionPlate.actionWidth
            : double.infinity;
        return SecurityActionPlate(
          icon: const Icon(Icons.file_download_outlined),
          title: 'authEncryptedWalletFileTitle'.tr(),
          description: 'authEncryptedWalletFileDescription'.tr(),
          status: generated == true
              ? WalletAccessNotice(
                  key: const Key('wallet-file-needs-password'),
                  text: 'authEncryptedWalletFileNeedsPassword'.tr(),
                  announce: false,
                )
              : null,
          // A file locked with a password the user has never seen could not
          // be restored by them, so the way forward is a password they know.
          trailingWidget: generated == true
              ? SecuritySecondaryButton(
                  key: const Key('wallet-file-set-password'),
                  width: width,
                  text: 'authSetWalletPassword'.tr(),
                  onPressed: security == null
                      ? null
                      : () => security.add(const PasswordUpdateEvent()),
                )
              : SecuritySecondaryButton(
                  key: const Key('wallet-file-download'),
                  width: width,
                  icon: const Icon(Icons.file_download_outlined),
                  text: LocaleKeys.seedPhraseSettingControlsDownloadSeed.tr(),
                  onPressed: generated == null ? null : _download,
                ),
        );
      },
    );
  }

  Future<void> _download() async {
    final authBloc = context.read<AuthBloc>();
    final expectedWalletId = authBloc.state.currentUser?.walletId;
    if (expectedWalletId == null) return;
    final String? password = await walletPasswordDialog(context);
    if (password == null) return;

    if (!mounted || authBloc.state.currentUser?.walletId != expectedWalletId) {
      return;
    }
    try {
      final access = context.read<WalletAccessService?>();
      final authorization = await access?.captureSensitiveExport(
        expectedWalletId,
      );
      if (!mounted ||
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
  }
}

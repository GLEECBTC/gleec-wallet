import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/wallet_move/wallet_move_types.dart';
import 'package:web_dex/services/wallet_transfer/wallet_transfer_config.dart';
import 'package:web_dex/services/wallet_transfer/wallet_transfer_secret.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_action_plate.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_section_card.dart';
import 'package:web_dex/views/wallet_backup/passkey_backup_section.dart';
import 'package:web_dex/views/wallet_move/transfer_qr_code.dart';
import 'package:web_dex/views/wallet_move/wallet_move_send.dart';

/// The Security settings sections for moving and backing up the open
/// wallet. Each takes its own space only when it is shown.
class WalletTransferSettings extends StatelessWidget {
  const WalletTransferSettings({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [WalletMoveSettingsSection(), PasskeyBackupSection()],
  );
}

/// "Move to another phone", for a wallet with a seed of its own on a phone
/// with the feature on.
class WalletMoveSettingsSection extends StatelessWidget {
  const WalletMoveSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final enabled =
        walletMoveSupportedHere &&
        (context.read<WalletTransferConfig?>()?.moveEnabled ?? false) &&
        context.read<WalletMoveProtocol?>() != null;
    if (!enabled) return const SizedBox.shrink();
    return BlocBuilder<AuthBloc, AuthBlocState>(
      buildWhen: (previous, current) =>
          previous.currentUser?.walletId != current.currentUser?.walletId,
      builder: (context, auth) {
        final type = auth.currentUser?.wallet.config.type;
        if (type == null || TransferWalletType.fromWalletType(type) == null) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: LayoutBuilder(
            builder: (context, constraints) => SecurityActionPlate(
              key: const Key('wallet-move-settings-section'),
              icon: const Icon(Icons.mobile_screen_share_outlined),
              title: 'walletMoveSettingsTitle'.tr(),
              description: 'walletMoveSettingsDescription'.tr(),
              trailingWidget: SecuritySecondaryButton(
                key: const Key('wallet-move-settings-start'),
                width: SecurityActionPlate.isWide(context, constraints)
                    ? SecurityActionPlate.actionWidth
                    : double.infinity,
                text: 'walletMoveSettingsAction'.tr(),
                onPressed: () => openWalletMoveSend(context),
              ),
            ),
          ),
        );
      },
    );
  }
}

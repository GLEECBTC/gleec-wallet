import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/services/wallet_backup/passkey_backup_types.dart';
import 'package:web_dex/services/wallet_move/wallet_move_types.dart';
import 'package:web_dex/services/wallet_transfer/wallet_transfer_config.dart';
import 'package:web_dex/views/common/wallet_access/wallet_passkey_icon.dart';
import 'package:web_dex/views/wallet_move/transfer_qr_code.dart';
import 'package:web_dex/views/wallet_move/transfer_widgets.dart';

/// The ways in that need no typing, under the phrase and file imports. A row
/// appears only where its feature is on and can work on this device.
class WalletTransferImportOptions extends StatefulWidget {
  const WalletTransferImportOptions({
    this.onMoveFromDevice,
    this.onRestoreFromPasskey,
    super.key,
  });

  final VoidCallback? onMoveFromDevice;
  final VoidCallback? onRestoreFromPasskey;

  @override
  State<WalletTransferImportOptions> createState() =>
      _WalletTransferImportOptionsState();
}

class _WalletTransferImportOptionsState
    extends State<WalletTransferImportOptions> {
  bool _canRestore = false;

  @override
  void initState() {
    super.initState();
    final controller = context.read<PasskeyBackupController?>();
    if (controller == null || widget.onRestoreFromPasskey == null) return;
    controller
        .availability()
        .then((availability) {
          if (mounted && availability.canRestore) {
            setState(() => _canRestore = true);
          }
        })
        // Without an answer the row stays hidden; the phrase still works.
        .catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final canMove =
        widget.onMoveFromDevice != null &&
        walletMoveSupportedHere &&
        (context.read<WalletTransferConfig?>()?.moveEnabled ?? false) &&
        context.read<WalletMoveProtocol?>() != null;
    if (!canMove && !_canRestore) return const SizedBox.shrink();
    final cardColor = Theme.of(context).cardColor;
    return TransferOpaqueText(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (canMove) ...[
            const SizedBox(height: 12),
            Semantics(
              button: true,
              child: UiListActionRow(
                rowKey: const Key('wallet-move-import-option'),
                title: 'walletMoveImportOption'.tr(),
                subtitle: 'walletMoveImportOptionHint'.tr(),
                leading: const Icon(Icons.qr_code_scanner, size: 24),
                backgroundColor: cardColor,
                onTap: widget.onMoveFromDevice,
              ),
            ),
          ],
          if (_canRestore) ...[
            const SizedBox(height: 12),
            Semantics(
              button: true,
              child: UiListActionRow(
                rowKey: const Key('passkey-backup-import-option'),
                title: 'passkeyBackupRestoreOption'.tr(),
                subtitle: 'passkeyBackupRestoreOptionHint'.tr(),
                leading: const WalletPasskeyIcon(),
                backgroundColor: cardColor,
                onTap: widget.onRestoreFromPasskey,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

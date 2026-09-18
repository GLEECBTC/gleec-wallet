import 'package:flutter/widgets.dart';
import 'package:web_dex/shared/seed_backup/seed_backup_policy.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/common/seed_backup_gate/seed_backup_gate.dart';

/// Copies a receive address, warning about backup first if the wallet needs it.
///
/// Exists because a gate that covers only the QR dialog is defeated in one tap:
/// the copy icon two pixels away hands over the same fundable address. Use this
/// wherever an address the user could be paid at is copied.
///
/// Do **not** use it for addresses that reveal nothing new - transaction
/// history, contract addresses - where blocking the copy is pure friction.
Future<void> gatedCopyAddress(
  BuildContext context,
  String address, {
  String? successMessage,
  bool isTestCoin = false,
}) async {
  final mayCopy = await ensureSeedBackedUp(
    context,
    reason: SeedBackupGateReason.copyAddress,
    isTestCoin: isTestCoin,
  );
  if (!mayCopy || !context.mounted) return;
  copyToClipBoard(context, address, successMessage);
}

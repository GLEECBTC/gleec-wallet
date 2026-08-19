import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/common/seed_backup_gate/gated_copy_address.dart';

class AddressCopyButton extends StatelessWidget {
  final String address;
  final String coinAbbr;

  /// Whether copying this address should first warn an un-backed-up wallet.
  ///
  /// Opt-in rather than default-on because this widget is shared with
  /// transaction history, where the address has already received funds and
  /// blocking the copy protects nothing. Set it true wherever the address is a
  /// *receive* target the user could still be paid at.
  final bool gateOnSeedBackup;

  /// Testnet addresses are never gated; see `seedBackupGateRequired`.
  final bool isTestCoin;

  const AddressCopyButton({
    super.key,
    required this.address,
    this.coinAbbr = '',
    this.gateOnSeedBackup = false,
    this.isTestCoin = false,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      splashRadius: 18,
      icon: const Icon(Icons.copy, size: 16),
      color: Theme.of(context).textTheme.bodyMedium!.color,
      tooltip: coinAbbr.isEmpty
          ? LocaleKeys.clipBoard.tr()
          : LocaleKeys.copyAddressToClipboard.tr(args: [coinAbbr]),
      onPressed: () {
        final successMessage = coinAbbr.isNotEmpty
            ? LocaleKeys.copiedAddressToClipboard.tr(args: [coinAbbr])
            : null;
        if (!gateOnSeedBackup) {
          copyToClipBoard(context, address, successMessage);
          return;
        }
        gatedCopyAddress(
          context,
          address,
          isTestCoin: isTestCoin,
          successMessage: successMessage,
        );
      },
    );
  }
}

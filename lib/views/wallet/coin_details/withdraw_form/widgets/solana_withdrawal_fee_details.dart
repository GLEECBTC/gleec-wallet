import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// The fee and account-creation deposit are denominated in the SOL platform,
/// even when the recipient receives an SPL token.
class SolanaWithdrawalFeeDetails extends StatelessWidget {
  const SolanaWithdrawalFeeDetails({required this.fee, super.key});

  final SolanaFeeInfo fee;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(String label, Decimal amount) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 16,
        runSpacing: 4,
        children: [Text(label), SelectableText('$amount ${fee.coin}')],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row('withdrawSolanaNetworkFee'.tr(), fee.feeAmount),
        row('withdrawSolanaAccountDeposit'.tr(), fee.rentAmount),
        if (fee.rentAmount > Decimal.zero)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'withdrawSolanaAccountDepositDescription'.tr(),
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

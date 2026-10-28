import 'package:decimal/decimal.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Recipient principal from a signed withdrawal, independent of wallet debit.
/// EVM/TRON encode the transferred value in totalAmount. UTXO totalAmount is
/// the consumed inputs, so change and the same-asset fee must be excluded.
/// For a Max self-transfer, all inputs less the fee return to the recipient.
Decimal withdrawalRecipientAmount(
  Asset asset,
  BalanceChanges changes,
  FeeInfo fee,
) {
  final protocol = asset.protocol;
  if (protocol is Erc20Protocol ||
      protocol is TrxProtocol ||
      protocol is Trc20Protocol) {
    return changes.totalAmount;
  }
  final sameAssetFee = fee.coin.isEmpty || fee.coin == asset.id.id
      ? fee.totalFee
      : Decimal.zero;
  final netDebit = changes.spentByMe - changes.receivedByMe;
  final principal =
      (netDebit > Decimal.zero ? netDebit : changes.spentByMe) - sameAssetFee;
  return principal > Decimal.zero ? principal : Decimal.zero;
}

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

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

/// Configured token precision, or the engine's native EVM unit scale when
/// its optional config field is absent. Never assume token decimals are 18.
int? withdrawalAmountPrecision(Asset asset) {
  final configured = asset.id.chainId.decimals;
  if (configured != null) return configured;
  final protocol = asset.protocol;
  if (protocol is Erc20Protocol &&
      (protocol.config.valueOrNull<String>('protocol', 'type') ??
              protocol.config.valueOrNull<String>('type')) ==
          'ETH') {
    return 18;
  }
  return null;
}

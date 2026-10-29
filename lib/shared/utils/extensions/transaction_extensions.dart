import 'package:decimal/decimal.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Extension methods for the Transaction class
extension TransactionExtensions on Transaction {
  /// Transfer within this wallet, with no external debit beyond a native fee
  /// (e.g. an EOA→custody consolidation or an HD self-transfer).
  bool get isInternalTransfer {
    final changes = balanceChanges;
    if (changes.receivedByMe <= Decimal.zero ||
        changes.spentByMe < changes.receivedByMe) {
      return false;
    }
    if (changes.netChange == Decimal.zero &&
        changes.spentByMe == changes.receivedByMe) {
      return true;
    }
    final networkFee = fee;
    // A native self-transfer returns the principal to this wallet and loses
    // only its network fee. UTXO change on an external send is not enough.
    return networkFee != null &&
        (networkFee.coin.isEmpty || networkFee.coin == assetId.id) &&
        changes.netChange == -networkFee.totalFee &&
        changes.spentByMe - changes.receivedByMe == networkFee.totalFee;
  }

  /// A gross amount alone does not establish whether this wallet sent it.
  bool get hasKnownMovementDirection =>
      isInternalTransfer ||
      amount != Decimal.zero ||
      balanceChanges.spentByMe != Decimal.zero ||
      balanceChanges.receivedByMe != Decimal.zero;

  /// Signed wallet movement, or the unsigned gross magnitude if direction is
  /// unavailable. Internal moves show principal, with their fee separately.
  Decimal get displayedMovement {
    if (isInternalTransfer) return balanceChanges.receivedByMe;
    if (amount != Decimal.zero) return amount;
    if (balanceChanges.receivedByMe != Decimal.zero ||
        balanceChanges.spentByMe != Decimal.zero) {
      return balanceChanges.receivedByMe - balanceChanges.spentByMe;
    }
    return balanceChanges.totalAmount;
  }

  /// Sanitizes a transaction by removing the sender from the recipient list
  /// and sorting recipients if multiple exist.
  /// [walletAddresses] is used to prioritize wallet addresses in the sorted list.
  /// If the sender is the only recipient, it returns the original transaction.
  /// If the transaction has no recipients, it returns the original transaction.
  ///
  /// Wallet addresses are sorted first in the recipient list, making it easy
  /// to access them using `.first` for UI display purposes.
  Transaction sanitize(Set<String> walletAddresses) {
    if (from.isEmpty) return this;
    final fromAddr = from.first;
    final List<String> sanitizedTo = to.length > 1
        ? (List<String>.from(to)..removeWhere((addr) => addr == fromAddr))
        : List<String>.from(to);

    if (sanitizedTo.length > 1 && walletAddresses.isNotEmpty) {
      sanitizedTo.sort((a, b) {
        final aMine = walletAddresses.contains(a);
        final bMine = walletAddresses.contains(b);
        if (aMine == bMine) return 0;
        return aMine ? -1 : 1;
      });
    }

    return copyWith(to: sanitizedTo);
  }
}

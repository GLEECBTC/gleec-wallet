import 'package:decimal/decimal.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Extension methods for the Transaction class
extension TransactionExtensions on Transaction {
  /// Net-zero transfer where every debit is matched by a credit to the same
  /// wallet (e.g. an EOA→custody consolidation or an HD self-transfer).
  bool get isInternalTransfer =>
      balanceChanges.netChange == Decimal.zero &&
      balanceChanges.spentByMe > Decimal.zero &&
      balanceChanges.spentByMe == balanceChanges.receivedByMe;

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

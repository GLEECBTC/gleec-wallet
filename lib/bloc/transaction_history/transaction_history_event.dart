import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:web_dex/model/coin.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

abstract class TransactionHistoryEvent {
  const TransactionHistoryEvent();
}

class TransactionHistorySubscribe extends TransactionHistoryEvent {
  const TransactionHistorySubscribe({required this.coin});
  final Coin coin;
}

class TransactionHistoryUpdated extends TransactionHistoryEvent {
  const TransactionHistoryUpdated({required this.transactions});
  final List<Transaction>? transactions;
}

class TransactionHistoryStartedLoading extends TransactionHistoryEvent {
  const TransactionHistoryStartedLoading();
}

/// The wallet's own addresses, which arrive after the list does.
///
/// They only affect how recipients are ordered for display, so the list is
/// rendered without them and re-sorted once they resolve. [assetId] guards
/// against a late resolution from a previous subscription landing on the
/// current one.
class TransactionHistoryAddressesUpdated extends TransactionHistoryEvent {
  const TransactionHistoryAddressesUpdated({
    required this.assetId,
    required this.addresses,
  });

  final AssetId assetId;
  final Set<String> addresses;
}

class TransactionHistoryFailure extends TransactionHistoryEvent {
  TransactionHistoryFailure({required this.error});
  final BaseError error;
}

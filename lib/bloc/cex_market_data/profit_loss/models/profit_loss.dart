import 'package:equatable/equatable.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/models/fiat_value.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/extensions/profit_loss_transaction_extension.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Represents a profit/loss for a specific coin.
class ProfitLoss extends Equatable {
  /// The running total profit/loss in the coin for the user calculated from
  /// their transaction history. The last profit/loss in the list is the current
  /// profit/loss.
  final double profitLoss;

  /// The komodo coin abbreviation from the coins repository
  /// (e.g. BTC, KMD, etc.).
  final String coin;

  /// The fiat price of the [coin] at or near the time of the transaction. This
  /// is currently derived from OHLC data from the CEX API.
  final FiatValue fiatPrice;

  /// The internal komodo ID of the transaction. This is kept to reference back
  /// to the transaction.
  final String internalId;

  /// The net change in the coin balance as a result of the transaction.
  final double myBalanceChange;

  /// The fiat price of the coin amount received in the transaction. This is
  /// the amount received multiplied by the fiat price of the coin at or near
  /// the time of the transaction.
  final double receivedAmountFiatPrice;

  /// The fiat price of the coin amount spent in the transaction. This is
  /// the amount spent multiplied by the fiat price of the coin at or near
  /// the time of the transaction.
  final double spentAmountFiatPrice;

  /// The timestamp of the transaction in seconds since epoch.
  final DateTime timestamp;

  /// The total amount of the coin transferred in the transaction.
  final double totalAmount;

  /// The transaction hash. This is kept to reference back to the transaction.
  final String txHash;

  /// Creates a new [ProfitLoss] instance.
  const ProfitLoss({
    required this.profitLoss,
    required this.coin,
    required this.fiatPrice,
    required this.internalId,
    required this.myBalanceChange,
    required this.receivedAmountFiatPrice,
    required this.spentAmountFiatPrice,
    required this.timestamp,
    required this.totalAmount,
    required this.txHash,
  });

  factory ProfitLoss.fromJson(Map<String, dynamic> json) {
    return ProfitLoss(
      profitLoss: (json['profit_loss'] as num?)?.toDouble() ?? 0.0,
      coin: json['coin'] ?? '',
      fiatPrice: FiatValue.fromJson(json['fiat_value'] as Map<String, dynamic>),
      internalId: json['internal_id'] as String,
      myBalanceChange: (json['my_balance_change'] as num).toDouble(),
      receivedAmountFiatPrice: (json['received_by_me'] as num).toDouble(),
      spentAmountFiatPrice: (json['spent_by_me'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp']),
      totalAmount: (json['total_amount'] as num).toDouble(),
      txHash: json['tx_hash'] as String,
    );
  }

  factory ProfitLoss.fromTransaction(
    Transaction transaction,
    FiatValue fiatPrice,
    double runningProfitLoss,
  ) {
    return ProfitLoss(
      profitLoss: runningProfitLoss,
      coin: transaction.assetId.id,
      fiatPrice: fiatPrice,
      internalId: transaction.internalId,
      myBalanceChange: transaction.amount.toDouble(),
      receivedAmountFiatPrice: transaction.amountReceived * fiatPrice.value,
      spentAmountFiatPrice: transaction.amountSpent * fiatPrice.value,
      totalAmount: transaction.totalAmountAsDouble,
      timestamp: transaction.timestamp,
      txHash: transaction.txHash ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'profit_loss': profitLoss,
      'coin': coin,
      'fiat_value': fiatPrice.toJson(),
      'internal_id': internalId,
      'my_balance_change': myBalanceChange,
      'received_by_me': receivedAmountFiatPrice,
      'spent_by_me': spentAmountFiatPrice,
      'timestamp': timestamp,
      'total_amount': totalAmount,
      'tx_hash': txHash,
    };
  }

  ProfitLoss copyWith({
    double? profitLoss,
    String? coin,
    FiatValue? fiatPrice,
    String? internalId,
    double? myBalanceChange,
    double? receivedByMe,
    double? spentByMe,
    DateTime? timestamp,
    double? totalAmount,
    String? txHash,
  }) {
    return ProfitLoss(
      profitLoss: profitLoss ?? this.profitLoss,
      coin: coin ?? this.coin,
      fiatPrice: fiatPrice ?? this.fiatPrice,
      internalId: internalId ?? this.internalId,
      myBalanceChange: myBalanceChange ?? this.myBalanceChange,
      receivedAmountFiatPrice: receivedByMe ?? receivedAmountFiatPrice,
      spentAmountFiatPrice: spentByMe ?? spentAmountFiatPrice,
      timestamp: timestamp ?? this.timestamp,
      totalAmount: totalAmount ?? this.totalAmount,
      txHash: txHash ?? this.txHash,
    );
  }

  @override
  List<Object?> get props => [
    profitLoss,
    coin,
    fiatPrice,
    internalId,
    myBalanceChange,
    receivedAmountFiatPrice,
    spentAmountFiatPrice,
    timestamp,
    totalAmount,
    txHash,
  ];
}

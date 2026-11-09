import 'package:rational/rational.dart';
import 'package:web_dex/shared/utils/utils.dart';

class TradePreimageExtendedFeeInfo {
  TradePreimageExtendedFeeInfo({
    required this.coin,
    required this.amount,
    required this.amountRational,
    required this.paidFromTradingVol,
    this.requiredBalance,
  });
  factory TradePreimageExtendedFeeInfo.fromJson(Map<String, dynamic> json) =>
      TradePreimageExtendedFeeInfo(
        coin: json['coin'],
        amount: json['amount'],
        amountRational: fract2rat(json['amount_fraction']) ?? Rational.zero,
        paidFromTradingVol: json['paid_from_trading_vol'] ?? false,
        requiredBalance: json['required_balance'] == null
            ? null
            : Rational.parse(json['required_balance'] as String),
      );

  final String coin;
  final String amount;
  final Rational amountRational;
  final bool paidFromTradingVol;

  /// Conservative fees required before trading, excluding trade principal.
  final Rational? requiredBalance;
}

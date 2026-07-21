import 'package:rational/rational.dart';
import 'package:web_dex/shared/utils/utils.dart';

class TradePreimageExtendedFeeInfo {
  TradePreimageExtendedFeeInfo({
    required this.coin,
    required this.amount,
    required this.amountRational,
    required this.paidFromTradingVol,
  });
  factory TradePreimageExtendedFeeInfo.fromJson(Map<String, dynamic> json) {
    final coin = json['coin'];
    final amount = json['amount'];
    final paidFromTradingVol = json['paid_from_trading_vol'];
    if (coin is! String ||
        coin.isEmpty ||
        coin.length > 64 ||
        coin.trim() != coin ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(coin) ||
        amount is! String ||
        amount.isEmpty ||
        amount.length > 128 ||
        amount.trim() != amount ||
        !RegExp(r'^[0-9]+(?:\.[0-9]+)?$').hasMatch(amount) ||
        (paidFromTradingVol != null && paidFromTradingVol is! bool)) {
      throw const FormatException('Invalid trade fee');
    }
    final fraction = _stringMap(json['amount_fraction']);
    final amountRational = fract2rat(fraction, false);
    final decimalAmount = Rational.tryParse(amount);
    if (amountRational == null ||
        amountRational < Rational.zero ||
        decimalAmount == null ||
        !_decimalRepresentsRational(amount, decimalAmount, amountRational)) {
      throw const FormatException('Invalid trade fee amount');
    }
    return TradePreimageExtendedFeeInfo(
      coin: coin,
      amount: amount,
      amountRational: amountRational,
      paidFromTradingVol: paidFromTradingVol as bool? ?? false,
    );
  }

  final String coin;
  final String amount;
  final Rational amountRational;
  final bool paidFromTradingVol;
}

Map<String, dynamic> _stringMap(Object? value) {
  if (value is! Map) throw const FormatException('Invalid trade fee fraction');
  try {
    return Map<String, dynamic>.from(value);
  } catch (_) {
    throw const FormatException('Invalid trade fee fraction');
  }
}

bool _decimalRepresentsRational(
  String source,
  Rational decimal,
  Rational exact,
) {
  if (decimal == exact) return true;
  final separator = source.indexOf('.');
  final fractionalDigits = separator < 0 ? 0 : source.length - separator - 1;
  if (fractionalDigits < 16) return false;
  final finalDecimalUnit = Rational(
    BigInt.one,
    BigInt.from(10).pow(fractionalDigits),
  );
  return (decimal - exact).abs() < finalDecimalUnit;
}

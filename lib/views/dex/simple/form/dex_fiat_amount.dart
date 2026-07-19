import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/shared/utils/formatters.dart';

class DexFiatAmount extends StatelessWidget {
  const DexFiatAmount({
    super.key,
    required this.coin,
    required this.amount,
    this.padding,
    this.textStyle,
  });

  final Coin? coin;
  final Rational? amount;
  final EdgeInsets? padding;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final Rational estAmount = amount ?? Rational.zero;
    final double usdPrice = coin?.usdPrice?.price?.toDouble() ?? 0.0;

    final double fiatAmount = estAmount.toDouble() * usdPrice;
    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: Text(
        '~ \$${formatAmt(fiatAmount)}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: Theme.of(context).calmCoreCompatibility.fiatAmountColor,
        ).merge(textStyle),
      ),
    );
  }
}

import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';

class OrderbookTableTitle extends StatelessWidget {
  const OrderbookTableTitle(
    this.title, {
    this.suffix,
    this.titleTextSize = 11,
    this.hidden = false,
  });
  final String title;
  final String? suffix;
  final bool hidden;
  final double titleTextSize;

  @override
  Widget build(BuildContext context) {
    final colors = GleecColorTokens.of(context);
    final typography = GleecTypography.of(context);
    final titleStyle = typography.labelMedium.copyWith(
      fontSize: titleTextSize,
      color: colors.textSecondary,
    );
    final coinStyle = typography.labelSmall.copyWith(
      fontSize: 10,
      color: colors.brand,
    );

    final coin = suffix;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(title, style: titleStyle),
        if (coin != null) const SizedBox(width: 3),
        if (coin != null) Text(coin, style: coinStyle),
      ],
    );
  }
}

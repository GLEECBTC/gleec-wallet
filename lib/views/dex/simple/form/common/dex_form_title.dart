import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';

class DexFormTitle extends StatelessWidget {
  const DexFormTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = GleecColorTokens.of(context);
    final typography = GleecTypography.of(context);
    final titleStyle = typography.labelMedium.copyWith(
      color: colors.textSecondary,
      letterSpacing: 0.4,
    );

    return Text(title, style: titleStyle, maxLines: 2);
  }
}

import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';

class DexSmallButton extends StatelessWidget {
  const DexSmallButton(this.text, this.onTap);

  final String text;
  final Function(BuildContext)? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = GleecColorTokens.of(context);
    final geometry = GleecGeometry.of(context);
    final typography = GleecTypography.of(context);
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: SizedBox.square(
        dimension: geometry.minimumTapTarget,
        child: Material(
          color: colors.selected,
          borderRadius: geometry.borderRadius12,
          child: InkWell(
            onTap: onTap == null ? null : () => onTap!(context),
            borderRadius: geometry.borderRadius12,
            child: Center(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: typography.labelMedium.copyWith(color: colors.brand),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

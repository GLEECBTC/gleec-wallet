import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';

class DexTextButton extends StatelessWidget {
  const DexTextButton({
    Key? key,
    required this.text,
    required this.isActive,
    this.onTap,
  }) : super(key: key);

  final String text;
  final bool isActive;
  final GestureTapCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = GleecColorTokens.of(context);
    final geometry = GleecGeometry.of(context);
    final typography = GleecTypography.of(context);
    return Semantics(
      button: true,
      selected: isActive,
      child: InkWell(
        onTap: onTap,
        borderRadius: geometry.borderRadius12,
        child: Container(
          constraints: BoxConstraints(
            minHeight: geometry.minimumTapTarget,
            minWidth: geometry.minimumTapTarget,
          ),
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: geometry.space16),
          decoration: BoxDecoration(
            color: isActive ? colors.selected : colors.surfaceHigh,
            borderRadius: geometry.borderRadius12,
            border: Border.all(color: isActive ? colors.brand : colors.border),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: typography.labelLarge.copyWith(
              color: isActive ? colors.brandHover : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

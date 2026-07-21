import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';

class FormPlate extends StatelessWidget {
  const FormPlate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = GleecColorTokens.of(context);
    final geometry = GleecGeometry.of(context);

    return Container(
      constraints: BoxConstraints(
        maxWidth: Theme.of(context).calmCoreCompatibility.dexFormWidth,
      ),
      padding: EdgeInsets.symmetric(horizontal: geometry.space16),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        border: Border.all(color: colors.border),
        borderRadius: geometry.borderRadius24,
        boxShadow: geometry.surfaceShadow(colors),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

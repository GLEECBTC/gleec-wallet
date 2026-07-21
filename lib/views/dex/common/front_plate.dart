import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';

class FrontPlate extends StatelessWidget {
  const FrontPlate({required this.child, this.shadowEnabled = false});

  final Widget child;
  final bool shadowEnabled;

  @override
  Widget build(BuildContext context) {
    final colors = GleecColorTokens.of(context);
    final geometry = GleecGeometry.of(context);
    final borderRadius = geometry.borderRadius20;
    final shadow = BoxShadow(
      color: colors.shadow,
      spreadRadius: 0,
      blurRadius: 24,
      offset: const Offset(0, 8),
    );
    return Container(
      constraints: BoxConstraints(
        minHeight: geometry.minimumTapTarget,
        minWidth: geometry.minimumTapTarget,
      ),
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surfaceHigh,
        border: Border.all(color: colors.border),
        borderRadius: borderRadius,
        boxShadow: shadowEnabled ? [shadow] : null,
      ),
      child: ClipRRect(borderRadius: borderRadius, child: child),
    );
  }
}

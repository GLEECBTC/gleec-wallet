import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';

class UiSimpleButton extends StatelessWidget {
  const UiSimpleButton({
    required this.child,
    this.disabled = false,
    this.onPressed,
    this.borderRadius = 8,
    super.key,
  });

  final Widget child;
  final bool disabled;
  final double borderRadius;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final materialTheme = Theme.of(context);
    final colors = materialTheme.extension<GleecColorTokens>();
    final geometry =
        materialTheme.extension<GleecGeometry>() ?? GleecGeometry.standard;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(
          borderRadius == 8 ? geometry.radius12 : borderRadius,
        ),
        onTap: disabled ? null : onPressed,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: geometry.minimumTapTarget,
            minHeight: geometry.minimumTapTarget,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: disabled
                  ? Colors.transparent
                  : colors?.selected ??
                        materialTheme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(
                borderRadius == 8 ? geometry.radius12 : borderRadius,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

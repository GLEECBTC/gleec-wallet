import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';

/// A reusable gradient button widget with customizable gradient, border radius,
/// and child content. Automatically applies white color to Icon widgets that
/// don't have a color specified.
class UiGradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final Gradient? gradient;
  final bool isMini;

  const UiGradientButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.padding,
    this.borderRadius = 16,
    this.gradient,
    this.isMini = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveGradient =
        gradient ?? Theme.of(context).calmCoreCompatibility.defaultSwitchColor;

    // Apply default white color to Icon widgets that don't have a color specified
    Widget effectiveChild = child;
    if (child is Icon && (child as Icon).color == null) {
      effectiveChild = Icon(
        (child as Icon).icon,
        color: Colors.white,
        size: (child as Icon).size,
        semanticLabel: (child as Icon).semanticLabel,
        textDirection: (child as Icon).textDirection,
      );
    }

    final double size = isMini ? 48.0 : 56.0;

    return LimitedBox(
      maxWidth: size,
      maxHeight: size,
      child: Container(
        decoration: BoxDecoration(
          gradient: effectiveGradient,
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: InkWell(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          onTap: onPressed,
          borderRadius: BorderRadius.circular(borderRadius),
          child: Padding(
            padding: padding ?? EdgeInsets.zero,
            child: Center(child: effectiveChild),
          ),
        ),
      ),
    );
  }
}

import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';

class UIBaseButton extends StatelessWidget {
  const UIBaseButton({
    required this.isEnabled,
    required this.child,
    required this.width,
    required this.height,
    required this.border,
    super.key,
  });
  final bool isEnabled;
  final double width;
  final double height;
  final BoxBorder? border;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final geometry =
        Theme.of(context).extension<GleecGeometry>() ?? GleecGeometry.standard;
    final effectiveHeight = height < geometry.minimumTapTarget
        ? geometry.minimumTapTarget
        : height;
    final effectiveWidth = width.isFinite && width < geometry.minimumTapTarget
        ? geometry.minimumTapTarget
        : width;

    return Semantics(
      button: true,
      enabled: isEnabled,
      child: IgnorePointer(
        ignoring: !isEnabled,
        child: Opacity(
          opacity: isEnabled ? 1 : 0.5,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: effectiveWidth.isFinite ? effectiveWidth : 0,
              maxWidth: effectiveWidth,
              minHeight: effectiveHeight,
            ),
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: geometry.borderRadius16,
                border: border,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

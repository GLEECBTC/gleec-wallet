import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/src/design_system/app_palette.dart';

/// Shapes for content drawn on [AppPalette] surfaces.
abstract final class AppSurface {
  /// The corner radius of a card or a group of rows, as on the wallet home.
  static const radius = 20.0;

  /// A card: a surface with a hairline border, which keeps it apart from the
  /// canvas in the dark theme, where the two are close.
  static BoxDecoration card(
    AppPalette palette, {
    double radius = AppSurface.radius,
    Color? color,
  }) => BoxDecoration(
    color: color ?? palette.surface,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: palette.border),
  );

  /// [card] as a shape, for a [Card] or a [Material].
  static RoundedRectangleBorder cardShape(
    AppPalette palette, {
    double radius = AppSurface.radius,
  }) => RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(radius),
    side: BorderSide(color: palette.border),
  );
}

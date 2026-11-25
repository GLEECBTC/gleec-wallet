import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/src/design_system/app_palette.dart';
import 'package:komodo_ui_kit/src/design_system/app_palette_theme.dart';

/// Draws [child] on [AppPalette]: below it the Material theme's surfaces,
/// text, controls and dialogs map onto the palette ([AppPaletteTheme]), so a
/// screen whose widgets still read `Theme.of` matches the screens built on
/// the palette directly. Dialogs and sheets opened from inside keep it,
/// because `showDialog` and `showModalBottomSheet` carry the theme across.
class AppPaletteScope extends StatelessWidget {
  const AppPaletteScope({
    required this.child,
    this.paintCanvas = true,
    super.key,
  });

  final Widget child;

  /// Whether to paint the palette's canvas behind [child]. Painted on a
  /// [Material], so presses on the canvas show and plain text takes the
  /// palette's colour.
  final bool paintCanvas;

  /// The palette when [context] is inside a scope, and null outside one.
  ///
  /// Shared widgets whose defaults come from the older global theme use it
  /// to draw on the palette inside palette screens while keeping their look
  /// everywhere else.
  static AppPalette? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PaletteMarker>()?.palette;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final palette = base.brightness == Brightness.light
        ? AppPalette.light
        : AppPalette.dark;
    final data = AppPaletteTheme.of(base, palette);
    return _PaletteMarker(
      palette: palette,
      child: Theme(
        data: data,
        child: paintCanvas
            ? Material(color: palette.canvas, child: child)
            : DefaultTextStyle.merge(
                style: TextStyle(color: palette.text),
                child: child,
              ),
      ),
    );
  }
}

/// An [InheritedTheme], so dialogs and sheets opened inside a scope carry it
/// across to their own route as they do the Material theme.
class _PaletteMarker extends InheritedTheme {
  const _PaletteMarker({required this.palette, required super.child});

  final AppPalette palette;

  @override
  Widget wrap(BuildContext context, Widget child) =>
      _PaletteMarker(palette: palette, child: child);

  @override
  bool updateShouldNotify(_PaletteMarker oldWidget) =>
      !identical(palette, oldWidget.palette);
}

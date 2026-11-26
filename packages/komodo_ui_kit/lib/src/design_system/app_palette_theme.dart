import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/src/design_system/app_palette.dart';
import 'package:komodo_ui_kit/src/design_system/app_surface.dart';

/// Material roles mapped onto [AppPalette], for screens whose widgets read
/// `Theme.of` rather than the palette. `AppPaletteScope` applies it.
///
/// Sizes, fonts, motion and theme extensions come from the base theme; only
/// colours and surface shapes change.
abstract final class AppPaletteTheme {
  static final _light = Expando<ThemeData>('AppPaletteTheme.light');
  static final _dark = Expando<ThemeData>('AppPaletteTheme.dark');

  /// [base] drawn in [palette].
  static ThemeData of(ThemeData base, AppPalette palette) {
    final cache = identical(palette, AppPalette.light) ? _light : _dark;
    return cache[base] ??= _build(base, palette);
  }

  static ThemeData _build(ThemeData base, AppPalette palette) {
    final card = AppSurface.cardShape(palette);
    return base.copyWith(
      colorScheme: _colorScheme(base.colorScheme, palette),
      textTheme: _textTheme(base.textTheme, palette),
      primaryColor: palette.brand,
      scaffoldBackgroundColor: palette.canvas,
      // A plain Material is a surface's ink layer, so it matches the cards.
      canvasColor: palette.surface,
      cardColor: palette.surface,
      dividerColor: palette.border,
      hintColor: palette.textTertiary,
      disabledColor: palette.onDisabled,
      unselectedWidgetColor: palette.controlBorder,
      shadowColor: palette.shadow,
      iconTheme: base.iconTheme.copyWith(color: palette.brand),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: palette.canvas,
        foregroundColor: palette.text,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: base.cardTheme.copyWith(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: palette.shadow,
        shape: card,
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: palette.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: card,
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: palette.surfaceRaised,
        modalBackgroundColor: palette.surfaceRaised,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: base.popupMenuTheme.copyWith(
        color: palette.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: AppSurface.cardShape(palette, radius: 12),
      ),
      dividerTheme: base.dividerTheme.copyWith(color: palette.border),
      tabBarTheme: base.tabBarTheme.copyWith(
        labelColor: palette.text,
        unselectedLabelColor: palette.textTertiary,
        indicatorColor: palette.brand,
        dividerColor: palette.border,
      ),
      listTileTheme: base.listTileTheme.copyWith(
        iconColor: palette.textSecondary,
      ),
      expansionTileTheme: base.expansionTileTheme.copyWith(
        iconColor: palette.textSecondary,
        collapsedIconColor: palette.textSecondary,
        textColor: palette.text,
        collapsedTextColor: palette.text,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: palette.surfaceHigh,
        side: BorderSide(color: palette.border),
        // A chip takes its whole label style from the theme once one is set.
        labelStyle: (base.chipTheme.labelStyle ?? base.textTheme.bodyLarge)
            ?.copyWith(color: palette.text),
      ),
      progressIndicatorTheme: base.progressIndicatorTheme.copyWith(
        color: palette.brand,
        linearTrackColor: palette.surfaceHighest,
      ),
      inputDecorationTheme: _inputs(base.inputDecorationTheme, palette),
      switchTheme: _switches(base.switchTheme, palette),
      checkboxTheme: base.checkboxTheme.copyWith(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? (states.contains(WidgetState.disabled)
                    ? palette.onDisabled
                    : palette.brand)
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(palette.onBrand),
        side: BorderSide(color: palette.controlBorder, width: 2),
      ),
      radioTheme: base.radioTheme.copyWith(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.brand
              : palette.controlBorder,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.brandHover,
          disabledForegroundColor: palette.onDisabled,
        ).merge(base.textButtonTheme.style),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.text,
          disabledForegroundColor: palette.onDisabled,
          side: BorderSide(color: palette.borderStrong),
        ).merge(base.outlinedButtonTheme.style),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.brand,
          foregroundColor: palette.onBrand,
          disabledBackgroundColor: palette.disabled,
          disabledForegroundColor: palette.onDisabled,
        ).merge(base.elevatedButtonTheme.style),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.brand,
          foregroundColor: palette.onBrand,
          disabledBackgroundColor: palette.disabled,
          disabledForegroundColor: palette.onDisabled,
        ).merge(base.filledButtonTheme.style),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: palette.surface,
          foregroundColor: palette.textSecondary,
          selectedBackgroundColor: palette.brand,
          selectedForegroundColor: palette.onBrand,
          side: BorderSide(color: palette.border),
        ).merge(base.segmentedButtonTheme.style),
      ),
    );
  }

  static ColorScheme _colorScheme(ColorScheme base, AppPalette palette) =>
      base.copyWith(
        primary: palette.brand,
        onPrimary: palette.onBrand,
        primaryContainer: palette.selected,
        onPrimaryContainer: palette.text,
        inversePrimary: palette.brandHover,
        // A fill under white text, as on the selected UiTab. As a text colour
        // it is under 4.5:1 on dark surfaces, so text that would use it is
        // given brandHover instead (UiSecondaryButton's borderColor, for one).
        secondary: palette.brand,
        onSecondary: palette.onBrand,
        secondaryContainer: palette.surfaceHigh,
        onSecondaryContainer: palette.text,
        // The legacy themes paint panels and button fills with tertiary.
        tertiary: palette.surfaceHigh,
        onTertiary: palette.text,
        tertiaryContainer: palette.infoBg,
        onTertiaryContainer: palette.info,
        error: palette.danger,
        onError: palette.surface,
        errorContainer: palette.dangerBg,
        onErrorContainer: palette.danger,
        surface: palette.surface,
        onSurface: palette.text,
        onSurfaceVariant: palette.textSecondary,
        surfaceDim: palette.canvas,
        surfaceBright: palette.surfaceHigh,
        surfaceContainerLowest: palette.canvas,
        surfaceContainerLow: palette.surface,
        surfaceContainer: palette.surfaceRaised,
        surfaceContainerHigh: palette.surfaceHigh,
        surfaceContainerHighest: palette.surfaceHighest,
        outline: palette.controlBorder,
        outlineVariant: palette.border,
        shadow: palette.shadow,
        inverseSurface: palette.text,
        onInverseSurface: palette.canvas,
      );

  /// Every style in the palette's text colour, except the two the legacy
  /// themes use for quieter copy: `bodyLarge` (half-transparent there, which
  /// fell under 4.5:1 in the light theme) and `bodySmall`.
  static TextTheme _textTheme(TextTheme base, AppPalette palette) => base
      .apply(bodyColor: palette.text, displayColor: palette.text)
      .copyWith(
        bodyLarge: base.bodyLarge?.copyWith(color: palette.textTertiary),
        bodySmall: base.bodySmall?.copyWith(color: palette.textSecondary),
      );

  static InputDecorationThemeData _inputs(
    InputDecorationThemeData base,
    AppPalette palette,
  ) {
    OutlineInputBorder outline(Color color, {double width = 1}) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: width),
        );
    return base.copyWith(
      fillColor: palette.surfaceHigh,
      focusColor: palette.surfaceHigh,
      hintStyle: TextStyle(color: palette.textTertiary),
      labelStyle: TextStyle(color: palette.textTertiary),
      floatingLabelStyle: TextStyle(color: palette.textSecondary),
      helperStyle: TextStyle(color: palette.textTertiary),
      errorStyle: TextStyle(color: palette.danger),
      iconColor: palette.textTertiary,
      prefixIconColor: palette.textTertiary,
      suffixIconColor: palette.textTertiary,
      focusedBorder: outline(palette.brand, width: 1.5),
      errorBorder: outline(palette.danger),
      focusedErrorBorder: outline(palette.danger, width: 1.5),
    );
  }

  static SwitchThemeData _switches(SwitchThemeData base, AppPalette palette) {
    final isLight = identical(palette, AppPalette.light);
    return base.copyWith(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return palette.onDisabled;
        if (states.contains(WidgetState.selected)) return palette.onBrand;
        return isLight ? palette.surface : palette.textSecondary;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return palette.disabled;
        if (states.contains(WidgetState.selected)) return palette.brand;
        return palette.borderStrong;
      }),
    );
  }
}

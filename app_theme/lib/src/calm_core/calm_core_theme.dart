import 'package:flutter/material.dart';

import '../dark/theme_custom_dark.dart';
import '../light/theme_custom_light.dart';
import '../new_theme/extensions/color_scheme_extension.dart';
import '../new_theme/extensions/text_theme_extension.dart';
import 'gleec_color_tokens.dart';
import 'gleec_geometry.dart';
import 'gleec_motion.dart';
import 'gleec_typography.dart';

ThemeData buildCalmCoreTheme(Brightness brightness) {
  final colors = brightness == Brightness.dark
      ? GleecColorTokens.dark
      : GleecColorTokens.light;
  const geometry = GleecGeometry.standard;
  const motion = GleecMotion.standardTokens;
  final typography = GleecTypography.fromColors(colors);
  final colorScheme = _colorScheme(colors, brightness);
  final legacyLight = brightness == Brightness.light
      ? ThemeCustomLight(colors: colors)
      : null;
  final legacyDark = brightness == Brightness.dark
      ? ThemeCustomDark(colors: colors)
      : null;

  final theme = ThemeData(
    useMaterial3: false,
    brightness: brightness,
    fontFamily: 'Manrope',
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    scaffoldBackgroundColor: colors.canvas,
    canvasColor: colors.surface,
    cardColor: colors.surfaceRaised,
    dividerColor: colors.border,
    disabledColor: colors.textTertiary.withValues(alpha: 0.5),
    focusColor: colors.brand.withValues(alpha: 0.24),
    hoverColor: colors.brand.withValues(alpha: 0.08),
    highlightColor: colors.brand.withValues(alpha: 0.12),
    splashColor: colors.brand.withValues(alpha: 0.16),
    hintColor: colors.textTertiary,
    primaryColor: colors.brand,
    colorScheme: colorScheme,
    textTheme: typography.toMaterialTextTheme(),
    primaryTextTheme: typography.toMaterialTextTheme(),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: colors.surface,
      foregroundColor: colors.textPrimary,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: typography.cardTitle,
      iconTheme: IconThemeData(color: colors.textPrimary),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      backgroundColor: colors.surface,
      selectedItemColor: colors.brand,
      unselectedItemColor: colors.textTertiary,
      selectedLabelStyle: typography.labelMedium,
      unselectedLabelStyle: typography.labelMedium,
    ),
    cardTheme: CardThemeData(
      color: colors.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.border),
        borderRadius: geometry.borderRadius20,
      ),
    ),
    dialogTheme: DialogThemeData(
      elevation: 0,
      backgroundColor: colors.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: typography.sectionTitle,
      contentTextStyle: typography.bodyMedium,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.border),
        borderRadius: geometry.borderRadius24,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: colors.border,
      space: 1,
      thickness: 1,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: _primaryButtonStyle(colors, typography, geometry),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: _secondaryButtonStyle(colors, typography, geometry),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll<Size>(
          Size(geometry.minimumTapTarget, geometry.minimumTapTarget),
        ),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.disabled)) {
            return colors.textTertiary.withValues(alpha: 0.5);
          }
          if (states.contains(WidgetState.pressed)) return colors.brandPressed;
          if (states.contains(WidgetState.hovered)) return colors.brandHover;
          return colors.brand;
        }),
        textStyle: WidgetStatePropertyAll<TextStyle>(typography.labelLarge),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: geometry.borderRadius12),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll<Size>(
          Size.square(geometry.minimumTapTarget),
        ),
        iconColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.disabled)) {
            return colors.textTertiary.withValues(alpha: 0.5);
          }
          return colors.textSecondary;
        }),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: geometry.borderRadius12),
        ),
      ),
    ),
    inputDecorationTheme: _inputDecorationTheme(colors, typography, geometry),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.brand,
      selectionColor: colors.brand.withValues(alpha: 0.3),
      selectionHandleColor: colors.brand,
    ),
    checkboxTheme: CheckboxThemeData(
      checkColor: WidgetStatePropertyAll<Color>(colorScheme.onPrimary),
      fillColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.selected)) return colors.brand;
        return Colors.transparent;
      }),
      side: BorderSide(color: colors.controlBorder, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.disabled)) {
          return colors.textTertiary.withValues(alpha: 0.5);
        }
        return states.contains(WidgetState.selected)
            ? colors.brand
            : colors.controlBorder;
      }),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.selected)) {
          return colors.brand.withValues(alpha: 0.45);
        }
        return colors.surfaceHighest;
      }),
      thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.selected)) return colors.brand;
        return colors.textTertiary;
      }),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: _secondaryButtonStyle(colors, typography, geometry).copyWith(
        backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
          return states.contains(WidgetState.selected)
              ? colors.selected
              : colors.surfaceHigh;
        }),
        foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
          return states.contains(WidgetState.selected)
              ? colors.textPrimary
              : colors.textSecondary;
        }),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: colors.border,
      labelColor: colors.textPrimary,
      unselectedLabelColor: colors.textTertiary,
      labelStyle: typography.labelLarge,
      unselectedLabelStyle: typography.labelLarge,
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(width: 2, color: colors.brand),
      ),
    ),
    listTileTheme: ListTileThemeData(
      minVerticalPadding: 12,
      iconColor: colors.textSecondary,
      textColor: colors.textPrimary,
      titleTextStyle: typography.bodyLarge.copyWith(
        fontWeight: FontWeight.w600,
      ),
      subtitleTextStyle: typography.bodyMedium,
      shape: RoundedRectangleBorder(borderRadius: geometry.borderRadius12),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: colors.brand),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll<Color>(
        colors.controlBorder.withValues(alpha: 0.8),
      ),
      radius: Radius.circular(geometry.radius12),
      thickness: const WidgetStatePropertyAll<double>(8),
    ),
    snackBarTheme: SnackBarThemeData(
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      backgroundColor: colors.surfaceHighest,
      contentTextStyle: typography.bodyMedium.copyWith(
        color: colors.textPrimary,
      ),
      actionTextColor: colors.brandHover,
      closeIconColor: colors.textSecondary,
      showCloseIcon: true,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.borderStrong),
        borderRadius: geometry.borderRadius16,
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colors.surfaceHighest,
        border: Border.all(color: colors.borderStrong),
        borderRadius: geometry.borderRadius12,
      ),
      textStyle: typography.bodySmall.copyWith(color: colors.textPrimary),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      waitDuration: motion.deliberate,
    ),
    extensions: <ThemeExtension<dynamic>>[
      colors,
      typography,
      geometry,
      motion,
      ColorSchemeExtension.fromCalmCore(colors),
      TextThemeExtension.fromCalmCore(typography),
      if (legacyLight != null) legacyLight,
      if (legacyDark != null) legacyDark,
    ],
  );

  legacyLight?.initializeThemeDependentColors(theme);
  legacyDark?.initializeThemeDependentColors(theme);
  return theme;
}

ColorScheme _colorScheme(GleecColorTokens colors, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return ColorScheme.fromSeed(
    seedColor: colors.brand,
    brightness: brightness,
  ).copyWith(
    primary: colors.brand,
    onPrimary: Colors.white,
    primaryContainer: colors.selected,
    onPrimaryContainer: colors.textPrimary,
    inversePrimary: colors.brandHover,
    secondary: colors.brandHover,
    onSecondary: dark ? colors.canvas : Colors.white,
    secondaryContainer: colors.surfaceHigh,
    onSecondaryContainer: colors.textPrimary,
    tertiary: colors.info,
    onTertiary: dark ? colors.canvas : Colors.white,
    tertiaryContainer: colors.infoContainer,
    onTertiaryContainer: colors.textPrimary,
    error: colors.danger,
    onError: dark ? colors.canvas : Colors.white,
    errorContainer: colors.dangerContainer,
    onErrorContainer: colors.textPrimary,
    surface: colors.surface,
    onSurface: colors.textPrimary,
    surfaceDim: dark ? colors.canvas : colors.surfaceHighest,
    surfaceBright: dark ? colors.surfaceHighest : colors.surface,
    surfaceContainerLowest: colors.canvas,
    surfaceContainerLow: colors.surface,
    surfaceContainer: colors.surfaceRaised,
    surfaceContainerHigh: colors.surfaceHigh,
    surfaceContainerHighest: colors.surfaceHighest,
    onSurfaceVariant: colors.textSecondary,
    outline: colors.controlBorder,
    outlineVariant: colors.border,
    shadow: colors.shadow,
    scrim: Colors.black,
    inverseSurface: colors.textPrimary,
    onInverseSurface: colors.canvas,
    surfaceTint: Colors.transparent,
  );
}

ButtonStyle _primaryButtonStyle(
  GleecColorTokens colors,
  GleecTypography typography,
  GleecGeometry geometry,
) {
  return ButtonStyle(
    elevation: const WidgetStatePropertyAll<double>(0),
    minimumSize: WidgetStatePropertyAll<Size>(
      Size(geometry.minimumTapTarget, geometry.minimumTapTarget),
    ),
    padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
      EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
      if (states.contains(WidgetState.disabled)) return colors.surfaceHighest;
      if (states.contains(WidgetState.pressed)) return colors.brandPressed;
      if (states.contains(WidgetState.hovered)) return colors.brandHover;
      return colors.brand;
    }),
    foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
      if (states.contains(WidgetState.disabled)) {
        return colors.textTertiary.withValues(alpha: 0.6);
      }
      return Colors.white;
    }),
    overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
    textStyle: WidgetStatePropertyAll<TextStyle>(typography.labelLarge),
    shape: WidgetStatePropertyAll<OutlinedBorder>(
      RoundedRectangleBorder(borderRadius: geometry.borderRadius16),
    ),
  );
}

ButtonStyle _secondaryButtonStyle(
  GleecColorTokens colors,
  GleecTypography typography,
  GleecGeometry geometry,
) {
  return ButtonStyle(
    elevation: const WidgetStatePropertyAll<double>(0),
    minimumSize: WidgetStatePropertyAll<Size>(
      Size(geometry.minimumTapTarget, geometry.minimumTapTarget),
    ),
    padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
      EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
      if (states.contains(WidgetState.disabled)) {
        return colors.surfaceHigh.withValues(alpha: 0.5);
      }
      if (states.contains(WidgetState.pressed)) return colors.surfaceHighest;
      return colors.surfaceHigh;
    }),
    foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
      if (states.contains(WidgetState.disabled)) {
        return colors.textTertiary.withValues(alpha: 0.5);
      }
      return colors.textPrimary;
    }),
    side: WidgetStateProperty.resolveWith<BorderSide>((states) {
      final color = states.contains(WidgetState.focused)
          ? colors.brand
          : colors.controlBorder;
      return BorderSide(
        color: color,
        width: states.contains(WidgetState.focused)
            ? geometry.focusRingWidth
            : 1,
      );
    }),
    textStyle: WidgetStatePropertyAll<TextStyle>(typography.labelLarge),
    shape: WidgetStatePropertyAll<OutlinedBorder>(
      RoundedRectangleBorder(borderRadius: geometry.borderRadius16),
    ),
  );
}

InputDecorationTheme _inputDecorationTheme(
  GleecColorTokens colors,
  GleecTypography typography,
  GleecGeometry geometry,
) {
  OutlineInputBorder border(Color color, [double width = 1]) {
    return OutlineInputBorder(
      borderSide: BorderSide(color: color, width: width),
      borderRadius: geometry.borderRadius12,
    );
  }

  return InputDecorationTheme(
    filled: true,
    fillColor: colors.surfaceHigh,
    constraints: BoxConstraints(minHeight: geometry.inputHeight),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    enabledBorder: border(colors.controlBorder),
    disabledBorder: border(colors.border),
    border: border(colors.controlBorder),
    focusedBorder: border(colors.brand, 2),
    errorBorder: border(colors.danger),
    focusedErrorBorder: border(colors.danger, 2),
    hintStyle: typography.bodyMedium.copyWith(color: colors.textTertiary),
    labelStyle: typography.bodyMedium.copyWith(color: colors.textSecondary),
    floatingLabelStyle: typography.labelMedium.copyWith(color: colors.brand),
    helperStyle: typography.bodySmall,
    errorStyle: typography.bodySmall.copyWith(color: colors.danger),
    prefixIconColor: colors.textTertiary,
    suffixIconColor: colors.textTertiary,
    hoverColor: colors.surfaceHighest,
    focusColor: colors.surfaceHigh,
  );
}

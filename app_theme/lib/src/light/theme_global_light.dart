import 'package:flutter/material.dart';
import 'theme_custom_light.dart';

ThemeData get themeGlobalLight {
  const Color inputBackgroundColor = Color.fromRGBO(243, 245, 246, 1);
  const Color textColor = Color.fromRGBO(69, 96, 120, 1);

  OutlineInputBorder outlineBorderLight(Color lightAccentColor) =>
      OutlineInputBorder(
        borderSide: BorderSide(color: lightAccentColor),
        borderRadius: BorderRadius.circular(12),
      );

  final ColorScheme colorScheme = const ColorScheme.light().copyWith(
    primary: const Color(0xFF8C41FF), // GLEEC Purple primary
    inversePrimary: const Color(0xFFB87DFF), // Lighter purple for gradients
    secondary: const Color(0xFF666666), // Muted gray for accents
    tertiary: const Color.fromARGB(255, 192, 225, 255),
    surface: const Color.fromRGBO(255, 255, 255, 1),
    onSurface: const Color.fromRGBO(251, 251, 251, 1),
    error: const Color.fromRGBO(229, 33, 103, 1),
  );

  final TextTheme textTheme = TextTheme(
    headlineMedium: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: textColor,
    ),
    headlineSmall: const TextStyle(
      fontSize: 40,
      fontWeight: FontWeight.w700,
      color: textColor,
    ),
    titleLarge: const TextStyle(
      fontSize: 26.0,
      color: textColor,
      fontWeight: FontWeight.w700,
    ),
    titleSmall: const TextStyle(fontSize: 18.0, color: textColor),
    bodyMedium: const TextStyle(
      fontSize: 16.0,
      color: textColor,
      fontWeight: FontWeight.w300,
    ),
    labelLarge: const TextStyle(fontSize: 16.0, color: textColor),
    bodyLarge: TextStyle(
      fontSize: 14.0,
      color: textColor.withAlpha(128),
    ), // 0.5 * 255
    bodySmall: TextStyle(
      fontSize: 12.0,
      color: textColor.withAlpha(204), // 0.8 * 255
      fontWeight: FontWeight.w400,
    ),
  );

  SnackBarThemeData snackBarThemeLight() => SnackBarThemeData(
        elevation: 12.0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.primaryContainer,
        contentTextStyle: textTheme.bodyLarge!.copyWith(
          color: colorScheme.onPrimaryContainer,
        ),
        actionTextColor: colorScheme.onPrimaryContainer,
        showCloseIcon: true,
        closeIconColor: colorScheme.onPrimaryContainer.withAlpha(179), // 70%
      );

  final customTheme = ThemeCustomLight();
  final theme = ThemeData(
    useMaterial3: false,
    fontFamily: 'Manrope',
    scaffoldBackgroundColor: colorScheme.onSurface,
    cardColor: colorScheme.surface,
    cardTheme: CardThemeData(
      color: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    colorScheme: colorScheme,
    primaryColor: colorScheme.primary,
    dividerColor: const Color.fromRGBO(208, 214, 237, 1),
    appBarTheme: AppBarTheme(color: colorScheme.surface),
    iconTheme: IconThemeData(color: colorScheme.primary),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colorScheme.primary,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Color.fromRGBO(255, 255, 255, 1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    canvasColor: colorScheme.surface,
    hintColor: const Color.fromRGBO(183, 187, 191, 1),
    snackBarTheme: snackBarThemeLight(),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: const Color(0xFF8C41FF), // GLEEC Purple primary
      selectionColor: const Color(0xFF8C41FF).withAlpha(77), // 0.3 * 255
      selectionHandleColor: const Color(0xFF8C41FF), // GLEEC Purple primary
    ),
    inputDecorationTheme: InputDecorationTheme(
      enabledBorder: outlineBorderLight(Colors.transparent),
      disabledBorder: outlineBorderLight(Colors.transparent),
      border: outlineBorderLight(Colors.transparent),
      focusedBorder: outlineBorderLight(Colors.transparent),
      errorBorder: outlineBorderLight(colorScheme.error),
      fillColor: inputBackgroundColor,
      focusColor: inputBackgroundColor,
      hoverColor: Colors.transparent,
      errorStyle: TextStyle(color: colorScheme.error),
      filled: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 22),
      hintStyle: TextStyle(
        color: textColor.withAlpha(148), // 0.58 * 255
      ),
      labelStyle: TextStyle(
        color: textColor.withAlpha(148), // 0.58 * 255
      ),
      prefixIconColor: textColor.withAlpha(148), // 0.58 * 255
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith<Color?>((
          Set<WidgetState> states,
        ) {
          if (states.contains(WidgetState.disabled)) return Colors.grey;
          return colorScheme.primary;
        }),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      checkColor: WidgetStateProperty.all<Color>(Colors.white),
      fillColor: WidgetStateProperty.all<Color>(colorScheme.primary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colorScheme.primary,
    ),
    textTheme: textTheme,
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all<Color?>(
        colorScheme.primary.withAlpha(204),
      ), // 0.8 * 255
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      // remove icons shift
      type: BottomNavigationBarType.fixed,
      backgroundColor: colorScheme.surface,
      selectedItemColor: const Color(0xFF8C41FF), // GLEEC Purple primary
      unselectedItemColor: textColor,
      unselectedLabelStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      selectedLabelStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith<Color?>(
        (Set<WidgetState> states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary.withOpacity(0.5);
          }
          return const Color(0xFFD1D1D1);
        },
      ),
      thumbColor: WidgetStateProperty.resolveWith<Color?>(
        (Set<WidgetState> states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return Colors.white;
        },
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: const Color.fromRGBO(243, 245, 246, 1),
        surfaceTintColor: Colors.purple,
        selectedBackgroundColor: colorScheme.primary,
        foregroundColor: textColor.withAlpha(179), // 0.7 * 255
        selectedForegroundColor: Colors.white,
        side: const BorderSide(color: Color.fromRGBO(208, 214, 237, 1)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: textColor,
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(width: 2.0, color: colorScheme.primary),
        // Match the card's border radius
        insets: const EdgeInsets.symmetric(horizontal: 18),
      ),
    ),
    extensions: [customTheme],
  );

  // Initialize theme-dependent colors after theme creation
  customTheme.initializeThemeDependentColors(theme);

  return theme;
}

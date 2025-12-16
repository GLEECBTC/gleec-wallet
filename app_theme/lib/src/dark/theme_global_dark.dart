import 'package:flutter/material.dart';
import 'theme_custom_dark.dart';

ThemeData get themeGlobalDark {
  const Color inputBackgroundColor = Color.fromRGBO(51, 57, 72, 1);
  const Color textColor = Color.fromRGBO(255, 255, 255, 1);

  OutlineInputBorder outlineBorderLight(Color lightAccentColor) =>
      OutlineInputBorder(
        borderSide: BorderSide(color: lightAccentColor),
        borderRadius: BorderRadius.circular(12),
      );

  //TODO! Implement all light-theme equivalent properties
  final ColorScheme colorScheme = ColorScheme.fromSeed(
    brightness: Brightness.dark,
    seedColor: const Color(0xFF8C41FF), // GLEEC Purple primary
    primary: const Color(0xFF8C41FF), // GLEEC Purple primary
    // secondary: const Color(0xFF00C3AA),
    tertiary: const Color(0xFF0A0A0A), // CORRECTED - darker for sidebar/header
    surface: const Color(0xFF141414), // Card color (correct)
    onSurface: const Color(0xFF000000), // Pure black main background
    error: const Color.fromRGBO(202, 78, 61, 1),
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

  final customTheme = ThemeCustomDark();
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
    dividerColor: const Color(0xFF1d1d1d),
    appBarTheme: AppBarTheme(
      color: const Color(0xFF0A0A0A), // Dark gray for header
    ),
    iconTheme: IconThemeData(color: colorScheme.primary),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colorScheme.primary,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Color(0xFF0A0A0A),
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
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.purple,
        selectedBackgroundColor: colorScheme.primary,
        foregroundColor: textColor.withAlpha(179), // 0.7 * 255
        selectedForegroundColor: textColor,
        side: BorderSide(color: colorScheme.outlineVariant),
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
    // outlinedButtonTheme: OutlinedButtonThemeData(
    //   style: ButtonStyle(
    //       // TODO!
    //       //   onPrimary: textColor,
    //       //   shape: RoundedRectangleBorder(
    //       //     borderRadius: BorderRadius.circular(18),
    //       //   ),
    //       ),
    // ),
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
        colorScheme.primary.withAlpha(204), // 0.8 * 255
      ),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      // remove icons shift
      type: BottomNavigationBarType.fixed,
      backgroundColor: colorScheme.surface,
      selectedItemColor: textColor,
      unselectedItemColor: const Color.fromRGBO(173, 175, 198, 1),
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
      trackColor: WidgetStateProperty.resolveWith<Color?>((
        Set<WidgetState> states,
      ) {
        if (states.contains(WidgetState.selected)) {
          return colorScheme.primary.withOpacity(0.5);
        }
        return const Color(0xFF444444);
      }),
      thumbColor: WidgetStateProperty.resolveWith<Color?>((
        Set<WidgetState> states,
      ) {
        if (states.contains(WidgetState.selected)) {
          return colorScheme.primary;
        }
        return Colors.white;
      }),
    ),
    extensions: [customTheme],
  );

  // Initialize theme-dependent colors after theme creation
  customTheme.initializeThemeDependentColors(theme);

  return theme;
}

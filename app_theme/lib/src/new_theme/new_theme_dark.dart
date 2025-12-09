import 'package:flutter/material.dart';

import '../../app_theme.dart';

const ColorSchemeExtension _colorSchemeExtension = ColorSchemeExtension(
  primary: Color(0xFF8C41FF), // GLEEC Purple primary (Figma)
  p50: Color(0xFF6B1FE0), // Darker purple
  p40: Color(0xFF5016B0), // Even darker purple
  p10: Color(0xFF1A0A30), // Very dark purple
  secondary: Color(0xFF8790B2), // Muted gray-blue for text/accents on dark
  s70: Color.fromRGBO(135, 144, 178, 1), // #8790B2
  s50: Color.fromRGBO(99, 105, 133, 1),
  s40: Color.fromRGBO(73, 78, 99, 1),
  s30: Color.fromRGBO(48, 53, 85, 1), // #303555
  s20: Color.fromRGBO(36, 39, 61, 1), // #24273D
  s10: Color.fromRGBO(32, 35, 55, 1), // #202337
  e10: Color.fromRGBO(46, 8, 26, 1),
  e20: Color.fromRGBO(92, 16, 52, 1),
  e50: Color.fromRGBO(184, 26, 83, 1),
  error: Color(0xFFE52167), // GLEEC Warning color
  g10: Color.fromRGBO(0, 19, 9, 1),
  g20: Color.fromRGBO(0, 38, 17, 1),
  green: Color(0xFF00C058), // GLEEC OK color
  surf: Color.fromRGBO(255, 255, 255, 1),
  surfCont: Color(0xFF171A2C), // GLEEC backgroundColorDeep
  surfContHigh: Color(0xFF202337), // GLEEC backgroundColor
  surfContHighest: Color(0xFF24273D), // GLEEC secondBackgroundColor
  surfContLow: Color(0xFF0F1221), // Deeper background
  surfContLowest: Color(0xFF0A0C15), // Darkest
  orange: Color.fromRGBO(237, 170, 70, 1),
  yellow: Color.fromRGBO(230, 188, 65, 1),
  purple: Color(0xFF8C41FF), // GLEEC Purple primary
);

final ColorScheme _colorScheme = theme.global.dark.colorScheme.copyWith(
  primary: _colorSchemeExtension.primary,
  secondary: _colorSchemeExtension.secondary,
);
final TextTheme _textTheme = theme.global.dark.textTheme.copyWith();
final TextThemeExtension _textThemeExtension = TextThemeExtension(
  textColor: _colorSchemeExtension.secondary,
);

final ThemeData newThemeDataDark = theme.global.dark.copyWith(
  colorScheme: _colorScheme,
  textTheme: _textTheme,
  inputDecorationTheme: theme.global.dark.inputDecorationTheme.copyWith(
    hintStyle: _textThemeExtension.bodySBold.copyWith(
      color: _colorSchemeExtension.s50,
    ),
    labelStyle: _textThemeExtension.bodyXSBold.copyWith(
      color: _colorSchemeExtension.primary,
    ),
    errorStyle: _textThemeExtension.bodyS.copyWith(
      color: _colorSchemeExtension.error,
    ),
    enabledBorder: _outlineBorderLight(_colorSchemeExtension.secondary),
    disabledBorder: _outlineBorderLight(_colorSchemeExtension.secondary),
    focusedBorder: _outlineBorderLight(_colorSchemeExtension.primary),
    errorBorder: _outlineBorderLight(_colorSchemeExtension.error),
    fillColor: Colors.transparent,
    hoverColor: Colors.transparent,
  ),
  extensions: [_colorSchemeExtension, _textThemeExtension],
);

OutlineInputBorder _outlineBorderLight(Color accentColor) => OutlineInputBorder(
  borderSide: BorderSide(color: accentColor, width: 2),
  borderRadius: BorderRadius.circular(12),
);

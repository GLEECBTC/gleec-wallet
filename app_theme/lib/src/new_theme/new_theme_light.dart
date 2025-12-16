import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';

const ColorSchemeExtension _colorSchemeExtension = ColorSchemeExtension(
  primary: Color(0xFF8C41FF), // GLEEC Purple primary (Figma)
  p50: Color(0xFFA66AFF), // Lighter purple
  p40: Color(0xFFC5A0FF), // Even lighter purple
  p10: Color(0xFFF0E6FF), // Very light purple
  secondary: Color(0xFF666666), // Muted gray for text/accents on light
  s70: Color.fromRGBO(125, 144, 161, 1),
  s50: Color.fromRGBO(162, 175, 187, 1),
  s40: Color.fromRGBO(181, 191, 201, 1),
  s30: Color.fromRGBO(199, 207, 214, 1),
  s20: Color.fromRGBO(218, 223, 228, 1),
  s10: Color.fromRGBO(236, 239, 241, 1),
  e10: Color.fromRGBO(253, 236, 242, 1),
  e20: Color.fromRGBO(251, 217, 228, 1),
  e50: Color.fromRGBO(242, 152, 179, 1),
  error: Color(0xFFE52167), // GLEEC Warning color
  g10: Color.fromRGBO(230, 249, 239, 1),
  g20: Color.fromRGBO(204, 243, 223, 1),
  green: Color(0xFF00C058), // GLEEC OK color
  surf: Color.fromRGBO(255, 255, 255, 1),
  surfCont: Color.fromRGBO(255, 255, 255, 1),
  surfContHigh: Color.fromRGBO(245, 245, 250, 1),
  surfContHighest: Color.fromRGBO(235, 237, 245, 1),
  surfContLow: Color.fromRGBO(253, 253, 255, 1),
  surfContLowest: Color.fromRGBO(248, 249, 252, 1),
  orange: Color.fromRGBO(237, 170, 70, 1),
  yellow: Color.fromRGBO(230, 188, 65, 1),
  purple: Color(0xFF8C41FF), // GLEEC Purple primary
);

final ColorScheme _colorScheme = theme.global.light.colorScheme.copyWith(
  primary: _colorSchemeExtension.primary,
  secondary: _colorSchemeExtension.secondary,
  error: _colorSchemeExtension.error,
);
final TextTheme _textTheme = theme.global.light.textTheme.copyWith();
final TextThemeExtension _textThemeExtension = TextThemeExtension(
  textColor: _colorSchemeExtension.secondary,
);
final ThemeData newThemeDataLight = theme.global.light.copyWith(
  colorScheme: _colorScheme,
  textTheme: _textTheme,
  inputDecorationTheme: theme.global.light.inputDecorationTheme.copyWith(
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

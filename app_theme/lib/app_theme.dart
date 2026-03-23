library;

import 'package:flutter/material.dart';

import 'src/common/theme_custom_base.dart';
import 'src/dark/theme_custom_dark.dart';
import 'src/light/theme_custom_light.dart';
import 'src/new_theme/new_theme_dark.dart';
import 'src/new_theme/new_theme_light.dart';
import 'src/theme_global.dart';

export 'src/dark/theme_custom_dark.dart';
export 'src/light/theme_custom_light.dart';
export 'src/new_theme/extensions/color_scheme_extension.dart';
export 'src/new_theme/extensions/text_theme_extension.dart';

final theme = AppTheme();

class AppTheme {
  final ThemeDataGlobal global = ThemeDataGlobal();
  ThemeMode mode = ThemeMode.dark;

  ThemeCustomBase get custom =>
      mode == ThemeMode.dark ? _themeCustomDark : _themeCustomLight;
  ThemeData get currentGlobal =>
      mode == ThemeMode.dark ? global.dark : global.light;
}

ThemeCustomBase get _themeCustomLight => ThemeCustomLight();

ThemeCustomBase get _themeCustomDark => ThemeCustomDark();

DexPageTheme get dexPageColors => theme.custom.dexPageTheme;

ThemeData get newThemeDark => newThemeDataDark;
ThemeData get newThemeLight => newThemeDataLight;

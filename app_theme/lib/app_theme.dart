library;

import 'package:flutter/material.dart';

import 'src/calm_core/gleec_color_tokens.dart';
import 'src/common/theme_custom_base.dart';
import 'src/dark/theme_custom_dark.dart';
import 'src/light/theme_custom_light.dart';
import 'src/new_theme/new_theme_dark.dart';
import 'src/new_theme/new_theme_light.dart';
import 'src/theme_global.dart';

export 'src/dark/theme_custom_dark.dart';
export 'src/light/theme_custom_light.dart';
export 'src/calm_core/gleec_color_tokens.dart';
export 'src/calm_core/gleec_geometry.dart';
export 'src/calm_core/gleec_motion.dart';
export 'src/calm_core/gleec_typography.dart';
export 'src/new_theme/extensions/color_scheme_extension.dart';
export 'src/new_theme/extensions/text_theme_extension.dart';

final theme = AppTheme();

/// Transitional access to the legacy compatibility values attached to the
/// active [ThemeData].
///
/// First-party widgets must resolve these values from their local theme so a
/// nested light/dark theme cannot diverge from the mutable application theme
/// mode. New widgets should prefer the Calm Core token extensions directly.
extension CalmCoreThemeCompatibility on ThemeData {
  ThemeCustomBase get calmCoreCompatibility {
    final colors = extension<GleecColorTokens>();
    if (brightness == Brightness.dark) {
      return extension<ThemeCustomDark>() ??
          ThemeCustomDark(colors: colors ?? GleecColorTokens.dark);
    }
    return extension<ThemeCustomLight>() ??
        ThemeCustomLight(colors: colors ?? GleecColorTokens.light);
  }
}

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

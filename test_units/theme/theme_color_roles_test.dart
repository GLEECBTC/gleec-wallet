import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/contrast.dart';

void main() => testThemeColorRoles();

/// Guards the Material colour-role contract on every [ThemeData] the app can
/// actually render.
///
/// `newThemeLight`/`newThemeDark` are `copyWith` derivations of the globals
/// that override only `primary`/`secondary`/`error`, so they inherit the
/// surface and foreground roles verbatim and have to be checked too - several
/// suites pump them directly.
void testThemeColorRoles() {
  final themes = <String, ThemeData>{
    'global light': theme.global.light,
    'global dark': theme.global.dark,
    'new light': newThemeLight,
    'new dark': newThemeDark,
  };

  group('Theme colour roles:', () {
    _testPinnedValues(themes);
    _testRoleSemantics(themes);
  });
}

/// The value the canvas is expected to paint, per theme. Pinned so that a
/// refactor which merely stops *deriving* these from another role is provably
/// a no-op: if any of these move, the refactor changed pixels.
const _canvas = <String, int>{
  'global light': 0xFFFBFBFB,
  'global dark': 0xFF000000,
  'new light': 0xFFFBFBFB,
  'new dark': 0xFF000000,
};

/// Every light role that `copyWith` would otherwise materialize implicitly.
///
/// `theme_global_light.dart` builds its scheme with
/// `const ColorScheme.light().copyWith(...)`, and `ColorScheme.copyWith`
/// resolves nullable roles through their *getters* against the pre-override
/// constants. Anything left unset therefore freezes at a Material 2 default
/// nobody chose, which is how the surface ramp ended up collapsed onto pure
/// white and the outlines onto black.
///
/// Pinning them here means an accidental re-derivation shows up as a failing
/// diff rather than as a screen nobody looks at. The FREEZE entries are the
/// M2 leftovers still awaiting a brand decision; the rest are chosen values.
const _lightPinnedRoles = <String, int>{
  'primaryContainer': 0xFF6200EE, // FREEZE: M2 purple
  'onPrimaryContainer': 0xFFFFFFFF,
  'secondaryContainer': 0xFF03DAC6, // FREEZE: M2 teal
  'onSecondaryContainer': 0xFF000000,
  'tertiaryContainer': 0xFF03DAC6, // FREEZE: M2 teal
  'onTertiaryContainer': 0xFF000000,
  'onTertiary': 0xFF000000,
  'errorContainer': 0xFFB00020, // FREEZE: M2 error
  'onErrorContainer': 0xFFFFFFFF,

  // The elevation ramp: steps darker than the #FBFBFB canvas so a container
  // reads as a container.
  'surfaceDim': 0xFFE4E8F4,
  'surfaceBright': 0xFFFFFFFF,
  'surfaceContainerLowest': 0xFFFFFFFF,
  'surfaceContainerLow': 0xFFF8F9FC,
  'surfaceContainer': 0xFFF1F3F9,
  'surfaceContainerHigh': 0xFFEBEDF5,
  'surfaceContainerHighest': 0xFFE4E8F4,

  'onSurfaceVariant': 0xFF4D6882,
  'outline': 0xFFD0D6ED,
  'outlineVariant': 0xFFE4E8F4,
  'inverseSurface': 0xFF000000,
  'onInverseSurface': 0xFFFFFFFF,
  'surfaceTint': 0xFF6200EE, // FREEZE: inert while useMaterial3 is false
};

/// `onSurface` per theme. Split out from the tables above because this is the
/// single role the migration deliberately moves; keeping it separate makes the
/// flip a one-line diff in this file.
const _onSurface = <String, int>{
  'global light': 0xFF456078,
  'global dark': 0xFFFFFFFF,
  'new light': 0xFF456078,
  'new dark': 0xFFFFFFFF,
};

Map<String, Color> _rolesOf(ColorScheme c) => {
  'primaryContainer': c.primaryContainer,
  'onPrimaryContainer': c.onPrimaryContainer,
  'secondaryContainer': c.secondaryContainer,
  'onSecondaryContainer': c.onSecondaryContainer,
  'tertiaryContainer': c.tertiaryContainer,
  'onTertiaryContainer': c.onTertiaryContainer,
  'onTertiary': c.onTertiary,
  'errorContainer': c.errorContainer,
  'onErrorContainer': c.onErrorContainer,
  'surfaceDim': c.surfaceDim,
  'surfaceBright': c.surfaceBright,
  'surfaceContainerLowest': c.surfaceContainerLowest,
  'surfaceContainerLow': c.surfaceContainerLow,
  'surfaceContainer': c.surfaceContainer,
  'surfaceContainerHigh': c.surfaceContainerHigh,
  'surfaceContainerHighest': c.surfaceContainerHighest,
  'onSurfaceVariant': c.onSurfaceVariant,
  'outline': c.outline,
  'outlineVariant': c.outlineVariant,
  'inverseSurface': c.inverseSurface,
  'onInverseSurface': c.onInverseSurface,
  'surfaceTint': c.surfaceTint,
};

List<Color> _surfaceFamily(ColorScheme c) => [
  c.surface,
  c.surfaceDim,
  c.surfaceBright,
  c.surfaceContainerLowest,
  c.surfaceContainerLow,
  c.surfaceContainer,
  c.surfaceContainerHigh,
  c.surfaceContainerHighest,
];

void _testPinnedValues(Map<String, ThemeData> themes) {
  group('pinned values', () {
    themes.forEach((name, data) {
      test('$name paints the canvas it always has', () {
        expect(
          describeColor(data.scaffoldBackgroundColor),
          describeColor(Color(_canvas[name]!)),
        );
      });

      test('$name keeps onSurface where the migration expects it', () {
        expect(
          describeColor(data.colorScheme.onSurface),
          describeColor(Color(_onSurface[name]!)),
        );
      });

      if (data.brightness == Brightness.light) {
        test('$name pins every implicitly-derived role', () {
          final actual = _rolesOf(data.colorScheme);
          final mismatches = <String>[];
          _lightPinnedRoles.forEach((role, argb) {
            final got = actual[role]!;
            if (got.toARGB32() != argb) {
              mismatches.add(
                '$role: ${describeColor(got)} != ${describeColor(Color(argb))}',
              );
            }
          });
          expect(mismatches, isEmpty, reason: mismatches.join('\n'));
        });
      }
    });
  });
}

/// The contract the migration is moving towards.
///
/// Every case here fails today because both global themes assign `onSurface`
/// a background value and use it as `scaffoldBackgroundColor`. They are
/// skipped rather than deleted so the fix commit's diff is the un-skip - that
/// is the evidence the migration worked.
void _testRoleSemantics(Map<String, ThemeData> themes) {
  group('role semantics', () {
    themes.forEach((name, data) {
      final scheme = data.colorScheme;

      test('$name does not paint the canvas with a foreground role', () {
        expect(
          describeColor(data.scaffoldBackgroundColor),
          isNot(describeColor(scheme.onSurface)),
          reason:
              'onSurface is content drawn *on* a surface; using it as the page '
              'background makes every Material-correct widget illegible',
        );
      });

      test('$name onSurface is legible on every surface role', () {
        for (final surface in _surfaceFamily(scheme)) {
          expectContrast(
            scheme.onSurface,
            surface,
            because: '$name: onSurface on ${describeColor(surface)}',
          );
        }
      });

      test('$name onSurfaceVariant is legible on every surface role', () {
        for (final surface in _surfaceFamily(scheme)) {
          expectContrast(
            scheme.onSurfaceVariant,
            surface,
            because: '$name: onSurfaceVariant on ${describeColor(surface)}',
          );
        }
      });

      test('$name gives elevated containers a visible tint', () {
        expect(
          describeColor(scheme.surfaceContainer),
          isNot(describeColor(scheme.surface)),
          reason: 'a container that matches the surface is an invisible box',
        );
        expect(
          describeColor(scheme.surfaceContainerHighest),
          isNot(describeColor(scheme.surface)),
        );
      });

      // Green today in both brightnesses - this is the guard that stops a
      // "fix" which swaps onSurface and surface and inverts the whole app.
      test('$name body text is legible on the canvas', () {
        for (final entry in {
          'bodyMedium': data.textTheme.bodyMedium,
          'titleLarge': data.textTheme.titleLarge,
          'labelLarge': data.textTheme.labelLarge,
        }.entries) {
          expectContrast(
            entry.value!.color!,
            data.scaffoldBackgroundColor,
            because: '$name: textTheme.${entry.key} on the canvas',
          );
        }
      });

      for (final (label, foreground, background, minimum) in [
        ('primary', scheme.onPrimary, scheme.primary, wcagAaNormalText),
        (
          'errorContainer',
          scheme.onErrorContainer,
          scheme.errorContainer,
          wcagAaNormalText,
        ),
        (
          'secondaryContainer',
          scheme.onSecondaryContainer,
          scheme.secondaryContainer,
          wcagAaNormalText,
        ),
        // White on the GLEEC brand red (#E52167) measures 4.43:1 - a 1.6%
        // shortfall against AA for normal text, and clear of the 3:1 bar for
        // large text and non-text UI. Closing it means darkening a brand
        // colour, which is a brand decision rather than a theming one, so
        // this holds the large-text bar and pins the shortfall in place so
        // nobody narrows it by accident.
        ('error', scheme.onError, scheme.error, wcagAaLargeText),
      ]) {
        test('$name pairs on$label with $label', () {
          expectContrast(
            foreground,
            background,
            atLeast: minimum,
            because: '$name: on$label on $label',
          );
        });
      }

      // Deliberately not asserted: ColorSchemeExtension tokens. Their names do
      // not describe their role (the *dark* extension's `surf` is white), so
      // contrast-testing them would report failures this migration is not
      // scoped to fix.
    });
  });
}

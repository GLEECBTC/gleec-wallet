import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.1 AA minimum contrast for normal body text.
const double wcagAaNormalText = 4.5;

/// WCAG 2.1 AA minimum for large text (>=18pt, or >=14pt bold).
const double wcagAaLargeText = 3;

/// WCAG 2.1 AA minimum for UI components, icons and focus indicators.
const double wcagAaNonText = 3;

/// `#aarrggbb`, so a failing assertion names the actual colours rather than
/// only the ratio it fell short of.
String describeColor(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0')}';

/// Source-over composite of [foreground] onto [background].
///
/// Thin wrapper over [Color.alphaBlend] so call sites read as intent rather
/// than as a Flutter API detail.
Color compositeOver(Color foreground, Color background) =>
    Color.alphaBlend(foreground, background);

/// Flattens a back-to-front stack of paint layers into one opaque colour.
///
/// `layers.first` is the base and must be opaque; each later entry is
/// composited on top of the result so far.
Color flattenLayers(List<Color> layers) {
  if (layers.isEmpty) {
    throw ArgumentError.value(layers, 'layers', 'needs at least a base layer');
  }
  final base = layers.first;
  if (base.a != 1.0) {
    throw ArgumentError.value(
      describeColor(base),
      'layers.first',
      'the base layer must be opaque, otherwise the composited result depends '
          'on paint this test cannot see',
    );
  }
  return layers
      .skip(1)
      .fold(base, (result, layer) => compositeOver(layer, result));
}

/// WCAG 2.1 contrast ratio: `(Llighter + 0.05) / (Ldarker + 0.05)`.
///
/// Delegates the relative-luminance term to [Color.computeLuminance], which
/// already implements the WCAG formula including sRGB linearization.
///
/// Both arguments must be opaque. Contrast against a translucent colour is
/// undefined - composite it over its background first ([compositeOver]).
double contrastRatio(Color a, Color b) {
  for (final (name, color) in [('a', a), ('b', b)]) {
    if (color.a != 1.0) {
      throw ArgumentError.value(
        describeColor(color),
        name,
        'contrast against a translucent colour is undefined; composite it '
        'over its background first',
      );
    }
  }
  final luminances = [a.computeLuminance(), b.computeLuminance()]..sort();
  return (luminances[1] + 0.05) / (luminances[0] + 0.05);
}

/// Matches a foreground colour that clears [atLeast] against [background].
Matcher hasContrastAgainst(
  Color background, {
  double atLeast = wcagAaNormalText,
}) => _HasContrastAgainst(background, atLeast);

/// [hasContrastAgainst] in imperative form, with a mandatory [because] naming
/// what is being measured - a bare ratio in a failure log is not diagnosable.
void expectContrast(
  Color foreground,
  Color background, {
  required String because,
  double atLeast = wcagAaNormalText,
}) => expect(
  foreground,
  hasContrastAgainst(background, atLeast: atLeast),
  reason: because,
);

class _HasContrastAgainst extends Matcher {
  const _HasContrastAgainst(this.background, this.minimum);

  final Color background;
  final double minimum;

  @override
  bool matches(Object? item, Map<dynamic, dynamic> matchState) {
    if (item is! Color) return false;
    matchState['ratio'] = contrastRatio(item, background);
    return (matchState['ratio'] as double) >= minimum;
  }

  @override
  Description describe(Description description) => description.add(
    'a colour with at least ${minimum.toStringAsFixed(1)}:1 contrast against '
    '${describeColor(background)}',
  );

  @override
  Description describeMismatch(
    Object? item,
    Description mismatchDescription,
    Map<dynamic, dynamic> matchState,
    bool verbose,
  ) {
    if (item is! Color) {
      return mismatchDescription.add('is not a Color');
    }
    final ratio = matchState['ratio'] as double;
    return mismatchDescription.add(
      '${describeColor(item)} on ${describeColor(background)} is only '
      '${ratio.toStringAsFixed(2)}:1, needs ${minimum.toStringAsFixed(1)}:1',
    );
  }
}

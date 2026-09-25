import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contrast.dart';

/// The colour a run of text is actually painted with.
///
/// Reads the [RenderParagraph] rather than the [Text] widget on purpose:
/// `Text.build` merges the ambient [DefaultTextStyle] with its own `style`
/// before handing the result to `RichText`, so text that inherits its colour -
/// which most correctly-written widgets do - has `Text.style?.color == null`.
/// Asserting off the widget would either throw or, worse, read a partial style
/// and pass.
Color resolvedTextColor(WidgetTester tester, Finder textFinder) {
  final paragraph = tester.renderObject<RenderParagraph>(textFinder);
  final span = paragraph.text;
  if (span is TextSpan && (span.children?.isNotEmpty ?? false)) {
    fail(
      'resolvedTextColor only handles flat spans; ${textFinder.describeMatch(Plurality.one)} '
      'has ${span.children!.length} child spans that may override the root '
      'colour. Assert on the individual spans instead.',
    );
  }
  final color = span.style?.color;
  if (color == null) {
    fail(
      'No resolved colour on ${textFinder.describeMatch(Plurality.one)}; '
      'RenderParagraph.text.style was ${span.style}',
    );
  }
  return color;
}

/// The opaque colour painted behind [finder], composited from every painted
/// ancestor layer up to and including the first opaque one.
///
/// Necessary because tinted containers carry alpha: measuring contrast against
/// a declared `Color(0x38...)` would report a falsely comfortable ratio.
///
/// Throws rather than guessing when the stack cannot be resolved - a helper
/// that silently substitutes white would turn this whole suite into a source
/// of false greens.
Color resolvedBackgroundBehind(WidgetTester tester, Finder finder) {
  final element = tester.element(finder);
  final layers = <Color>[];
  var foundOpaque = false;

  void collect(Color? color) {
    if (color == null || color.a == 0) return;
    layers.add(color);
    if (color.a == 1.0) foundOpaque = true;
  }

  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    switch (widget) {
      case final ColoredBox box:
        collect(box.color);
      case final DecoratedBox box:
        collect(_backgroundOf(box.decoration, finder));
      case final Container container:
        collect(container.color ?? _backgroundOf(container.decoration, finder));
      case final Card card:
        final theme = Theme.of(ancestor);
        collect(card.color ?? theme.cardTheme.color ?? theme.cardColor);
      case final Material material:
        collect(
          material.color ??
              (material.type == MaterialType.canvas
                  ? Theme.of(ancestor).canvasColor
                  : null),
        );
      case final Scaffold scaffold:
        collect(
          scaffold.backgroundColor ??
              Theme.of(ancestor).scaffoldBackgroundColor,
        );
    }
    // Everything above the first opaque layer is invisible.
    return !foundOpaque;
  });

  if (!foundOpaque) {
    throw StateError(
      'No opaque background found behind ${finder.describeMatch(Plurality.one)}. Translucent '
      'layers seen: ${layers.map(describeColor).join(", ")}. Pump the widget '
      'inside a Scaffold or an opaque container so the painted colour is '
      'determinate.',
    );
  }
  return flattenLayers(layers.reversed.toList());
}

Color? _backgroundOf(Decoration? decoration, Finder finder) {
  if (decoration == null) return null;
  if (decoration is! BoxDecoration) return null;
  if (decoration.gradient != null || decoration.image != null) {
    throw StateError(
      'The background behind ${finder.describeMatch(Plurality.one)} is a gradient or image, so '
      'it has no single contrast value. Assert on the specific stops instead '
      'of using resolvedBackgroundBehind.',
    );
  }
  return decoration.color;
}

/// Asserts the text matched by [textFinder] is legible against the colour
/// actually painted behind it.
void expectLegibleText(
  WidgetTester tester,
  Finder textFinder, {
  required String because,
  double atLeast = wcagAaNormalText,
}) {
  final foreground = resolvedTextColor(tester, textFinder);
  final background = resolvedBackgroundBehind(tester, textFinder);
  expectContrast(foreground, background, atLeast: atLeast, because: because);
}

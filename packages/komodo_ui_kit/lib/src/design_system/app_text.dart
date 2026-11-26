import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/src/design_system/app_palette.dart';

/// The app's type scale, relative to the ambient text theme so the user's
/// text scaling applies. Colours come from [AppPalette].
abstract final class AppText {
  static TextStyle _base(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium ?? const TextStyle();

  /// Page title: "Swap", "Activity", "Review swap".
  static TextStyle title(BuildContext context) => _base(context).copyWith(
    fontSize: 28,
    height: 1.15,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.4,
    color: AppPalette.of(context).text,
  );

  /// Sheet and hero headings.
  static TextStyle heading(BuildContext context) => _base(context).copyWith(
    fontSize: 20,
    height: 1.25,
    fontWeight: FontWeight.w800,
    color: AppPalette.of(context).text,
  );

  /// The large amount in an amount card.
  static TextStyle amount(BuildContext context) => _base(context).copyWith(
    fontSize: 32,
    height: 1.12,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.1,
    color: AppPalette.of(context).text,
  );

  /// Body copy.
  static TextStyle body(BuildContext context) => _base(context).copyWith(
    fontSize: 15,
    height: 1.45,
    color: AppPalette.of(context).textSecondary,
  );

  /// Emphasised body copy.
  static TextStyle strong(BuildContext context) => _base(context).copyWith(
    fontSize: 15,
    height: 1.35,
    fontWeight: FontWeight.w700,
    color: AppPalette.of(context).text,
  );

  /// Secondary labels and helper lines.
  static TextStyle small(BuildContext context) => _base(context).copyWith(
    fontSize: 13,
    height: 1.4,
    color: AppPalette.of(context).textTertiary,
  );

  /// Upper-case eyebrow labels ("WHAT HAPPENED?").
  static TextStyle eyebrow(BuildContext context) => _base(context).copyWith(
    fontSize: 11,
    height: 1.3,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.8,
    color: AppPalette.of(context).textTertiary,
  );

  /// Monospace for addresses, hashes and ids.
  static TextStyle code(BuildContext context) => _base(context).copyWith(
    fontSize: 13,
    height: 1.4,
    fontFamily: 'monospace',
    fontFamilyFallback: const ['Courier New', 'Courier'],
    color: AppPalette.of(context).text,
  );

  /// How wide a [Text] of [text] in [style] sets on one line here, or, with
  /// [longestWord], how wide its longest unbreakable run is.
  static double widthOf(
    BuildContext context,
    String text,
    TextStyle style, {
    bool longestWord = false,
  }) {
    final painter = _painter(context, TextSpan(text: text), style)..layout();
    final width = longestWord
        ? painter.minIntrinsicWidth
        : painter.maxIntrinsicWidth;
    painter.dispose();
    return width;
  }

  /// How tall a [Text] of [span] in [style] sets here when it wraps at
  /// [maxWidth], for reserving its room before it is shown.
  static double heightOf(
    BuildContext context,
    InlineSpan span,
    TextStyle style, {
    double maxWidth = double.infinity,
  }) {
    final painter = _painter(context, span, style)..layout(maxWidth: maxWidth);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  static TextPainter _painter(
    BuildContext context,
    InlineSpan span,
    TextStyle style,
  ) {
    // The adjustments Text.build makes before it lays the text out.
    var effective = style.inherit
        ? DefaultTextStyle.of(context).style.merge(style)
        : style;
    if (MediaQuery.boldTextOf(context)) {
      effective = effective.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    effective = effective.copyWith(
      letterSpacing: MediaQuery.maybeLetterSpacingOverrideOf(context),
      wordSpacing: MediaQuery.maybeWordSpacingOverrideOf(context),
    );
    return TextPainter(
      text: TextSpan(style: effective, children: [span]),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    );
  }
}

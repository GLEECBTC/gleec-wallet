import 'package:flutter/material.dart';

/// The swap surface's colour tokens, from the unified swap design spec.
///
/// The swap surface is designed against one token set in both themes rather
/// than the app's Material roles, because its status colours (success,
/// warning, pending, danger, info) each come as a foreground and background
/// pair that Material has no roles for. The surfaces match `new_theme`.
@immutable
class SwapPalette {
  const SwapPalette._({
    required this.brand,
    required this.brandHover,
    required this.brandPressed,
    required this.onBrand,
    required this.success,
    required this.successBg,
    required this.warning,
    required this.warningBg,
    required this.pending,
    required this.pendingBg,
    required this.danger,
    required this.dangerBg,
    required this.info,
    required this.infoBg,
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceHigh,
    required this.surfaceHighest,
    required this.selected,
    required this.text,
    required this.textSecondary,
    required this.textTertiary,
    required this.border,
    required this.borderStrong,
    required this.controlBorder,
    required this.shadow,
  });

  static const dark = SwapPalette._(
    brand: Color(0xFF8C41FF),
    brandHover: Color(0xFFA162FF),
    brandPressed: Color(0xFF7530E3),
    onBrand: Color(0xFFFFFFFF),
    success: Color(0xFF62DD98),
    successBg: Color(0xFF0B3B26),
    warning: Color(0xFFF3C95F),
    warningBg: Color(0xFF3A2D06),
    pending: Color(0xFFFF9B5A),
    pendingBg: Color(0xFF3B210F),
    danger: Color(0xFFFF7AAA),
    dangerBg: Color(0xFF441526),
    info: Color(0xFF82B1FF),
    infoBg: Color(0xFF102A4F),
    canvas: Color(0xFF0A0C15),
    surface: Color(0xFF0F1221),
    surfaceRaised: Color(0xFF171A2C),
    surfaceHigh: Color(0xFF202337),
    surfaceHighest: Color(0xFF24273D),
    selected: Color(0xFF2E145C),
    text: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFD7DAE7),
    textTertiary: Color(0xFFAEB5CF),
    border: Color(0xFF30344D),
    borderStrong: Color(0xFF4E5575),
    controlBorder: Color(0xFF747A9B),
    shadow: Color(0x66000000),
  );

  static const light = SwapPalette._(
    brand: Color(0xFF8C41FF),
    brandHover: Color(0xFF6F22DC),
    brandPressed: Color(0xFF6821D3),
    onBrand: Color(0xFFFFFFFF),
    success: Color(0xFF006B32),
    successBg: Color(0xFFDFF8EA),
    warning: Color(0xFF745000),
    warningBg: Color(0xFFFFF5D6),
    pending: Color(0xFF9C3D00),
    pendingBg: Color(0xFFFFF0E4),
    danger: Color(0xFFA80E45),
    dangerBg: Color(0xFFFFE7F0),
    info: Color(0xFF1D559E),
    infoBg: Color(0xFFE6F0FF),
    canvas: Color(0xFFFAFAFD),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFF5F5FA),
    surfaceHighest: Color(0xFFEBEDF5),
    selected: Color(0xFFF6EEFF),
    text: Color(0xFF0A0C15),
    textSecondary: Color(0xFF4E5575),
    textTertiary: Color(0xFF555F80),
    border: Color(0xFFD7DAE7),
    borderStrong: Color(0xFFB0B6CE),
    controlBorder: Color(0xFF767C96),
    shadow: Color(0x1F1A1E32),
  );

  /// The palette for the ambient theme's brightness.
  static SwapPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? light : dark;

  final Color brand;
  final Color brandHover;
  final Color brandPressed;
  final Color onBrand;
  final Color success;
  final Color successBg;
  final Color warning;
  final Color warningBg;
  final Color pending;
  final Color pendingBg;
  final Color danger;
  final Color dangerBg;
  final Color info;
  final Color infoBg;
  final Color canvas;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceHigh;
  final Color surfaceHighest;
  final Color selected;
  final Color text;
  final Color textSecondary;
  final Color textTertiary;
  final Color border;
  final Color borderStrong;
  final Color controlBorder;
  final Color shadow;

  /// The foreground of [tone].
  Color toneColor(SwapTone tone) => switch (tone) {
    SwapTone.neutral => textSecondary,
    SwapTone.brand => text,
    SwapTone.success => success,
    SwapTone.warning => warning,
    SwapTone.pending => pending,
    SwapTone.danger => danger,
    SwapTone.info => info,
  };

  /// The background of [tone].
  Color toneBackground(SwapTone tone) => switch (tone) {
    SwapTone.neutral => surfaceHigh,
    SwapTone.brand => selected,
    SwapTone.success => successBg,
    SwapTone.warning => warningBg,
    SwapTone.pending => pendingBg,
    SwapTone.danger => dangerBg,
    SwapTone.info => infoBg,
  };

  /// The border of [tone].
  Color toneBorder(SwapTone tone) => switch (tone) {
    SwapTone.neutral => border,
    SwapTone.brand => brand,
    SwapTone.success => success,
    SwapTone.warning => warning,
    SwapTone.pending => pending,
    SwapTone.danger => danger,
    SwapTone.info => info,
  };
}

/// The status tones used by badges, callouts and icons.
enum SwapTone { neutral, brand, success, warning, pending, danger, info }

/// Type scale for the swap surface, relative to the ambient text theme so the
/// user's text scaling applies.
abstract final class SwapText {
  static TextStyle _base(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium ?? const TextStyle();

  /// Page title: "Swap", "Activity", "Review swap".
  static TextStyle title(BuildContext context) => _base(context).copyWith(
    fontSize: 28,
    height: 1.15,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.4,
    color: SwapPalette.of(context).text,
  );

  /// Sheet and hero headings.
  static TextStyle heading(BuildContext context) => _base(context).copyWith(
    fontSize: 20,
    height: 1.25,
    fontWeight: FontWeight.w800,
    color: SwapPalette.of(context).text,
  );

  /// The large amount in an amount card.
  static TextStyle amount(BuildContext context) => _base(context).copyWith(
    fontSize: 32,
    height: 1.12,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.1,
    color: SwapPalette.of(context).text,
  );

  /// Body copy.
  static TextStyle body(BuildContext context) => _base(context).copyWith(
    fontSize: 15,
    height: 1.45,
    color: SwapPalette.of(context).textSecondary,
  );

  /// Emphasised body copy.
  static TextStyle strong(BuildContext context) => _base(context).copyWith(
    fontSize: 15,
    height: 1.35,
    fontWeight: FontWeight.w700,
    color: SwapPalette.of(context).text,
  );

  /// Secondary labels and helper lines.
  static TextStyle small(BuildContext context) => _base(context).copyWith(
    fontSize: 13,
    height: 1.4,
    color: SwapPalette.of(context).textTertiary,
  );

  /// Upper-case eyebrow labels ("WHAT HAPPENED?").
  static TextStyle eyebrow(BuildContext context) => _base(context).copyWith(
    fontSize: 11,
    height: 1.3,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.8,
    color: SwapPalette.of(context).textTertiary,
  );

  /// Monospace for addresses, hashes and ids.
  static TextStyle code(BuildContext context) => _base(context).copyWith(
    fontSize: 13,
    height: 1.4,
    fontFamily: 'monospace',
    fontFamilyFallback: const ['Courier New', 'Courier'],
    color: SwapPalette.of(context).text,
  );

  /// How wide a [Text] of [text] in [style] sets on one line here, or, with
  /// [longestWord], how wide its longest unbreakable run is.
  static double widthOf(
    BuildContext context,
    String text,
    TextStyle style, {
    bool longestWord = false,
  }) {
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
    final painter = TextPainter(
      text: TextSpan(text: text, style: effective),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    )..layout();
    final width = longestWord
        ? painter.minIntrinsicWidth
        : painter.maxIntrinsicWidth;
    painter.dispose();
    return width;
  }
}

/// Shared geometry.
abstract final class SwapGeometry {
  /// The readable column width of every swap screen.
  static const contentWidth = 576.0;

  /// The width of a side panel on a wide screen.
  static const panelWidth = 520.0;

  /// Width from which review and pickers open beside the form, not over it.
  static const sidePanelBreakpoint = 960.0;

  /// The minimum interactive size.
  static const touchTarget = 48.0;
}

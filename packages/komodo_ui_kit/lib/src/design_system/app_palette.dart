import 'package:flutter/material.dart';

/// The app's colour tokens, from the unified design spec that Swap
/// introduced and the wallet home, coin page, Buy and Settings share.
///
/// Screens are designed against one token set in both themes rather than
/// the app's Material roles, because the status colours (success, warning,
/// pending, danger, info) each come as a foreground and background pair that
/// Material has no roles for. Screens whose widgets still read Material roles
/// get these tokens through `AppPaletteScope`.
///
/// Every text token clears 4.5:1 on every surface token in its theme. [brand]
/// does not as text on dark surfaces; brand-coloured text uses [brandHover],
/// on [canvas], [surface] or [surfaceRaised].
@immutable
class AppPalette {
  const AppPalette._({
    required this.brand,
    required this.brandHover,
    required this.brandPressed,
    required this.onBrand,
    required this.disabled,
    required this.onDisabled,
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

  static const dark = AppPalette._(
    brand: Color(0xFF8C41FF),
    brandHover: Color(0xFFA162FF),
    brandPressed: Color(0xFF7530E3),
    onBrand: Color(0xFFFFFFFF),
    disabled: Color(0xFF24273D),
    onDisabled: Color(0xFFAEB5CF),
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

  static const light = AppPalette._(
    brand: Color(0xFF8C41FF),
    brandHover: Color(0xFF6F22DC),
    brandPressed: Color(0xFF6821D3),
    onBrand: Color(0xFFFFFFFF),
    disabled: Color(0xFFEBEDF5),
    onDisabled: Color(0xFF4E5575),
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
  static AppPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? light : dark;

  final Color brand;
  final Color brandHover;
  final Color brandPressed;
  final Color onBrand;

  /// A control that cannot be used yet, and its label. The label is often
  /// the form's status, so the pair keeps text contrast (4.5:1) in both
  /// themes rather than fading the enabled colours.
  final Color disabled;
  final Color onDisabled;
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
  Color toneColor(AppTone tone) => switch (tone) {
    AppTone.neutral => textSecondary,
    AppTone.brand => text,
    AppTone.success => success,
    AppTone.warning => warning,
    AppTone.pending => pending,
    AppTone.danger => danger,
    AppTone.info => info,
  };

  /// The background of [tone].
  Color toneBackground(AppTone tone) => switch (tone) {
    AppTone.neutral => surfaceHigh,
    AppTone.brand => selected,
    AppTone.success => successBg,
    AppTone.warning => warningBg,
    AppTone.pending => pendingBg,
    AppTone.danger => dangerBg,
    AppTone.info => infoBg,
  };

  /// The border of [tone].
  Color toneBorder(AppTone tone) => switch (tone) {
    AppTone.neutral => border,
    AppTone.brand => brand,
    AppTone.success => success,
    AppTone.warning => warning,
    AppTone.pending => pending,
    AppTone.danger => danger,
    AppTone.info => info,
  };
}

/// The status tones used by badges, callouts and icons.
enum AppTone { neutral, brand, success, warning, pending, danger, info }

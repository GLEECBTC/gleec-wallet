import 'package:flutter/material.dart';

/// Calm Core's semantic color contract.
///
/// These values mirror the approved Unified Swap prototype. Widgets should
/// consume semantic roles from this extension (or the Material [ColorScheme]
/// derived from it) instead of introducing feature-local color constants.
@immutable
class GleecColorTokens extends ThemeExtension<GleecColorTokens> {
  const GleecColorTokens({
    required this.brand,
    required this.brandHover,
    required this.brandPressed,
    required this.success,
    required this.warning,
    required this.pending,
    required this.danger,
    required this.info,
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceHigh,
    required this.surfaceHighest,
    required this.selected,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.border,
    required this.borderStrong,
    required this.controlBorder,
    required this.successContainer,
    required this.warningContainer,
    required this.pendingContainer,
    required this.dangerContainer,
    required this.infoContainer,
    required this.shadow,
  });

  static const GleecColorTokens dark = GleecColorTokens(
    brand: Color(0xFF8C41FF),
    brandHover: Color(0xFFA162FF),
    brandPressed: Color(0xFF7530E3),
    success: Color(0xFF62DD98),
    warning: Color(0xFFF3C95F),
    pending: Color(0xFFFF9B5A),
    danger: Color(0xFFFF7AAA),
    info: Color(0xFF82B1FF),
    canvas: Color(0xFF0A0C15),
    surface: Color(0xFF0F1221),
    surfaceRaised: Color(0xFF171A2C),
    surfaceHigh: Color(0xFF202337),
    surfaceHighest: Color(0xFF24273D),
    selected: Color(0xFF2E145C),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFD7DAE7),
    textTertiary: Color(0xFFAEB5CF),
    border: Color(0xFF30344D),
    borderStrong: Color(0xFF4E5575),
    controlBorder: Color(0xFF747A9B),
    successContainer: Color(0xFF0B3B26),
    warningContainer: Color(0xFF3A2D06),
    pendingContainer: Color(0xFF3B210F),
    dangerContainer: Color(0xFF441526),
    infoContainer: Color(0xFF102A4F),
    shadow: Color(0x52000000),
  );

  static const GleecColorTokens light = GleecColorTokens(
    brand: Color(0xFF8C41FF),
    brandHover: Color(0xFF6F22DC),
    brandPressed: Color(0xFF6821D3),
    success: Color(0xFF006B32),
    warning: Color(0xFF745000),
    pending: Color(0xFF9C3D00),
    danger: Color(0xFFA80E45),
    info: Color(0xFF1D559E),
    canvas: Color(0xFFFAFAFD),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFF5F5FA),
    surfaceHighest: Color(0xFFEBEDF5),
    selected: Color(0xFFF6EEFF),
    textPrimary: Color(0xFF0A0C15),
    textSecondary: Color(0xFF4E5575),
    textTertiary: Color(0xFF555F80),
    border: Color(0xFFD7DAE7),
    borderStrong: Color(0xFFB0B6CE),
    controlBorder: Color(0xFF767C96),
    successContainer: Color(0xFFDFF8EA),
    warningContainer: Color(0xFFFFF5D6),
    pendingContainer: Color(0xFFFFF0E4),
    dangerContainer: Color(0xFFFFE7F0),
    infoContainer: Color(0xFFE6F0FF),
    shadow: Color(0x1F1A1E32),
  );

  static GleecColorTokens of(BuildContext context) {
    final tokens = Theme.of(context).extension<GleecColorTokens>();
    assert(tokens != null, 'GleecColorTokens not found in ThemeData');
    return tokens!;
  }

  final Color brand;
  final Color brandHover;
  final Color brandPressed;
  final Color success;
  final Color warning;
  final Color pending;
  final Color danger;
  final Color info;
  final Color canvas;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceHigh;
  final Color surfaceHighest;
  final Color selected;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color border;
  final Color borderStrong;
  final Color controlBorder;
  final Color successContainer;
  final Color warningContainer;
  final Color pendingContainer;
  final Color dangerContainer;
  final Color infoContainer;
  final Color shadow;

  @override
  GleecColorTokens copyWith({
    Color? brand,
    Color? brandHover,
    Color? brandPressed,
    Color? success,
    Color? warning,
    Color? pending,
    Color? danger,
    Color? info,
    Color? canvas,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceHigh,
    Color? surfaceHighest,
    Color? selected,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? border,
    Color? borderStrong,
    Color? controlBorder,
    Color? successContainer,
    Color? warningContainer,
    Color? pendingContainer,
    Color? dangerContainer,
    Color? infoContainer,
    Color? shadow,
  }) {
    return GleecColorTokens(
      brand: brand ?? this.brand,
      brandHover: brandHover ?? this.brandHover,
      brandPressed: brandPressed ?? this.brandPressed,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      pending: pending ?? this.pending,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      surfaceHighest: surfaceHighest ?? this.surfaceHighest,
      selected: selected ?? this.selected,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      controlBorder: controlBorder ?? this.controlBorder,
      successContainer: successContainer ?? this.successContainer,
      warningContainer: warningContainer ?? this.warningContainer,
      pendingContainer: pendingContainer ?? this.pendingContainer,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      infoContainer: infoContainer ?? this.infoContainer,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  GleecColorTokens lerp(GleecColorTokens? other, double t) {
    if (other == null) return this;
    return GleecColorTokens(
      brand: Color.lerp(brand, other.brand, t)!,
      brandHover: Color.lerp(brandHover, other.brandHover, t)!,
      brandPressed: Color.lerp(brandPressed, other.brandPressed, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      pending: Color.lerp(pending, other.pending, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      surfaceHighest: Color.lerp(surfaceHighest, other.surfaceHighest, t)!,
      selected: Color.lerp(selected, other.selected, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      controlBorder: Color.lerp(controlBorder, other.controlBorder, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      pendingContainer: Color.lerp(
        pendingContainer,
        other.pendingContainer,
        t,
      )!,
      dangerContainer: Color.lerp(dangerContainer, other.dangerContainer, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

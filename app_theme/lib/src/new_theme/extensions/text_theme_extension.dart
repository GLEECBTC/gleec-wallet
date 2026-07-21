import 'package:flutter/material.dart';

import '../../calm_core/gleec_typography.dart';

/// Deprecated compatibility scale for screens awaiting Calm Core migration.
class TextThemeExtension extends ThemeExtension<TextThemeExtension> {
  TextThemeExtension({required Color textColor})
    : this._(
        heading1: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
        heading2: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
        bodyM: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 16,
          color: textColor,
          fontWeight: FontWeight.w500,
        ),
        bodyMBold: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
        bodyS: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: textColor,
        ),
        bodySBold: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
        bodyXS: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: textColor,
        ),
        bodyXSBold: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
        bodyXXS: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: textColor,
        ),
        bodyXXSBold: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      );

  TextThemeExtension._({
    required this.heading1,
    required this.heading2,
    required this.bodyM,
    required this.bodyMBold,
    required this.bodyS,
    required this.bodySBold,
    required this.bodyXS,
    required this.bodyXSBold,
    required this.bodyXXS,
    required this.bodyXXSBold,
  });

  factory TextThemeExtension.fromCalmCore(GleecTypography typography) {
    return TextThemeExtension._(
      heading1: typography.pageTitle,
      heading2: typography.sectionTitle,
      bodyM: typography.bodyLarge.copyWith(fontWeight: FontWeight.w500),
      bodyMBold: typography.bodyLarge.copyWith(fontWeight: FontWeight.w700),
      bodyS: typography.bodyMedium,
      bodySBold: typography.bodyMedium.copyWith(fontWeight: FontWeight.w700),
      bodyXS: typography.bodySmall,
      bodyXSBold: typography.bodySmall.copyWith(fontWeight: FontWeight.w700),
      bodyXXS: typography.labelSmall.copyWith(fontWeight: FontWeight.w500),
      bodyXXSBold: typography.labelSmall,
    );
  }

  static TextThemeExtension of(BuildContext context) {
    final textTheme = Theme.of(context).extension<TextThemeExtension>();
    assert(textTheme != null, 'TextThemeExtension not found in context');
    return textTheme!;
  }

  final TextStyle heading1;
  final TextStyle heading2;
  final TextStyle bodyM;
  final TextStyle bodyMBold;
  final TextStyle bodyS;
  final TextStyle bodySBold;
  final TextStyle bodyXS;
  final TextStyle bodyXSBold;
  final TextStyle bodyXXS;
  final TextStyle bodyXXSBold;

  @override
  TextThemeExtension copyWith({
    TextStyle? heading1,
    TextStyle? heading2,
    TextStyle? bodyM,
    TextStyle? bodyMBold,
    TextStyle? bodyS,
    TextStyle? bodySBold,
    TextStyle? bodyXS,
    TextStyle? bodyXSBold,
    TextStyle? bodyXXS,
    TextStyle? bodyXXSBold,
  }) {
    return TextThemeExtension._(
      heading1: heading1 ?? this.heading1,
      heading2: heading2 ?? this.heading2,
      bodyM: bodyM ?? this.bodyM,
      bodyMBold: bodyMBold ?? this.bodyMBold,
      bodyS: bodyS ?? this.bodyS,
      bodySBold: bodySBold ?? this.bodySBold,
      bodyXS: bodyXS ?? this.bodyXS,
      bodyXSBold: bodyXSBold ?? this.bodyXSBold,
      bodyXXS: bodyXXS ?? this.bodyXXS,
      bodyXXSBold: bodyXXSBold ?? this.bodyXXSBold,
    );
  }

  @override
  TextThemeExtension lerp(TextThemeExtension? other, double t) {
    if (other == null) return this;
    return TextThemeExtension._(
      heading1: TextStyle.lerp(heading1, other.heading1, t)!,
      heading2: TextStyle.lerp(heading2, other.heading2, t)!,
      bodyM: TextStyle.lerp(bodyM, other.bodyM, t)!,
      bodyMBold: TextStyle.lerp(bodyMBold, other.bodyMBold, t)!,
      bodyS: TextStyle.lerp(bodyS, other.bodyS, t)!,
      bodySBold: TextStyle.lerp(bodySBold, other.bodySBold, t)!,
      bodyXS: TextStyle.lerp(bodyXS, other.bodyXS, t)!,
      bodyXSBold: TextStyle.lerp(bodyXSBold, other.bodyXSBold, t)!,
      bodyXXS: TextStyle.lerp(bodyXXS, other.bodyXXS, t)!,
      bodyXXSBold: TextStyle.lerp(bodyXXSBold, other.bodyXXSBold, t)!,
    );
  }
}

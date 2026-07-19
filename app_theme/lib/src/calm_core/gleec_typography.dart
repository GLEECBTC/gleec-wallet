import 'package:flutter/material.dart';

import 'gleec_color_tokens.dart';

/// Calm Core's Manrope type scale.
@immutable
class GleecTypography extends ThemeExtension<GleecTypography> {
  const GleecTypography({
    required this.amountDisplay,
    required this.pageTitle,
    required this.sectionTitle,
    required this.cardTitle,
    required this.bodyLarge,
    required this.bodyMedium,
    required this.bodySmall,
    required this.labelLarge,
    required this.labelMedium,
    required this.labelSmall,
    required this.tabularAmount,
    required this.tabularAmountCompact,
  });

  factory GleecTypography.fromColors(GleecColorTokens colors) {
    const tabular = <FontFeature>[FontFeature.tabularFigures()];
    return GleecTypography(
      amountDisplay: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 38.4,
        height: 1.15,
        letterSpacing: -1.344,
        fontWeight: FontWeight.w800,
        color: colors.textPrimary,
        fontFeatures: tabular,
      ),
      pageTitle: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 32,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: colors.textPrimary,
      ),
      sectionTitle: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 24,
        height: 1.35,
        fontWeight: FontWeight.w700,
        color: colors.textPrimary,
      ),
      cardTitle: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 18,
        height: 1.35,
        fontWeight: FontWeight.w700,
        color: colors.textPrimary,
      ),
      bodyLarge: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 16,
        height: 1.5,
        fontWeight: FontWeight.w400,
        color: colors.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 14,
        height: 1.5,
        fontWeight: FontWeight.w500,
        color: colors.textSecondary,
      ),
      bodySmall: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 12,
        height: 1.5,
        fontWeight: FontWeight.w500,
        color: colors.textTertiary,
      ),
      labelLarge: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 14,
        height: 1.35,
        fontWeight: FontWeight.w700,
        color: colors.textPrimary,
      ),
      labelMedium: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 12,
        height: 1.35,
        fontWeight: FontWeight.w700,
        color: colors.textSecondary,
      ),
      labelSmall: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 10,
        height: 1.35,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
        color: colors.textTertiary,
      ),
      tabularAmount: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 24,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: colors.textPrimary,
        fontFeatures: tabular,
      ),
      tabularAmountCompact: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 14,
        height: 1.35,
        fontWeight: FontWeight.w700,
        color: colors.textPrimary,
        fontFeatures: tabular,
      ),
    );
  }

  static GleecTypography of(BuildContext context) {
    final tokens = Theme.of(context).extension<GleecTypography>();
    assert(tokens != null, 'GleecTypography not found in ThemeData');
    return tokens!;
  }

  final TextStyle amountDisplay;
  final TextStyle pageTitle;
  final TextStyle sectionTitle;
  final TextStyle cardTitle;
  final TextStyle bodyLarge;
  final TextStyle bodyMedium;
  final TextStyle bodySmall;
  final TextStyle labelLarge;
  final TextStyle labelMedium;
  final TextStyle labelSmall;
  final TextStyle tabularAmount;
  final TextStyle tabularAmountCompact;

  TextTheme toMaterialTextTheme() => TextTheme(
    displaySmall: amountDisplay,
    headlineSmall: pageTitle,
    titleLarge: sectionTitle,
    titleMedium: cardTitle,
    titleSmall: labelLarge,
    bodyLarge: bodyLarge,
    bodyMedium: bodyMedium,
    bodySmall: bodySmall,
    labelLarge: labelLarge,
    labelMedium: labelMedium,
    labelSmall: labelSmall,
  );

  @override
  GleecTypography copyWith({
    TextStyle? amountDisplay,
    TextStyle? pageTitle,
    TextStyle? sectionTitle,
    TextStyle? cardTitle,
    TextStyle? bodyLarge,
    TextStyle? bodyMedium,
    TextStyle? bodySmall,
    TextStyle? labelLarge,
    TextStyle? labelMedium,
    TextStyle? labelSmall,
    TextStyle? tabularAmount,
    TextStyle? tabularAmountCompact,
  }) {
    return GleecTypography(
      amountDisplay: amountDisplay ?? this.amountDisplay,
      pageTitle: pageTitle ?? this.pageTitle,
      sectionTitle: sectionTitle ?? this.sectionTitle,
      cardTitle: cardTitle ?? this.cardTitle,
      bodyLarge: bodyLarge ?? this.bodyLarge,
      bodyMedium: bodyMedium ?? this.bodyMedium,
      bodySmall: bodySmall ?? this.bodySmall,
      labelLarge: labelLarge ?? this.labelLarge,
      labelMedium: labelMedium ?? this.labelMedium,
      labelSmall: labelSmall ?? this.labelSmall,
      tabularAmount: tabularAmount ?? this.tabularAmount,
      tabularAmountCompact: tabularAmountCompact ?? this.tabularAmountCompact,
    );
  }

  @override
  GleecTypography lerp(GleecTypography? other, double t) {
    if (other == null) return this;
    return GleecTypography(
      amountDisplay: TextStyle.lerp(amountDisplay, other.amountDisplay, t)!,
      pageTitle: TextStyle.lerp(pageTitle, other.pageTitle, t)!,
      sectionTitle: TextStyle.lerp(sectionTitle, other.sectionTitle, t)!,
      cardTitle: TextStyle.lerp(cardTitle, other.cardTitle, t)!,
      bodyLarge: TextStyle.lerp(bodyLarge, other.bodyLarge, t)!,
      bodyMedium: TextStyle.lerp(bodyMedium, other.bodyMedium, t)!,
      bodySmall: TextStyle.lerp(bodySmall, other.bodySmall, t)!,
      labelLarge: TextStyle.lerp(labelLarge, other.labelLarge, t)!,
      labelMedium: TextStyle.lerp(labelMedium, other.labelMedium, t)!,
      labelSmall: TextStyle.lerp(labelSmall, other.labelSmall, t)!,
      tabularAmount: TextStyle.lerp(tabularAmount, other.tabularAmount, t)!,
      tabularAmountCompact: TextStyle.lerp(
        tabularAmountCompact,
        other.tabularAmountCompact,
        t,
      )!,
    );
  }
}

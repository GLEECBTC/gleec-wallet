import 'package:flutter/material.dart';

import '../../calm_core/gleec_color_tokens.dart';

/// Deprecated compatibility palette for first-party screens that have not yet
/// moved to [GleecColorTokens] or Material [ColorScheme] roles.
class ColorSchemeExtension extends ThemeExtension<ColorSchemeExtension> {
  const ColorSchemeExtension({
    required this.primary,
    required this.p50,
    required this.p40,
    required this.p10,
    required this.secondary,
    required this.s70,
    required this.s50,
    required this.s40,
    required this.s30,
    required this.s20,
    required this.s10,
    required this.surf,
    required this.surfContHighest,
    required this.surfContHigh,
    required this.surfCont,
    required this.surfContLow,
    required this.surfContLowest,
    required this.error,
    required this.e50,
    required this.e20,
    required this.e10,
    required this.green,
    required this.g20,
    required this.g10,
    required this.orange,
    required this.yellow,
    required this.purple,
  });

  factory ColorSchemeExtension.fromCalmCore(GleecColorTokens colors) {
    return ColorSchemeExtension(
      primary: colors.brand,
      p50: colors.brandHover,
      p40: colors.brandPressed,
      p10: colors.selected,
      secondary: colors.textSecondary,
      s70: colors.textTertiary,
      s50: colors.controlBorder,
      s40: colors.borderStrong,
      s30: colors.border,
      s20: colors.surfaceHighest,
      s10: colors.surfaceHigh,
      surf: colors.surface,
      surfContHighest: colors.surfaceHighest,
      surfContHigh: colors.surfaceHigh,
      surfCont: colors.surfaceRaised,
      surfContLow: colors.surface,
      surfContLowest: colors.canvas,
      error: colors.danger,
      e50: colors.danger,
      e20: colors.dangerContainer,
      e10: colors.dangerContainer,
      green: colors.success,
      g20: colors.successContainer,
      g10: colors.successContainer,
      orange: colors.pending,
      yellow: colors.warning,
      purple: colors.brand,
    );
  }

  static ColorSchemeExtension of(BuildContext context) {
    final extension = Theme.of(context).extension<ColorSchemeExtension>();
    assert(extension != null, 'ColorSchemeExtension not found in ThemeData');
    return extension!;
  }

  final Color primary;
  final Color p50;
  final Color p40;
  final Color p10;
  final Color secondary;
  final Color s70;
  final Color s50;
  final Color s40;
  final Color s30;
  final Color s20;
  final Color s10;
  final Color surf;
  final Color surfContHighest;
  final Color surfContHigh;
  final Color surfCont;
  final Color surfContLow;
  final Color surfContLowest;
  final Color error;
  final Color e50;
  final Color e20;
  final Color e10;
  final Color green;
  final Color g20;
  final Color g10;
  final Color orange;
  final Color yellow;
  final Color purple;

  @override
  ColorSchemeExtension copyWith({
    Color? primary,
    Color? p50,
    Color? p40,
    Color? p10,
    Color? secondary,
    Color? s70,
    Color? s50,
    Color? s40,
    Color? s30,
    Color? s20,
    Color? s10,
    Color? surf,
    Color? surfContHighest,
    Color? surfContHigh,
    Color? surfCont,
    Color? surfContLow,
    Color? surfContLowest,
    Color? error,
    Color? e50,
    Color? e20,
    Color? e10,
    Color? green,
    Color? g20,
    Color? g10,
    Color? orange,
    Color? yellow,
    Color? purple,
  }) {
    return ColorSchemeExtension(
      primary: primary ?? this.primary,
      p50: p50 ?? this.p50,
      p40: p40 ?? this.p40,
      p10: p10 ?? this.p10,
      secondary: secondary ?? this.secondary,
      s70: s70 ?? this.s70,
      s50: s50 ?? this.s50,
      s40: s40 ?? this.s40,
      s30: s30 ?? this.s30,
      s20: s20 ?? this.s20,
      s10: s10 ?? this.s10,
      surf: surf ?? this.surf,
      surfContHighest: surfContHighest ?? this.surfContHighest,
      surfContHigh: surfContHigh ?? this.surfContHigh,
      surfCont: surfCont ?? this.surfCont,
      surfContLow: surfContLow ?? this.surfContLow,
      surfContLowest: surfContLowest ?? this.surfContLowest,
      error: error ?? this.error,
      e50: e50 ?? this.e50,
      e20: e20 ?? this.e20,
      e10: e10 ?? this.e10,
      green: green ?? this.green,
      g20: g20 ?? this.g20,
      g10: g10 ?? this.g10,
      orange: orange ?? this.orange,
      yellow: yellow ?? this.yellow,
      purple: purple ?? this.purple,
    );
  }

  @override
  ColorSchemeExtension lerp(ColorSchemeExtension? other, double t) {
    if (other == null) return this;
    Color blend(Color from, Color to) => Color.lerp(from, to, t)!;
    return ColorSchemeExtension(
      primary: blend(primary, other.primary),
      p50: blend(p50, other.p50),
      p40: blend(p40, other.p40),
      p10: blend(p10, other.p10),
      secondary: blend(secondary, other.secondary),
      s70: blend(s70, other.s70),
      s50: blend(s50, other.s50),
      s40: blend(s40, other.s40),
      s30: blend(s30, other.s30),
      s20: blend(s20, other.s20),
      s10: blend(s10, other.s10),
      surf: blend(surf, other.surf),
      surfContHighest: blend(surfContHighest, other.surfContHighest),
      surfContHigh: blend(surfContHigh, other.surfContHigh),
      surfCont: blend(surfCont, other.surfCont),
      surfContLow: blend(surfContLow, other.surfContLow),
      surfContLowest: blend(surfContLowest, other.surfContLowest),
      error: blend(error, other.error),
      e50: blend(e50, other.e50),
      e20: blend(e20, other.e20),
      e10: blend(e10, other.e10),
      green: blend(green, other.green),
      g20: blend(g20, other.g20),
      g10: blend(g10, other.g10),
      orange: blend(orange, other.orange),
      yellow: blend(yellow, other.yellow),
      purple: blend(purple, other.purple),
    );
  }
}

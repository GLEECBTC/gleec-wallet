import 'dart:ui';

import 'package:flutter/material.dart';

import 'gleec_color_tokens.dart';

/// Calm Core's spacing, radius, focus, and elevation geometry.
@immutable
class GleecGeometry extends ThemeExtension<GleecGeometry> {
  const GleecGeometry({
    this.space4 = 4,
    this.space8 = 8,
    this.space12 = 12,
    this.space16 = 16,
    this.space20 = 20,
    this.space24 = 24,
    this.space32 = 32,
    this.radius12 = 12,
    this.radius16 = 16,
    this.radius20 = 20,
    this.radius24 = 24,
    this.minimumTapTarget = 48,
    this.inputHeight = 52,
    this.focusRingWidth = 3,
    this.focusRingOffset = 3,
    this.shadowBlurRadius = 48,
    this.shadowOffset = const Offset(0, 18),
  });

  static const GleecGeometry standard = GleecGeometry();

  static GleecGeometry of(BuildContext context) {
    final tokens = Theme.of(context).extension<GleecGeometry>();
    assert(tokens != null, 'GleecGeometry not found in ThemeData');
    return tokens!;
  }

  final double space4;
  final double space8;
  final double space12;
  final double space16;
  final double space20;
  final double space24;
  final double space32;
  final double radius12;
  final double radius16;
  final double radius20;
  final double radius24;
  final double minimumTapTarget;
  final double inputHeight;
  final double focusRingWidth;
  final double focusRingOffset;
  final double shadowBlurRadius;
  final Offset shadowOffset;

  BorderRadius get borderRadius12 => BorderRadius.circular(radius12);
  BorderRadius get borderRadius16 => BorderRadius.circular(radius16);
  BorderRadius get borderRadius20 => BorderRadius.circular(radius20);
  BorderRadius get borderRadius24 => BorderRadius.circular(radius24);

  List<BoxShadow> surfaceShadow(GleecColorTokens colors) => <BoxShadow>[
    BoxShadow(
      color: colors.shadow,
      blurRadius: shadowBlurRadius,
      offset: shadowOffset,
    ),
  ];

  @override
  GleecGeometry copyWith({
    double? space4,
    double? space8,
    double? space12,
    double? space16,
    double? space20,
    double? space24,
    double? space32,
    double? radius12,
    double? radius16,
    double? radius20,
    double? radius24,
    double? minimumTapTarget,
    double? inputHeight,
    double? focusRingWidth,
    double? focusRingOffset,
    double? shadowBlurRadius,
    Offset? shadowOffset,
  }) {
    return GleecGeometry(
      space4: space4 ?? this.space4,
      space8: space8 ?? this.space8,
      space12: space12 ?? this.space12,
      space16: space16 ?? this.space16,
      space20: space20 ?? this.space20,
      space24: space24 ?? this.space24,
      space32: space32 ?? this.space32,
      radius12: radius12 ?? this.radius12,
      radius16: radius16 ?? this.radius16,
      radius20: radius20 ?? this.radius20,
      radius24: radius24 ?? this.radius24,
      minimumTapTarget: minimumTapTarget ?? this.minimumTapTarget,
      inputHeight: inputHeight ?? this.inputHeight,
      focusRingWidth: focusRingWidth ?? this.focusRingWidth,
      focusRingOffset: focusRingOffset ?? this.focusRingOffset,
      shadowBlurRadius: shadowBlurRadius ?? this.shadowBlurRadius,
      shadowOffset: shadowOffset ?? this.shadowOffset,
    );
  }

  @override
  GleecGeometry lerp(GleecGeometry? other, double t) {
    if (other == null) return this;
    return GleecGeometry(
      space4: lerpDouble(space4, other.space4, t)!,
      space8: lerpDouble(space8, other.space8, t)!,
      space12: lerpDouble(space12, other.space12, t)!,
      space16: lerpDouble(space16, other.space16, t)!,
      space20: lerpDouble(space20, other.space20, t)!,
      space24: lerpDouble(space24, other.space24, t)!,
      space32: lerpDouble(space32, other.space32, t)!,
      radius12: lerpDouble(radius12, other.radius12, t)!,
      radius16: lerpDouble(radius16, other.radius16, t)!,
      radius20: lerpDouble(radius20, other.radius20, t)!,
      radius24: lerpDouble(radius24, other.radius24, t)!,
      minimumTapTarget: lerpDouble(
        minimumTapTarget,
        other.minimumTapTarget,
        t,
      )!,
      inputHeight: lerpDouble(inputHeight, other.inputHeight, t)!,
      focusRingWidth: lerpDouble(focusRingWidth, other.focusRingWidth, t)!,
      focusRingOffset: lerpDouble(focusRingOffset, other.focusRingOffset, t)!,
      shadowBlurRadius: lerpDouble(
        shadowBlurRadius,
        other.shadowBlurRadius,
        t,
      )!,
      shadowOffset: Offset.lerp(shadowOffset, other.shadowOffset, t)!,
    );
  }
}

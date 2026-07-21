import 'dart:ui';

import 'package:flutter/material.dart';

/// Calm Core's restrained, reduced-motion-aware transition contract.
@immutable
class GleecMotion extends ThemeExtension<GleecMotion> {
  const GleecMotion({
    this.fast = const Duration(milliseconds: 150),
    this.standard = const Duration(milliseconds: 220),
    this.deliberate = const Duration(milliseconds: 250),
    this.reduced = Duration.zero,
    this.standardCurve = Curves.easeOutCubic,
    this.emphasizedCurve = Curves.easeInOutCubic,
  });

  static const GleecMotion standardTokens = GleecMotion();

  static GleecMotion of(BuildContext context) {
    final tokens = Theme.of(context).extension<GleecMotion>();
    assert(tokens != null, 'GleecMotion not found in ThemeData');
    return tokens!;
  }

  final Duration fast;
  final Duration standard;
  final Duration deliberate;
  final Duration reduced;
  final Curve standardCurve;
  final Curve emphasizedCurve;

  Duration resolve(BuildContext context, Duration duration) {
    return MediaQuery.disableAnimationsOf(context) ? reduced : duration;
  }

  @override
  GleecMotion copyWith({
    Duration? fast,
    Duration? standard,
    Duration? deliberate,
    Duration? reduced,
    Curve? standardCurve,
    Curve? emphasizedCurve,
  }) {
    return GleecMotion(
      fast: fast ?? this.fast,
      standard: standard ?? this.standard,
      deliberate: deliberate ?? this.deliberate,
      reduced: reduced ?? this.reduced,
      standardCurve: standardCurve ?? this.standardCurve,
      emphasizedCurve: emphasizedCurve ?? this.emphasizedCurve,
    );
  }

  @override
  GleecMotion lerp(GleecMotion? other, double t) {
    if (other == null) return this;
    Duration interpolate(Duration from, Duration to) {
      return Duration(
        microseconds: lerpDouble(
          from.inMicroseconds.toDouble(),
          to.inMicroseconds.toDouble(),
          t,
        )!.round(),
      );
    }

    return GleecMotion(
      fast: interpolate(fast, other.fast),
      standard: interpolate(standard, other.standard),
      deliberate: interpolate(deliberate, other.deliberate),
      reduced: interpolate(reduced, other.reduced),
      standardCurve: t < 0.5 ? standardCurve : other.standardCurve,
      emphasizedCurve: t < 0.5 ? emphasizedCurve : other.emphasizedCurve,
    );
  }
}

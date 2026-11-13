import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// A mask for [BlendMode.dstIn] that fades out the edges of [bounds] with
/// content hidden past them, over [fadeWidth] (at most a third of the
/// width), as [TextOverflow.fade] fades a cut-off line.
///
/// [hiddenBefore] and [hiddenAfter] are how far content runs past the leading
/// and trailing edges; an edge with less than half a pixel hidden is not
/// faded.
Shader edgeFadeShader(
  Rect bounds, {
  required double hiddenBefore,
  required double hiddenAfter,
  required double fadeWidth,
}) {
  const opaque = Color(0xFFFFFFFF);
  const clear = Color(0x00FFFFFF);
  final fade = bounds.width <= 0
      ? 0.0
      : math.min(fadeWidth, bounds.width / 3) / bounds.width;
  return LinearGradient(
    colors: [
      if (hiddenBefore > 0.5) clear else opaque,
      opaque,
      opaque,
      if (hiddenAfter > 0.5) clear else opaque,
    ],
    stops: [0, fade, 1 - fade, 1],
  ).createShader(bounds);
}

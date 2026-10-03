import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Durations and curves for the swap screens' motion.
///
/// Every animation built on these ends on its own, and any burst of motion
/// ends within five seconds, as WCAG 2.2.2 asks of motion that starts by
/// itself beside other content.
abstract final class SwapMotion {
  static const press = Duration(milliseconds: 100);
  static const release = Duration(milliseconds: 220);
  static const colour = Duration(milliseconds: 200);
  static const pop = Duration(milliseconds: 240);
  static const settle = Duration(milliseconds: 360);
  static const reveal = Duration(milliseconds: 300);
  static const screen = Duration(milliseconds: 300);
  static const grow = Duration(milliseconds: 280);
  static const stagger = Duration(milliseconds: 60);

  /// A timeline step changing, the connector below it filling, and how much
  /// the next step's change overlaps it. However many steps change at once,
  /// they take at most [cascadeLimit] together.
  static const step = Duration(milliseconds: 300);
  static const fill = Duration(milliseconds: 360);
  static const stepOverlap = Duration(milliseconds: 70);
  static const cascadeLimit = Duration(milliseconds: 1200);

  static const beat = Duration(milliseconds: 1000);
  static const beatSpacing = Duration(milliseconds: 1200);
  static const ring = Duration(milliseconds: 600);

  static const Curve enter = Easing.emphasizedDecelerate;
  static const Curve standard = Easing.standard;

  /// A success settles with a small overshoot, a warning with less; an error
  /// never bounces.
  static const Curve success = Cubic(0.34, 1.4, 0.64, 1);
  static const Curve warning = Cubic(0.3, 1.2, 0.6, 1);
  static const Curve error = Easing.standardDecelerate;

  /// Whether motion is on; `ReducedMotionScope` makes this follow every
  /// platform's reduced-motion setting.
  static bool enabled(BuildContext context) =>
      !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  static Duration of(BuildContext context, Duration duration) =>
      enabled(context) ? duration : Duration.zero;
}

/// Haptics for the swap screens: native iOS and Android only, one for each
/// discrete event, never awaited; a platform that refuses one is ignored.
abstract final class SwapHaptics {
  static void selection() => _play(HapticFeedback.selectionClick);
  static void light() => _play(HapticFeedback.lightImpact);
  static void medium() => _play(HapticFeedback.mediumImpact);
  static void success() => _play(HapticFeedback.successNotification);
  static void warning() => _play(HapticFeedback.warningNotification);
  static void error() => _play(HapticFeedback.errorNotification);

  static void _play(Future<void> Function() feedback) {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    unawaited(feedback().catchError((Object _) {}));
  }
}

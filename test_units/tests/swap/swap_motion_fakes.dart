import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// [child] centred, with only what the motion primitives read around it.
Widget motionApp(
  Widget child, {
  bool reduceMotion = false,
  TextDirection direction = TextDirection.ltr,
}) => Directionality(
  textDirection: direction,
  child: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Center(child: child),
  ),
);

/// The opacity layers the last frame painted.
List<OpacityLayer> opacityLayers(WidgetTester tester) =>
    tester.layers.whereType<OpacityLayer>().toList();

/// The transform an effect painted in the last frame, when one is running.
/// The first transform layer is the view's own.
Matrix4? effectTransform(WidgetTester tester) {
  final transforms = tester.layers.whereType<TransformLayer>().toList();
  return transforms.length < 2 ? null : transforms.last.transform;
}

/// How much [transform] scales along x, whatever it turns.
double scaleOf(Matrix4 transform) => math.sqrt(
  math.pow(transform.entry(0, 0), 2) + math.pow(transform.entry(1, 0), 2),
);

/// How much each effect running in the last frame scales, after the view's
/// own transform.
Iterable<double> effectScales(WidgetTester tester) => tester.layers
    .whereType<TransformLayer>()
    .skip(1)
    .map((layer) => scaleOf(layer.transform ?? Matrix4.identity()));

/// Whether any effect painted something turned in the last frame.
bool effectTurning(WidgetTester tester) => tester.layers
    .whereType<TransformLayer>()
    .any((layer) => (layer.transform?.entry(1, 0) ?? 0).abs() > 1e-6);

/// Records the haptic feedback the rest of the test plays.
List<String> recordHaptics(WidgetTester tester) {
  final played = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'HapticFeedback.vibrate') {
      played.add(call.arguments as String);
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return played;
}

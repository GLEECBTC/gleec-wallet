import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/services/reduced_motion/reduced_motion_signal.dart';
import 'package:web_dex/shared/widgets/reduced_motion_scope.dart';

const _channel = MethodChannel('gleec/reduced-motion');

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

Future<void> _push(bool reduce) => _messenger.handlePlatformMessage(
  _channel.name,
  const StandardMethodCodec().encodeMethodCall(MethodCall('changed', reduce)),
  (_) {},
);

class _Counter extends StatefulWidget {
  const _Counter({required this.seen});

  final List<bool> seen;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  static int created = 0;

  @override
  void initState() {
    super.initState();
    created++;
  }

  @override
  Widget build(BuildContext context) {
    widget.seen.add(MediaQuery.disableAnimationsOf(context));
    return const SizedBox.shrink();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReducedMotionScope', () {
    late ReducedMotionSignal signal;
    late List<bool> seen;

    setUp(() {
      signal = ReducedMotionSignal(
        isWeb: false,
        platform: TargetPlatform.android,
      );
      seen = [];
      _CounterState.created = 0;
    });

    tearDown(() => signal.dispose());

    Future<void> pumpScope(WidgetTester tester) => tester.pumpWidget(
      ReducedMotionScope(
        signal: signal,
        child: _Counter(seen: seen),
      ),
    );

    testWidgets('leaves motion on when nothing asks for less', (tester) async {
      await pumpScope(tester);
      expect(seen.last, isFalse);
    });

    testWidgets('keeps the flag Android and Linux set themselves', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpScope(tester);
      expect(seen.last, isTrue);
    });

    testWidgets('follows iOS Reduce Motion as it changes', (tester) async {
      await pumpScope(tester);
      expect(seen.last, isFalse);

      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(reduceMotion: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pump();
      expect(seen.last, isTrue);

      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      await tester.pump();
      expect(seen.last, isFalse);
    });

    testWidgets('follows the platform signal without remounting the app', (
      tester,
    ) async {
      await pumpScope(tester);
      signal.value = true;
      await tester.pump();
      expect(seen.last, isTrue);

      signal.value = false;
      await tester.pump();
      expect(seen.last, isFalse);
      expect(_CounterState.created, 1);
    });
  });

  group('ReducedMotionSignal', () {
    tearDown(() => _messenger.setMockMethodCallHandler(_channel, null));

    for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
      test(
        'asks the ${platform.name} runner and follows its changes',
        () async {
          _messenger.setMockMethodCallHandler(_channel, (call) async {
            expect(call.method, 'get');
            return true;
          });
          final signal = ReducedMotionSignal(isWeb: false, platform: platform);
          addTearDown(signal.dispose);
          await pumpEventQueue();
          expect(signal.value, isTrue);

          await _push(false);
          expect(signal.value, isFalse);
          await _push(true);
          expect(signal.value, isTrue);
        },
      );
    }

    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.linux,
    ]) {
      test('leaves ${platform.name} to the engine', () async {
        var asked = false;
        _messenger.setMockMethodCallHandler(_channel, (_) async {
          asked = true;
          return true;
        });
        final signal = ReducedMotionSignal(isWeb: false, platform: platform);
        addTearDown(signal.dispose);
        await pumpEventQueue();
        expect(asked, isFalse);
        expect(signal.value, isFalse);
      });
    }

    test('keeps motion on when the runner has no channel', () async {
      _messenger.setMockMethodCallHandler(
        _channel,
        (_) async => throw MissingPluginException(),
      );
      final signal = ReducedMotionSignal(
        isWeb: false,
        platform: TargetPlatform.macOS,
      );
      addTearDown(signal.dispose);
      await pumpEventQueue();
      expect(signal.value, isFalse);
    });

    test('keeps motion on when the runner cannot read the setting', () async {
      _messenger.setMockMethodCallHandler(
        _channel,
        (_) async => throw PlatformException(code: 'unavailable'),
      );
      final signal = ReducedMotionSignal(
        isWeb: false,
        platform: TargetPlatform.windows,
      );
      addTearDown(signal.dispose);
      await pumpEventQueue();
      expect(signal.value, isFalse);
    });

    test('ignores an answer that arrives after it is disposed', () async {
      final answer = Completer<bool>();
      _messenger.setMockMethodCallHandler(_channel, (_) => answer.future);
      ReducedMotionSignal(
        isWeb: false,
        platform: TargetPlatform.macOS,
      ).dispose();
      answer.complete(true);
      await pumpEventQueue();
    });

    test('reads the browser on web and follows its changes', () {
      late void Function(bool) change;
      var stopped = false;
      final signal = ReducedMotionSignal(
        isWeb: true,
        webQuery: () => true,
        watchWeb: (onChange) {
          change = onChange;
          return () => stopped = true;
        },
      );
      expect(signal.value, isTrue);

      change(false);
      expect(signal.value, isFalse);

      signal.dispose();
      expect(stopped, isTrue);
    });
  });
}

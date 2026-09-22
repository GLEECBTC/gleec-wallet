// The analyzer does not recognize this repository's test_units/ test directory.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart'
    show MethodChannelFirebase;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/bloc/analytics/analytics_repo.dart';
import 'package:web_dex/bloc/analytics/firebase_analytics_api.dart';
import 'package:web_dex/model/settings/analytics_settings.dart';

const _queueKey = 'firebase_analytics_persisted_queue';
const _enabled = AnalyticsSettings(isSendAllowed: true);
const _configuredOptions = FirebaseOptions(
  apiKey: 'test-api-key',
  appId: '1:123456789:ios:abcdef1234567890',
  messagingSenderId: '123456789',
  projectId: 'example-project',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FirebaseAnalyticsApi configuration', () {
    late _FirebaseCoreHost core;
    final analyticsCalls = <String, List<Object?>>{};
    const analyticsMethods = ['setAnalyticsCollectionEnabled', 'logEvent'];

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      MethodChannelFirebase.appInstances.clear();
      MethodChannelFirebase.isCoreInitialized = false;
      core = _FirebaseCoreHost();
      TestFirebaseCoreHostApi.setUp(core);
      analyticsCalls.clear();
      for (final method in analyticsMethods) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockDecodedMessageHandler<Object?>(_analyticsChannel(method), (
              message,
            ) async {
              analyticsCalls.putIfAbsent(method, () => []).add(message);
              return <Object?>[null];
            });
      }
    });

    tearDown(() {
      TestFirebaseCoreHostApi.setUp(null);
      MethodChannelFirebase.appInstances.clear();
      MethodChannelFirebase.isCoreInitialized = false;
      debugDefaultTargetPlatformOverride = null;
      for (final method in analyticsMethods) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockDecodedMessageHandler<Object?>(
              _analyticsChannel(method),
              null,
            );
      }
    });

    for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
      test('$platform placeholders never reach Firebase or start timers', () {
        debugDefaultTargetPlatformOverride = platform;
        fakeAsync((async) {
          final provider = FirebaseAnalyticsApi();
          var completed = false;
          provider.initialize(_enabled).then((_) => completed = true);
          async.flushMicrotasks();
          expect(completed, isTrue);
          expect(provider.isInitialized, isFalse);
          expect(provider.isEnabled, isFalse);

          provider.retryInitialization(_enabled);
          async.flushMicrotasks();
          expect(core.initializeCoreCalls, 0);
          expect(core.requests, isEmpty);
          expect(analyticsCalls, isEmpty);
          expect(async.periodicTimerCount, 0);

          provider.dispose();
          async.flushMicrotasks();
          expect(async.pendingTimers, isEmpty);
        });
      });
    }

    test('unconfigured builds discard queued and persisted events', () async {
      SharedPreferences.setMockInitialValues({
        _queueKey: jsonEncode([
          {'name': 'previous_session', 'parameters': <String, Object?>{}},
        ]),
      });
      final provider = FirebaseAnalyticsApi();
      addTearDown(provider.dispose);
      final event = PersistedAnalyticsEventData(
        name: 'test_event',
        parameters: {},
      );
      await provider.sendEvent(event);
      await provider.initialize(_enabled);
      await provider.sendEvent(event);
      await provider.activate();
      await provider.dispose();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_queueKey), isNull);
      expect(core.initializeCoreCalls, 0);
      expect(analyticsCalls, isEmpty);
    });

    test('repository stays disabled when no provider can initialize', () {
      fakeAsync((async) {
        final repository = AnalyticsRepository(_enabled);
        async.flushMicrotasks();
        expect(repository.isInitialized, isFalse);
        expect(repository.isEnabled, isFalse);
        repository.activate();
        async.flushMicrotasks();
        expect(repository.isEnabled, isFalse);
        repository.dispose();
        async.flushMicrotasks();
        expect(async.pendingTimers, isEmpty);
      });
    });

    test(
      'configured builds initialize and send queued and new events',
      () async {
        final provider = FirebaseAnalyticsApi(options: _configuredOptions);
        addTearDown(provider.dispose);
        final event = PersistedAnalyticsEventData(
          name: 'test_event',
          parameters: {},
        );
        await provider.sendEvent(event);
        await provider.initialize(_enabled);
        await provider.sendEvent(event);

        expect(provider.isInitialized, isTrue);
        expect(provider.isEnabled, isTrue);
        expect(core.requests, hasLength(1));
        expect(
          FirebaseOptions.fromPigeon(core.requests.single),
          _configuredOptions,
        );
        expect(analyticsCalls['setAnalyticsCollectionEnabled'], [
          [true],
        ]);
        expect(analyticsCalls['logEvent'], hasLength(2));
      },
    );

    test('configured builds respect disabled collection', () async {
      final provider = FirebaseAnalyticsApi(options: _configuredOptions);
      addTearDown(provider.dispose);
      await provider.initialize(const AnalyticsSettings(isSendAllowed: false));
      await provider.sendEvent(
        PersistedAnalyticsEventData(name: 'test_event', parameters: {}),
      );
      expect(provider.isInitialized, isTrue);
      expect(provider.isEnabled, isFalse);
      expect(analyticsCalls['setAnalyticsCollectionEnabled'], [
        [false],
      ]);
      expect(analyticsCalls['logEvent'], isNull);
    });

    test('initialization retries share one disposable persistence timer', () {
      core.failInitialization = true;
      fakeAsync((async) {
        final provider = FirebaseAnalyticsApi(options: _configuredOptions);
        var completed = false;
        provider.initialize(_enabled).then((_) => completed = true);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 12));
        expect(completed, isTrue);
        expect(core.requests, hasLength(4));
        expect(provider.isInitialized, isFalse);
        expect(async.periodicTimerCount, 1);
        provider.dispose();
        async.flushMicrotasks();
        expect(async.pendingTimers, isEmpty);
      });
    });
  });
}

BasicMessageChannel<Object?> _analyticsChannel(String method) =>
    BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.firebase_analytics_platform_interface.'
      'FirebaseAnalyticsHostApi.$method',
      const StandardMessageCodec(),
    );

class _FirebaseCoreHost extends MockFirebaseApp {
  int initializeCoreCalls = 0;
  bool failInitialization = false;
  final requests = <CoreFirebaseOptions>[];

  @override
  Future<List<CoreInitializeResponse>> initializeCore() async {
    initializeCoreCalls++;
    return [];
  }

  @override
  Future<CoreInitializeResponse> initializeApp(
    String appName,
    CoreFirebaseOptions initializeAppRequest,
  ) async {
    requests.add(initializeAppRequest);
    if (failInitialization) {
      throw PlatformException(code: 'unavailable');
    }
    return CoreInitializeResponse(
      name: appName,
      options: initializeAppRequest,
      pluginConstants: {},
    );
  }
}

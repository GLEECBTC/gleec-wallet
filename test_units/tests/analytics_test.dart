import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/analytics/analytics_repo.dart';
import 'package:web_dex/model/settings/analytics_settings.dart';

void main() {
  group('AnalyticsRepository Tests', () {
    late AnalyticsSettings testSettings;

    setUp(() {
      testSettings = const AnalyticsSettings(isSendAllowed: true);
    });

    test('AnalyticsRepository implements AnalyticsRepo', () {
      final repo = AnalyticsRepository(testSettings);
      addTearDown(() async => repo.dispose());
      expect(repo, isA<AnalyticsRepo>());
    });

    test('AnalyticsRepository has correct initialization state', () {
      final repo = AnalyticsRepository(testSettings);
      addTearDown(() async => repo.dispose());

      // Initially should not be initialized (async initialization)
      expect(repo.isInitialized, false);
      expect(repo.isEnabled, false);
    });

    test('AnalyticsRepository can send test event', () async {
      final repo = AnalyticsRepository(testSettings);
      addTearDown(() async => repo.dispose());

      final testEvent = TestAnalyticsEvent();
      await repo.queueEvent(testEvent);
    });
  });
}

class TestAnalyticsEvent extends AnalyticsEventData {
  @override
  String get name => 'test_event';

  @override
  Map<String, dynamic> get parameters => {
    'test_parameter': 'test_value',
    'timestamp': DateTime.now().toIso8601String(),
  };
}

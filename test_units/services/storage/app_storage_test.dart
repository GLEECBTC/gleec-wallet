// The analyzer does not recognize this repository's test_units directory.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:web_dex/services/storage/app_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppStorage persistence results', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));
    tearDown(() => SharedPreferences.setMockInitialValues({}));

    for (final value in <Object>[
      true,
      1.5,
      7,
      'consent-version',
      {'accepted': true},
    ]) {
      test(
        'does not acknowledge rejected ${value.runtimeType} writes',
        () async {
          SharedPreferencesStorePlatform.instance = _RejectingStore();
          final storage = AppStorage();

          expect(await storage.write('audit-setting', value), isFalse);
          // A platform failure must not be mistaken for durable consent or
          // protection metadata, even if SharedPreferences updated its cache.
          expect(await storage.read('audit-setting'), isNull);
        },
      );
    }

    test('acknowledges and reads back a persisted value', () async {
      final storage = AppStorage();
      expect(await storage.write('audit-setting', {'accepted': true}), isTrue);
      expect(await storage.read('audit-setting'), {'accepted': true});
    });

    test('returns false when the platform write throws', () async {
      SharedPreferencesStorePlatform.instance = _RejectingStore(throws: true);
      expect(await AppStorage().write('audit-setting', true), isFalse);
    });
  });
}

class _RejectingStore extends InMemorySharedPreferencesStore {
  _RejectingStore({this.throws = false}) : super.empty();

  final bool throws;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (throws) throw StateError('Fixture persistence failure');
    return false;
  }
}

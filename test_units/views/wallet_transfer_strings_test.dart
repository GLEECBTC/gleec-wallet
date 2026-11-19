import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The move and backup screens carry safety warnings: a missing key would
/// show its name instead. Every key they use must exist in English.
void main() {
  group('move and backup strings', () {
    final english = jsonDecode(
      File('assets/translations/en.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final sources = [
      for (final dir in ['lib/views/wallet_move', 'lib/views/wallet_backup'])
        ...Directory(dir)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart')),
    ];
    // Keys picked in a switch and translated later are found by prefix.
    final featureKey = RegExp(
      r'''['"]((?:walletMove|walletTransfer|passkeyBackup)[A-Za-z0-9]*)['"]''',
    );
    final translated = RegExp(r'''['"]([A-Za-z][A-Za-z0-9_.]*)['"]\s*\.tr\(''');

    test('the screens are where this test looks', () {
      expect(sources, hasLength(greaterThan(5)));
    });

    test('every key the screens use exists in en.json', () {
      final missing = <String>{};
      for (final file in sources) {
        final text = file.readAsStringSync();
        for (final pattern in [featureKey, translated]) {
          for (final match in pattern.allMatches(text)) {
            final key = match.group(1)!;
            if (!english.containsKey(key)) missing.add('$key (${file.path})');
          }
        }
      }
      expect(missing, isEmpty);
    });

    test('placeholders in the new strings are balanced', () {
      for (final MapEntry(:key, :value) in english.entries) {
        if (!featureKey.hasMatch("'$key'") || value is! String) continue;
        expect(
          '{'.allMatches(value).length,
          '}'.allMatches(value).length,
          reason: key,
        );
      }
    });
  });
}

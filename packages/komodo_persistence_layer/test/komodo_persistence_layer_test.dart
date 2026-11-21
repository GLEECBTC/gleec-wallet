import 'dart:io';

import 'package:hive_ce/hive.dart';
import 'package:komodo_persistence_layer/komodo_persistence_layer.dart';
import 'package:test/test.dart';

void main() {
  test(
    'HiveBoxProvider persists inserts, updates and deletions across reopen',
    () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'komodo_persistence_test_',
      );
      final String boxName = directory.uri.pathSegments.lastWhere(
        (String segment) => segment.isNotEmpty,
      );
      final List<Box<PersistedString>> boxes = <Box<PersistedString>>[];

      addTearDown(() async {
        try {
          for (final Box<PersistedString> box in boxes) {
            if (box.isOpen) {
              await box.close();
            }
          }
        } finally {
          await directory.delete(recursive: true);
        }
      });

      Hive.registerAdapter<PersistedString>(PersistedStringAdapter());

      Future<HiveBoxProvider<String, PersistedString>> openProvider() async {
        final Box<PersistedString> box = await Hive.openBox<PersistedString>(
          boxName,
          path: directory.path,
        );
        boxes.add(box);
        return HiveBoxProvider<String, PersistedString>.init(
          name: boxName,
          box: box,
        );
      }

      final HiveBoxProvider<String, PersistedString> initial =
          await openProvider();
      await initial.insert(PersistedString('theme', 'dark'));
      await initial.insertAll(<PersistedString>[
        PersistedString('locale', '日本語'),
        PersistedString('unrelated', 'keep me'),
      ]);
      await boxes.last.close();

      final HiveBoxProvider<String, PersistedString> reopened =
          await openProvider();
      final PersistedString? stored = await reopened.get('locale');
      expect(stored?.primaryKey, 'locale');
      expect(stored?.value, '日本語');
      expect((await reopened.get('theme'))?.value, 'dark');
      expect(await reopened.getAll(), hasLength(3));

      await reopened.update(PersistedString('theme', 'light'));
      await reopened.delete('locale');
      await boxes.last.close();

      final HiveBoxProvider<String, PersistedString> afterChanges =
          await openProvider();
      expect((await afterChanges.get('theme'))?.value, 'light');
      expect(await afterChanges.get('locale'), isNull);
      expect(await afterChanges.containsKey('locale'), isFalse);
      expect((await afterChanges.get('unrelated'))?.value, 'keep me');
      expect(await afterChanges.getAll(), hasLength(2));

      await afterChanges.deleteAll();
      await boxes.last.close();

      final HiveBoxProvider<String, PersistedString> afterDeleteAll =
          await openProvider();
      expect(await afterDeleteAll.getAll(), isEmpty);
    },
  );
}

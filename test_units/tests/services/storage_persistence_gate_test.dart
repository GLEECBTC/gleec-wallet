import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/services/storage/base_storage.dart';
import 'package:web_dex/services/storage/storage_persistence_gate.dart';

/// A real in-memory store. Not `MockStorage`, whose `read` returns the key
/// rather than null for a missing entry - which would read as a permanent
/// backoff.
class _MemoryStorage implements BaseStorage {
  final Map<String, dynamic> values = {};

  @override
  Future<bool> write(String key, dynamic value) async {
    values[key] = value;
    return true;
  }

  @override
  Future<dynamic> read(String key) async => values[key];

  @override
  Future<bool> delete(String key) async {
    values.remove(key);
    return true;
  }
}

void testStoragePersistenceGate() {
  group('StoragePersistenceGate', () {
    late _MemoryStorage storage;
    var now = DateTime.utc(2026, 8, 19);

    setUp(() {
      storage = _MemoryStorage();
      now = DateTime.utc(2026, 8, 19);
    });

    StoragePersistenceGate build(Future<StoragePersistence> Function() probe) =>
        StoragePersistenceGate(storage: storage, probe: probe, now: () => now);

    test('probes once per session and no more', () async {
      var calls = 0;
      final gate = build(() async {
        calls++;
        return StoragePersistence.granted;
      });

      expect(await gate.maybeRequest(), StoragePersistence.granted);
      expect(await gate.maybeRequest(), isNull);
      expect(calls, 1);
    });

    test(
      'a denial starts a backoff that suppresses the next session',
      () async {
        var calls = 0;
        Future<StoragePersistence> probe() async {
          calls++;
          return StoragePersistence.denied;
        }

        expect(await build(probe).maybeRequest(), StoragePersistence.denied);
        expect(calls, 1);

        // New session, same storage.
        now = now.add(const Duration(days: 3));
        expect(await build(probe).maybeRequest(), isNull);
        expect(calls, 1, reason: 'backoff should have skipped the probe');
      },
    );

    test('the backoff expires and the probe runs again', () async {
      var calls = 0;
      Future<StoragePersistence> probe() async {
        calls++;
        return StoragePersistence.denied;
      }

      await build(probe).maybeRequest();
      // Denials are not sticky in the browser either, which is why retrying is
      // worth doing at all.
      now = now.add(const Duration(days: 31));
      expect(await build(probe).maybeRequest(), StoragePersistence.denied);
      expect(calls, 2);
    });

    test('a grant sets no backoff', () async {
      await build(() async => StoragePersistence.granted).maybeRequest();
      expect(storage.values, isEmpty);
    });

    test('already-persistent sets no backoff', () async {
      await build(
        () async => StoragePersistence.alreadyPersistent,
      ).maybeRequest();
      expect(storage.values, isEmpty);
    });

    test('unsupported sets no backoff, and returns unsupported', () async {
      final result = await build(
        () async => StoragePersistence.unsupported,
      ).maybeRequest();

      expect(result, StoragePersistence.unsupported);
      expect(storage.values, isEmpty);
    });

    test('a throwing probe is swallowed and reports nothing', () async {
      final result = await build(
        () async => throw StateError('browser said no, loudly'),
      ).maybeRequest();

      expect(result, isNull);
    });

    test('a corrupt backoff value does not wedge the gate', () async {
      storage.values['storage_persistence_denied_at'] = 'not a date';

      expect(
        await build(() async => StoragePersistence.granted).maybeRequest(),
        StoragePersistence.granted,
      );
    });
  });
}

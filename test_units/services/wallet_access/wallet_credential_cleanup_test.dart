import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/services/storage/base_storage.dart';
import 'package:web_dex/services/wallet_access/platform/credential_backend.dart';
import 'package:web_dex/services/wallet_access/wallet_access_record.dart';
import 'package:web_dex/services/wallet_access/wallet_access_types.dart';
import 'package:web_dex/services/wallet_access/wallet_credential_cleanup.dart';

const _pendingKey = 'wallet_access_pending_v1';
const _lastKey = 'wallet_access_last_v1';
const _token = 'canary-one-use-deletion-authorization';

WalletAccessRecord _record(String id, {bool protected = false}) =>
    WalletAccessRecord(
      entryId: id,
      walletName: 'Same wallet name',
      isHd: true,
      protection: protected
          ? CredentialProtection.authenticationBound
          : CredentialProtection.appLocal,
      requiresAuthentication: protected,
      phase: 'ready',
      pubkeyHash: 'same-seed-pubkey',
    );

Matcher get _storageFailure => isA<WalletAccessException>().having(
  (error) => error.failure,
  'failure',
  WalletAccessFailure.storageFailed,
);

void main() {
  group('wallet credential cleanup journal', () {
    late _MemoryStorage storage;
    late _CredentialBackend backend;
    late WalletCredentialCleanup cleanup;
    late WalletAccessRecord original;

    void seed({bool protected = false}) {
      original = _record('original-entry', protected: protected);
      storage = _MemoryStorage({
        WalletCredentialCleanup.recordsKey: {
          original.entryId: original.toJson(),
        },
        _pendingKey: original.entryId,
        _lastKey: {'entryId': original.entryId},
      });
      backend = _CredentialBackend()..add(original);
      cleanup = WalletCredentialCleanup(storage, backend);
    }

    Future<void> expectRemoved() async {
      expect(await cleanup.hasIntents, isFalse);
      expect(await cleanup.hasPending, isFalse);
      expect(await backend.metadata(original.credentialKey), isNull);
      expect(
        await storage.read(WalletCredentialCleanup.recordsKey),
        isNot(contains(original.entryId)),
      );
      expect(await storage.read(_pendingKey), isNull);
      expect(await storage.read(_lastKey), isNull);
    }

    setUp(seed);

    test('preparation is durable but invisible until engine removal', () async {
      await cleanup.prepare(original, null);
      expect(await cleanup.hasIntents, isTrue);
      expect(await cleanup.hasPending, isFalse);

      final restarted = WalletCredentialCleanup(storage, backend);
      await restarted.resume({original.entryId});
      await restarted.retry(
        (_) async => fail('must not authorize a live wallet'),
      );
      // A caller without the prepared immutable identity cannot convert an
      // unrelated failed wallet deletion into a credential purge.
      await restarted.complete(original.walletName, original.pubkeyHash);
      expect(await restarted.hasPending, isFalse);
      expect(backend.deletions, isEmpty);
      expect(await backend.metadata(original.credentialKey), isNotNull);
    });

    for (final lieAboutPersistence in [false, true]) {
      test(
        'preparation rejects ${lieAboutPersistence ? 'false persistence success' : 'failed persistence'} before deletion',
        () async {
          storage.failAtWrite = lieAboutPersistence ? null : 1;
          storage.ignoreAtWrite = lieAboutPersistence ? 1 : null;
          await expectLater(
            cleanup.prepare(original, _token),
            throwsA(_storageFailure),
          );
          expect(await cleanup.hasIntents, isFalse);
          expect(backend.deletions, isEmpty);
        },
      );
    }

    test(
      'startup repairs an interrupted engine deletion without prompting',
      () async {
        await cleanup.prepare(original, null);
        // Process exits after engine removal, before complete() was invoked.
        final restarted = WalletCredentialCleanup(storage, backend);
        await restarted.resume({});
        expect(backend.deletions.single.authorization, isNull);
        await expectRemoved();
      },
    );

    test(
      'tokens never persist or survive restart; protected cleanup stays pending',
      () async {
        seed(protected: true);
        await cleanup.prepare(original, _token);
        expect(jsonEncode(storage.values), isNot(contains(_token)));
        final restarted = WalletCredentialCleanup(storage, backend);
        await restarted.resume({});
        expect(await restarted.hasPending, isTrue);
        expect(backend.deletions, isEmpty);
        final prompts = <String>[];
        await restarted.retry((key) async {
          prompts.add(key);
          return _token;
        });
        expect(prompts, [original.credentialKey]);
        expect(backend.deletions.single.authorization, _token);
        expect(jsonEncode(storage.values), isNot(contains(_token)));
        await expectRemoved();
      },
    );

    test(
      'revoked authorization never opens a protected cleanup path',
      () async {
        seed(protected: true);
        await cleanup.prepare(original, _token);
        cleanup.revokeAuthorizations();
        await expectLater(
          cleanup.complete(
            original.walletName,
            original.pubkeyHash,
            expectedEntryId: original.entryId,
          ),
          throwsA(_storageFailure),
        );
        expect(await cleanup.hasPending, isTrue);
        expect(backend.deletions, isEmpty);
      },
    );

    test(
      'a prepared token can purge an invalidated wrapper without probing it first',
      () async {
        seed(protected: true);
        backend.invalidated.add(original.credentialKey);
        await cleanup.prepare(original, _token);
        await cleanup.complete(
          original.walletName,
          original.pubkeyHash,
          expectedEntryId: original.entryId,
        );
        expect(backend.deletions.single.authorization, _token);
        await expectRemoved();
      },
    );

    test(
      'failed native purge remains visible and needs a new authorization',
      () async {
        seed(protected: true);
        await cleanup.prepare(original, _token);
        backend.failNextDeletion = true;
        await expectLater(
          cleanup.complete(
            original.walletName,
            original.pubkeyHash,
            expectedEntryId: original.entryId,
          ),
          throwsA(_storageFailure),
        );
        expect(await cleanup.hasPending, isTrue);
        await cleanup.resume({});
        expect(backend.deletions, hasLength(1));
        await cleanup.retry((_) async => _token);
        expect(backend.deletions, hasLength(2));
        await expectRemoved();
      },
    );

    test(
      'same-name same-seed replacement keeps its credential and last-wallet identity',
      () async {
        final replacement = _record('replacement-entry');
        await storage.write(WalletCredentialCleanup.recordsKey, {
          original.entryId: original.toJson(),
          replacement.entryId: replacement.toJson(),
        });
        await storage.write(_pendingKey, replacement.entryId);
        await storage.write(_lastKey, {'entryId': replacement.entryId});
        backend.add(replacement);
        await cleanup.prepare(original, null);
        await cleanup.prepare(replacement, null);

        await cleanup.complete(
          original.walletName,
          original.pubkeyHash,
          expectedEntryId: original.entryId,
        );
        // A late duplicate completion cannot discover and delete the replacement.
        await cleanup.complete(
          original.walletName,
          original.pubkeyHash,
          expectedEntryId: original.entryId,
        );
        await WalletCredentialCleanup(
          storage,
          backend,
        ).resume({replacement.entryId});
        expect(backend.deletions.map((call) => call.key), [
          original.credentialKey,
        ]);
        expect(await backend.metadata(replacement.credentialKey), isNotNull);
        expect(await storage.read(_pendingKey), replacement.entryId);
        expect(await storage.read(_lastKey), {'entryId': replacement.entryId});
        expect(await cleanup.hasPending, isFalse);
        expect(await cleanup.hasIntents, isTrue);
      },
    );

    test(
      'a native success without deletion fails its readback check',
      () async {
        await cleanup.prepare(original, null);
        backend.ignoreNextDeletion = true;
        await expectLater(
          cleanup.complete(
            original.walletName,
            original.pubkeyHash,
            expectedEntryId: original.entryId,
          ),
          throwsA(_storageFailure),
        );
        expect(await cleanup.hasPending, isTrue);
        expect(
          await storage.read(WalletCredentialCleanup.recordsKey),
          contains(original.entryId),
        );
        await WalletCredentialCleanup(storage, backend).resume({});
        await expectRemoved();
      },
    );

    test(
      'canceled repair preserves the pending cleanup and credential',
      () async {
        seed(protected: true);
        await cleanup.prepare(original, null);
        await cleanup.resume({});
        await expectLater(
          cleanup.retry(
            (_) async =>
                throw const WalletAccessException(WalletAccessFailure.canceled),
          ),
          throwsA(
            isA<WalletAccessException>().having(
              (error) => error.failure,
              'failure',
              WalletAccessFailure.canceled,
            ),
          ),
        );
        expect(await cleanup.hasPending, isTrue);
        expect(backend.deletions, isEmpty);
        expect(await backend.metadata(original.credentialKey), isNotNull);
      },
    );

    test(
      'startup preserves a live immutable entry even with a completed intent',
      () async {
        seed(protected: true);
        await cleanup.prepare(original, null);
        await expectLater(
          cleanup.complete(
            original.walletName,
            original.pubkeyHash,
            expectedEntryId: original.entryId,
          ),
          throwsA(_storageFailure),
        );
        expect(await cleanup.hasPending, isTrue);
        await WalletCredentialCleanup(
          storage,
          backend,
        ).resume({original.entryId});
        expect(backend.deletions, isEmpty);
        expect(await backend.metadata(original.credentialKey), isNotNull);
        expect(await storage.read(_lastKey), {'entryId': original.entryId});
      },
    );

    test(
      'retry authorizes each same-name completed intent separately',
      () async {
        seed(protected: true);
        final other = _record('other-entry', protected: true);
        backend.add(other);
        await storage.write(WalletCredentialCleanup.recordsKey, {
          original.entryId: original.toJson(),
          other.entryId: other.toJson(),
        });
        for (final record in [original, other]) {
          await cleanup.prepare(record, null);
          await expectLater(
            cleanup.complete(
              record.walletName,
              record.pubkeyHash,
              expectedEntryId: record.entryId,
            ),
            throwsA(_storageFailure),
          );
        }
        final authorized = <String>[];
        await cleanup.retry((key) async {
          authorized.add(key);
          return _token;
        });
        expect(authorized, [original.credentialKey, other.credentialKey]);
        expect(backend.deletions.map((call) => call.key), authorized);
        await expectRemoved();
        expect(await backend.metadata(other.credentialKey), isNull);
      },
    );

    for (final boundary in [
      'deletion marker',
      'catalog removal',
      'pending identity',
      'last identity',
      'journal removal',
    ]) {
      test('restart completes cleanup after failure at $boundary', () async {
        await cleanup.prepare(original, null);
        storage.writeCount = 0;
        switch (boundary) {
          case 'deletion marker':
            storage.failAtWrite = 1;
          case 'catalog removal':
            storage.failAtWrite = 2;
          case 'pending identity':
            storage.failDeleteKey = _pendingKey;
          case 'last identity':
            storage.failDeleteKey = _lastKey;
          case 'journal removal':
            storage.failAtWrite = 3;
        }
        await expectLater(
          cleanup.complete(
            original.walletName,
            original.pubkeyHash,
            expectedEntryId: original.entryId,
          ),
          throwsA(_storageFailure),
        );
        expect(await cleanup.hasIntents, isTrue);
        storage.clearFaults();
        await WalletCredentialCleanup(storage, backend).resume({});
        await expectRemoved();
        expect(backend.deletions, hasLength(1));
      });
    }

    for (final committedWrite in [1, 2, 3]) {
      test(
        'restart is safe after termination following durable write $committedWrite',
        () async {
          await cleanup.prepare(original, null);
          storage.writeCount = 0;
          storage.crashAfterWrite = committedWrite;
          await expectLater(
            cleanup.complete(
              original.walletName,
              original.pubkeyHash,
              expectedEntryId: original.entryId,
            ),
            throwsA(isA<_SimulatedProcessExit>()),
          );
          storage.clearFaults();
          await WalletCredentialCleanup(storage, backend).resume({});
          await expectRemoved();
          expect(backend.deletions, hasLength(1));
        },
      );
    }
  });
}

class _SimulatedProcessExit implements Exception {}

class _MemoryStorage implements BaseStorage {
  _MemoryStorage(Map<String, dynamic> initial)
    : values = Map<String, dynamic>.from(_copy(initial) as Map);

  final Map<String, dynamic> values;
  int writeCount = 0;
  int? failAtWrite;
  int? ignoreAtWrite;
  int? crashAfterWrite;
  String? failDeleteKey;

  static dynamic _copy(dynamic value) => jsonDecode(jsonEncode(value));

  void clearFaults() {
    failAtWrite = null;
    ignoreAtWrite = null;
    crashAfterWrite = null;
    failDeleteKey = null;
  }

  @override
  Future<dynamic> read(String key) async => _copy(values[key]);

  @override
  Future<bool> write(String key, dynamic data) async {
    final count = ++writeCount;
    if (count == failAtWrite) return false;
    if (count == ignoreAtWrite) return true;
    values[key] = _copy(data);
    if (count == crashAfterWrite) throw _SimulatedProcessExit();
    return true;
  }

  @override
  Future<bool> delete(String key) async {
    if (key == failDeleteKey) return false;
    values.remove(key);
    return true;
  }
}

class _CredentialBackend extends CredentialBackend {
  final records = <String, CredentialRecordInfo>{};
  final invalidated = <String>{};
  final deletions = <({String key, String? authorization})>[];
  bool failNextDeletion = false;
  bool ignoreNextDeletion = false;

  void add(WalletAccessRecord record) {
    records[record.credentialKey] = CredentialRecordInfo(
      protection: record.protection,
      enrolled: record.requiresAuthentication,
    );
  }

  @override
  Future<CredentialRecordInfo?> metadata(String key) async {
    if (invalidated.contains(key)) {
      throw const WalletAccessException(WalletAccessFailure.invalidated);
    }
    return records[key];
  }

  @override
  Future<void> delete(String key, {String? authorization}) async {
    deletions.add((key: key, authorization: authorization));
    if (failNextDeletion) {
      failNextDeletion = false;
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
    if (ignoreNextDeletion) {
      ignoreNextDeletion = false;
      return;
    }
    if (records[key]?.enrolled == true && authorization != _token) {
      throw const WalletAccessException(WalletAccessFailure.canceled);
    }
    records.remove(key);
    invalidated.remove(key);
  }

  @override
  Future<void> cancel() async {}
  @override
  Future<CredentialCapabilities> capabilities() => throw UnimplementedError();
  @override
  Future<String?> read(
    String key, {
    required String reason,
    bool requireAuthentication = false,
    bool automatic = false,
    String? purpose,
  }) => throw UnimplementedError();
  @override
  Future<void> write(
    String key,
    String value, {
    required bool requireAuthentication,
  }) => throw UnimplementedError();
  @override
  Future<PasswordManagerOutcome> savePassword({
    required String username,
    required String password,
    required String title,
  }) => throw UnimplementedError();
}

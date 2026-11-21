import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:web_dex/services/wallet_access/platform/native_credential_backend.dart';
import 'package:web_dex/services/wallet_access/wallet_access_types.dart';

const _key = 'immutable-entry.credential';
const _canary = 'synthetic-linux-secret-canary';

/// Fault injection is at the provider boundary; the production backend still
/// takes its real Platform.isLinux branch and uses real Linux files/chmod.
class _SecretService extends FlutterSecureStorage {
  final records = <String, String>{};
  bool unavailable = false;
  bool failWrite = false;
  bool failDelete = false;
  bool retainAfterDelete = false;
  final reads = <String>[];

  void _check(bool fail) {
    if (unavailable || fail) {
      throw PlatformException(code: 'provider-failure', message: _canary);
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    reads.add(key);
    _check(false);
    return records[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _check(failWrite);
    records[key] = value!;
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _check(failDelete);
    if (!retainAfterDelete) records.remove(key);
  }
}

String _record(String value, CredentialProtection protection) =>
    jsonEncode({'value': value, 'protection': protection.name});

Future<void> _storageFailure(Future<Object?> operation) async {
  try {
    await operation;
    fail('Expected a typed storage failure');
  } catch (error) {
    expect(error, isA<WalletAccessException>());
    expect(
      (error as WalletAccessException).failure,
      WalletAccessFailure.storageFailed,
    );
    expect(error.toString(), isNot(contains(_canary)));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group(
    'Linux credential backend',
    () {
      late Directory root;
      late _SecretService provider;
      late NativeCredentialBackend backend;
      File local() =>
          File(p.join(root.path, 'wallet_credentials', '$_key.json'));
      File marker() => File('${local().path}.secret-service');
      File pending() => File('${local().path}.pending');
      NativeCredentialBackend fresh() => NativeCredentialBackend(
        linuxStorage: provider,
        supportDirectory: () async => root,
      );
      Future<void> staleLocal({String? contents}) async {
        await local().parent.create(recursive: true);
        await local().writeAsString(
          contents ?? _record('stale', CredentialProtection.appLocal),
        );
      }

      Future<void> markProtected() async {
        await marker().parent.create(recursive: true);
        await marker().writeAsString('1');
      }

      setUp(() async {
        root = await Directory.systemTemp.createTemp('gleec-linux-credential-');
        provider = _SecretService();
        backend = fresh();
      });
      tearDown(() async => root.delete(recursive: true));

      test(
        'available Secret Service reports OS-account storage without biometrics',
        () async {
          final capability = await backend.capabilities();
          expect(
            capability.protection,
            CredentialProtection.osAccountProtected,
          );
          expect(capability.available, isTrue);
          expect(capability.deviceAuthentication, isFalse);
          await backend.write(_key, _canary, requireAuthentication: false);
          final info = (await backend.metadata(_key))!;
          expect(info.protection, CredentialProtection.osAccountProtected);
          expect(info.enrolled, isFalse);
          expect(await local().exists(), isFalse);
          expect(await marker().readAsString(), '1');
        },
      );

      test(
        'missing provider stores app-local with real 0700/0600 permissions',
        () async {
          provider.unavailable = true;
          final capability = await backend.capabilities();
          expect(capability.protection, CredentialProtection.appLocal);
          expect(capability.deviceAuthentication, isFalse);
          await backend.write(_key, _canary, requireAuthentication: false);
          expect((await local().parent.stat()).mode & 0x1ff, 0x1c0);
          expect((await local().stat()).mode & 0x1ff, 0x180);
          expect(await pending().exists(), isFalse);
          expect(await marker().exists(), isFalse);
          expect(await fresh().read(_key, reason: 'test'), _canary);
          final info = (await backend.metadata(_key))!;
          expect(info.protection, CredentialProtection.appLocal);
          expect(info.enrolled, isFalse);
        },
      );

      test(
        'app-local policy remains explicit when a provider appears later',
        () async {
          provider.unavailable = true;
          await backend.write(_key, 'initial', requireAuthentication: false);
          provider.unavailable = false;
          backend = fresh();
          expect(
            (await backend.capabilities()).protection,
            CredentialProtection.osAccountProtected,
          );
          await backend.write(_key, 'updated', requireAuthentication: false);
          expect(
            (await backend.metadata(_key))!.protection,
            CredentialProtection.appLocal,
          );
          expect(await backend.read(_key, reason: 'test'), 'updated');
          expect(provider.records, isEmpty);
        },
      );

      for (final stale in [
        'malformed $_canary',
        _record('stale', CredentialProtection.appLocal),
      ]) {
        test(
          'protected marker wins over ${stale.startsWith('malformed') ? 'corrupt' : 'valid'} unattended file',
          () async {
            await staleLocal(contents: stale);
            await markProtected();
            provider.records[_key] = _record(
              'protected-value',
              CredentialProtection.osAccountProtected,
            );
            expect(await backend.read(_key, reason: 'test'), 'protected-value');
            expect(
              (await backend.metadata(_key))!.protection,
              CredentialProtection.osAccountProtected,
            );
            expect(await local().readAsString(), stale);
          },
        );
      }

      test(
        'provider loss never opens or rewrites the unattended shadow',
        () async {
          await staleLocal();
          await markProtected();
          provider.unavailable = true;
          expect(
            (await backend.capabilities()).protection,
            CredentialProtection.appLocal,
          );
          await _storageFailure(backend.read(_key, reason: 'test'));
          await _storageFailure(backend.metadata(_key));
          await _storageFailure(
            backend.write(_key, _canary, requireAuthentication: false),
          );
          expect(
            await local().readAsString(),
            _record('stale', CredentialProtection.appLocal),
          );
          expect(await marker().exists(), isTrue);
        },
      );

      test(
        'missing protected record never resolves to its local shadow',
        () async {
          await staleLocal();
          await markProtected();
          expect(await backend.read(_key, reason: 'test'), isNull);
          expect(await backend.metadata(_key), isNull);
          expect(await marker().exists(), isTrue);
        },
      );

      test(
        'verified protected write removes obsolete local and pending copies',
        () async {
          await staleLocal();
          await pending().writeAsString('obsolete');
          await markProtected();
          await backend.write(_key, _canary, requireAuthentication: false);
          expect(await local().exists(), isFalse);
          expect(await pending().exists(), isFalse);
          expect(await marker().exists(), isTrue);
          expect((await marker().parent.stat()).mode & 0x1ff, 0x1c0);
          expect((await marker().stat()).mode & 0x1ff, 0x180);
          expect(await backend.read(_key, reason: 'test'), _canary);
        },
      );

      test(
        'failed first protected write preserves policy through backend restart',
        () async {
          provider.failWrite = true;
          await _storageFailure(
            backend.write(_key, _canary, requireAuthentication: false),
          );
          expect(await marker().exists(), isTrue);
          expect(await local().exists(), isFalse);
          provider.unavailable = true;
          await _storageFailure(
            fresh().write(_key, _canary, requireAuthentication: false),
          );
          expect(await local().exists(), isFalse);
        },
      );

      for (final (index, malformed) in [
        'broken $_canary',
        jsonEncode([_canary]),
        jsonEncode({'value': 123, 'protection': 'appLocal'}),
        jsonEncode({'value': _canary}),
        _record(_canary, CredentialProtection.osAccountProtected),
      ].indexed) {
        test(
          'invalid local record shape $index fails without secret diagnostics',
          () async {
            await staleLocal(contents: malformed);
            await _storageFailure(backend.read(_key, reason: 'test'));
            await _storageFailure(backend.metadata(_key));
          },
        );
      }

      test('corrupt provider data is sanitized and cannot downgrade', () async {
        await staleLocal();
        await markProtected();
        provider.records[_key] = 'corrupt $_canary';
        await _storageFailure(backend.read(_key, reason: 'test'));
        provider.records[_key] = _record(
          _canary,
          CredentialProtection.appLocal,
        );
        await _storageFailure(backend.metadata(_key));
      });

      for (final loseProvider in [false, true]) {
        test(
          'delete ${loseProvider ? 'provider loss' : 'provider rejection'} keeps policy and redacts errors',
          () async {
            await backend.write(_key, _canary, requireAuthentication: false);
            provider.unavailable = loseProvider;
            provider.failDelete = !loseProvider;
            await _storageFailure(fresh().delete(_key));
            expect(await marker().exists(), isTrue);
            expect(provider.records.containsKey(_key), isTrue);
          },
        );
      }

      test(
        'delete verifies provider absence before removing policy and shadows',
        () async {
          await backend.write(_key, _canary, requireAuthentication: false);
          await staleLocal();
          await pending().writeAsString('pending');
          provider.retainAfterDelete = true;
          await _storageFailure(backend.delete(_key));
          expect(await marker().exists(), isTrue);
          expect(await local().exists(), isTrue);
          provider.retainAfterDelete = false;
          await backend.delete(_key);
          expect(provider.records.containsKey(_key), isFalse);
          expect(await marker().exists(), isFalse);
          expect(await local().exists(), isFalse);
          expect(await pending().exists(), isFalse);
        },
      );

      test(
        'fresh backend can delete app-local and pending files without a provider',
        () async {
          provider.unavailable = true;
          await backend.write(_key, _canary, requireAuthentication: false);
          await pending().writeAsString(_canary);
          await fresh().delete(_key);
          expect(await local().exists(), isFalse);
          expect(await pending().exists(), isFalse);
        },
      );

      test(
        'real Linux deletion failure is typed and preserves the credential',
        () async {
          final uid = await Process.run('id', ['-u']);
          if (uid.stdout.toString().trim() == '0') {
            markTestSkipped(
              'Permission denial requires an unprivileged Linux user',
            );
            return;
          }
          provider.unavailable = true;
          await backend.write(_key, _canary, requireAuthentication: false);
          expect(
            (await Process.run('chmod', ['500', local().parent.path])).exitCode,
            0,
          );
          try {
            await _storageFailure(backend.delete(_key));
            expect(await local().exists(), isTrue);
          } finally {
            await Process.run('chmod', ['700', local().parent.path]);
          }
        },
      );

      test(
        'filesystem failures remain typed without leaking error paths',
        () async {
          backend = NativeCredentialBackend(
            linuxStorage: provider,
            supportDirectory: () async => throw FileSystemException(_canary),
          );
          await _storageFailure(backend.read(_key, reason: 'test'));
          await _storageFailure(
            backend.write(_key, _canary, requireAuthentication: false),
          );
          await _storageFailure(backend.delete(_key));
        },
      );

      test('Linux never promises an authentication-bound operation', () async {
        await expectLater(
          backend.write(_key, _canary, requireAuthentication: true),
          throwsA(
            isA<WalletAccessException>().having(
              (error) => error.failure,
              'failure',
              WalletAccessFailure.unavailable,
            ),
          ),
        );
        await expectLater(
          backend.read(_key, reason: 'test', requireAuthentication: true),
          throwsA(
            isA<WalletAccessException>().having(
              (error) => error.failure,
              'failure',
              WalletAccessFailure.unavailable,
            ),
          ),
        );
        expect(provider.records, isEmpty);
        expect(
          await backend.savePassword(
            username: 'wallet',
            password: _canary,
            title: 'wallet',
          ),
          PasswordManagerOutcome.unavailable,
        );
      });
    },
    skip: Platform.isLinux
        ? false
        : 'Requires real Linux filesystem and Platform.isLinux branch',
  );
}

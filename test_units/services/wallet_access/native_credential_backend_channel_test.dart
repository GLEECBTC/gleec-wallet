import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/services/wallet_access/platform/native_credential_backend.dart';
import 'package:web_dex/services/wallet_access/wallet_access_types.dart';

const _key = 'immutable-entry.credential';

Matcher _fails(WalletAccessFailure failure) => throwsA(
  isA<WalletAccessException>().having(
    (error) => error.failure,
    'failure',
    failure,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('credential channel error codes', () {
    test('an interrupted prompt fails enrolment and cancels anything else', () {
      expect(
        credentialChannelFailure('interrupted', enrolling: true),
        WalletAccessFailure.unavailable,
      );
      expect(
        credentialChannelFailure('interrupted', enrolling: false),
        WalletAccessFailure.canceled,
      );
    });

    test('a user cancellation stays a cancellation in both cases', () {
      for (final enrolling in [true, false]) {
        for (final code in ['canceled', 'cancelled']) {
          expect(
            credentialChannelFailure(code, enrolling: enrolling),
            WalletAccessFailure.canceled,
          );
        }
      }
    });

    test('the remaining codes keep their closed mapping', () {
      const expected = {
        'unavailable': WalletAccessFailure.unavailable,
        'invalidated': WalletAccessFailure.invalidated,
        'lockedOut': WalletAccessFailure.lockedOut,
        'busy': WalletAccessFailure.busy,
        'storageFailed': WalletAccessFailure.storageFailed,
        'anything-else': WalletAccessFailure.storageFailed,
      };
      for (final enrolling in [true, false]) {
        for (final MapEntry(key: code, value: failure) in expected.entries) {
          expect(credentialChannelFailure(code, enrolling: enrolling), failure);
        }
      }
    });
  });

  group(
    'native credential channel',
    () {
      const channel = MethodChannel('test/credential-vault');
      final calls = <MethodCall>[];
      late String code;
      late NativeCredentialBackend backend;

      setUp(() {
        calls.clear();
        code = 'interrupted';
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              throw PlatformException(code: code);
            });
        backend = NativeCredentialBackend(channel: channel);
      });
      tearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      Future<String?> readback() => backend.read(
        _key,
        reason: 'Confirm wallet protection',
        purpose: 'verifyWrite',
        requireAuthentication: true,
      );

      test(
        'interrupted protected write is unavailable, not declined',
        () async {
          await expectLater(
            backend.write(_key, 'value', requireAuthentication: true),
            _fails(WalletAccessFailure.unavailable),
          );
          expect(calls.single.method, 'write');
          expect(calls.single.arguments, {
            'key': _key,
            'value': 'value',
            'requireAuthentication': true,
          });
        },
      );

      test('interrupted enrolment readback is unavailable', () async {
        await expectLater(readback(), _fails(WalletAccessFailure.unavailable));
        expect(calls.single.method, 'read');
        expect(calls.single.arguments, {
          'key': _key,
          'reason': 'Confirm wallet protection',
          'requireAuthentication': true,
          'purpose': 'verifyWrite',
        });
      });

      test('interrupted key repair is unavailable', () async {
        await expectLater(
          backend.repairInvalidated(_key, 'value'),
          _fails(WalletAccessFailure.unavailable),
        );
        expect(calls.single.method, 'repairInvalidated');
      });

      test(
        'interrupted unlock and deletion calls stay cancellations',
        () async {
          final operations = <String, Future<Object?> Function()>{
            'read': () => backend.read(
              _key,
              reason: 'Unlock',
              requireAuthentication: true,
            ),
            'read for delete': () =>
                backend.read(_key, reason: 'Delete', purpose: 'delete'),
            'unprotected write': () =>
                backend.write(_key, 'value', requireAuthentication: false),
            'prepareDelete': () =>
                backend.prepareDelete(_key, reason: 'Delete'),
            'delete': () => backend.delete(_key),
            'metadata': () => backend.metadata(_key),
          };
          for (final MapEntry(key: name, value: operation)
              in operations.entries) {
            await expectLater(
              operation(),
              _fails(WalletAccessFailure.canceled),
              reason: name,
            );
          }
          expect(calls, hasLength(operations.length));
        },
      );

      test('declining the enrolment prompt is still a cancellation', () async {
        code = 'canceled';
        await expectLater(
          backend.write(_key, 'value', requireAuthentication: true),
          _fails(WalletAccessFailure.canceled),
        );
        await expectLater(readback(), _fails(WalletAccessFailure.canceled));
      });
    },
    skip: Platform.isLinux
        ? 'Linux stores credentials without the native channel'
        : false,
  );

  group('Secret Service session-bus lookup', () {
    const owned = '''
   array [
      string "org.freedesktop.DBus"
      string "org.freedesktop.secrets"
   ]''';
    const other = '''
   array [
      string "org.freedesktop.DBus"
      string "org.freedesktop.secrets.Extra"
   ]''';
    final asked = <String>[];
    final commands = <String>[];
    setUp(() {
      asked.clear();
      commands.clear();
    });

    Future<ProcessResult> Function(String, List<String>) bus(
      Map<String, String> replies, {
      Set<String> missing = const {},
      int exitCode = 0,
    }) => (tool, arguments) async {
      final method = arguments.last.split('.').last;
      asked.add('$tool $method');
      commands.add([tool, ...arguments].join(' '));
      if (missing.contains(tool)) throw ProcessException(tool, arguments);
      return ProcessResult(1, exitCode, replies[method] ?? other, '');
    };

    test('a provider that owns the bus name is present', () async {
      expect(
        await secretServiceOnSessionBus(run: bus({'ListNames': owned})),
        isTrue,
      );
      expect(asked, ['gdbus ListNames']);
    });

    test('a provider that can be started on demand is present', () async {
      expect(
        await secretServiceOnSessionBus(
          run: bus({'ListActivatableNames': "(['org.freedesktop.secrets'],)"}),
        ),
        isTrue,
      );
      expect(asked, ['gdbus ListNames', 'gdbus ListActivatableNames']);
    });

    test('the next tool is asked when one is not installed', () async {
      expect(
        await secretServiceOnSessionBus(
          run: bus({'ListNames': owned}, missing: {'gdbus'}),
        ),
        isTrue,
      );
      expect(asked, ['gdbus ListNames', 'dbus-send ListNames']);
    });

    test('a bus without the provider, or a longer name, is absent', () async {
      expect(await secretServiceOnSessionBus(run: bus({})), isFalse);
      expect(asked, ['gdbus ListNames', 'gdbus ListActivatableNames']);
    });

    test('no reachable bus and no tool both read as absent', () async {
      expect(
        await secretServiceOnSessionBus(
          run: bus({'ListNames': owned}, exitCode: 1),
        ),
        isFalse,
      );
      expect(commands, [
        for (final method in ['ListNames', 'ListActivatableNames']) ...[
          'gdbus call --session --dest org.freedesktop.DBus '
              '--object-path /org/freedesktop/DBus '
              '--method org.freedesktop.DBus.$method',
          'dbus-send --session --print-reply --dest=org.freedesktop.DBus '
              '/org/freedesktop/DBus org.freedesktop.DBus.$method',
          'busctl --user call org.freedesktop.DBus /org/freedesktop/DBus '
              'org.freedesktop.DBus $method',
        ],
      ]);
      expect(
        await secretServiceOnSessionBus(
          run: bus(
            {'ListNames': owned},
            missing: {'gdbus', 'dbus-send', 'busctl'},
          ),
        ),
        isFalse,
      );
    });
  });
}

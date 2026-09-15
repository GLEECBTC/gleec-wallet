import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';
import 'package:web_dex/services/file_loader/guarded_file_saver.dart';
import 'package:web_dex/services/file_loader/guarded_file_saver_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Guarded desktop export', () {
    late Directory directory;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('guarded-export-');
    });
    tearDown(() async => directory.delete(recursive: true));

    test(
      'revocation in the authentication continuation prevents a write',
      () async {
        final file = File(path.join(directory.path, 'keys.json'));
        var authorized = true;
        final saver = DesktopGuardedFileSaver(
          selectDestination: (_) async => file.path,
        );
        await expectLater(
          saver.save(
            fileName: 'keys.json',
            data: 'SECRET_SENTINEL',
            beforeWrite: () async =>
                scheduleMicrotask(() => authorized = false),
            beforeCommit: () {
              if (!authorized) throw StateError('Session expired');
            },
          ),
          throwsStateError,
        );
        expect(file.existsSync(), isFalse);
      },
    );

    test('session invalidation during picker never writes a key', () async {
      final file = File(path.join(directory.path, 'keys.json'));
      var authorized = true;
      final saver = DesktopGuardedFileSaver(
        selectDestination: (_) async {
          authorized = false;
          return file.path;
        },
      );
      await expectLater(
        saver.save(
          fileName: 'keys.json',
          data: 'SECRET_SENTINEL',
          beforeCommit: () {},
          beforeWrite: () async {
            if (!authorized) throw StateError('Session expired');
          },
        ),
        throwsStateError,
      );
      expect(await file.exists(), isFalse);
    });

    test(
      'cancel is distinct and an authorized save preserves exact data',
      () async {
        var checks = 0;
        final cancel = DesktopGuardedFileSaver(
          selectDestination: (_) async => null,
        );
        expect(
          await cancel.save(
            fileName: 'keys.json',
            data: 'key',
            beforeCommit: () {},
            beforeWrite: () async {
              checks++;
            },
          ),
          FileSaveOutcome.cancelled,
        );
        expect(checks, 0);
        final file = File(path.join(directory.path, 'keys.json'));
        final saver = DesktopGuardedFileSaver(
          selectDestination: (_) async => file.path,
        );
        expect(
          await saver.save(
            fileName: 'keys.json',
            data: 'SECRET_SENTINEL',
            beforeCommit: () {},
            beforeWrite: () async {
              checks++;
            },
          ),
          FileSaveOutcome.completed,
        );
        expect(checks, 1);
        expect(await file.readAsString(), 'SECRET_SENTINEL');
      },
    );
  });

  group('Guarded Android export channel', () {
    const channel = MethodChannel('test/guarded-export');
    const saver = AndroidGuardedFileSaver(channel: channel);
    final calls = <MethodCall>[];
    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return call.method == 'chooseDestination' ? 'opaque-token' : null;
          });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
      'microtask revocation discards the destination without sending data',
      () async {
        var authorized = true;
        await expectLater(
          saver.save(
            fileName: 'keys.json',
            data: 'SECRET_SENTINEL',
            beforeWrite: () async =>
                scheduleMicrotask(() => authorized = false),
            beforeCommit: () {
              if (!authorized) throw StateError('Session expired');
            },
          ),
          throwsStateError,
        );
        expect(calls.map((call) => call.method), [
          'chooseDestination',
          'discard',
        ]);
      },
    );

    test(
      'picker receives no bytes and rejected session only discards destination',
      () async {
        await expectLater(
          saver.save(
            fileName: 'keys.json',
            data: 'SECRET_SENTINEL',
            beforeCommit: () {},
            beforeWrite: () async => throw StateError('Session expired'),
          ),
          throwsStateError,
        );
        expect(calls.map((call) => call.method), [
          'chooseDestination',
          'discard',
        ]);
        expect(
          calls.map((call) => call.arguments).toString(),
          isNot(contains('SECRET_SENTINEL')),
        );
      },
    );

    test('key bytes cross the channel only after authorization', () async {
      expect(
        await saver.save(
          fileName: 'keys.json',
          data: 'SECRET_SENTINEL',
          beforeCommit: () {},
          beforeWrite: () async {
            expect(calls.map((call) => call.method), ['chooseDestination']);
          },
        ),
        FileSaveOutcome.completed,
      );
      expect(calls.map((call) => call.method), [
        'chooseDestination',
        'write',
        'discard',
      ]);
      expect(calls[1].arguments, {
        'token': 'opaque-token',
        'data': 'SECRET_SENTINEL',
      });
    });
  });

  group('Guarded iOS share staging', () {
    late Directory directory;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('ios-key-export-test-');
    });
    tearDown(() async => directory.delete(recursive: true));

    test(
      'dismissed sharing removes staged keys and reports cancellation',
      () async {
        final saver = IosGuardedFileSaver(
          temporaryDirectory: () async => directory,
          share: (params) async {
            expect(
              await File(params.files!.single.path).readAsString(),
              'SECRET_SENTINEL',
            );
            return const ShareResult('', ShareResultStatus.dismissed);
          },
        );
        expect(
          await saver.save(
            fileName: 'keys.json',
            data: 'SECRET_SENTINEL',
            beforeWrite: () async {},
            beforeCommit: () {},
          ),
          FileSaveOutcome.cancelled,
        );
        expect(await directory.list().isEmpty, isTrue);
      },
    );

    test('share failure still removes staged keys', () async {
      final saver = IosGuardedFileSaver(
        temporaryDirectory: () async => directory,
        share: (_) async => throw StateError('Sharing failed'),
      );
      await expectLater(
        saver.save(
          fileName: 'keys.json',
          data: 'SECRET_SENTINEL',
          beforeWrite: () async {},
          beforeCommit: () {},
        ),
        throwsStateError,
      );
      expect(await directory.list().isEmpty, isTrue);
    });
  });
}

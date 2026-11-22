import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';
import 'package:web_dex/services/file_loader/file_loader.dart';
import 'package:web_dex/services/file_loader/guarded_file_saver.dart';
import 'package:web_dex/services/file_loader/guarded_file_saver_native.dart';
import 'package:web_dex/services/file_loader/mobile/file_loader_native_android.dart';
import 'package:web_dex/services/file_loader/mobile/file_loader_native_ios.dart';

/// The system import picker: reports what it was asked to offer and returns
/// the file the "user" chose.
class _ImportPicker extends FilePicker {
  PlatformFile? picked;
  List<String>? offered;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    offered = allowedExtensions;
    final file = picked;
    return file == null ? null : FilePickerResult([file]);
  }
}

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
      'destination request declares the type its file name maps to',
      () async {
        // A JSON type on a .txt name made Android save "<name>.txt.json".
        for (final (name, mimeType) in const [
          ('wallet.txt', 'text/plain'),
          ('my.wallet', 'text/plain'),
          ('keys.json', 'application/json'),
          ('KEYS.JSON', 'application/json'),
        ]) {
          calls.clear();
          await saver.save(
            fileName: name,
            data: 'SECRET_SENTINEL',
            beforeWrite: () async {},
            beforeCommit: () {},
          );
          expect(calls.first.method, 'chooseDestination');
          expect(calls.first.arguments, {
            'fileName': name,
            'mimeType': mimeType,
          });
        }
      },
    );

    test('revoked operation never opens the destination picker', () async {
      await expectLater(
        saver.save(
          fileName: 'keys.json',
          data: 'SECRET_SENTINEL',
          beforeWrite: () async {},
          beforeCommit: () => throw StateError('Session expired'),
        ),
        throwsStateError,
      );
      expect(calls, isEmpty);
    });

    test(
      'owned selection failure still discards its returned native token',
      () async {
        await expectLater(
          saver.save(
            fileName: 'keys.json',
            data: 'SECRET_SENTINEL',
            beforeWrite: () async {},
            beforeCommit: () {},
            selectDestination: (choose) async {
              expect(await choose(), 'opaque-token');
              throw StateError('Foreground authorization expired');
            },
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

    test(
      'owned selection finishes before any write authorization or bytes',
      () async {
        final order = <String>[];
        final outcome = await saver.save(
          fileName: 'keys.json',
          data: 'SECRET_SENTINEL',
          beforeCommit: () => order.add('guard'),
          beforeWrite: () async => order.add('write'),
          selectDestination: (choose) async {
            order.add('owned-start');
            final token = await choose();
            expect(calls.map((call) => call.method), ['chooseDestination']);
            order.add('owned-return');
            return token;
          },
        );
        expect(outcome, FileSaveOutcome.completed);
        expect(order, [
          'guard',
          'owned-start',
          'owned-return',
          'write',
          'guard',
        ]);
        expect(calls.map((call) => call.method), [
          'chooseDestination',
          'write',
          'discard',
        ]);
      },
    );

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

    test('staged export is shared as the type its name maps to', () async {
      final shared = <String, String?>{};
      final saver = IosGuardedFileSaver(
        temporaryDirectory: () async => directory,
        share: (params) async {
          final file = params.files!.single;
          shared[path.basename(file.path)] = file.mimeType;
          return const ShareResult('', ShareResultStatus.success);
        },
      );
      for (final name in ['wallet.txt', 'keys.json']) {
        expect(
          await saver.save(
            fileName: name,
            data: 'SECRET_SENTINEL',
            beforeWrite: () async {},
            beforeCommit: () {},
          ),
          FileSaveOutcome.completed,
        );
      }
      expect(shared, {
        'wallet.txt': 'text/plain',
        'keys.json': 'application/json',
      });
    });

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

  group('Mobile import picker', () {
    late Directory directory;
    late _ImportPicker picker;
    FilePicker? previousPicker;

    setUpAll(() {
      try {
        previousPicker = FilePicker.platform;
      } on Error {
        previousPicker = null;
      }
    });
    tearDownAll(() {
      if (previousPicker case final picker?) FilePicker.platform = picker;
    });
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('import-picker-test-');
      picker = _ImportPicker();
      FilePicker.platform = picker;
    });
    tearDown(() async => directory.delete(recursive: true));

    Future<({String? name, String? content, String? error})> pick(
      FileLoader loader,
      String fileName,
    ) async {
      final file = File(path.join(directory.path, fileName))
        ..writeAsStringSync('BACKUP');
      picker.picked = PlatformFile(path: file.path, name: fileName, size: 6);
      String? name;
      String? content;
      String? error;
      await loader.upload(
        fileType: LoadFileType.text,
        onUpload: (pickedName, pickedContent) {
          name = pickedName;
          content = pickedContent;
        },
        onError: (message) => error = message,
      );
      return (name: name, content: content, error: error);
    }

    test('only a .txt.json export is accepted among JSON documents', () {
      expect(LoadFileType.text.importExtensions, ['txt', 'json']);
      expect(LoadFileType.compressed.importExtensions, ['zip']);
      for (final name in ['wallet.txt', 'wallet.txt.json', 'Wallet.TXT.JSON']) {
        expect(LoadFileType.text.acceptsImport(name), isTrue, reason: name);
      }
      // A provider may show a text document without any extension.
      expect(LoadFileType.text.acceptsImport('wallet'), isTrue);
      for (final name in ['keys.json', 'KEYS.JSON', 'wallet.txt.old.json']) {
        expect(LoadFileType.text.acceptsImport(name), isFalse, reason: name);
      }
    });

    for (final (platform, loader) in const <(String, FileLoader)>[
      ('Android', FileLoaderNativeAndroid()),
      ('iOS', FileLoaderNativeIOS()),
    ]) {
      test(
        '$platform import reads a .txt.json backup and no other JSON file',
        () async {
          final legacy = await pick(loader, 'wallet.txt.json');
          expect(picker.offered, ['txt', 'json']);
          expect(legacy.name, 'wallet.txt.json');
          expect(legacy.content, 'BACKUP');
          expect(legacy.error, isNull);

          expect((await pick(loader, 'wallet.txt')).content, 'BACKUP');

          final other = await pick(loader, 'private_keys_1.json');
          expect(other.content, isNull);
          expect(other.error, isNotNull);
        },
      );
    }
  });
}

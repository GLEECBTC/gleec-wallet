import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/services/file_loader/file_loader.dart';
import 'package:web_dex/services/logger/diagnostic_log_bridge.dart';
import 'package:web_dex/services/logger/diagnostic_log_store.dart';
import 'package:web_dex/services/logger/mock_logger.dart';
import 'package:web_dex/services/logger/safe_log_exporter.dart';
import 'package:web_dex/services/logger/universal_logger.dart';
import 'package:web_dex/services/platform_info/platform_info.dart';

class _Store implements DiagnosticLogStore {
  final records = <String>[];
  Future<void>? ready;
  var attempts = 0;
  var reads = 0;
  var closed = false;
  bool fail = false;
  @override
  Future<void> initialize() async {
    attempts++;
    await ready;
    if (fail) throw StateError('SENTINEL');
  }

  @override
  Future<void> writeRecord(String record) async => records.add(record);
  @override
  Stream<String> readRecords() {
    reads++;
    return Stream.fromIterable(records.map((record) => '$record\n'));
  }

  @override
  Future<void> dispose() async {
    closed = true;
  }
}

class _Platform extends PlatformInfo {
  const _Platform();
  @override
  String get osLanguage => 'en';
  @override
  String get platform => 'test';
  @override
  String get screenSize => '800x600';
  @override
  Future<PlatformType> get platformType async => PlatformType.unknown;
}

class _FileLoader implements FileLoader {
  String? data;
  @override
  Future<void> save({
    required String fileName,
    required String data,
    required LoadFileType type,
  }) async {
    this.data = data;
    expect(fileName, startsWith('komodo_wallet_log_'));
    expect(type, LoadFileType.compressed);
  }

  @override
  Future<void> upload({
    required void Function(String, String?) onUpload,
    required void Function(String) onError,
    LoadFileType? fileType,
  }) async {}
}

class _TrapError implements Exception {
  @override
  String toString() => throw StateError('An error object was stringified');
}

void main() {
  group('app diagnostic privacy and lifecycle', () {
    test(
      'concurrent init/export waits for cleanup and store readiness once',
      () async {
        final cleanup = Completer<void>();
        final storageReady = Completer<void>();
        final store = _Store()..ready = storageReady.future;
        var cleanups = 0;
        final logger = UniversalLogger(
          platformInfo: const _Platform(),
          store: store,
          purgeLegacyArtifacts: () {
            cleanups++;
            return cleanup.future;
          },
        );
        final init = logger.init();
        final export = logger.exportLogs();
        expect(cleanups, 1);
        expect(store.attempts, 0);
        cleanup.complete();
        await Future<void>.delayed(Duration.zero);
        expect(store.attempts, 1);
        expect(store.reads, 0);
        storageReady.complete();
        await init;
        expect((await export).isEmpty, isTrue);
        expect(cleanups, 1);
        await logger.dispose();
      },
    );

    test(
      'cleanup/storage failures never read stale data and can be retried',
      () async {
        final store = _Store()..records.add('{"message":"SENTINEL"}');
        var cleanupFails = true;
        final logger = UniversalLogger(
          platformInfo: const _Platform(),
          store: store,
          purgeLegacyArtifacts: () async {
            if (cleanupFails) throw StateError('SENTINEL');
          },
        );
        await logger
            .init(); // Optional logging must not abort application startup.
        await expectLater(
          logger.exportLogs(),
          throwsA(isA<DiagnosticLogsUnavailable>()),
        );
        expect(store.reads, 0);
        expect(store.attempts, 0);
        cleanupFails = false;
        store.fail = true;
        await expectLater(
          logger.exportLogs(),
          throwsA(isA<DiagnosticLogsUnavailable>()),
        );
        expect(store.reads, 0);
        store.fail = false;
        expect((await logger.exportLogs()).isEmpty, isTrue);
        expect(store.attempts, 2);
        await logger.dispose();
      },
    );

    test(
      'all sinks use safe copies and manual downloads share the exporter',
      () async {
        final store = _Store();
        final loader = _FileLoader();
        final logger = UniversalLogger(
          platformInfo: const _Platform(),
          store: store,
          fileLoader: loader,
          purgeLegacyArtifacts: () async {},
        );
        final prints = <String>[];
        await runZoned(
          () async {
            await logger.write('private_key=SENTINEL');
            await const MockLogger().write('seed=SENTINEL');
            await logger.init();
            logger.setSessionMetadata({
              'appVersion': '0.9.7',
              'wallet': 'SENTINEL',
            });
            await logger.write('RPC response: {"priv_key":"SENTINEL"}');
            await logger.write('Connected', 'Network');
            final debug = <String>[];
            await forwardDiagnosticRecord(
              LogRecord(
                Level.WARNING,
                'Connection failed',
                'Network',
                _TrapError(),
                StackTrace.fromString('private_key=SENTINEL'),
              ),
              logger,
              debugOutput: debug.add,
            );
            expect(debug.single, 'WARNING: Connection failed (unknown)');
            final attachment = await logger.exportLogs();
            await logger.getLogFile();
            expect(loader.data, utf8.decode(attachment.bytes));
            expect(loader.data, isNot(contains('SENTINEL')));
            expect(loader.data, contains('Connected'));
          },
          zoneSpecification: ZoneSpecification(
            print: (_, _, _, line) {
              prints.add(line);
            },
          ),
        );
        expect(prints, isEmpty);
        expect(store.records, hasLength(2));
        await logger.dispose();
        await logger.write('After disposal');
        await expectLater(
          logger.exportLogs(),
          throwsA(isA<DiagnosticLogsUnavailable>()),
        );
        expect(store.closed, isTrue);
        expect(store.records, hasLength(2));
      },
    );

    test(
      'custom levels and secret-bearing source names are classified',
      () async {
        final store = _Store();
        final logger = UniversalLogger(
          platformInfo: const _Platform(),
          store: store,
          purgeLegacyArtifacts: () async {},
        );
        await logger.init();
        final debug = <String>[];
        await forwardDiagnosticRecord(
          LogRecord(
            const Level('private_key=SENTINEL', 850),
            'Ready',
            'private_key=SENTINEL',
          ),
          logger,
          debugOutput: debug.add,
        );
        expect(debug.single, 'INFO: Ready');
        expect(store.records.single, isNot(contains('SENTINEL')));
        expect(jsonDecode(store.records.single).containsKey('source'), isFalse);
        await logger.dispose();
      },
    );

    test(
      'disposing during initialization cannot make exports ready again',
      () async {
        final ready = Completer<void>();
        final store = _Store()..ready = ready.future;
        final logger = UniversalLogger(
          platformInfo: const _Platform(),
          store: store,
          purgeLegacyArtifacts: () async {},
        );
        final init = logger.init();
        final dispose = logger.dispose();
        ready.complete();
        await init;
        await dispose;
        expect(store.closed, isTrue);
        await expectLater(
          logger.exportLogs(),
          throwsA(isA<DiagnosticLogsUnavailable>()),
        );
        expect(store.reads, 0);
      },
    );
  });
}

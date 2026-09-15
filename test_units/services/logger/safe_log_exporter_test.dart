import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/services/logger/safe_log_exporter.dart';

String diagnosticFixture(
  String message, {
  int timestamp = 1,
  Map<String, Object?> extra = const {},
}) =>
    '${jsonEncode({'schema': 1, 'timestamp': timestamp, 'message': message, ...extra})}\n';

class FixtureLogSource implements DiagnosticLogSource {
  FixtureLogSource(this.chunks, {this.readiness});
  final List<String> chunks;
  final Future<void>? readiness;
  var reads = 0;
  @override
  Future<void> ensureReady() async => readiness;
  @override
  Stream<String> readRecords() {
    reads++;
    return Stream.fromIterable(chunks);
  }
}

class _FailingLogSource extends FixtureLogSource {
  _FailingLogSource() : super(const []);

  @override
  Stream<String> readRecords() async* {
    yield diagnosticFixture('Ready');
    throw StateError('private_key=SENTINEL');
  }
}

void main() {
  group('safe diagnostic exporter', () {
    test(
      'rejects legacy, payload, malformed and unknown-schema records across chunks',
      () async {
        final text =
            'legacy seed: SENTINEL\n'
            '${diagnosticFixture('Connected')}'
            '${diagnosticFixture('RPC response: {"priv_key":"SENTINEL"}')}'
            '${diagnosticFixture('private_key=SENTINEL')}'
            '${diagnosticFixture('first line\nSENTINEL')}'
            '${diagnosticFixture('Connected', extra: {'schema': 99})}'
            '${diagnosticFixture('Connected', extra: {'payload': 'SENTINEL'})}'
            '{invalid SENTINEL}\n';
        final source = FixtureLogSource(text.split(''));
        final attachment = await SafeLogExporter(source: source).export();
        expect(utf8.decode(attachment.bytes), diagnosticFixture('Connected'));
      },
    );

    test(
      'scrubs optional context/source and ignores unknown metadata',
      () async {
        final source = FixtureLogSource([
          diagnosticFixture(
            'Connected',
            extra: {
              'source': 'private_key=SENTINEL',
              'context': {
                'appVersion': '0.9.7',
                'wallet': 'SENTINEL',
                'platform': 'secret=SENTINEL',
              },
            },
          ),
        ]);
        final result = jsonDecode(
          utf8.decode((await SafeLogExporter(source: source).export()).bytes),
        );
        expect(result['context'], {'appVersion': '0.9.7'});
        expect(result.containsKey('source'), isFalse);
      },
    );

    test(
      'retains newest whole UTF-8 records and never cuts a record',
      () async {
        final first = diagnosticFixture('Connected ✓', timestamp: 1);
        final last = diagnosticFixture('Ready ✓', timestamp: 2);
        final cap = utf8.encode(last).length;
        final attachment = await SafeLogExporter(
          source: FixtureLogSource([first, last]),
        ).export(maxBytes: cap);
        expect(attachment.length, cap);
        expect(utf8.decode(attachment.bytes), last);
        final copy = attachment.bytes;
        copy.fillRange(0, copy.length, 0);
        expect(utf8.decode(attachment.bytes), last);
      },
    );

    test(
      'drops oversized and incomplete records without consuming the next entry',
      () async {
        final source = FixtureLogSource([
          'x' * (SafeLogExporter.maxRecordCharacters + 1),
          'SENTINEL\n',
          diagnosticFixture('Ready'),
          diagnosticFixture('Incomplete').trimRight(),
        ]);
        final result = await SafeLogExporter(source: source).export();
        expect(utf8.decode(result.bytes), diagnosticFixture('Ready'));
      },
    );

    test('awaits readiness and does not read when migration fails', () async {
      final ready = Completer<void>();
      final source = FixtureLogSource([
        diagnosticFixture('Ready'),
      ], readiness: ready.future);
      final export = SafeLogExporter(source: source).export();
      expect(source.reads, 0);
      final expectation = expectLater(
        export,
        throwsA(
          isA<DiagnosticLogsUnavailable>().having(
            (error) => error.toString(),
            'safe error',
            isNot(contains('SENTINEL')),
          ),
        ),
      );
      ready.completeError(StateError('SENTINEL'));
      await expectation;
      expect(source.reads, 0);
    });

    test('failed reads never expose partial exports or raw errors', () async {
      await expectLater(
        SafeLogExporter(source: _FailingLogSource()).export(),
        throwsA(
          isA<DiagnosticLogsUnavailable>().having(
            (error) => error.toString(),
            'safe error',
            isNot(contains('SENTINEL')),
          ),
        ),
      );
    });

    test(
      'empty exports remain valid and negative bounds are rejected',
      () async {
        final exporter = SafeLogExporter(
          source: FixtureLogSource([diagnosticFixture('Ready')]),
        );
        expect((await exporter.export(maxBytes: 0)).isEmpty, isTrue);
        await expectLater(exporter.export(maxBytes: -1), throwsArgumentError);
      },
    );
  });
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/gasless/tron_gasless_receive_gate.dart';

const _provider = 'TLntW9Z59LYY5KEi9cmwk3PKjQga828ird';
final _now = DateTime.utc(2026, 7, 10, 12);

void main() => testTronGaslessReceiveGate();

void testTronGaslessReceiveGate() {
  group('TRON GasFree runtime receive gate', () {
    test('control endpoint validation is HTTPS-only and credential-free', () {
      expect(tronGaslessControlUrl, isEmpty);
      expect(
        parseTronGaslessControlEndpoint(
          'https://config.gleec.com/v1/tron-gasfree',
        ),
        Uri.parse('https://config.gleec.com/v1/tron-gasfree'),
      );

      for (final unsafe in <String>[
        '',
        'http://config.gleec.com/v1/tron-gasfree',
        'https://user:secret@config.gleec.com/v1/tron-gasfree',
        'https://config.gleec.com',
        'https://config.gleec.com/',
        'https://config.gleec.com/v1/tron-gasfree/',
        'https://config.gleec.com/v1/tron-gasfree?enabled=true',
        'https://config.gleec.com/v1/tron-gasfree#override',
        'https://config.gleec.com/v1/%74ron-gasfree',
        'https://config.gleec.com/v1/../tron-gasfree',
        'https://config.gleec.com/v1/tron gasfree',
        'https://config_gleec.com/v1/tron-gasfree',
      ]) {
        expect(parseTronGaslessControlEndpoint(unsafe), isNull, reason: unsafe);
      }
    });

    test(
      'enables only a fresh response bound to network and provider',
      () async {
        late http.BaseRequest capturedRequest;
        final client = _FakeClient((request) async {
          capturedRequest = request;
          return _jsonResponse(_validBody(receiveEnabled: true));
        });
        final service = _service(client);

        final decision = await service.evaluate();

        expect(decision.outcome, TronGaslessReceiveGateOutcome.enabled);
        expect(decision.reason, GaslessReceiveReasonCode.remoteEnabled);
        expect(decision.receiveEnabled, isTrue);
        expect(decision.expiresAt, _now.add(const Duration(minutes: 2)));
        expect(capturedRequest.method, 'GET');
        expect(capturedRequest.followRedirects, isFalse);
        expect(capturedRequest.headers['Accept'], 'application/json');
        expect(capturedRequest.headers['Cache-Control'], 'no-cache');
      },
    );

    test(
      'honors a fresh remote disable without treating it as an error',
      () async {
        final service = _service(
          _FakeClient(
            (_) async => _jsonResponse(_validBody(receiveEnabled: false)),
          ),
        );

        final decision = await service.evaluate();

        expect(decision.outcome, TronGaslessReceiveGateOutcome.disabled);
        expect(decision.reason, GaslessReceiveReasonCode.remoteDisabled);
        expect(decision.receiveEnabled, isFalse);
      },
    );

    test(
      'fails closed for expired and excessively long-lived documents',
      () async {
        final expired = _service(
          _FakeClient(
            (_) async => _jsonResponse(
              _validBody(expiresAt: _now.subtract(const Duration(seconds: 1))),
            ),
          ),
        );
        final tooLong = _service(
          _FakeClient(
            (_) async => _jsonResponse(
              _validBody(expiresAt: _now.add(const Duration(minutes: 6))),
            ),
          ),
        );

        expect(
          (await expired.evaluate()).reason,
          GaslessReceiveReasonCode.remoteExpired,
        );
        expect(
          (await tooLong.evaluate()).reason,
          GaslessReceiveReasonCode.remoteExpiryTooFar,
        );
      },
    );

    test(
      'fails closed for malformed, extended, and cross-network JSON',
      () async {
        final malformed = _service(
          _FakeClient((_) async => _jsonResponse('{not-json')),
        );
        final extended = _service(
          _FakeClient(
            (_) async => _jsonResponse(
              jsonEncode({
                ..._validPayload(),
                'unexpected': 'must not be ignored',
              }),
            ),
          ),
        );
        final wrongNetwork = _service(
          _FakeClient(
            (_) async => _jsonResponse(
              jsonEncode({..._validPayload(), 'network': 'nile'}),
            ),
          ),
        );

        expect(
          (await malformed.evaluate()).reason,
          GaslessReceiveReasonCode.remoteMalformed,
        );
        expect(
          (await extended.evaluate()).reason,
          GaslessReceiveReasonCode.remoteSchemaMismatch,
        );
        expect(
          (await wrongNetwork.evaluate()).reason,
          GaslessReceiveReasonCode.remoteBindingMismatch,
        );
      },
    );

    test(
      'fails closed for redirects, non-JSON, and oversized bodies',
      () async {
        final redirect = _service(
          _FakeClient((request) async {
            expect(request.followRedirects, isFalse);
            return http.StreamedResponse(
              const Stream<List<int>>.empty(),
              302,
              headers: {'location': 'https://other.example/control'},
            );
          }),
        );
        final html = _service(
          _FakeClient(
            (_) async => http.StreamedResponse(
              Stream.value(utf8.encode('<html>not config</html>')),
              200,
              headers: {'content-type': 'text/html'},
            ),
          ),
        );
        final oversized = _service(
          _FakeClient(
            (_) async => http.StreamedResponse(
              Stream.value(List<int>.filled(4097, 32)),
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
        );

        expect(
          (await redirect.evaluate()).reason,
          GaslessReceiveReasonCode.remoteHttpRejected,
        );
        expect(
          (await html.evaluate()).reason,
          GaslessReceiveReasonCode.remoteContentTypeInvalid,
        );
        expect(
          (await oversized.evaluate()).reason,
          GaslessReceiveReasonCode.remoteResponseTooLarge,
        );
      },
    );

    test('transport errors and timeout stay retryable but disabled', () async {
      final transportError = _service(
        _FakeClient((_) async => throw StateError('offline')),
      );
      final timeout = _service(
        _FakeClient((_) => Completer<http.StreamedResponse>().future),
        timeout: const Duration(milliseconds: 5),
      );

      expect(
        (await transportError.evaluate()).reason,
        GaslessReceiveReasonCode.remoteUnavailable,
      );
      final timeoutDecision = await timeout.evaluate();
      expect(
        timeoutDecision.outcome,
        TronGaslessReceiveGateOutcome.unavailable,
      );
      expect(timeoutDecision.reason, GaslessReceiveReasonCode.remoteTimeout);
      expect(timeoutDecision.receiveEnabled, isFalse);
    });

    test('empty and unsafe control endpoints stay blocked', () async {
      var requests = 0;
      final client = _FakeClient((_) async {
        requests += 1;
        return _jsonResponse(_validBody());
      });
      final missing = HttpTronGaslessReceiveGate(
        endpoint: '',
        expectedNetwork: 'tron',
        expectedServiceProvider: _provider,
        httpClient: client,
        now: () => _now,
      );
      final unsafe = HttpTronGaslessReceiveGate(
        endpoint: 'http://config.gleec.com/control',
        expectedNetwork: 'tron',
        expectedServiceProvider: _provider,
        httpClient: client,
      );

      final missingDecision = await missing.evaluate();
      expect(missingDecision.outcome, TronGaslessReceiveGateOutcome.invalid);
      expect(
        missingDecision.reason,
        GaslessReceiveReasonCode.controlEndpointMissing,
      );
      expect(
        (await unsafe.evaluate()).reason,
        GaslessReceiveReasonCode.controlEndpointInvalid,
      );
      expect(requests, 0);
    });

    test('reason identifiers are stable and contain no configuration data', () {
      expect(GaslessReceiveReasonCode.ready.code, 'ready');
      expect(
        GaslessReceiveReasonCode.reactivationRequired.code,
        'reactivation_required',
      );
      expect(
        GaslessReceiveReasonCode.remoteBindingMismatch.code,
        'remote_binding_mismatch',
      );
      for (final reason in GaslessReceiveReasonCode.values) {
        expect(reason.code, isNot(contains('://')));
        expect(reason.code, isNot(contains(_provider)));
      }
    });
  });
}

HttpTronGaslessReceiveGate _service(
  http.Client client, {
  Duration timeout = const Duration(seconds: 1),
}) => HttpTronGaslessReceiveGate(
  endpoint: 'https://config.gleec.com/v1/tron-gasfree',
  expectedNetwork: 'tron',
  expectedServiceProvider: _provider,
  httpClient: client,
  now: () => _now,
  timeout: timeout,
);

Map<String, Object> _validPayload({
  bool receiveEnabled = true,
  DateTime? expiresAt,
}) => {
  'schemaVersion': 1,
  'receiveEnabled': receiveEnabled,
  'expiresAt': (expiresAt ?? _now.add(const Duration(minutes: 2)))
      .toIso8601String(),
  'network': 'tron',
  'serviceProvider': _provider,
};

String _validBody({bool receiveEnabled = true, DateTime? expiresAt}) =>
    jsonEncode(
      _validPayload(receiveEnabled: receiveEnabled, expiresAt: expiresAt),
    );

http.StreamedResponse _jsonResponse(String body) => http.StreamedResponse(
  Stream.value(utf8.encode(body)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class _FakeClient extends http.BaseClient {
  _FakeClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _handler(request);
}

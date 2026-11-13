import 'dart:async';
import 'dart:convert' show jsonEncode;
import 'dart:io' show HttpException;

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:web_dex/bloc/system_health/providers/http_time_provider.dart';

void testHttpTimeProvider() {
  group('HttpTimeProvider', () {
    late HttpTimeProvider provider;
    late MockClient mockClient;

    setUp(() {
      mockClient = MockClient();
      provider = HttpTimeProvider(
        url: 'http://example.com',
        timeFieldPath: 'currentDateTime',
        timeFormat: TimeFormat.iso8601,
        providerName: 'TestProvider',
        httpClient: mockClient,
      );
    });

    tearDown(() {
      provider.dispose();
    });

    test('returns DateTime when response is valid', () async {
      final now = DateTime.utc(2025, 5, 7, 12, 34, 56);
      mockClient.mockResponse = http.Response(
        jsonEncode({'currentDateTime': now.toIso8601String()}),
        200,
      );
      final result = await provider.getCurrentUtcTime();
      expect(result, equals(now));
    });

    test('throws HttpException on non-200 response', () async {
      mockClient.mockResponse = http.Response('error', 500);
      expect(() => provider.getCurrentUtcTime(), throwsA(isA<HttpException>()));
    });

    test('throws FormatException if field missing', () async {
      mockClient.mockResponse = http.Response(
        jsonEncode({'other': 'value'}),
        200,
      );
      expect(
        () => provider.getCurrentUtcTime(),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException on invalid date format', () async {
      mockClient.mockResponse = http.Response(
        jsonEncode({'currentDateTime': 'not-a-date'}),
        200,
      );
      expect(
        () => provider.getCurrentUtcTime(),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws HttpException on exception', () async {
      mockClient.shouldThrow = true;
      expect(() => provider.getCurrentUtcTime(), throwsA(isA<HttpException>()));
    });
  });
}

class MockClient extends http.BaseClient {
  http.Response mockResponse = http.Response('', 200);
  bool shouldThrow = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (shouldThrow) throw const HttpException('error');
    return http.StreamedResponse(
      Stream.value(mockResponse.bodyBytes),
      mockResponse.statusCode,
      headers: mockResponse.headers,
    );
  }
}

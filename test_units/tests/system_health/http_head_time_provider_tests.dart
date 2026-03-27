import 'dart:async' show TimeoutException;
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:web_dex/bloc/system_health/providers/http_head_time_provider.dart';

void testHttpHeadTimeProvider() {
  group('HttpHeadTimeProvider', () {
    late HttpHeadTimeProvider provider;
    late MockClient mockClient;

    setUp(() {
      mockClient = MockClient();
      provider = HttpHeadTimeProvider(
        httpClient: mockClient,
        timeout: const Duration(seconds: 1),
      );
    });

    tearDown(() {
      provider.dispose();
    });

    test('returns DateTime when header is valid', () async {
      // RFC 1123 date format used in HTTP headers
      const dateHeader = 'Wed, 07 May 2025 12:34:56 GMT';
      final expectedDateTime = HttpDate.parse(dateHeader);

      mockClient.mockResponse = http.Response(
        '',
        200,
        headers: {'date': dateHeader},
      );

      final result = await provider.getCurrentUtcTime();

      expect(result, isNotNull);
      expect(result, equals(expectedDateTime));
    });

    // Timeout expected because other servers should be tried rather than
    // exiting
    test('throws TimeoutException when date header is missing', () async {
      mockClient.mockResponse = http.Response('', 200, headers: {});

      expect(
        () => provider.getCurrentUtcTime(),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('throws TimeoutException when response status is not 200', () async {
      mockClient.mockResponse = http.Response('', 404);

      expect(
        () => provider.getCurrentUtcTime(),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('throws TimeoutException when all servers fail', () async {
      mockClient.mockResponse = http.Response('', 500);

      expect(
        () => provider.getCurrentUtcTime(),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('throws TimeoutException on timeout', () async {
      mockClient.shouldThrowTimeout = true;

      expect(
        () => provider.getCurrentUtcTime(),
        throwsA(isA<TimeoutException>()),
      );
    });

    // HttpDate.parse is used, which throws HttpException
    test('throws TimeoutException with invalid date', () async {
      mockClient.mockResponse = http.Response(
        '',
        200,
        headers: {'date': 'invalid-date-format'},
      );

      expect(
        () => provider.getCurrentUtcTime(),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}

/// Simple mock HTTP client for testing
class MockClient extends http.BaseClient {
  http.Response mockResponse = http.Response('', 200);
  bool shouldThrowTimeout = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (shouldThrowTimeout) {
      throw TimeoutException('Timeout');
    }

    return http.StreamedResponse(
      Stream.value(mockResponse.bodyBytes),
      mockResponse.statusCode,
      headers: mockResponse.headers,
    );
  }
}

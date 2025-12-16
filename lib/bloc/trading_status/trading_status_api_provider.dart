import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:web_dex/shared/constants.dart';

/// Provider responsible for making API calls to trading status endpoints.
class TradingStatusApiProvider {
  TradingStatusApiProvider({http.Client? httpClient, Duration? timeout})
    : _httpClient = httpClient ?? http.Client(),
      _timeout = timeout ?? const Duration(seconds: 10);

  final http.Client _httpClient;
  final Duration _timeout;
  final Logger _log = Logger('TradingStatusApiProvider');

  static const String _apiKeyHeader = 'X-KW-KEY';

  static Uri _ensureTrailingSlash(Uri uri) {
    if (uri.path.endsWith('/')) return uri;
    return uri.replace(path: '${uri.path}/');
  }

  /// Fetches trading status from the geo blocker API.
  ///
  /// Throws [TimeoutException] on timeout.
  /// Throws [http.ClientException] on HTTP client errors.
  /// Throws [FormatException] on JSON parsing errors.
  Future<Map<String, dynamic>> fetchGeoStatus({required String apiKey}) async {
    _log.fine('Fetching geo status from API');

    final uri = _ensureTrailingSlash(Uri.parse(geoBlockerApiUrl));
    final headers = <String, String>{_apiKeyHeader: apiKey};

    try {
      final response = await _httpClient
          .post(uri, headers: headers)
          .timeout(_timeout);

      _log.fine('Geo status API response: ${response.statusCode}');

      if (response.statusCode != 200) {
        _log.warning('Geo status API returned status ${response.statusCode}');
        throw http.ClientException(
          'API returned status ${response.statusCode}',
          uri,
        );
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      _log.fine('Successfully parsed geo status response');
      return data;
    } on TimeoutException catch (e) {
      _log.warning('Geo status API request timed out: $e');
      rethrow;
    } on http.ClientException catch (e) {
      _log.warning('HTTP client error fetching geo status: ${e.message}');
      rethrow;
    } on FormatException catch (e) {
      _log.severe('Failed to parse geo status JSON response: $e');
      rethrow;
    }
  }

  /// Fetches trading blacklist for testing purposes.
  ///
  /// Throws [TimeoutException] on timeout.
  /// Throws [http.ClientException] on HTTP client errors.
  Future<http.Response> fetchTradingBlacklist() async {
    _log.fine('Fetching trading blacklist for testing');

    final uri = Uri.parse(tradingBlacklistUrl);

    try {
      final response = await _httpClient
          .post(uri, headers: const <String, String>{})
          .timeout(_timeout);

      _log.fine('Trading blacklist API response: ${response.statusCode}');
      return response;
    } on TimeoutException catch (e) {
      _log.warning('Trading blacklist API request timed out: $e');
      rethrow;
    } on http.ClientException catch (e) {
      _log.warning(
        'HTTP client error fetching trading blacklist: ${e.message}',
      );
      rethrow;
    }
  }

  void dispose() {
    _httpClient.close();
  }
}

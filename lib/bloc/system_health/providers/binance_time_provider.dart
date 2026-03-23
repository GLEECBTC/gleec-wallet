import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:web_dex/bloc/system_health/providers/time_provider.dart';

/// A time provider that fetches time from the Binance API
class BinanceTimeProvider extends TimeProvider {
  BinanceTimeProvider({
    this.url = 'https://api.binance.com/api/v3/time',
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 2),
    this.maxRetries = 3,
    Logger? logger,
  }) : _httpClient = httpClient ?? http.Client(),
       _logger = logger ?? Logger('BinanceTimeProvider');

  /// The URL of the Binance time API
  final String url;

  /// Timeout for HTTP requests
  final Duration timeout;

  /// Maximum retries
  final int maxRetries;

  /// Logger instance
  final Logger _logger;

  /// HTTP client for making requests
  final http.Client _httpClient;

  @override
  String get name => 'Binance';

  @override
  Future<DateTime> getCurrentUtcTime() async {
    int retries = 0;

    while (retries < maxRetries) {
      try {
        final serverTime = await _fetchServerTime();
        _logger.fine('Successfully retrieved time from Binance API');
        return serverTime;
      } on SocketException catch (e, s) {
        _logger.warning('Socket error with Binance API', e, s);
      } on TimeoutException catch (e, s) {
        _logger.warning('Timeout with Binance API', e, s);
      } on FormatException catch (e, s) {
        _logger.severe('Failed to parse response from Binance API', e, s);
      } on Exception catch (e, s) {
        _logger.severe('Error fetching time from Binance API', e, s);
      }
      retries++;

      // Calculate exponential backoff: 100ms, 200ms, 400ms, 800ms...
      if (retries < maxRetries) {
        final delayDuration = Duration(milliseconds: 100 * (1 << retries));
        await Future<void>.delayed(delayDuration);
      }
    }

    _logger.severe(
      'Failed to get time from Binance API after $maxRetries retries',
    );
    throw TimeoutException(
      'Failed to get time from Binance API after $maxRetries retries',
    );
  }

  /// Fetches server time from the Binance API
  Future<DateTime> _fetchServerTime() async {
    final response = await _httpClient.get(Uri.parse(url)).timeout(timeout);

    if (response.statusCode != 200) {
      _logger.warning('HTTP error from $url: ${response.statusCode}');
      throw HttpException(
        'HTTP error from $url: ${response.statusCode}',
        uri: Uri.parse(url),
      );
    }

    final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
    final serverTime = (jsonData['serverTime'] as num?)?.toInt();

    if (serverTime == null) {
      throw const FormatException(
        'No serverTime field in Binance API response',
      );
    }

    return DateTime.fromMillisecondsSinceEpoch(serverTime, isUtc: true);
  }

  @override
  void dispose() {
    _httpClient.close();
  }
}

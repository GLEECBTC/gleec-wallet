import 'package:logging/logging.dart';
import 'package:web_dex/bloc/system_health/providers/time_provider_registry.dart';

class SystemClockRepository {
  SystemClockRepository({
    TimeProviderRegistry? providerRegistry,
    Duration? maxAllowedDifference,
    Duration? apiTimeout,
    Logger? logger,
  }) : _maxAllowedDifference =
           maxAllowedDifference ?? const Duration(seconds: 60),
       _providerRegistry =
           providerRegistry ?? TimeProviderRegistry(apiTimeout: apiTimeout),
       _logger = logger ?? Logger('SystemClockRepository');

  final Duration _maxAllowedDifference;
  final TimeProviderRegistry _providerRegistry;
  final Logger _logger;

  /// Queries the available time providers to validate the system clock validity
  /// returning true if the system clock is within allowed difference of the
  /// first provider that responds, false otherwise.
  ///
  /// Health-only callers retain the legacy fail-open behavior. Financial
  /// execution boundaries must pass [failClosed] so provider outages or
  /// malformed provider failures cannot bypass expiry checks.
  Future<bool> isSystemClockValid({bool failClosed = false}) async {
    try {
      final providers = _providerRegistry.providers;
      bool receivedValidResponse = false;

      for (final provider in providers) {
        try {
          final apiTime = await provider.getCurrentUtcTime();
          receivedValidResponse = true;

          final localTime = DateTime.timestamp();
          final Duration difference = apiTime.difference(localTime).abs();

          final isValid = difference < _maxAllowedDifference;
          if (isValid) {
            _logger.info('System clock validated by ${provider.name} provider');
          } else {
            _logger.warning(
              'System clock differs by ${difference.inSeconds}s from '
              '${provider.name} provider',
            );
          }

          return isValid;
        } catch (e, s) {
          _logger.severe('Provider ${provider.name} failed', e, s);
        }
      }

      if (!receivedValidResponse) {
        _logger.warning('All time providers failed to provide a time');
      }

      // Read-only screens may preserve the legacy fail-open behavior, but a
      // financial execution boundary must explicitly request fail-closed
      // validation so an unavailable time source cannot bypass expiries.
      return !failClosed;
    } catch (e, s) {
      _logger.shout('Failed to validate system clock', e, s);
      return !failClosed;
    }
  }

  void dispose() {
    _providerRegistry.dispose();
  }
}

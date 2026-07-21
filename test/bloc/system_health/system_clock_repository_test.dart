import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/system_health/providers/time_provider.dart';
import 'package:web_dex/bloc/system_health/providers/time_provider_registry.dart';
import 'package:web_dex/bloc/system_health/system_clock_repository.dart';

void main() {
  group('SystemClockRepository', () {
    test(
      'financial callers can fail closed when every provider fails',
      () async {
        final repository = SystemClockRepository(
          providerRegistry: TimeProviderRegistry(
            providers: [_FailingTimeProvider()],
          ),
        );
        addTearDown(repository.dispose);

        expect(await repository.isSystemClockValid(failClosed: true), isFalse);
      },
    );

    test('legacy health checks retain fail-open outage behavior', () async {
      final repository = SystemClockRepository(
        providerRegistry: TimeProviderRegistry(
          providers: [_FailingTimeProvider()],
        ),
      );
      addTearDown(repository.dispose);

      expect(await repository.isSystemClockValid(), isTrue);
    });

    test('rejects a clock outside the permitted skew', () async {
      final repository = SystemClockRepository(
        maxAllowedDifference: const Duration(seconds: 30),
        providerRegistry: TimeProviderRegistry(
          providers: [
            _FixedTimeProvider(
              () => DateTime.timestamp().add(const Duration(minutes: 2)),
            ),
          ],
        ),
      );
      addTearDown(repository.dispose);

      expect(await repository.isSystemClockValid(failClosed: true), isFalse);
    });
  });
}

class _FailingTimeProvider extends TimeProvider {
  @override
  String get name => 'failing';

  @override
  Future<DateTime> getCurrentUtcTime() async {
    throw StateError('provider unavailable');
  }
}

class _FixedTimeProvider extends TimeProvider {
  _FixedTimeProvider(this._now);

  final DateTime Function() _now;

  @override
  String get name => 'fixed';

  @override
  Future<DateTime> getCurrentUtcTime() async => _now();
}

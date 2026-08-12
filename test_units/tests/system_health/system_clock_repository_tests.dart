import 'package:test/test.dart';
import 'package:web_dex/bloc/system_health/providers/time_provider.dart';
import 'package:web_dex/bloc/system_health/providers/time_provider_registry.dart';
import 'package:web_dex/bloc/system_health/system_clock_repository.dart';

void testSystemClockRepository() {
  group('SystemClockRepository', () {
    late SystemClockRepository repository;
    late MockTimeProviderRegistry mockRegistry;

    setUp(() {
      mockRegistry = MockTimeProviderRegistry();
      repository = SystemClockRepository(
        providerRegistry: mockRegistry,
        maxAllowedDifference: const Duration(seconds: 30),
      );
    });

    tearDown(() {
      repository.dispose();
    });

    test('returns true when first provider returns valid time', () async {
      mockRegistry.mockProviders = [
        MockTimeProvider(name: 'ValidProvider', returnTime: DateTime.now()),
      ];

      final result = await repository.isSystemClockValid();

      expect(result, isTrue);
    });

    test('returns false when first provider time differs too much', () async {
      // This time is significantly different from local time
      mockRegistry.mockProviders = [
        MockTimeProvider(
          name: 'InvalidTimeProvider',
          returnTime: DateTime.utc(2030),
        ),
      ];

      final result = await repository.isSystemClockValid();

      expect(result, isFalse);
    });

    test('returns true when no providers respond', () async {
      mockRegistry.mockProviders = [
        MockTimeProvider(name: 'FailingProvider', returnTime: DateTime.now()),
      ];

      final result = await repository.isSystemClockValid();

      expect(result, isTrue);
    });

    test('returns true when provider throws exception', () async {
      mockRegistry.mockProviders = [
        MockTimeProvider(
          name: 'ExceptionProvider',
          shouldThrow: true,
          returnTime: DateTime.now(),
        ),
      ];

      final result = await repository.isSystemClockValid();

      expect(result, isTrue);
    });

    test('uses provider order from registry', () async {
      final validProvider = MockTimeProvider(
        name: 'ValidProvider',
        returnTime: DateTime.timestamp().toUtc(),
      );
      final failingProvider = MockTimeProvider(
        name: 'FailingProvider',
        returnTime: DateTime.now(),
      );

      mockRegistry.mockProviders = [validProvider, failingProvider];
      await repository.isSystemClockValid();

      expect(validProvider.callCount, 1);
      expect(failingProvider.callCount, 0);
    });
  });
}

class MockTimeProviderRegistry implements TimeProviderRegistry {
  List<TimeProvider> mockProviders = [];

  @override
  List<TimeProvider> get providers => mockProviders;

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return null;
  }
}

class MockTimeProvider extends TimeProvider {
  MockTimeProvider({
    required String name,
    required this.returnTime,
    this.shouldThrow = false,
  }) : _name = name;

  final String _name;
  final DateTime returnTime;
  final bool shouldThrow;
  int callCount = 0;

  @override
  String get name => _name;

  @override
  Future<DateTime> getCurrentUtcTime() async {
    callCount++;
    if (shouldThrow) {
      throw Exception('Test exception');
    }
    return returnTime;
  }
}

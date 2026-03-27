import 'package:test/test.dart';
import 'package:web_dex/bloc/system_health/providers/time_provider.dart';
import 'package:web_dex/bloc/system_health/providers/time_provider_registry.dart';

void testTimeProviderRegistry() {
  group('TimeProviderRegistry', () {
    test('returns default providers', () {
      final registry = TimeProviderRegistry();
      expect(registry.providers, isNotEmpty);
      expect(registry.providers.first.name, isNotEmpty);
    });

    test('accepts custom providers', () {
      final custom = _MockTimeProvider();
      final registry = TimeProviderRegistry(providers: [custom]);
      expect(registry.providers.length, 1);
      expect(registry.providers.first, custom);
    });

    test('dispose calls dispose on all providers', () {
      final disposed = <bool>[];
      final p1 = _MockTimeProvider(onDispose: () => disposed.add(true));
      final p2 = _MockTimeProvider(onDispose: () => disposed.add(true));
      TimeProviderRegistry(providers: [p1, p2]).dispose();
      expect(disposed.length, 2);
    });
  });
}

class _MockTimeProvider extends TimeProvider {
  _MockTimeProvider({this.onDispose});
  final void Function()? onDispose;
  @override
  String get name => 'mock';
  @override
  Future<DateTime> getCurrentUtcTime() async => DateTime.now();
  @override
  void dispose() {
    onDispose?.call();
  }
}

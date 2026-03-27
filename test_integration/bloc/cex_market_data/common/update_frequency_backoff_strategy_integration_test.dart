// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/cex_market_data/common/update_frequency_backoff_strategy.dart';

void main() {
  group('UpdateFrequencyBackoffStrategy Integration Tests', () {
    test('should demonstrate realistic backoff progression over time', () {
      final strategy = UpdateFrequencyBackoffStrategy();
      final List<Duration> actualIntervals = [];

      // Simulate 20 update attempts
      for (int i = 0; i < 20; i++) {
        actualIntervals.add(strategy.getNextInterval());
      }

      // Verify the pattern: 1min pairs, then 2min pairs, then 4min, etc. (default base)
      expect(actualIntervals[0], const Duration(minutes: 1)); // Attempt 0
      expect(actualIntervals[1], const Duration(minutes: 1)); // Attempt 1
      expect(actualIntervals[2], const Duration(minutes: 2)); // Attempt 2
      expect(actualIntervals[3], const Duration(minutes: 2)); // Attempt 3
      expect(actualIntervals[4], const Duration(minutes: 4)); // Attempt 4
      expect(actualIntervals[5], const Duration(minutes: 4)); // Attempt 5
      expect(actualIntervals[6], const Duration(minutes: 8)); // Attempt 6
      expect(actualIntervals[7], const Duration(minutes: 8)); // Attempt 7
      expect(actualIntervals[8], const Duration(minutes: 16)); // Attempt 8
      expect(actualIntervals[9], const Duration(minutes: 16)); // Attempt 9
      expect(actualIntervals[10], const Duration(minutes: 32)); // Attempt 10
      expect(actualIntervals[11], const Duration(minutes: 32)); // Attempt 11
      expect(actualIntervals[12], const Duration(minutes: 60)); // Capped at 1 hour
      expect(actualIntervals[13], const Duration(minutes: 60)); // Capped at 1 hour

      // Verify that all subsequent intervals are capped at max
      for (int i = 14; i < actualIntervals.length; i++) {
        expect(actualIntervals[i], const Duration(minutes: 60));
      }
    });

    test('should reduce API calls over time compared to fixed interval', () {
      final strategy = UpdateFrequencyBackoffStrategy();

      // Calculate total time and API calls over 24 hours with backoff strategy
      const simulationDuration = Duration(hours: 24);
      int backoffApiCalls = 0;
      Duration totalBackoffTime = Duration.zero;

      while (totalBackoffTime < simulationDuration) {
        final interval = strategy.getNextInterval();
        totalBackoffTime += interval;
        backoffApiCalls++;
      }

      // Compare to fixed polling at the same base interval (1 minute)
      const fixedInterval = Duration(minutes: 1);
      final fixedApiCalls =
          simulationDuration.inMinutes ~/ fixedInterval.inMinutes;

      // Backoff strategy should make significantly fewer API calls
      expect(backoffApiCalls, lessThan(fixedApiCalls));
      expect(backoffApiCalls, lessThan(fixedApiCalls * 0.5)); // Less than 50% of fixed calls

      print('Fixed interval (1min): $fixedApiCalls API calls in 24h');
      print('Backoff strategy: $backoffApiCalls API calls in 24h');
      print(
        'Reduction: ${((fixedApiCalls - backoffApiCalls) / fixedApiCalls * 100).toStringAsFixed(1)}%',
      );
    });

    test('should recover quickly after reset', () {
      final strategy = UpdateFrequencyBackoffStrategy();

      // Advance to high attempt count
      for (int i = 0; i < 10; i++) {
        strategy.getNextInterval();
      }

      // Should be at a high interval
      expect(strategy.getCurrentInterval(), greaterThan(const Duration(minutes: 10)));

      // Reset and verify quick recovery
      strategy.reset();
      expect(strategy.getNextInterval(), const Duration(minutes: 1));
      expect(strategy.getNextInterval(), const Duration(minutes: 1));
      expect(strategy.getNextInterval(), const Duration(minutes: 2));
    });

    test('should handle custom intervals for different use cases', () {
      // Test for a more aggressive backoff (shorter max interval)
      final aggressiveStrategy = UpdateFrequencyBackoffStrategy(
        baseInterval: const Duration(minutes: 1),
        maxInterval: const Duration(minutes: 10),
      );

      // Test for a more conservative backoff (longer base interval)
      final conservativeStrategy = UpdateFrequencyBackoffStrategy(
        baseInterval: const Duration(minutes: 5),
        maxInterval: const Duration(hours: 2),
      );

      // Aggressive should reach max quickly (after 6 attempts: 1,1,2,2,4,4,8...)
      for (int i = 0; i < 6; i++) {
        aggressiveStrategy.getNextInterval();
      }
      expect(aggressiveStrategy.getCurrentInterval(), const Duration(minutes: 8));

      // Conservative should start and progress more slowly
      expect(conservativeStrategy.getNextInterval(), const Duration(minutes: 5));
      expect(conservativeStrategy.getNextInterval(), const Duration(minutes: 5));
      expect(conservativeStrategy.getNextInterval(), const Duration(minutes: 10));
      expect(conservativeStrategy.getNextInterval(), const Duration(minutes: 10));
    });

    test('should be suitable for portfolio update scenarios', () {
      final strategy = UpdateFrequencyBackoffStrategy();

      // First hour of updates (user just logged in)
      final firstHourIntervals = <Duration>[];
      Duration elapsed = Duration.zero;
      const oneHour = Duration(hours: 1);

      while (elapsed < oneHour) {
        final interval = strategy.getNextInterval();
        firstHourIntervals.add(interval);
        elapsed += interval;
      }

      // Should have frequent updates in the first hour
      expect(firstHourIntervals.length, greaterThan(5));
      expect(firstHourIntervals.length, lessThan(30)); // But not too frequent

      // First few updates should be relatively quick
      expect(firstHourIntervals[0], const Duration(minutes: 1));
      expect(firstHourIntervals[1], const Duration(minutes: 1));

      // Later updates should be less frequent
      final lastInterval = firstHourIntervals.last;
      expect(lastInterval, greaterThan(const Duration(minutes: 1)));

      print('Updates in first hour: ${firstHourIntervals.length}');
      print(
        'Intervals: ${firstHourIntervals.map((d) => '${d.inMinutes}min').join(', ')}',
      );
    });
  });
}

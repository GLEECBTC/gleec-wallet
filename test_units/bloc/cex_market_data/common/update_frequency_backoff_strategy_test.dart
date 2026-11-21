import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/cex_market_data/common/update_frequency_backoff_strategy.dart';

void main() {
  group('UpdateFrequencyBackoffStrategy', () {
    late UpdateFrequencyBackoffStrategy strategy;

    setUp(() {
      strategy = UpdateFrequencyBackoffStrategy();
    });

    test('should start with attempt count 0', () {
      expect(strategy.attemptCount, 0);
    });

    test('should return base interval for first two attempts', () {
      expect(strategy.getCurrentInterval(), const Duration(minutes: 1));
      expect(strategy.getNextInterval(), const Duration(minutes: 1));
      expect(strategy.attemptCount, 1);

      expect(strategy.getCurrentInterval(), const Duration(minutes: 1));
      expect(strategy.getNextInterval(), const Duration(minutes: 1));
      expect(strategy.attemptCount, 2);
    });

    test('should double interval for next pair of attempts', () {
      // Skip first two attempts
      strategy.getNextInterval(); // 1 min
      strategy.getNextInterval(); // 1 min

      expect(strategy.getCurrentInterval(), const Duration(minutes: 2));
      expect(strategy.getNextInterval(), const Duration(minutes: 2));
      expect(strategy.attemptCount, 3);

      expect(strategy.getCurrentInterval(), const Duration(minutes: 2));
      expect(strategy.getNextInterval(), const Duration(minutes: 2));
      expect(strategy.attemptCount, 4);
    });

    test('should follow exponential backoff pattern: 1,1,2,2,4,4,8,8', () {
      final expectedIntervals = [
        const Duration(minutes: 1), // attempt 0
        const Duration(minutes: 1), // attempt 1
        const Duration(minutes: 2), // attempt 2
        const Duration(minutes: 2), // attempt 3
        const Duration(minutes: 4), // attempt 4
        const Duration(minutes: 4), // attempt 5
        const Duration(minutes: 8), // attempt 6
        const Duration(minutes: 8), // attempt 7
      ];

      for (int i = 0; i < expectedIntervals.length; i++) {
        expect(
          strategy.getNextInterval(),
          expectedIntervals[i],
          reason: 'Attempt $i should return ${expectedIntervals[i]}',
        );
      }
    });

    test('should cap at maximum interval', () {
      strategy = UpdateFrequencyBackoffStrategy(
        baseInterval: const Duration(minutes: 1),
        maxInterval: const Duration(minutes: 5),
      );

      // Skip to high attempt count to reach max
      for (int i = 0; i < 10; i++) {
        strategy.getNextInterval();
      }

      // Should be capped at 5 minutes
      expect(strategy.getCurrentInterval(), const Duration(minutes: 5));
    });

    test('should reset to initial state', () {
      // Make some attempts
      strategy.getNextInterval();
      strategy.getNextInterval();
      strategy.getNextInterval();

      expect(strategy.attemptCount, 3);
      expect(strategy.getCurrentInterval(), const Duration(minutes: 2));

      // Reset
      strategy.reset();

      expect(strategy.attemptCount, 0);
      expect(strategy.getCurrentInterval(), const Duration(minutes: 1));
    });

    test('should always return true for shouldUpdateCache', () {
      // Test for various attempt counts
      for (int i = 0; i < 10; i++) {
        expect(strategy.shouldUpdateCache(), true);
        strategy.getNextInterval();
      }
    });

    test('should preview next intervals without changing state', () {
      // Start at attempt count 0
      expect(strategy.attemptCount, 0);

      final preview = strategy.previewNextIntervals(6);

      // State should be unchanged
      expect(strategy.attemptCount, 0);

      // Preview should show correct intervals
      expect(preview, [
        const Duration(minutes: 1), // attempt 0
        const Duration(minutes: 1), // attempt 1
        const Duration(minutes: 2), // attempt 2
        const Duration(minutes: 2), // attempt 3
        const Duration(minutes: 4), // attempt 4
        const Duration(minutes: 4), // attempt 5
      ]);
    });

    test('should preview intervals from current position', () {
      // Advance to attempt 2
      strategy.getNextInterval(); // 1 min
      strategy.getNextInterval(); // 1 min

      expect(strategy.attemptCount, 2);

      final preview = strategy.previewNextIntervals(4);

      // Should show intervals starting from attempt 2
      expect(preview, [
        const Duration(minutes: 2), // attempt 2
        const Duration(minutes: 2), // attempt 3
        const Duration(minutes: 4), // attempt 4
        const Duration(minutes: 4), // attempt 5
      ]);

      // State should be unchanged
      expect(strategy.attemptCount, 2);
    });

    test('should handle custom base and max intervals', () {
      strategy = UpdateFrequencyBackoffStrategy(
        baseInterval: const Duration(minutes: 1),
        maxInterval: const Duration(minutes: 3),
      );

      final intervals = [
        strategy.getNextInterval(), // 1min
        strategy.getNextInterval(), // 1min
        strategy.getNextInterval(), // 2min
        strategy.getNextInterval(), // 2min
        strategy.getNextInterval(), // 3min (capped at max)
      ];

      expect(intervals, [
        const Duration(minutes: 1),
        const Duration(minutes: 1),
        const Duration(minutes: 2),
        const Duration(minutes: 2),
        const Duration(minutes: 3), // Capped
      ]);
    });
  });
}

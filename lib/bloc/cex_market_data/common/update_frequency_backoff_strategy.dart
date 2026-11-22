import 'dart:math' as math;

/// A strategy for implementing exponential backoff with paired intervals.
/// The pattern is: 1min, 1min, 2min, 2min, 4min, 4min, 8min, 8min, etc.
/// This reduces API calls while still providing reasonable update frequency.
class UpdateFrequencyBackoffStrategy {
  UpdateFrequencyBackoffStrategy({
    this.baseInterval = const Duration(minutes: 1),
    this.maxInterval = const Duration(hours: 1),
  });

  /// The base interval for the first attempts (default: 1 minute)
  final Duration baseInterval;
  
  /// The maximum interval to backoff to (default: 1 hour)
  final Duration maxInterval;
  
  int _attemptCount = 0;
  
  /// Reset the backoff strategy to start from the beginning
  void reset() {
    _attemptCount = 0;
  }
  
  /// Get the current attempt count
  int get attemptCount => _attemptCount;
  
  /// Get the next interval duration and increment the attempt count
  Duration getNextInterval() {
    final interval = getCurrentInterval();
    _attemptCount++;
    return interval;
  }
  
  /// Get the current interval duration without incrementing the attempt count
  Duration getCurrentInterval() {
    // Calculate which "pair" we're in (0, 1, 2, 3, ...)
    // Each pair has 2 attempts with the same interval
    final pairIndex = _attemptCount ~/ 2;
    
    // Calculate the multiplier: 2^pairIndex
    final multiplier = math.pow(2, pairIndex).toInt();
    
    // Calculate the interval
    final intervalMs = baseInterval.inMilliseconds * multiplier;
    
    // Cap at maximum interval
    final cappedIntervalMs = math.min(intervalMs, maxInterval.inMilliseconds);
    
    return Duration(milliseconds: cappedIntervalMs);
  }
  
  /// Check if we should update the cache on the current attempt
  /// Returns true for cache update attempts, false for cache-only reads
  bool shouldUpdateCache() {
    // Update cache on every attempt for now, but this could be modified
    // to only update on certain intervals if needed
    return true;
  }
  
  /// Get a preview of the next N intervals without affecting the state
  List<Duration> previewNextIntervals(int count) {
    final currentAttempt = _attemptCount;
    final intervals = <Duration>[];
    
    for (int i = 0; i < count; i++) {
      final pairIndex = (currentAttempt + i) ~/ 2;
      final multiplier = math.pow(2, pairIndex).toInt();
      final intervalMs = baseInterval.inMilliseconds * multiplier;
      final cappedIntervalMs = math.min(intervalMs, maxInterval.inMilliseconds);
      intervals.add(Duration(milliseconds: cappedIntervalMs));
    }
    
    return intervals;
  }
}
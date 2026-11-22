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
  Duration getCurrentInterval() => _intervalForAttempt(_attemptCount);

  /// Check if we should update the cache on the current attempt
  /// Returns true for cache update attempts, false for cache-only reads
  bool shouldUpdateCache() {
    // Update cache on every attempt for now, but this could be modified
    // to only update on certain intervals if needed
    return true;
  }

  /// Get a preview of the next N intervals without affecting the state
  List<Duration> previewNextIntervals(int count) => [
    for (var i = 0; i < count; i++) _intervalForAttempt(_attemptCount + i),
  ];

  /// Each pair of attempts shares an interval twice the previous pair's.
  ///
  /// Doubling stops at [maxInterval] instead of computing 2^pair first: the
  /// attempt count grows for as long as the app runs, and from pair 48 that
  /// power overflows a 64-bit integer into a negative, then zero, interval.
  Duration _intervalForAttempt(int attempt) {
    var interval = baseInterval;
    for (
      var pair = attempt ~/ 2;
      pair > 0 && interval > Duration.zero && interval < maxInterval;
      pair--
    ) {
      interval *= 2;
    }
    return interval < maxInterval ? interval : maxInterval;
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/analytics/events/advanced_trading_events.dart';

void main() {
  test('Advanced lifecycle analytics remains enum-only and privacy-safe', () {
    const event = AdvancedTradeLifecycleEventData(
      kind: AdvancedTradeKind.takerSwap,
      outcome: AdvancedTradeOutcome.uncertain,
      durationBucket: AdvancedTradeDurationBucket.thirtySecondsToTwoMinutes,
    );

    expect(event.name, 'advanced_trade_lifecycle');
    expect(event.parameters, {
      'kind': 'takerSwap',
      'outcome': 'uncertain',
      'duration_bucket': 'thirtySecondsToTwoMinutes',
    });
    for (final sensitiveKey in <String>{
      'asset',
      'amount',
      'fee',
      'network',
      'address',
      'uuid',
      'error',
    }) {
      expect(event.parameters.keys, isNot(contains(sensitiveKey)));
    }
  });

  test('duration bucketing exposes no exact duration', () {
    expect(
      advancedTradeDurationBucket(const Duration(seconds: 29)),
      AdvancedTradeDurationBucket.underThirtySeconds,
    );
    expect(
      advancedTradeDurationBucket(const Duration(seconds: 30)),
      AdvancedTradeDurationBucket.thirtySecondsToTwoMinutes,
    );
    expect(
      advancedTradeDurationBucket(const Duration(minutes: 2)),
      AdvancedTradeDurationBucket.twoToTenMinutes,
    );
    expect(
      advancedTradeDurationBucket(const Duration(minutes: 10)),
      AdvancedTradeDurationBucket.overTenMinutes,
    );
    expect(
      advancedTradeDurationBucket(null),
      AdvancedTradeDurationBucket.unknown,
    );
  });
}

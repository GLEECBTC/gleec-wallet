import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:web_dex/bloc/analytics/analytics_event.dart';
import 'package:web_dex/bloc/analytics/analytics_repo.dart';

/// Coarse Advanced trading categories that cannot carry wallet, asset, amount,
/// address, order, route, transaction, provider, or raw-error identifiers.
enum AdvancedTradeKind { takerSwap, makerOrder }

enum AdvancedTradeOutcome {
  initiated,
  completed,
  failed,
  uncertain,
  recoveryRequired,
}

enum AdvancedTradeDurationBucket {
  underThirtySeconds,
  thirtySecondsToTwoMinutes,
  twoToTenMinutes,
  overTenMinutes,
  unknown,
}

/// Privacy-safe lifecycle telemetry for the legacy Advanced DEX surface.
///
/// Keep this schema enum-only. Exact financial or identity values belong in
/// the wallet UI and authoritative local state, never analytics payloads.
class AdvancedTradeLifecycleEventData extends AnalyticsEventData {
  const AdvancedTradeLifecycleEventData({
    required this.kind,
    required this.outcome,
    this.durationBucket = AdvancedTradeDurationBucket.unknown,
  });

  final AdvancedTradeKind kind;
  final AdvancedTradeOutcome outcome;
  final AdvancedTradeDurationBucket durationBucket;

  @override
  String get name => 'advanced_trade_lifecycle';

  @override
  JsonMap get parameters => {
    'kind': kind.name,
    'outcome': outcome.name,
    'duration_bucket': durationBucket.name,
  };
}

class AnalyticsAdvancedTradeLifecycleEvent extends AnalyticsSendDataEvent {
  AnalyticsAdvancedTradeLifecycleEvent({
    required AdvancedTradeKind kind,
    required AdvancedTradeOutcome outcome,
    AdvancedTradeDurationBucket durationBucket =
        AdvancedTradeDurationBucket.unknown,
  }) : super(
         AdvancedTradeLifecycleEventData(
           kind: kind,
           outcome: outcome,
           durationBucket: durationBucket,
         ),
       );
}

AdvancedTradeDurationBucket advancedTradeDurationBucket(Duration? duration) {
  if (duration == null || duration.isNegative) {
    return AdvancedTradeDurationBucket.unknown;
  }
  if (duration < const Duration(seconds: 30)) {
    return AdvancedTradeDurationBucket.underThirtySeconds;
  }
  if (duration < const Duration(minutes: 2)) {
    return AdvancedTradeDurationBucket.thirtySecondsToTwoMinutes;
  }
  if (duration < const Duration(minutes: 10)) {
    return AdvancedTradeDurationBucket.twoToTenMinutes;
  }
  return AdvancedTradeDurationBucket.overTenMinutes;
}

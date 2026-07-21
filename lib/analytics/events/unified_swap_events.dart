import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:web_dex/bloc/analytics/analytics_event.dart';
import 'package:web_dex/bloc/analytics/analytics_repo.dart';

enum UnifiedSwapRouteSourceCategory { atomic, external, composite, unknown }

enum UnifiedSwapDurationBucket {
  underThirtySeconds,
  thirtySecondsToTwoMinutes,
  twoToTenMinutes,
  overTenMinutes,
  unknown,
}

enum UnifiedSwapOutcomeCategory {
  completed,
  cancelled,
  failed,
  recoveryRequired,
  unknown,
}

/// Privacy-safe route outcome telemetry.
///
/// This schema deliberately cannot accept assets, amounts, addresses, route or
/// transaction identifiers, provider details, payloads, or raw errors.
class UnifiedSwapOutcomeEventData extends AnalyticsEventData {
  UnifiedSwapOutcomeEventData({
    required this.routeSourceCategory,
    required this.stageCount,
    required this.durationBucket,
    required this.outcomeCategory,
  }) {
    if (stageCount < 0 || stageCount > 17) {
      throw ArgumentError.value(stageCount, 'stageCount', 'Must be 0 to 17');
    }
  }

  final UnifiedSwapRouteSourceCategory routeSourceCategory;
  final int stageCount;
  final UnifiedSwapDurationBucket durationBucket;
  final UnifiedSwapOutcomeCategory outcomeCategory;

  @override
  String get name => 'unified_swap_outcome';

  @override
  JsonMap get parameters => {
    'route_source_category': routeSourceCategory.name,
    'stage_count': stageCount,
    'duration_bucket': durationBucket.name,
    'outcome_category': outcomeCategory.name,
  };
}

class AnalyticsUnifiedSwapOutcomeEvent extends AnalyticsSendDataEvent {
  AnalyticsUnifiedSwapOutcomeEvent({
    required UnifiedSwapRouteSourceCategory routeSourceCategory,
    required int stageCount,
    required UnifiedSwapDurationBucket durationBucket,
    required UnifiedSwapOutcomeCategory outcomeCategory,
  }) : super(
         UnifiedSwapOutcomeEventData(
           routeSourceCategory: routeSourceCategory,
           stageCount: stageCount,
           durationBucket: durationBucket,
           outcomeCategory: outcomeCategory,
         ),
       );
}

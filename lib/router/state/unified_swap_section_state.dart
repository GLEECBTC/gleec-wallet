import 'package:flutter/foundation.dart';
import 'package:web_dex/model/trading_entity_id.dart';

enum UnifiedSwapDestination { swap, activity, activityDetails, advanced }

@immutable
class UnifiedSwapLegacyHints {
  const UnifiedSwapLegacyHints({
    this.sourceAsset,
    this.destinationAsset,
    this.sourceAmount,
  });

  final String? sourceAsset;
  final String? destinationAsset;
  final String? sourceAmount;

  bool get isEmpty =>
      sourceAsset == null && destinationAsset == null && sourceAmount == null;
}

@immutable
class UnifiedSwapRouteState {
  const UnifiedSwapRouteState({
    required this.destination,
    this.routeExecutionId,
    this.legacyHints = const UnifiedSwapLegacyHints(),
  });

  const UnifiedSwapRouteState.swap({
    UnifiedSwapLegacyHints legacyHints = const UnifiedSwapLegacyHints(),
  }) : this(destination: UnifiedSwapDestination.swap, legacyHints: legacyHints);

  const UnifiedSwapRouteState.activity()
    : this(destination: UnifiedSwapDestination.activity);

  const UnifiedSwapRouteState.activityDetails(String routeExecutionId)
    : this(
        destination: UnifiedSwapDestination.activityDetails,
        routeExecutionId: routeExecutionId,
      );

  const UnifiedSwapRouteState.advanced({
    UnifiedSwapLegacyHints legacyHints = const UnifiedSwapLegacyHints(),
  }) : this(
         destination: UnifiedSwapDestination.advanced,
         legacyHints: legacyHints,
       );

  final UnifiedSwapDestination destination;
  final String? routeExecutionId;

  /// Untrusted same-session hints accepted from a legacy entry URL.
  ///
  /// They are never restored into a canonical Unified Swap URL and must be
  /// resolved to exact activated asset identities before use.
  final UnifiedSwapLegacyHints legacyHints;
}

/// Holds the complete Unified Swap route as one immutable value.
///
/// Replacing this value emits a single notification, avoiding transient
/// activity/detail combinations while browser navigation is restored.
class UnifiedSwapSectionState extends ChangeNotifier {
  UnifiedSwapRouteState _value = const UnifiedSwapRouteState.swap();

  UnifiedSwapRouteState get value => _value;

  void replace(UnifiedSwapRouteState next) {
    final resolved = _validated(next);
    if (identical(_value, resolved) ||
        (_value.destination == resolved.destination &&
            _value.routeExecutionId == resolved.routeExecutionId &&
            identical(_value.legacyHints, resolved.legacyHints))) {
      return;
    }
    _value = resolved;
    notifyListeners();
  }

  UnifiedSwapRouteState _validated(UnifiedSwapRouteState next) {
    if (next.destination != UnifiedSwapDestination.activityDetails) {
      return next;
    }
    final routeId = normalizeTradingEntityUuid(next.routeExecutionId);
    return routeId == null
        ? const UnifiedSwapRouteState.activity()
        : UnifiedSwapRouteState.activityDetails(routeId);
  }

  void reset() => replace(const UnifiedSwapRouteState.swap());
}

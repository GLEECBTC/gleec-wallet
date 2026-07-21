import 'package:flutter/foundation.dart';

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
    if (identical(_value, next)) return;
    _value = next;
    notifyListeners();
  }

  void reset() => replace(const UnifiedSwapRouteState.swap());
}

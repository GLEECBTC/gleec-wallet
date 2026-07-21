import 'package:web_dex/model/trading_entity_id.dart';
import 'package:web_dex/router/parsers/base_route_parser.dart';
import 'package:web_dex/router/routes.dart';

class _UnifiedSwapRouteParser implements BaseRouteParser {
  const _UnifiedSwapRouteParser();

  @override
  AppRoutePath getRoutePath(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.length == 1 && segments.first == 'swap') {
      return UnifiedSwapRoutePath.swap();
    }
    if (segments.length == 1 && segments.first == 'activity') {
      return UnifiedSwapRoutePath.activity();
    }
    if (segments.length == 2 && segments.first == 'activity') {
      final routeId = normalizeTradingEntityUuid(segments[1]);
      if (routeId != null) {
        return UnifiedSwapRoutePath.activityDetails(routeId);
      }
    }
    if (segments.length == 1 && segments.first == 'advanced') {
      return UnifiedSwapRoutePath.advanced();
    }

    return segments.isNotEmpty && segments.first == 'activity'
        ? UnifiedSwapRoutePath.activity()
        : UnifiedSwapRoutePath.swap();
  }
}

const unifiedSwapRouteParser = _UnifiedSwapRouteParser();

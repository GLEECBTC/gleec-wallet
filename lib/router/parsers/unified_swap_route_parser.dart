import 'package:web_dex/router/parsers/base_route_parser.dart';
import 'package:web_dex/router/routes.dart';

class _UnifiedSwapRouteParser implements BaseRouteParser {
  const _UnifiedSwapRouteParser();

  static final RegExp _routeExecutionId = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  @override
  AppRoutePath getRoutePath(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.length == 1 && segments.first == 'swap') {
      return UnifiedSwapRoutePath.swap();
    }
    if (segments.length == 1 && segments.first == 'activity') {
      return UnifiedSwapRoutePath.activity();
    }
    if (segments.length == 2 &&
        segments.first == 'activity' &&
        _routeExecutionId.hasMatch(segments[1])) {
      return UnifiedSwapRoutePath.activityDetails(segments[1].toLowerCase());
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

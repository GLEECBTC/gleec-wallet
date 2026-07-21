import 'package:web_dex/router/parsers/base_route_parser.dart';
import 'package:web_dex/router/routes.dart';
import 'package:web_dex/router/state/bridge_section_state.dart';

class _BridgeRouteParser implements BaseRouteParser {
  const _BridgeRouteParser();

  @override
  AppRoutePath getRoutePath(Uri uri) {
    if (uri.pathSegments.length == 3) {
      if (uri.pathSegments[1] == 'trading_details' &&
          uri.pathSegments[2].isNotEmpty) {
        return BridgeRoutePath.swapDetails(
          BridgeAction.tradingDetails,
          uri.pathSegments[2],
        );
      }
    }

    return UnifiedSwapRoutePath.swap();
  }
}

const bridgeRouteParser = _BridgeRouteParser();

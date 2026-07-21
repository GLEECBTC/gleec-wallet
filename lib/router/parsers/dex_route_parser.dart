import 'package:web_dex/router/parsers/base_route_parser.dart';
import 'package:web_dex/model/trading_entity_id.dart';
import 'package:web_dex/router/routes.dart';
import 'package:web_dex/router/state/dex_state.dart';
import 'package:web_dex/router/state/unified_swap_section_state.dart';

class _DexRouteParser implements BaseRouteParser {
  const _DexRouteParser();

  bool handlesDeepLinkParameters(Iterable<String> keys) {
    const dexParams = {
      'from_currency',
      'from_amount',
      'to_currency',
      'to_amount',
      'order_type',
    };

    for (final key in keys) {
      if (dexParams.contains(key)) return true;
    }
    return false;
  }

  @override
  AppRoutePath getRoutePath(Uri uri) {
    if (uri.pathSegments.length == 4 &&
        uri.pathSegments[1] == 'trading_details' &&
        normalizeTradingEntityUuid(uri.pathSegments[3]) != null) {
      final uuid = normalizeTradingEntityUuid(uri.pathSegments[3])!;
      final kind = switch (uri.pathSegments[2]) {
        'swap' => DexTradingEntityKind.swap,
        'order' => DexTradingEntityKind.order,
        _ => null,
      };
      if (kind != null) {
        return DexRoutePath.swapDetails(
          DexAction.tradingDetails,
          uuid,
          entityKind: kind,
        );
      }
    }
    if (uri.pathSegments.length == 3) {
      if (uri.pathSegments[1] == 'trading_details' &&
          normalizeTradingEntityUuid(uri.pathSegments[2]) != null) {
        return DexRoutePath.swapDetails(
          DexAction.tradingDetails,
          normalizeTradingEntityUuid(uri.pathSegments[2])!,
          entityKind: DexTradingEntityKind.swap,
        );
      }
    }

    if (uri.pathSegments.length <= 1) {
      final hints = UnifiedSwapLegacyHints(
        sourceAsset: _assetHint(uri.queryParameters['from_currency']),
        destinationAsset: _assetHint(uri.queryParameters['to_currency']),
        sourceAmount: _amountHint(uri.queryParameters['from_amount']),
      );
      return uri.queryParameters['order_type'] == 'maker'
          ? UnifiedSwapRoutePath.advanced(legacyHints: hints)
          : UnifiedSwapRoutePath.swap(legacyHints: hints);
    }
    return UnifiedSwapRoutePath.swap();
  }

  String? _assetHint(String? value) {
    if (value == null ||
        !RegExp(r'^[A-Za-z][A-Za-z0-9._-]{0,31}$').hasMatch(value)) {
      return null;
    }
    return value;
  }

  String? _amountHint(String? value) {
    if (value == null ||
        value.length > 100 ||
        !RegExp(r'^(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$').hasMatch(value)) {
      return null;
    }
    return value;
  }
}

const dexRouteParser = _DexRouteParser();

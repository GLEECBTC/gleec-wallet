import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/router/parsers/bridge_route_parser.dart';
import 'package:web_dex/router/parsers/dex_route_parser.dart';
import 'package:web_dex/router/parsers/unified_swap_route_parser.dart';
import 'package:web_dex/router/routes.dart';
import 'package:web_dex/router/state/unified_swap_section_state.dart';

void main() {
  group('Unified Swap canonical routes', () {
    test('parses and restores canonical paths without query data', () {
      final paths = <String, UnifiedSwapDestination>{
        '/swap': UnifiedSwapDestination.swap,
        '/activity': UnifiedSwapDestination.activity,
        '/advanced': UnifiedSwapDestination.advanced,
      };

      for (final entry in paths.entries) {
        final path = unifiedSwapRouteParser.getRoutePath(Uri.parse(entry.key));
        expect(path, isA<UnifiedSwapRoutePath>());
        expect((path as UnifiedSwapRoutePath).route.destination, entry.value);
        expect(path.location, entry.key);
      }
    });

    test('accepts only canonical UUIDs for activity details', () {
      const id = '550e8400-e29b-41d4-a716-446655440000';
      final valid = unifiedSwapRouteParser.getRoutePath(
        Uri.parse('/activity/$id'),
      );
      final invalid = unifiedSwapRouteParser.getRoutePath(
        Uri.parse('/activity/not-an-id'),
      );

      expect((valid as UnifiedSwapRoutePath).route.routeExecutionId, id);
      expect(valid.location, '/activity/$id');
      expect(
        (invalid as UnifiedSwapRoutePath).route.destination,
        UnifiedSwapDestination.activity,
      );
      expect(invalid.location, '/activity');
    });

    test(
      'canonical locations never restore hints or unexpected query data',
      () {
        final path = UnifiedSwapRoutePath.swap(
          legacyHints: const UnifiedSwapLegacyHints(
            sourceAsset: 'ETH',
            destinationAsset: 'USDC-ERC20',
            sourceAmount: '1.25',
          ),
        );

        expect(path.location, '/swap');
        expect(Uri.parse(path.location).queryParameters, isEmpty);
      },
    );
  });

  group('legacy redirects', () {
    test('dex taker entry redirects to swap with allowlisted hints only', () {
      final path = dexRouteParser.getRoutePath(
        Uri.parse(
          '/dex?from_currency=ETH&from_amount=1.25&to_currency=USDC-ERC20'
          '&to_amount=999&order_type=taker&recipient=0xsecret',
        ),
      );

      expect(path, isA<UnifiedSwapRoutePath>());
      final route = (path as UnifiedSwapRoutePath).route;
      expect(route.destination, UnifiedSwapDestination.swap);
      expect(route.legacyHints.sourceAsset, 'ETH');
      expect(route.legacyHints.destinationAsset, 'USDC-ERC20');
      expect(route.legacyHints.sourceAmount, '1.25');
      expect(path.location, '/swap');
      expect(path.location, isNot(contains('recipient')));
      expect(path.location, isNot(contains('999')));
    });

    test('maker intent redirects to advanced', () {
      final path = dexRouteParser.getRoutePath(
        Uri.parse('/dex?from_currency=KMD&order_type=maker'),
      );

      expect(
        (path as UnifiedSwapRoutePath).route.destination,
        UnifiedSwapDestination.advanced,
      );
      expect(path.location, '/advanced');
    });

    test('legacy detail IDs remain legacy and are not route execution IDs', () {
      final dex = dexRouteParser.getRoutePath(
        Uri.parse('/dex/trading_details/legacy-id'),
      );
      final bridge = bridgeRouteParser.getRoutePath(
        Uri.parse('/bridge/trading_details/legacy-id'),
      );

      expect(dex, isA<DexRoutePath>());
      expect(bridge, isA<BridgeRoutePath>());
    });

    test('bridge root redirects to swap', () {
      final path = bridgeRouteParser.getRoutePath(Uri.parse('/bridge'));

      expect(path, isA<UnifiedSwapRoutePath>());
      expect(path.location, '/swap');
    });
  });
}

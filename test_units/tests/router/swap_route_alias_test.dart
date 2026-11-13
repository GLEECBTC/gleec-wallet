import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/router/navigators/app_router_delegate.dart';
import 'package:web_dex/router/parsers/root_route_parser.dart';
import 'package:web_dex/router/routes.dart';
import 'package:web_dex/router/state/dex_state.dart';
import 'package:web_dex/router/state/routing_state.dart';

/// `/swap` is the Swap menu's own name for `/dex`, so a link written either
/// way lands on the same surface.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final parser = RootRouteInformationParser(_NoCoins());

  Future<AppRoutePath> parse(String location) =>
      parser.parseRouteInformation(RouteInformation(uri: Uri.parse(location)));

  test('/swap opens the swap surface with its deep link', () async {
    final path = await parse(
      '/swap?from_currency=ETH&to_currency=USDC-ERC20&from_amount=1',
    );

    expect(path, isA<DexRoutePath>());
    final dex = path as DexRoutePath;
    expect(dex.fromCurrency, 'ETH');
    expect(dex.toCurrency, 'USDC-ERC20');
    expect(dex.fromAmount, '1');
    // It settles on the one canonical address.
    expect(
      dex.location,
      '/dex?from_currency=ETH&from_amount=1&to_currency=USDC-ERC20',
    );
  });

  test('/swap/trading_details/<uuid> opens that swap', () async {
    final path = await parse('/swap/trading_details/abc-123');
    expect((path as DexRoutePath).uuid, 'abc-123');
    expect(path.action, DexAction.tradingDetails);
  });

  group('in the browser', () {
    /// Each address the app told the browser, and whether it replaced the
    /// current history entry.
    late List<({String uri, bool replace})> told;

    setUp(() {
      final previous = routingState;
      routingState = RoutingState();
      addTearDown(() => routingState = previous);
    });

    Future<void> open(WidgetTester tester, String location) async {
      told = [];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.navigation, (
        call,
      ) async {
        if (call.method == 'routeInformationUpdated') {
          final arguments = call.arguments as Map;
          told.add((
            uri: arguments['uri'] as String,
            replace: arguments['replace'] as bool,
          ));
        }
        return null;
      });
      addTearDown(
        () =>
            messenger.setMockMethodCallHandler(SystemChannels.navigation, null),
      );
      tester.platformDispatcher.defaultRouteNameTestValue = location;
      addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
      await tester.pumpWidget(
        WidgetsApp.router(
          color: const Color(0xFF8C41FF),
          routeInformationProvider: PlatformRouteInformationProvider(
            initialRouteInformation: RouteInformation(uri: Uri.parse(location)),
          ),
          routeInformationParser: RootRouteInformationParser(_NoCoins()),
          routerDelegate: _BareDelegate(),
        ),
      );
      await tester.pump();
    }

    /// The browser showing [location]: typed in, followed, or reached with
    /// Back or Forward.
    Future<void> browserShows(WidgetTester tester, String location) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.navigation.name,
        SystemChannels.navigation.codec.encodeMethodCall(
          MethodCall('pushRouteInformation', {
            'location': location,
            'state': null,
          }),
        ),
        (_) {},
      );
      await tester.pump();
    }

    testWidgets('opened at /swap, keeps that one history entry', (
      tester,
    ) async {
      await open(tester, '/swap?from_currency=ETH');

      expect(told, isNotEmpty);
      expect(told.where((entry) => !entry.replace), isEmpty);
      expect(told.last.uri, '/swap?from_currency=ETH');
      expect(routingState.dexState.fromCurrency, 'ETH');
    });

    testWidgets('Back to /swap stays there instead of adding /dex again', (
      tester,
    ) async {
      await open(tester, '/wallet');
      await browserShows(tester, '/swap');
      await browserShows(tester, '/wallet');
      told.clear();

      await browserShows(tester, '/swap');

      expect(told.where((entry) => !entry.replace), isEmpty);
    });

    testWidgets('moving on from /swap in the app adds the canonical address', (
      tester,
    ) async {
      await open(tester, '/swap');
      told.clear();

      routingState.dexState.setDetailsAction('abc-123');
      await tester.pump();

      expect(told, [(uri: '/dex/trading_details/abc-123', replace: false)]);
    });

    testWidgets('back on the swap surface in the app, says /swap again', (
      tester,
    ) async {
      await open(tester, '/swap');
      routingState.selectedMenu = MainMenuValue.wallet;
      await tester.pump();
      expect(told.last, (uri: '/wallet', replace: false));
      told.clear();

      // Changing menu resets the old one first, so the parser cannot tell a
      // visit elsewhere from a route still being applied; either address
      // leads to the same place.
      routingState.selectedMenu = MainMenuValue.dex;
      await tester.pump();

      expect(told, [(uri: '/swap', replace: false)]);
    });

    testWidgets('/dex reports itself as before', (tester) async {
      await open(tester, '/dex?from_currency=ETH');

      expect(told.where((entry) => !entry.replace), isEmpty);
      expect(told.last.uri, '/dex?from_currency=ETH');
    });
  });
}

class _NoCoins implements CoinsBloc {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The app's own route handling, without the layout it builds.
class _BareDelegate extends AppRouterDelegate {
  @override
  Widget build(BuildContext context) => const SizedBox();
}

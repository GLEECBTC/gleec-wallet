import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/swap_activity/swap_activity_bloc.dart';
import 'package:web_dex/bloc/system_health/system_health_bloc.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/dex/dex_page.dart';
import 'package:web_dex/views/swap/execution/swap_execution_view.dart';
import 'package:web_dex/views/swap/swap_page.dart';
import 'package:web_dex/views/swap/swap_shell.dart';

import 'swap_accessibility_checks.dart';
import 'swap_surface_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Arriving at the Swap surface from elsewhere: a coin page's Swap action, a
/// `/dex` link, or a notice's View — whether or not the surface was open.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('arriving at the swap surface', () {
    late BlocObserver previousObserver;
    late RecordingBlocObserver observer;
    late FakeExecutor routed;
    late SwapExecutionRegistry registry;
    late SurfaceServices services;

    setUpAll(loadSurfaceCopy);

    setUp(() {
      previousObserver = Bloc.observer;
      Bloc.observer = observer = RecordingBlocObserver();
      routed = FakeExecutor(SwapLiquiditySource.routed);
      registry = SwapExecutionRegistry(
        executors: [routed],
        inFlight: () async => const [],
      );
      services = SurfaceServices(registry);
      useFreshRoutingState();
    });

    tearDown(() async {
      Bloc.observer = previousObserver;
      await registry.dispose();
      await services.dispose();
      resetSurfaceCopy();
    });

    Future<void> show(
      WidgetTester tester, {
      SwapDestination initial = SwapDestination.swap,
    }) => pumpSurface(
      tester,
      SwapShell(initialDestination: initial),
      services: services,
      wrap: [
        (child) => BlocProvider<TradingStatusBloc>.value(
          value: FakeTradingStatusBloc(),
          child: child,
        ),
        (child) => BlocProvider<SystemHealthBloc>.value(
          value: FakeSystemHealthBloc(),
          child: child,
        ),
      ],
    );

    List<UnifiedSwapIntentApplied> intents() =>
        observer.eventsOf<UnifiedSwapIntentApplied>().toList();

    void expectTradingPage(WidgetTester tester) {
      expect(find.byType(DexPage), findsOneWidget);
      // The trading page's own dependencies are not provided here.
      expect(tester.takeException(), isA<FlutterError>());
    }

    const ref = (id: 'routed-9', source: SwapLiquiditySource.routed);

    group('a Swap action from another screen', () {
      testWidgets('made before the surface opened fills the form, once', (
        tester,
      ) async {
        services.requestIntent((
          pay: 'ETH',
          receive: 'USDC-ERC20',
          amount: '1',
        ));
        await show(tester, initial: SwapDestination.activity);

        expect(intents(), [
          const UnifiedSwapIntentApplied(
            pay: 'ETH',
            receive: 'USDC-ERC20',
            amount: '1',
          ),
        ]);
        expect(find.byType(SwapPage), findsOneWidget);
        expect(services.takePendingIntent(), isNull);
      });

      testWidgets('made while it is open fills the form and shows it', (
        tester,
      ) async {
        await show(tester, initial: SwapDestination.activity);
        expect(intents(), isEmpty);

        services.requestIntent((pay: 'BTC', receive: null, amount: null));
        await tester.pumpAndSettle();

        expect(intents(), [const UnifiedSwapIntentApplied(pay: 'BTC')]);
        expect(find.byType(SwapPage), findsOneWidget);
      });
    });

    group('a /dex link', () {
      void link({String from = '', String to = '', String amount = ''}) {
        routingState.dexState
          ..fromCurrency = from
          ..toCurrency = to
          ..fromAmount = amount;
      }

      testWidgets('fills the form once, however often the surface rebuilds', (
        tester,
      ) async {
        link(from: 'ETH', to: 'USDC-ERC20', amount: '2');
        await show(tester);

        expect(intents(), [
          const UnifiedSwapIntentApplied(
            pay: 'ETH',
            receive: 'USDC-ERC20',
            amount: '2',
          ),
        ]);
        expect(services.lastRouteIntent, 'ETH|USDC-ERC20|2');

        await tester.pumpWidget(const SizedBox());
        await show(tester);
        expect(intents(), hasLength(1));
      });

      testWidgets('followed again is applied again', (tester) async {
        link(from: 'ETH', to: 'USDC-ERC20', amount: '2');
        await show(tester);

        routingState.dexState.fromAmount = '2';
        await tester.pumpAndSettle();

        expect(intents(), hasLength(2));
        expect(intents().last, intents().first);
      });

      testWidgets('naming one side leaves the other to choose', (tester) async {
        link(to: 'USDC-ERC20');
        await show(tester);

        expect(intents(), [
          const UnifiedSwapIntentApplied(receive: 'USDC-ERC20'),
        ]);
      });

      testWidgets('without a pair is not a swap', (tester) async {
        link(amount: '5');
        await show(tester);

        expect(intents(), isEmpty);
        expect(services.lastRouteIntent, isNull);
      });

      testWidgets('to a maker order is for the trading interface', (
        tester,
      ) async {
        link(from: 'ETH', to: 'USDC-ERC20');
        routingState.dexState.orderType = 'maker';
        await show(tester);

        expect(intents(), isEmpty);
        expectTradingPage(tester);
      });

      testWidgets('to a maker order, followed while open, leaves the form', (
        tester,
      ) async {
        await show(tester);

        // The order AppRouterDelegate applies a /dex path in.
        routingState.dexState
          ..fromCurrency = 'ETH'
          ..fromAmount = '2'
          ..toCurrency = 'USDC-ERC20'
          ..orderType = 'maker';
        await tester.pumpAndSettle();

        expect(intents(), isEmpty);
        expectTradingPage(tester);
      });

      testWidgets('to a swap in the trading interface opens it there', (
        tester,
      ) async {
        await show(tester);
        expect(intents(), isEmpty);

        routingState.dexState.fromCurrency = 'ETH';
        await tester.pumpAndSettle();
        expect(intents(), [const UnifiedSwapIntentApplied(pay: 'ETH')]);

        routingState.dexState.setDetailsAction('uuid-1');
        await tester.pumpAndSettle();

        expect(intents(), hasLength(1));
        expectTradingPage(tester);
      });
    });

    group('a notice\'s View', () {
      testWidgets('made before the surface opened shows the swap in Activity', (
        tester,
      ) async {
        routed.resumable[ref.id] = FakeHandle(snapshotOf(id: ref.id));
        services.requestOpen(ref);
        await show(tester);

        final view = tester.widget<SwapExecutionView>(
          find.byType(SwapExecutionView),
        );
        expect((view.id, view.source), (ref.id, ref.source));
        expect(view.context, SwapExecutionContext.activity);
        expect(find.text('Confirming on Ethereum'), findsWidgets);
        expect(services.takePendingOpen(), isNull);
      });

      testWidgets('made while it is open shows the swap, then its list', (
        tester,
      ) async {
        routed.resumable[ref.id] = FakeHandle(snapshotOf(id: ref.id));
        await show(tester);

        services.requestOpen(ref);
        await tester.pumpAndSettle();

        expect(find.byType(SwapExecutionView), findsOneWidget);
        expect(observer.eventsOf<SwapActivityStarted>(), isEmpty);
        await expectSwapAccessible(tester);

        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();

        expect(find.byType(SwapExecutionView), findsNothing);
        expect(observer.eventsOf<SwapActivityStarted>(), hasLength(1));
        expect(find.text('1 ETH → 3,000 USDC'), findsOneWidget);
      });
    });
  });
}

// The binding's lifecycle hook and a notifier's listener count are protected;
// the analyzer does not treat test_units as tests.
// ignore_for_file: invalid_use_of_protected_member

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/swap_activity/swap_activity_bloc.dart';
import 'package:web_dex/bloc/system_health/system_health_bloc.dart';
import 'package:web_dex/bloc/trading_status/disallowed_feature.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/dex/dex_page.dart';
import 'package:web_dex/views/swap/entry/swap_entry_view.dart';
import 'package:web_dex/views/swap/swap_page.dart';
import 'package:web_dex/views/swap/swap_shell.dart';

import 'swap_accessibility_checks.dart';
import 'swap_surface_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// The Swap surface's own state: the form and Activity blocs it owns, kept
/// in step with trading availability, the clock, the app's lifecycle and
/// which destination is on screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the swap surface state', () {
    late BlocObserver previousObserver;
    late RecordingBlocObserver observer;
    late SwapExecutionRegistry registry;
    late ScriptedHistory history;
    late SurfaceServices services;
    late FakeTradingStatusBloc tradingStatus;
    late FakeSystemHealthBloc systemHealth;

    setUpAll(loadSurfaceCopy);

    setUp(() {
      previousObserver = Bloc.observer;
      Bloc.observer = observer = RecordingBlocObserver();
      registry = SwapExecutionRegistry(
        executors: [FakeExecutor(SwapLiquiditySource.routed)],
        inFlight: () async => const [],
      );
      history = ScriptedHistory();
      services = SurfaceServices(registry, history: history);
      tradingStatus = FakeTradingStatusBloc();
      systemHealth = FakeSystemHealthBloc();
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
          value: tradingStatus,
          child: child,
        ),
        (child) => BlocProvider<SystemHealthBloc>.value(
          value: systemHealth,
          child: child,
        ),
      ],
    );

    UnifiedSwapBloc form(WidgetTester tester) =>
        BlocProvider.of<UnifiedSwapBloc>(tester.element(find.byType(SwapPage)));

    List<UnifiedSwapCapabilitiesChanged> capabilities() =>
        observer.eventsOf<UnifiedSwapCapabilitiesChanged>().toList();

    Future<void> go(WidgetTester tester, SwapDestination destination) async {
      await tester.tap(find.byKey(Key('swap-destination-${destination.name}')));
      await tester.pumpAndSettle();
    }

    testWidgets('starts the form with the trading and clock checks it finds', (
      tester,
    ) async {
      systemHealth = FakeSystemHealthBloc(SystemHealthLoadSuccess(false));
      await show(tester);

      expect(observer.eventsOf<UnifiedSwapEvent>().take(2), [
        const UnifiedSwapCapabilitiesChanged(
          tradingEnabled: true,
          clockValid: false,
        ),
        const UnifiedSwapStarted(),
      ]);
      expect(form(tester).state.clockValid, isFalse);
      expect(form(tester).state.loadingAssets, isFalse);
      expect(find.byType(SwapEntryView), findsOneWidget);
      await expectSwapAccessible(tester);
    });

    testWidgets('prices only what the live trading status and clock allow', (
      tester,
    ) async {
      await show(tester);
      final tradingAllowed = services.tradingAllowed!;
      final clockValid = services.clockValid!;

      expect(tradingAllowed(eth, usdc), isTrue);
      expect(clockValid(), isTrue);

      tradingStatus.push(TradingStatusLoadSuccess(disallowedAssets: {usdc}));
      systemHealth.push(SystemHealthLoadSuccess(false));
      expect(tradingAllowed(eth, usdc), isFalse);
      expect(tradingAllowed(eth, btc), isTrue);
      expect(clockValid(), isFalse);

      systemHealth.push(SystemHealthLoadInProgress());
      expect(clockValid(), isTrue);
    });

    testWidgets('tells the form when trading or the clock changes', (
      tester,
    ) async {
      await show(tester);

      tradingStatus.push(
        TradingStatusLoadSuccess(
          disallowedFeatures: {DisallowedFeature.trading},
        ),
      );
      await tester.pumpAndSettle();
      expect(
        capabilities().last,
        const UnifiedSwapCapabilitiesChanged(
          tradingEnabled: false,
          clockValid: true,
        ),
      );
      expect(form(tester).state.tradingEnabled, isFalse);
      expect(find.text('Trading unavailable in your location'), findsWidgets);

      systemHealth.push(SystemHealthLoadSuccess(false));
      await tester.pumpAndSettle();
      expect(
        capabilities().last,
        const UnifiedSwapCapabilitiesChanged(
          tradingEnabled: false,
          clockValid: false,
        ),
      );
    });

    testWidgets('pauses re-pricing only while the app is out of sight', (
      tester,
    ) async {
      await show(tester);
      final binding = tester.binding;

      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();

      expect(
        observer.eventsOf<UnifiedSwapForegroundChanged>().map(
          (event) => event.foreground,
        ),
        [true, false, true, true],
      );
    });

    testWidgets('pauses the form away from Swap, and loads Activity once', (
      tester,
    ) async {
      await show(tester);
      expect(history.loads, isEmpty);

      await go(tester, SwapDestination.activity);
      expect(
        observer.eventsOf<UnifiedSwapVisibilityChanged>().last,
        const UnifiedSwapVisibilityChanged(visible: false),
      );
      expect(observer.eventsOf<SwapActivityStarted>(), hasLength(1));
      expect(find.text('No active swaps'), findsOneWidget);

      await go(tester, SwapDestination.swap);
      expect(
        observer.eventsOf<UnifiedSwapVisibilityChanged>().last,
        const UnifiedSwapVisibilityChanged(visible: true),
      );

      await go(tester, SwapDestination.activity);
      expect(observer.eventsOf<SwapActivityStarted>(), hasLength(1));
      expect(observer.eventsOf<SwapActivityRefreshed>(), hasLength(1));
      expect(history.loads, hasLength(2));
    });

    testWidgets('opened on Activity, loads it straight away', (tester) async {
      await show(tester, initial: SwapDestination.activity);

      expect(observer.eventsOf<SwapActivityStarted>(), hasLength(1));
      expect(history.loads.single.filter.name, 'active');
      expect(find.text('No active swaps'), findsOneWidget);
    });

    testWidgets('Advanced is the full trading interface', (tester) async {
      await show(tester);
      await go(tester, SwapDestination.advanced);

      expect(find.byType(DexPage), findsOneWidget);
      // Only the trading page's own dependencies are missing here: the shell
      // handed Advanced to it.
      expect(
        tester.takeException(),
        isA<FlutterError>().having(
          (error) => error.message,
          'message',
          contains('TradingEntitiesBloc'),
        ),
      );

      await go(tester, SwapDestination.swap);
      expect(find.byType(DexPage), findsNothing);
      expect(find.byType(SwapPage), findsOneWidget);
    });

    testWidgets('releases everything it owns when it closes', (tester) async {
      await show(tester);
      final swapBloc = form(tester);
      expect(routingState.dexState.hasListeners, isTrue);

      await tester.pumpWidget(const SizedBox());
      // Closing a bloc awaits stream cancellations that complete outside the
      // test's fake clock.
      for (var i = 0; i < 10 && observer.closed.length < 2; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }

      expect(swapBloc.isClosed, isTrue);
      expect(observer.closed.whereType<UnifiedSwapBloc>(), hasLength(1));
      expect(observer.closed.whereType<SwapActivityBloc>(), hasLength(1));
      expect(routingState.dexState.hasListeners, isFalse);

      final before = capabilities().length;
      tradingStatus.push(TradingStatusLoadFailure());
      services.requestOpen((id: 'late', source: SwapLiquiditySource.routed));
      await tester.pump();
      expect(capabilities(), hasLength(before));
      expect(services.takePendingOpen()?.id, 'late');
    });
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/swap_activity/swap_activity_bloc.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_history_repository.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/activity/swap_activity_view.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/execution/swap_execution_view.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

import 'swap_accessibility_checks.dart';
import 'swap_surface_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Moving around Activity: an incomplete list, older pages, pulling to
/// refresh, and a swap's detail and back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('moving around Activity', () {
    late GatedExecutor routed;
    late SwapExecutionRegistry registry;
    late ScriptedHistory history;
    late SurfaceServices services;
    late RecordingSwapBloc swap;
    late SwapShellController shell;

    setUpAll(loadSurfaceCopy);

    setUp(() {
      routed = GatedExecutor(SwapLiquiditySource.routed);
      registry = SwapExecutionRegistry(
        executors: [routed],
        inFlight: () async => const [],
      );
      history = ScriptedHistory();
      services = SurfaceServices(registry, history: history);
      swap = RecordingSwapBloc(registry);
      shell = SwapShellController(initial: SwapDestination.activity);
    });

    tearDown(() async {
      await swap.close();
      await registry.dispose();
      await services.dispose();
      shell.dispose();
      resetSurfaceCopy();
    });

    Future<void> show(WidgetTester tester) => pumpSurface(
      tester,
      const SwapActivityView(),
      services: services,
      swap: swap,
      shell: shell,
      wrap: [
        (child) => BlocProvider(
          create: (_) =>
              SwapActivityBloc(history: history, registry: registry)
                ..add(const SwapActivityStarted()),
          child: child,
        ),
      ],
    );

    final running = snapshotOf(id: 'running', createdAt: DateTime(2020, 3, 1));
    const partial =
        "Some swaps couldn't be loaded, so this list may be incomplete.";

    Finder loadMore() => find.ancestor(
      of: find.text('Load older swaps'),
      matching: find.byType(SwapButton),
    );

    group('an incomplete list', () {
      testWidgets('says so, and can be read again', (tester) async {
        history
          ..entries = [running]
          ..failedSources = {SwapLiquiditySource.atomic};
        await show(tester);

        expect(find.text(partial), findsOneWidget);
        expect(find.text('1 ETH → 3,000 USDC'), findsOneWidget);
        await expectSwapAccessible(tester);

        history.failedSources = {};
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();

        expect(history.loads, hasLength(2));
        expect(history.loads.last.limit, 25);
        expect(find.text(partial), findsNothing);
      });

      testWidgets('is not a warning when nothing could be read at all', (
        tester,
      ) async {
        history.failedSources = SwapLiquiditySource.values.toSet();
        await show(tester);

        expect(find.text("We couldn't load Activity"), findsOneWidget);
        expect(find.text(partial), findsNothing);
      });
    });

    group('older swaps', () {
      testWidgets('load on request, with the button busy meanwhile', (
        tester,
      ) async {
        history
          ..entries = [running]
          ..hasMore = true;
        await show(tester);

        history.gate = Completer<void>();
        await tester.ensureVisible(loadMore());
        await tester.pumpAndSettle();
        await tester.tap(loadMore());
        await tester.pump();

        expect(history.loads.last.limit, 50);
        final button = tester.widget<SwapButton>(loadMore());
        expect(button.busy, isTrue);
        expect(
          find.descendant(
            of: loadMore(),
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget,
        );

        history
          ..hasMore = false
          ..gate!.complete();
        history.gate = null;
        await tester.pumpAndSettle();

        expect(find.text('Load older swaps'), findsNothing);
      });

      testWidgets('are not offered when there are none', (tester) async {
        history.entries = [running];
        await show(tester);

        expect(find.text('Load older swaps'), findsNothing);
      });
    });

    testWidgets('pulling the list down reads it again', (tester) async {
      history.entries = [running];
      await show(tester);

      await tester.fling(
        find.text('1 ETH → 3,000 USDC'),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();

      expect(history.loads, hasLength(2));
      expect(history.loads.last.filter, SwapActivityFilter.active);
    });

    group('a swap', () {
      testWidgets('opens from its row at once, and back returns to the list', (
        tester,
      ) async {
        history.entries = [running];
        routed
          ..resumable['running'] = FakeHandle(running)
          ..resumeGate = Completer<void>();
        await show(tester);

        await tester.tap(find.text('Confirming on Ethereum'));
        await tester.pump();
        await tester.pump();

        expect(shell.detail, (
          id: 'running',
          source: SwapLiquiditySource.routed,
        ));
        final view = tester.widget<SwapExecutionView>(
          find.byType(SwapExecutionView),
        );
        expect(view.initial, running);
        expect(view.context, SwapExecutionContext.activity);
        expect(find.byType(SwapSkeleton), findsNothing);
        expect(
          find.descendant(
            of: find.byType(SwapStatusHero),
            matching: find.text('Confirming on Ethereum'),
          ),
          findsOneWidget,
        );

        routed.resumeGate!.complete();
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();

        expect(shell.detail, isNull);
        expect(find.byType(SwapExecutionView), findsNothing);
        expect(find.text('Confirming on Ethereum'), findsOneWidget);
      });

      testWidgets('Activity has not loaded opens from its source', (
        tester,
      ) async {
        final other = snapshotOf(
          id: 'elsewhere',
          outcome: failed(SwapFailureReason.routeFailed),
        );
        routed.resumable['elsewhere'] = FakeHandle(other);
        await show(tester);

        shell.showActivity(
          swap: (id: 'elsewhere', source: SwapLiquiditySource.routed),
        );
        await tester.pumpAndSettle();

        final view = tester.widget<SwapExecutionView>(
          find.byType(SwapExecutionView),
        );
        expect(view.initial, isNull);
        expect(view.source, SwapLiquiditySource.routed);
        expect(find.text('Gleec support is needed'), findsWidgets);
        expect(find.text('WHERE ARE THE FUNDS?'), findsOneWidget);
      });
    });
  });
}

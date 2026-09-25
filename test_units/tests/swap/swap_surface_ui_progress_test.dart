import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/common/swap_format.dart';
import 'package:web_dex/views/swap/execution/swap_execution_view.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

import 'swap_surface_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Around a swap's status: leaving the screen, the route's own page, and the
/// evidence box every swap screen ends with.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('around a swap', () {
    late FakeExecutor routed;
    late SwapExecutionRegistry registry;
    late SurfaceServices services;
    late RecordingSwapBloc swap;
    late SwapShellController shell;

    setUpAll(loadSurfaceCopy);

    setUp(() {
      routed = FakeExecutor(SwapLiquiditySource.routed);
      registry = SwapExecutionRegistry(
        executors: [routed],
        inFlight: () async => const [],
      );
      services = SurfaceServices(registry);
      swap = RecordingSwapBloc(registry);
      shell = SwapShellController();
    });

    tearDown(() async {
      await swap.close();
      await registry.dispose();
      await services.dispose();
      shell.dispose();
      resetSurfaceCopy();
    });

    Future<void> follow(
      WidgetTester tester,
      SwapExecutionSnapshot snapshot, {
      SwapExecutionContext context = SwapExecutionContext.flow,
    }) async {
      routed.resumable[snapshot.id] = FakeHandle(snapshot);
      await pumpSurface(
        tester,
        SwapExecutionView(id: snapshot.id, context: context),
        services: services,
        swap: swap,
        shell: shell,
      );
    }

    testWidgets('counts as on screen, for notices, only while shown', (
      tester,
    ) async {
      await follow(tester, snapshotOf());
      expect(services.viewing, {'swap-1'});

      await tester.pumpWidget(const SizedBox());
      expect(services.viewing, isEmpty);
    });

    group('leaving', () {
      testWidgets('closing the progress screen leaves the swap running', (
        tester,
      ) async {
        await follow(tester, snapshotOf());
        expect(find.text('Swap progress'), findsOneWidget);

        await tester.tap(find.byTooltip('Close'));
        await tester.pump();

        expect(swap.events, [const UnifiedSwapProgressLeft()]);
      });

      testWidgets('View in Activity opens this swap there', (tester) async {
        await follow(tester, snapshotOf());

        await tester.tap(find.text('View in Activity'));
        await tester.pump();

        expect(swap.events, [const UnifiedSwapProgressLeft()]);
        expect(shell.destination, SwapDestination.activity);
        expect(shell.detail, (
          id: 'swap-1',
          source: SwapLiquiditySource.routed,
        ));
      });

      testWidgets('from Activity, shows the pair and goes back to the list', (
        tester,
      ) async {
        shell.showActivity(
          swap: (id: 'swap-1', source: SwapLiquiditySource.routed),
        );
        await follow(
          tester,
          snapshotOf(),
          context: SwapExecutionContext.activity,
        );

        expect(find.text('Activity'), findsOneWidget);
        expect(find.text('1 ETH → 3,000 USDC'), findsOneWidget);
        expect(find.text('View in Activity'), findsNothing);

        await tester.tap(find.byTooltip('Back'));
        await tester.pump();

        expect(shell.detail, isNull);
        expect(shell.destination, SwapDestination.activity);
        expect(swap.events, isEmpty);
      });
    });

    group('the route page', () {
      SwapExecutionSnapshot linked(SwapProgressStage stage) => reshaped(
        snapshotOf(stage: stage),
        evidence: const SwapEvidence(
          executionId: 'swap-1',
          providerExplorerUrl: 'https://route.example/status/1',
        ),
      );

      testWidgets('opens when the route needs the user to act', (tester) async {
        final launcher = recordUrlLaunches();
        await follow(tester, linked(SwapProgressStage.actionRequired));

        await tester.tap(find.text('Open route page'));
        await tester.pump();

        expect(launcher.launched, ['https://route.example/status/1']);
      });

      testWidgets('is not offered while the swap needs nothing', (
        tester,
      ) async {
        await follow(tester, linked(SwapProgressStage.bridging));

        expect(find.text('Open route page'), findsNothing);
      });

      testWidgets('is not offered without a link to open', (tester) async {
        await follow(
          tester,
          snapshotOf(stage: SwapProgressStage.actionRequired),
        );

        expect(find.text('Open route page'), findsNothing);
      });
    });

    group('the evidence box', () {
      testWidgets('shows the last update and the swap id to quote', (
        tester,
      ) async {
        final updated = DateTime(2020, 1, 2, 3, 4);
        await follow(tester, reshaped(snapshotOf(), updatedAt: updated));

        expect(find.text('Last update'), findsOneWidget);
        expect(find.text(SwapFormat.time(updated)), findsOneWidget);
        expect(find.text('Swap ID'), findsOneWidget);
        expect(find.text('swap-1'), findsOneWidget);
      });

      testWidgets('falls back to when the swap finished', (tester) async {
        final finished = DateTime(2020, 5, 6, 7);
        await follow(
          tester,
          snapshotOf(outcome: completed(), finishedAt: finished),
        );

        expect(find.text(SwapFormat.time(finished)), findsOneWidget);
      });

      testWidgets('leaves the time out when none is known', (tester) async {
        await follow(tester, snapshotOf());

        expect(find.text('Last update'), findsNothing);
        expect(find.text('Swap ID'), findsOneWidget);
      });

      testWidgets('opens the full evidence', (tester) async {
        await follow(tester, snapshotOf());

        await tester.tap(find.text('View evidence'));
        await tester.pumpAndSettle();

        expect(find.text('Swap evidence'), findsOneWidget);
        expect(find.text('ROUTE'), findsOneWidget);
      });
    });
  });
}

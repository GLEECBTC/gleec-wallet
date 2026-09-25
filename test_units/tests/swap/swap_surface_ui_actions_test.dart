import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/execution/swap_execution_view.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

import 'swap_accessibility_checks.dart';
import 'swap_surface_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// What each next step on a finished swap does: every new swap goes back
/// through the form for a fresh quote and consent; nothing restarts behind
/// the user's back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("a finished swap's next steps", () {
    late FakeExecutor routed;
    late FakeExecutor atomic;
    late SwapExecutionRegistry registry;
    late SurfaceServices services;
    late RecordingSwapBloc swap;
    late SwapShellController shell;

    setUpAll(loadSurfaceCopy);

    setUp(() {
      routed = FakeExecutor(SwapLiquiditySource.routed);
      atomic = FakeExecutor(SwapLiquiditySource.atomic);
      registry = SwapExecutionRegistry(
        executors: [routed, atomic],
        inFlight: () async => const [],
      );
      services = SurfaceServices(registry);
      swap = RecordingSwapBloc(registry);
      shell = SwapShellController(initial: SwapDestination.activity);
      useFreshRoutingState();
    });

    tearDown(() async {
      await swap.close();
      await registry.dispose();
      await services.dispose();
      shell.dispose();
      resetSurfaceCopy();
    });

    Future<void> show(
      WidgetTester tester,
      SwapExecutionSnapshot snapshot, {
      SwapExecutionContext context = SwapExecutionContext.activity,
    }) async {
      final executor = snapshot.source == SwapLiquiditySource.atomic
          ? atomic
          : routed;
      executor.resumable[snapshot.id] = FakeHandle(snapshot);
      await pumpSurface(
        tester,
        SwapExecutionView(id: snapshot.id, context: context),
        services: services,
        swap: swap,
        shell: shell,
      );
    }

    Future<void> choose(WidgetTester tester, String action) async {
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
    }

    SwapExecutionSnapshot otherToken() => snapshotOf(
      outcome: SwapExecutionOutcome(
        kind: SwapOutcomeKind.partialOtherToken,
        receivedAmount: d('1.25'),
        receivedAsset: weth,
      ),
    );

    testWidgets('swapping the token that arrived starts from the form', (
      tester,
    ) async {
      await show(tester, otherToken());
      await choose(tester, 'Swap WETH to USDC');

      expect(swap.events, [
        UnifiedSwapFollowUpRequested(pay: weth, receive: usdc, amount: '1.25'),
      ]);
      expect(shell.destination, SwapDestination.swap);
    });

    testWidgets('keeping the token that arrived opens an empty form', (
      tester,
    ) async {
      await show(tester, otherToken());
      await choose(tester, 'Keep token');

      expect(swap.events, [const UnifiedSwapResetRequested()]);
      expect(shell.destination, SwapDestination.swap);
    });

    testWidgets('after a success, another swap starts from the form', (
      tester,
    ) async {
      await show(tester, snapshotOf(outcome: completed()));
      await choose(tester, 'Start another swap');

      expect(swap.events, [const UnifiedSwapResetRequested()]);
      expect(shell.destination, SwapDestination.swap);
    });

    testWidgets('the updated quote goes to the form for consent', (
      tester,
    ) async {
      final fresh = quoteOf(guaranteed: '2900');
      await show(
        tester,
        snapshotOf(
          fundsMovement: SwapFundsMovement.none,
          outcome: failed(SwapFailureReason.priceMoved, freshQuote: fresh),
        ),
      );
      await choose(tester, 'Accept updated quote');

      expect(swap.events, [UnifiedSwapFreshQuoteAccepted(fresh)]);
      expect(shell.destination, SwapDestination.swap);
    });

    testWidgets('trying again fills the form with the same swap', (
      tester,
    ) async {
      await show(
        tester,
        snapshotOf(
          outcome: const SwapExecutionOutcome(kind: SwapOutcomeKind.refunded),
        ),
      );
      await choose(tester, 'Try again');

      expect(swap.events, [
        UnifiedSwapFollowUpRequested(pay: eth, receive: usdc, amount: '1'),
      ]);
      expect(shell.destination, SwapDestination.swap);
    });

    testWidgets('trying again without an amount leaves it to be typed', (
      tester,
    ) async {
      await show(
        tester,
        reshaped(
          snapshotOf(
            outcome: const SwapExecutionOutcome(kind: SwapOutcomeKind.refunded),
          ),
          noSellAmount: true,
          noTo: true,
        ),
      );
      await choose(tester, 'Try again');

      expect(swap.events, [UnifiedSwapFollowUpRequested(pay: eth)]);
    });

    testWidgets('trying again with an asset the wallet lost opens a new form', (
      tester,
    ) async {
      await show(
        tester,
        reshaped(
          snapshotOf(
            fundsMovement: SwapFundsMovement.none,
            outcome: const SwapExecutionOutcome(
              kind: SwapOutcomeKind.cancelled,
            ),
          ),
          noFrom: true,
        ),
      );
      await choose(tester, 'Try again');

      expect(swap.events, [const UnifiedSwapResetRequested()]);
      expect(shell.destination, SwapDestination.swap);
    });

    testWidgets('a locked exchange opens in the full trading interface', (
      tester,
    ) async {
      await show(
        tester,
        snapshotOf(
          id: 'uuid-7',
          source: SwapLiquiditySource.atomic,
          routeKind: SwapRouteKind.direct,
          outcome: failed(SwapFailureReason.exchangeFailed),
        ),
      );
      await choose(tester, 'Open in Advanced');

      expect(routingState.dexState.isTradingDetails, isTrue);
      expect(routingState.dexState.uuid, 'uuid-7');
      expect(shell.destination, SwapDestination.advanced);
      expect(swap.events, isEmpty);
    });

    group('the explorer', () {
      SwapExecutionSnapshot reverted() => snapshotOf(
        fundsMovement: SwapFundsMovement.feesOnly,
        sourceTxHash: '0xsource',
        outcome: failed(SwapFailureReason.reverted),
      );

      testWidgets('opens the source transaction on its network', (
        tester,
      ) async {
        final launcher = recordUrlLaunches();
        services.explorer['0xsource'] = Uri.parse(
          'https://etherscan.io/tx/0x1',
        );
        await show(tester, reverted());

        await choose(tester, 'View on Explorer');

        expect(launcher.launched, ['https://etherscan.io/tx/0x1']);
        expect(services.explorerAsked, {'0xsource': eth});
      });

      testWidgets('opens nothing when the network has no explorer', (
        tester,
      ) async {
        final launcher = recordUrlLaunches();
        await show(tester, reverted());

        await choose(tester, 'View on Explorer');

        expect(launcher.launched, isEmpty);
        expect(services.explorerAsked.keys, ['0xsource']);
      });
    });

    testWidgets('support gets the evidence to share', (tester) async {
      await show(
        tester,
        snapshotOf(outcome: failed(SwapFailureReason.routeFailed)),
      );
      await choose(tester, 'Contact Gleec support');

      expect(find.text('Swap evidence'), findsOneWidget);
      expect(find.text('Copy details for support'), findsOneWidget);
      expect(swap.events, isEmpty);
    });

    group('straight after starting', () {
      testWidgets('a success is done, and leaves the progress screen', (
        tester,
      ) async {
        await show(
          tester,
          snapshotOf(outcome: completed()),
          context: SwapExecutionContext.flow,
        );

        expect(find.text('Done'), findsOneWidget);
        expect(find.text('View in Activity'), findsNothing);
        await choose(tester, 'Done');

        expect(swap.events, [const UnifiedSwapProgressLeft()]);
        expect(shell.detail, isNull);
        await expectSwapAccessible(tester);
      });

      testWidgets('anything else is followed up in Activity', (tester) async {
        await show(
          tester,
          snapshotOf(outcome: failed(SwapFailureReason.routeFailed)),
          context: SwapExecutionContext.flow,
        );

        expect(find.text('Done'), findsNothing);
        await choose(tester, 'View in Activity');

        expect(swap.events, [const UnifiedSwapProgressLeft()]);
        expect(shell.destination, SwapDestination.activity);
        expect(shell.detail, (
          id: 'swap-1',
          source: SwapLiquiditySource.routed,
        ));
      });
    });

    testWidgets('from Activity, a finished swap offers only its next steps', (
      tester,
    ) async {
      await show(tester, snapshotOf(outcome: completed()));

      expect(find.text('Done'), findsNothing);
      expect(find.text('View in Activity'), findsNothing);
      expect(find.text('Start another swap'), findsOneWidget);
    });
  });
}

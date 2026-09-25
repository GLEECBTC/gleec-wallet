import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/execution/swap_execution_view.dart';
import 'package:web_dex/views/swap/execution/swap_timeline_view.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

import 'swap_accessibility_checks.dart';
import 'swap_surface_ui_fakes.dart';
import 'swap_test_fixtures.dart';

typedef _Outcome = ({
  SwapExecutionSnapshot snapshot,
  String title,
  String body,
  String? funds,
  List<String> actions,
  String timeline,
});

/// How each way a swap can end is told: the headline, where the funds are,
/// and only the next steps that are possible now.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a finished swap', () {
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
      shell = SwapShellController();
    });

    tearDown(() async {
      await swap.close();
      await registry.dispose();
      await services.dispose();
      shell.dispose();
      resetSurfaceCopy();
    });

    final permission = SwapApprovalRequirement(
      asset: usdc,
      exactAmount: d('1250'),
      resetsFirst: false,
    );
    const unchanged = 'Your balance is unchanged.';

    final outcomes = <String, _Outcome>{
      'completed': (
        snapshot: snapshotOf(outcome: completed()),
        title: 'You received 3,001 USDC',
        body: 'Received at 0x5520…7B91 on Ethereum.',
        funds: null,
        actions: ['Start another swap'],
        timeline: 'Completed: Received.',
      ),
      'completed, to an address it does not know': (
        snapshot: reshaped(snapshotOf(outcome: completed()), noToAddress: true),
        title: 'You received 3,001 USDC',
        body: 'Received on Ethereum.',
        funds: null,
        actions: ['Start another swap'],
        timeline: 'Completed: Received. 3,001 USDC on Ethereum',
      ),
      'below the minimum': (
        snapshot: snapshotOf(
          outcome: SwapExecutionOutcome(
            kind: SwapOutcomeKind.partialBelowMinimum,
            receivedAmount: d('2900'),
            receivedAsset: usdc,
          ),
        ),
        title: 'Received less than the minimum',
        body:
            'The swap completed with 2,900 USDC, below the minimum of '
            '2,985 USDC.',
        funds: '2,900 USDC at 0x5520…7B91 on Ethereum.',
        actions: ['Start another swap', 'Contact Gleec support'],
        timeline: 'Completed: Received.',
      ),
      'a different token': (
        snapshot: snapshotOf(
          outcome: SwapExecutionOutcome(
            kind: SwapOutcomeKind.partialOtherToken,
            receivedAmount: d('1'),
            receivedAsset: weth,
          ),
        ),
        title: 'A different token was received',
        body: 'The swap completed with 1 WETH, not USDC.',
        funds: '1 WETH at 0x5520…7B91 on Ethereum.',
        actions: ['Swap WETH to USDC', 'Keep token'],
        timeline: 'Completed: Received. 1 WETH at',
      ),
      'a token the wallet does not know': (
        snapshot: reshaped(
          snapshotOf(
            outcome: SwapExecutionOutcome(
              kind: SwapOutcomeKind.partialOtherToken,
              receivedAmount: d('7'),
              receivedSymbol: 'XYZ',
            ),
          ),
          noToAddress: true,
        ),
        title: 'A different token was received',
        body: 'The swap completed with 7 XYZ, not USDC.',
        funds: '7 XYZ on Ethereum.',
        actions: ['Keep token'],
        timeline: 'Completed: Received. 7 XYZ on Ethereum',
      ),
      'refunded': (
        snapshot: snapshotOf(
          outcome: const SwapExecutionOutcome(kind: SwapOutcomeKind.refunded),
        ),
        title: 'Refund received',
        body: "The swap didn't happen. Your ETH was returned on Ethereum.",
        funds: 'Returned to your address on Ethereum.',
        actions: ['Try again'],
        timeline: 'Cancelled: Receive USDC.',
      ),
      'cancelled': (
        snapshot: snapshotOf(
          fundsMovement: SwapFundsMovement.none,
          outcome: const SwapExecutionOutcome(kind: SwapOutcomeKind.cancelled),
        ),
        title: 'Cancelled before funds moved',
        body: 'No asset transfer was broadcast.',
        funds: unchanged,
        actions: ['Try again'],
        timeline: 'Cancelled: Preparing.',
      ),
      'cancelled, leaving a permission': (
        snapshot: snapshotOf(
          fundsMovement: SwapFundsMovement.feesOnly,
          approval: permission,
          approvalRemains: true,
          approvalTxHashes: ['0xapproval'],
          outcome: const SwapExecutionOutcome(kind: SwapOutcomeKind.cancelled),
        ),
        title: 'Cancelled before funds moved',
        body:
            'No swap was sent. The exact permission for 1,250 USDC stays '
            'on-chain.',
        // The approval that left the permission was paid for.
        funds:
            "Your ETH didn't leave. Network fees were spent. An exact "
            'permission for 1,250 USDC remains on-chain.',
        actions: ['Try again'],
        timeline: 'Cancelled: Sending on Ethereum.',
      ),
      'unmatched': (
        snapshot: snapshotOf(
          source: SwapLiquiditySource.atomic,
          routeKind: SwapRouteKind.direct,
          fundsMovement: SwapFundsMovement.none,
          stages: const [],
          outcome: const SwapExecutionOutcome(kind: SwapOutcomeKind.noMatch),
        ),
        title: 'No match found',
        body: 'No one took this exchange in time. Nothing was sent.',
        funds: unchanged,
        actions: ['Try again'],
        timeline: 'Not started: Exchanging asset.',
      ),
    };

    Future<void> show(
      WidgetTester tester,
      SwapExecutionSnapshot snapshot,
    ) async {
      final executor = snapshot.source == SwapLiquiditySource.atomic
          ? atomic
          : routed;
      executor.resumable[snapshot.id] = FakeHandle(snapshot);
      await pumpSurface(
        tester,
        SwapExecutionView(
          id: snapshot.id,
          source: snapshot.source,
          initial: snapshot,
          context: SwapExecutionContext.activity,
        ),
        services: services,
        swap: swap,
        shell: shell,
      );
    }

    SwapQuestion? question(WidgetTester tester, String eyebrow) => tester
        .widgetList<SwapQuestion>(find.byType(SwapQuestion))
        .where((question) => question.eyebrow == eyebrow)
        .firstOrNull;

    for (final MapEntry(key: name, value: outcome) in outcomes.entries) {
      testWidgets('$name: "${outcome.title}", then ${outcome.actions}', (
        tester,
      ) async {
        await show(tester, outcome.snapshot);

        final hero = tester.widget<SwapStatusHero>(find.byType(SwapStatusHero));
        expect(hero.title, outcome.title);
        expect(hero.body, outcome.body);
        expect(find.text(outcome.title), findsWidgets);

        final funds = outcome.funds;
        if (funds == null) {
          expect(find.byType(SwapQuestion), findsNothing);
        } else {
          final what = question(tester, 'What happened?')!;
          expect((what.title, what.body), (outcome.title, outcome.body));
          expect(question(tester, 'Where are the funds?')!.body, funds);
          expect(
            question(tester, 'What can I do now?')!.body,
            'Only actions available right now are shown. A new swap always '
            'gets a fresh quote and your consent.',
          );
          expect(find.text('WHAT HAPPENED?'), findsOneWidget);
          expect(find.text('WHERE ARE THE FUNDS?'), findsOneWidget);
          expect(find.text('WHAT CAN I DO NOW?'), findsOneWidget);
        }

        final buttons = tester.widgetList<SwapButton>(find.byType(SwapButton));
        expect(buttons.map((button) => button.label), outcome.actions);
        expect(buttons.map((button) => button.variant), [
          SwapButtonVariant.primary,
          for (var i = 1; i < outcome.actions.length; i++)
            SwapButtonVariant.secondary,
        ]);
        expect(find.byKey(const Key('swap-cancel')), findsNothing);
        expect(
          find.text(
            'You can leave this screen. The swap continues in Activity.',
          ),
          findsNothing,
        );
        expect(
          tester.getSemantics(find.byType(SwapTimelineView)).label,
          contains(outcome.timeline),
        );
        await expectSwapAccessible(tester);
      });
    }

    testWidgets('a success shows what arrived, not the recovery questions', (
      tester,
    ) async {
      await show(tester, snapshotOf(outcome: completed(amount: '2999.999')));

      expect(find.text('1 ETH → 2,999.99 USDC'), findsOneWidget);
      expect(find.text('You received 2,999.99 USDC'), findsOneWidget);
      expect(find.text('WHERE ARE THE FUNDS?'), findsNothing);
    });

    testWidgets('a cancelled swap marks every step it never reached', (
      tester,
    ) async {
      await show(
        tester,
        snapshotOf(
          fundsMovement: SwapFundsMovement.none,
          outcome: const SwapExecutionOutcome(kind: SwapOutcomeKind.cancelled),
        ),
      );

      final label = tester.getSemantics(find.byType(SwapTimelineView)).label;
      expect(label, contains('Cancelled: Preparing.'));
      expect(label, contains('Not started: Sending on Ethereum.'));
      expect(label, contains('Not started: Receive USDC.'));
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });
  });
}

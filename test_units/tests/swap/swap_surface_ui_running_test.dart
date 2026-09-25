import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
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

/// A running swap: where it has got to at every stage, while its status
/// loads, when no source knows it, and on two screens at once.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a running swap', () {
    late GatedExecutor routed;
    late _Engine atomic;
    late SwapExecutionRegistry registry;
    late SurfaceServices services;
    late RecordingSwapBloc swap;
    late SwapShellController shell;

    setUpAll(loadSurfaceCopy);

    setUp(() {
      routed = GatedExecutor(SwapLiquiditySource.routed);
      atomic = _Engine(SwapLiquiditySource.atomic);
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

    Future<FakeHandle> follow(
      WidgetTester tester,
      SwapExecutionSnapshot snapshot,
    ) async {
      final followed = FakeHandle(snapshot);
      routed.resumable[snapshot.id] = followed;
      await pumpSurface(
        tester,
        SwapExecutionView(id: snapshot.id, context: SwapExecutionContext.flow),
        services: services,
        swap: swap,
        shell: shell,
      );
      return followed;
    }

    Finder hero(String text) => find.descendant(
      of: find.byType(SwapStatusHero),
      matching: find.text(text),
    );

    String timeline(WidgetTester tester) =>
        tester.getSemantics(find.byType(SwapTimelineView)).label;

    final approve = SwapRouteStage(
      kind: SwapRouteStageKind.approve,
      asset: usdc,
    );
    final send = SwapRouteStage(kind: SwapRouteStageKind.send, asset: eth);
    final receive = SwapRouteStage(
      kind: SwapRouteStageKind.receive,
      asset: usdc,
    );
    const prepare = SwapRouteStage(kind: SwapRouteStageKind.prepare);
    final permission = SwapApprovalRequirement(
      asset: usdc,
      exactAmount: d('1250'),
      resetsFirst: false,
    );

    final stages =
        <
          String,
          (SwapExecutionSnapshot, String title, String body, String step)
        >{
          'preparing': (
            snapshotOf(stage: SwapProgressStage.preparing),
            'Preparing swap',
            'Checking the latest details before anything is signed.',
            'Current: Preparing. Checking the latest details',
          ),
          'matching': (
            snapshotOf(stage: SwapProgressStage.matching),
            'Finding a counterparty',
            'Waiting for a peer to take this exchange. Nothing has left your '
                'wallet.',
            'Current: Preparing.',
          ),
          'approving': (
            snapshotOf(
              stage: SwapProgressStage.approving,
              approval: permission,
              stages: [prepare, approve, send, receive],
            ),
            'Approving exact amount',
            "Approving exactly 1,250 USDC. Network fees apply; the USDC you're "
                "swapping hasn't moved.",
            'Current: Approving USDC. Exact amount only',
          ),
          'resetting a permission first': (
            snapshotOf(
              stage: SwapProgressStage.approving,
              approval: SwapApprovalRequirement(
                asset: usdc,
                exactAmount: d('1250'),
                resetsFirst: true,
              ),
              stages: [
                prepare,
                SwapRouteStage(
                  kind: SwapRouteStageKind.resetApproval,
                  asset: usdc,
                ),
                approve,
                send,
                receive,
              ],
            ),
            'Resetting token permission',
            'Setting the current USDC permission to zero, then approving '
                'exactly 1,250 USDC.',
            'Current: Resetting permission.',
          ),
          'signing': (
            snapshotOf(stage: SwapProgressStage.signing),
            'Signing',
            'Signing the swap request on this device. Nothing has been sent yet.',
            'Current: Preparing.',
          ),
          'sending': (
            snapshotOf(stage: SwapProgressStage.sending),
            'Sending on Ethereum',
            "Sending the transaction to Ethereum. It can't be cancelled now.",
            'Current: Sending on Ethereum. Source transaction',
          ),
          'confirming': (
            snapshotOf(stage: SwapProgressStage.confirming),
            'Confirming on Ethereum',
            'Waiting for the source transaction to confirm.',
            'Current: Sending on Ethereum.',
          ),
          'bridging': (
            snapshotOf(
              stage: SwapProgressStage.bridging,
              routeKind: SwapRouteKind.crossChain,
            ),
            'Moving to Ethereum',
            'This can take a few minutes. Gleec will keep tracking.',
            'Current: Receive USDC.',
          ),
          'awaiting delivery': (
            snapshotOf(stage: SwapProgressStage.awaitingDelivery),
            'Arriving on Ethereum',
            'Waiting for delivery on Ethereum.',
            'Current: Receive USDC. 3,000 USDC at 0x5520…7B91 on Ethereum',
          ),
          'refunding': (
            snapshotOf(stage: SwapProgressStage.refunding),
            'Refund in progress',
            'The route is returning your funds. Gleec will keep tracking.',
            'Current: Receive USDC.',
          ),
          'action required': (
            snapshotOf(stage: SwapProgressStage.actionRequired),
            'Action required',
            "Open the route's page to continue.",
            'Current: Receive USDC.',
          ),
          'exchanging': (
            snapshotOf(
              source: SwapLiquiditySource.atomic,
              routeKind: SwapRouteKind.direct,
              stage: SwapProgressStage.exchanging,
              stages: const [],
            ),
            'Exchanging asset',
            'Your payment is locked in the exchange. Waiting for the other side '
                'to complete.',
            'Current: Exchanging asset. Peer-to-peer exchange',
          ),
          'in a stage this build does not know': (
            snapshotOf(stage: SwapProgressStage.unknown),
            'Tracking your swap',
            'Gleec is checking the latest status. This does not mean the swap '
                'failed.',
            'Current: Receive USDC.',
          ),
          'with status reads failing': (
            snapshotOf(delayedSince: DateTime(2026, 9, 24)),
            'Status update delayed',
            "We don't have a current update yet. This does not mean the swap "
                'failed.',
            'Current: Sending on Ethereum.',
          ),
        };

    for (final MapEntry(key: name, value: (snapshot, title, body, step))
        in stages.entries) {
      testWidgets('$name: says "$title" and marks the step it is on', (
        tester,
      ) async {
        await follow(tester, snapshot);

        expect(hero(title), findsOneWidget);
        expect(hero(body), findsOneWidget);
        expect(timeline(tester), contains(step));
        expect(
          find.text(
            'You can leave this screen. The swap continues in Activity.',
          ),
          findsOneWidget,
        );
        await expectSwapAccessible(tester);
      });
    }

    testWidgets('follows the swap as it moves on and finishes', (tester) async {
      final handle = await follow(tester, snapshotOf());
      expect(hero('Confirming on Ethereum'), findsOneWidget);

      handle.push(snapshotOf(stage: SwapProgressStage.awaitingDelivery));
      await tester.pumpAndSettle();
      expect(hero('Arriving on Ethereum'), findsOneWidget);

      handle.push(snapshotOf(outcome: completed()));
      await tester.pumpAndSettle();
      expect(hero('You received 3,001 USDC'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('holds the layout while the first status loads', (
      tester,
    ) async {
      routed.resumeGate = Completer<void>();
      await pumpSurface(
        tester,
        const SwapExecutionView(id: 'slow', context: SwapExecutionContext.flow),
        services: services,
        swap: swap,
        shell: shell,
        settle: false,
      );
      await tester.pump();

      expect(find.byType(SwapSkeleton), findsNWidgets(4));
      expect(find.byType(SwapStatusHero), findsNothing);
    });

    testWidgets('says so, calmly, when no source knows the swap', (
      tester,
    ) async {
      await pumpSurface(
        tester,
        const SwapExecutionView(
          id: 'ghost',
          context: SwapExecutionContext.flow,
        ),
        services: services,
        swap: swap,
        shell: shell,
      );

      expect(hero('Tracking your swap'), findsOneWidget);
      expect(find.byIcon(Icons.search_off_rounded), findsOneWidget);
      expect(find.byType(SwapTimelineView), findsNothing);
    });

    testWidgets('two screens opening one swap both keep following it', (
      tester,
    ) async {
      final exchange = snapshotOf(
        id: 'shared',
        source: SwapLiquiditySource.atomic,
        routeKind: SwapRouteKind.direct,
        stage: SwapProgressStage.matching,
      );
      atomic.push(exchange);
      await pumpSurface(
        tester,
        const Column(
          children: [
            Expanded(
              child: SwapExecutionView(
                id: 'shared',
                context: SwapExecutionContext.flow,
              ),
            ),
            Expanded(
              child: SwapExecutionView(
                id: 'shared',
                context: SwapExecutionContext.activity,
              ),
            ),
          ],
        ),
        services: services,
        swap: swap,
        shell: shell,
      );
      expect(hero('Finding a counterparty'), findsNWidgets(2));

      atomic.push(
        snapshotOf(
          id: 'shared',
          source: SwapLiquiditySource.atomic,
          routeKind: SwapRouteKind.direct,
          stage: SwapProgressStage.exchanging,
        ),
      );
      await tester.pumpAndSettle();

      expect(hero('Exchanging asset'), findsNWidgets(2));
    });
  });
}

/// Resumes the way the app's executors do: a new handle on every resume,
/// each following the same engine.
class _Engine implements SwapExecutor {
  _Engine(this.source);

  @override
  final SwapLiquiditySource source;
  final Map<String, SwapExecutionSnapshot> _latest = {};
  final StreamController<SwapExecutionSnapshot> _engine =
      StreamController<SwapExecutionSnapshot>.broadcast();

  void push(SwapExecutionSnapshot snapshot) {
    _latest[snapshot.id] = snapshot;
    _engine.add(snapshot);
  }

  @override
  Future<SwapExecutionHandle?> resume(String id) async {
    final latest = _latest[id];
    if (latest == null) return null;
    return StreamSwapExecutionHandle(
      initial: latest,
      source: _engine.stream.where((snapshot) => snapshot.id == id),
      cancel: () async {},
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

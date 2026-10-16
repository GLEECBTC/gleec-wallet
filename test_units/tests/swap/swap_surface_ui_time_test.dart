import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/execution/swap_execution_view.dart';
import 'package:web_dex/views/swap/execution/swap_time_context.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

import 'swap_accessibility_checks.dart';
import 'swap_common_ui_fakes.dart';
import 'swap_surface_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// [base] with the times [snapshotOf] cannot set.
SwapExecutionSnapshot _timed(
  SwapExecutionSnapshot base, {
  Duration? estimate,
  DateTime? unlock,
}) => SwapExecutionSnapshot(
  id: base.id,
  source: base.source,
  routeKind: base.routeKind,
  from: base.from,
  fromTicker: base.fromTicker,
  to: base.to,
  toTicker: base.toTicker,
  sellAmount: base.sellAmount,
  expectedReceive: base.expectedReceive,
  minimumReceive: base.minimumReceive,
  stage: base.stage,
  outcome: base.outcome,
  fundsMovement: base.fundsMovement,
  canCancel: base.canCancel,
  stages: base.stages,
  estimatedDuration: estimate,
  createdAt: base.createdAt,
  finishedAt: base.finishedAt,
  delayedSince: base.delayedSince,
  refundUnlocksAt: unlock,
  evidence: base.evidence,
);

/// Covers the line under the hero that says when a swap started, how long
/// it has run or took, and when a refund unlocks.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final start = DateTime(2026, 9, 30, 14, 2);

  group('the time under the hero', () {
    useSwapUi();

    late DateTime clock;

    Future<void> show(
      WidgetTester tester,
      SwapExecutionSnapshot snapshot, {
      bool delayed = false,
      double textScale = 1,
      Size size = const Size(420, 900),
    }) => pumpSwapUi(
      tester,
      SwapTimeContext(snapshot: snapshot, delayed: delayed, now: () => clock),
      size: size,
      media: (
        textScale: textScale,
        boldText: false,
        reduceMotion: false,
        announces: false,
      ),
    );

    testWidgets('says when a running swap started and how long it has run', (
      tester,
    ) async {
      final running = snapshotOf(createdAt: start);
      for (final (after, text) in [
        (const Duration(seconds: 20), 'Started 14:02 · under a minute'),
        (const Duration(minutes: 12, seconds: 30), 'Started 14:02 · 12 min'),
        (const Duration(hours: 1, minutes: 5), 'Started 14:02 · 1 h 5 min'),
        (const Duration(hours: 2), 'Started 14:02 · 2 h'),
      ]) {
        clock = start.add(after);
        await show(tester, running);
        expect(find.text(text), findsOneWidget);
      }
    });

    testWidgets('moves on with each minute', (tester) async {
      clock = start.add(const Duration(seconds: 30));
      await show(tester, snapshotOf(createdAt: start));
      expect(find.text('Started 14:02 · under a minute'), findsOneWidget);

      clock = start.add(const Duration(minutes: 1));
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('Started 14:02 · 1 min'), findsOneWidget);
    });

    testWidgets('says how long a routed swap usually takes, then that it is '
        'taking longer', (tester) async {
      final routed = _timed(
        snapshotOf(createdAt: start),
        estimate: const Duration(minutes: 2, seconds: 30),
      );
      clock = start.add(const Duration(minutes: 1));
      await show(tester, routed);
      expect(find.text('Usually takes about 3 min'), findsOneWidget);

      clock = start.add(const Duration(minutes: 3));
      await tester.pump(const Duration(minutes: 2));
      expect(find.text('Taking longer than usual'), findsOneWidget);
      expect(find.text('Usually takes about 3 min'), findsNothing);
    });

    testWidgets('says a short estimate plainly', (tester) async {
      clock = start.add(const Duration(seconds: 10));
      await show(
        tester,
        _timed(
          snapshotOf(createdAt: start),
          estimate: const Duration(seconds: 45),
        ),
      );
      expect(find.text('Usually takes under a minute'), findsOneWidget);
    });

    testWidgets('leaves the estimate out while the status may be stale', (
      tester,
    ) async {
      clock = start.add(const Duration(minutes: 1));
      await show(
        tester,
        _timed(
          snapshotOf(createdAt: start),
          estimate: const Duration(minutes: 3),
        ),
        delayed: true,
      );
      expect(find.text('Started 14:02 · 1 min'), findsOneWidget);
      expect(find.textContaining('Usually'), findsNothing);
    });

    testWidgets('says when a refund unlocks, then that it has', (tester) async {
      final unlock = DateTime(2026, 9, 30, 16, 40);
      clock = start.add(const Duration(minutes: 20));
      await show(
        tester,
        _timed(
          snapshotOf(createdAt: start, stage: SwapProgressStage.refunding),
          estimate: const Duration(minutes: 3),
          unlock: unlock,
        ),
      );
      expect(find.text('Refund unlocks at about 16:40'), findsOneWidget);
      expect(find.textContaining('Usually'), findsNothing);

      clock = unlock;
      await tester.pump(
        unlock.difference(start.add(const Duration(minutes: 20))),
      );
      expect(find.text('Refund unlocked at 16:40'), findsOneWidget);
    });

    testWidgets('says when a finished swap finished and how long it took', (
      tester,
    ) async {
      final end = start.add(const Duration(minutes: 4));
      clock = end.add(const Duration(hours: 1));
      await show(
        tester,
        snapshotOf(createdAt: start, finishedAt: end, outcome: completed()),
      );
      expect(find.text('Finished 14:06 · took 4 min'), findsOneWidget);

      await show(tester, snapshotOf(finishedAt: end, outcome: completed()));
      expect(find.text('Finished 14:06'), findsOneWidget);

      await show(tester, snapshotOf(outcome: completed()));
      expect(find.textContaining('Finished'), findsNothing);
    });

    testWidgets('wraps at the largest text rather than cutting off', (
      tester,
    ) async {
      clock = start.add(const Duration(hours: 1, minutes: 5));
      await show(
        tester,
        _timed(
          snapshotOf(createdAt: start),
          estimate: const Duration(minutes: 30),
        ),
        textScale: 2,
        size: const Size(375, 900),
      );
      expect(tester.takeException(), isNull);
      await expectSwapAccessible(tester, largeText: true);
    });
  });

  group('on the progress screen', () {
    late GatedExecutor routed;
    late SwapExecutionRegistry registry;
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

    testWidgets('sits under the hero, outside what it announces', (
      tester,
    ) async {
      final snapshot = snapshotOf(createdAt: start);
      routed.resumable[snapshot.id] = FakeHandle(snapshot);
      await pumpSurface(
        tester,
        SwapExecutionView(id: snapshot.id, context: SwapExecutionContext.flow),
        services: services,
        swap: swap,
        shell: shell,
      );

      final line = find.textContaining('Started ');
      expect(line, findsOneWidget);
      expect(
        find.ancestor(of: line, matching: find.byType(SwapStatusHero)),
        findsNothing,
      );
      expect(
        tester.getTopLeft(line).dy,
        greaterThan(tester.getBottomLeft(find.byType(SwapStatusHero)).dy - 1),
      );
    });
  });
}

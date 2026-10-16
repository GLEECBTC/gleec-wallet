import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/execution/swap_execution_view.dart';
import 'package:web_dex/views/swap/execution/swap_time_context.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

import 'swap_accessibility_checks.dart';
import 'swap_common_ui_fakes.dart';
import 'swap_surface_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the cue that a quiet swap is still being checked: when the engine
/// last answered, in steps that change only when they read differently.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final start = DateTime(2026, 9, 30, 14, 2);

  group('the last check', () {
    useSwapUi();

    late DateTime clock;
    final answered = start.add(const Duration(minutes: 12));

    Future<void> show(
      WidgetTester tester, {
      DateTime? checkedAt,
      Stream<DateTime>? checks,
      SwapExecutionSnapshot? snapshot,
      double textScale = 1,
    }) => pumpSwapUi(
      tester,
      SwapTimeContext(
        snapshot: snapshot ?? snapshotOf(createdAt: start),
        checkedAt: checkedAt,
        checks: checks,
        now: () => clock,
      ),
      size: Size(375, 900 * textScale),
      media: (
        textScale: textScale,
        boldText: false,
        reduceMotion: false,
        announces: false,
      ),
    );

    Future<void> after(WidgetTester tester, Duration age) async {
      clock = answered.add(age);
      await tester.pump(const Duration(minutes: 2));
    }

    testWidgets('joins the time the swap started', (tester) async {
      clock = answered.add(const Duration(seconds: 5));
      await show(tester, checkedAt: answered);

      expect(
        find.text('Started 14:02 · 12 min · checked just now'),
        findsOneWidget,
      );
    });

    testWidgets('grows older in tens of seconds, then in minutes', (
      tester,
    ) async {
      clock = answered;
      await show(tester, checkedAt: answered);

      for (final (age, text) in [
        (const Duration(seconds: 19), 'checked just now'),
        (const Duration(seconds: 25), 'checked 20 s ago'),
        (const Duration(seconds: 59), 'checked 50 s ago'),
        (const Duration(minutes: 2, seconds: 5), 'checked 2 min ago'),
      ]) {
        await after(tester, age);
        expect(find.textContaining(text), findsOneWidget, reason: '$age');
      }
    });

    testWidgets('comes back to just now with each answer', (tester) async {
      final checks = StreamController<DateTime>();
      addTearDown(checks.close);
      clock = answered.add(const Duration(minutes: 3));
      await show(tester, checkedAt: answered, checks: checks.stream);
      expect(find.textContaining('checked 3 min ago'), findsOneWidget);

      checks.add(clock);
      // Heard in one frame, built in the next.
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('checked just now'), findsOneWidget);
    });

    testWidgets('says nothing of checks before an answer, or once finished', (
      tester,
    ) async {
      clock = answered;
      await show(tester);
      expect(find.text('Started 14:02 · 12 min'), findsOneWidget);

      await show(
        tester,
        checkedAt: answered,
        snapshot: snapshotOf(
          createdAt: start,
          finishedAt: answered,
          outcome: completed(),
        ),
      );
      expect(find.textContaining('checked'), findsNothing);
    });

    testWidgets('fits at 200% text on a phone', (tester) async {
      clock = answered.add(const Duration(seconds: 40));
      await show(tester, checkedAt: answered, textScale: 2);
      await expectSwapAccessible(tester, largeText: true);
    });
  });

  group('on the progress screen', () {
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

    testWidgets('shows each answer as it arrives', (tester) async {
      final running = snapshotOf(
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      final handle = FakeHandle(running);
      routed.resumable[running.id] = handle;
      await pumpSurface(
        tester,
        SwapExecutionView(id: running.id, context: SwapExecutionContext.flow),
        services: services,
        swap: swap,
        shell: shell,
      );
      expect(find.textContaining('checked'), findsNothing);

      handle.check(DateTime.now());
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('· checked just now'), findsOneWidget);
    });
  });
}

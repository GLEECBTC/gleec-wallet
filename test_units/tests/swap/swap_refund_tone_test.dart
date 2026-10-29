import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/swap_activity/swap_activity_bloc.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_history_repository.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/activity/swap_activity_view.dart';
import 'package:web_dex/views/swap/common/swap_copy.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/execution/swap_timeline_view.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

import 'swap_common_ui_fakes.dart';
import 'swap_motion_fakes.dart';
import 'swap_surface_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers how a refund reads: amber wherever it is marked, never a
/// completion's green or a cancellation's grey.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("a refund's step", () {
    useSwapUi();

    const d = SwapStepStatus.done;
    const n = SwapStepStatus.notStarted;
    const r = SwapStepStatus.refunded;

    Future<void> show(
      WidgetTester tester,
      List<SwapStepStatus> statuses, {
      bool animate = false,
      bool settle = true,
    }) => pumpSwapUi(
      tester,
      SwapTimelineView(
        steps: [
          for (final (i, status) in statuses.indexed)
            SwapTimelineStep(
              title: 'Step $i',
              detail: 'Detail $i',
              status: status,
            ),
        ],
        animate: animate,
      ),
      settle: settle,
    );

    testWidgets('is amber, marked with a turn back, and says so', (
      tester,
    ) async {
      await show(tester, [d, r, n]);

      final circle = tester.widget<Container>(
        find
            .ancestor(
              of: find.byIcon(Icons.undo_rounded),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = circle.decoration! as BoxDecoration;
      final palette = SwapPalette.of(
        tester.element(find.byType(Container).first),
      );
      expect(decoration.color, palette.warningBg);
      expect((decoration.border! as Border).top.color, palette.warning);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
      expect(
        tester.getSemantics(find.byType(SwapTimelineView)).label,
        contains('Refunded: Step 1. Detail 1'),
      );
    });

    testWidgets('arrives without a bounce', (tester) async {
      await show(tester, [d, SwapStepStatus.current, n], animate: true);
      await show(tester, [d, r, n], animate: true, settle: false);

      final scales = <double>[];
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        final transform = effectTransform(tester);
        if (transform != null) scales.add(scaleOf(transform));
      }
      await tester.pumpAndSettle();

      expect(scales, isNotEmpty, reason: 'the turn back pops in');
      expect(
        scales.every((scale) => scale <= 1.0001),
        isTrue,
        reason: '$scales',
      );
    });
  });

  group('a refund in Activity', () {
    late FakeExecutor routed;
    late SwapExecutionRegistry registry;
    late ScriptedHistory history;
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

    testWidgets('says so in amber', (tester) async {
      history.entries = [
        snapshotOf(
          id: 'refunded',
          outcome: const SwapExecutionOutcome(kind: SwapOutcomeKind.refunded),
          createdAt: DateTime(2020, 3, 1),
        ),
        snapshotOf(
          id: 'completed',
          outcome: completed(),
          createdAt: DateTime(2020, 3, 2),
        ),
      ];
      await pumpSurface(
        tester,
        const SwapActivityView(),
        services: services,
        swap: swap,
        shell: shell,
        wrap: [
          (child) => BlocProvider(
            create: (_) =>
                SwapActivityBloc(history: history, registry: registry)..add(
                  const SwapActivityStarted(
                    filter: SwapActivityFilter.completed,
                  ),
                ),
            child: child,
          ),
        ],
      );

      final palette = SwapPalette.of(
        tester.element(find.text('Activity').first),
      );
      Color? colourOf(String status) =>
          tester.widget<Text>(find.text(status)).style?.color;
      expect(colourOf('Refund received'), palette.warning);
      expect(colourOf('Received'), palette.textTertiary);
    });
  });
}

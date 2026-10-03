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
import 'package:web_dex/views/swap/common/swap_format.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

import 'swap_accessibility_checks.dart';
import 'swap_surface_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Activity's list: Active, Needs attention and Completed, what each row
/// says, and what an empty, partial or unreadable history says.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Activity', () {
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

    Future<void> show(WidgetTester tester, {bool settle = true}) => pumpSurface(
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
      settle: settle,
    );

    Future<void> filter(WidgetTester tester, String label) async {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    Finder row(String status) =>
        find.ancestor(of: find.text(status), matching: find.byType(InkWell));

    Color? colourOf(WidgetTester tester, String text) =>
        tester.widget<Text>(find.text(text).first).style?.color;

    final running = snapshotOf(id: 'running', createdAt: DateTime(2020, 3, 1));
    final waiting = snapshotOf(
      id: 'waiting',
      stage: SwapProgressStage.actionRequired,
      createdAt: DateTime(2020, 2, 1),
    );

    testWidgets('holds the list open while it loads', (tester) async {
      history.gate = Completer<void>();
      await show(tester, settle: false);
      await tester.pump();

      expect(find.byType(SwapSkeleton), findsNWidgets(3));
      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.text('No active swaps'), findsNothing);
    });

    testWidgets('an unreadable history is an error, with a retry', (
      tester,
    ) async {
      history.error = StateError('offline');
      await show(tester);

      expect(find.text("We couldn't load Activity"), findsOneWidget);
      expect(find.text('Saved swaps are unchanged.'), findsOneWidget);

      history
        ..error = null
        ..entries = [running];
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(history.loads, hasLength(2));
      expect(find.text("We couldn't load Activity"), findsNothing);
      expect(find.text('1 ETH → 3,000 USDC'), findsOneWidget);
    });

    group('when there is nothing to show', () {
      testWidgets('Active says where swaps will continue, and offers one', (
        tester,
      ) async {
        await show(tester);

        expect(find.text('No active swaps'), findsOneWidget);
        expect(
          find.text(
            'Swaps you start continue here, even after you leave the progress '
            'screen.',
          ),
          findsOneWidget,
        );
        await expectSwapAccessible(tester);

        await tester.tap(find.text('Start a swap'));
        await tester.pump();
        expect(shell.destination, SwapDestination.swap);
      });

      testWidgets('Needs attention reassures, with nothing to start', (
        tester,
      ) async {
        await show(tester);
        await filter(tester, 'Needs attention');

        expect(find.text('Nothing needs attention'), findsOneWidget);
        expect(
          find.text('Swaps that finish differently than expected appear here.'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.task_alt_rounded), findsOneWidget);
        expect(find.text('Start a swap'), findsNothing);
        expect(history.loads.last.filter, SwapActivityFilter.attention);
      });

      testWidgets('Completed says finished swaps land there', (tester) async {
        await show(tester);
        await filter(tester, 'Completed');

        expect(find.text('No completed swaps yet'), findsOneWidget);
        expect(find.text('Finished swaps appear here.'), findsOneWidget);
        expect(find.text('Start a swap'), findsOneWidget);
      });
    });

    testWidgets('Active lists running swaps, flagging one that needs action', (
      tester,
    ) async {
      history.entries = [running, waiting];
      await show(tester);

      expect(find.text('Confirming on Ethereum'), findsOneWidget);
      expect(find.text('Action required'), findsNWidgets(2));
      expect(find.byType(SwapBadge), findsOneWidget);
      expect(find.text(SwapFormat.time(DateTime(2020, 3, 1))), findsOneWidget);
      expect(find.text(SwapFormat.time(DateTime(2020, 2, 1))), findsOneWidget);
      final palette = SwapPalette.dark;
      expect(colourOf(tester, 'Confirming on Ethereum'), palette.textTertiary);
      expect(colourOf(tester, 'Action required'), palette.warning);
      await expectSwapAccessible(tester);
    });

    testWidgets('Needs attention says why each swap is there', (tester) async {
      history.entries = [
        snapshotOf(id: 'lost', outcome: failed(SwapFailureReason.routeFailed)),
        snapshotOf(
          id: 'approved',
          fundsMovement: SwapFundsMovement.feesOnly,
          approvalRemains: true,
          outcome: const SwapExecutionOutcome(kind: SwapOutcomeKind.cancelled),
        ),
        snapshotOf(
          id: 'short',
          outcome: SwapExecutionOutcome(
            kind: SwapOutcomeKind.partialBelowMinimum,
            receivedAmount: d('2900'),
            receivedAsset: usdc,
          ),
        ),
        snapshotOf(
          id: 'other',
          outcome: SwapExecutionOutcome(
            kind: SwapOutcomeKind.partialOtherToken,
            receivedAmount: d('1'),
            receivedAsset: weth,
          ),
        ),
      ];
      await show(tester);
      await filter(tester, 'Needs attention');

      for (final status in [
        'Gleec support is needed',
        'Permission remains',
        'Received less than expected',
        'Different token received',
      ]) {
        expect(find.text(status), findsOneWidget, reason: status);
        expect(colourOf(tester, status), SwapPalette.dark.warning);
      }
      expect(find.text('Needs attention'), findsNWidgets(5));
    });

    testWidgets('Completed says how each swap ended, and when', (tester) async {
      final updated = DateTime(2020, 4, 1, 9);
      final finished = DateTime(2020, 4, 2, 9);
      history.entries = [
        reshaped(
          snapshotOf(id: 'done', outcome: completed()),
          updatedAt: updated,
        ),
        snapshotOf(
          id: 'refund',
          finishedAt: finished,
          outcome: const SwapExecutionOutcome(kind: SwapOutcomeKind.refunded),
        ),
        snapshotOf(
          id: 'stopped',
          fundsMovement: SwapFundsMovement.none,
          outcome: const SwapExecutionOutcome(kind: SwapOutcomeKind.cancelled),
        ),
        snapshotOf(
          id: 'unmatched',
          source: SwapLiquiditySource.atomic,
          fundsMovement: SwapFundsMovement.none,
          outcome: const SwapExecutionOutcome(kind: SwapOutcomeKind.noMatch),
        ),
      ];
      await show(tester);
      await filter(tester, 'Completed');

      for (final status in [
        'Received',
        'Refund received',
        'Cancelled',
        'No match found',
      ]) {
        expect(find.text(status), findsOneWidget, reason: status);
      }
      expect(find.byType(SwapBadge), findsNothing);
      expect(find.text(SwapFormat.time(updated)), findsOneWidget);
      expect(find.text(SwapFormat.time(finished)), findsOneWidget);
      expect(textsOf(tester, row('Cancelled')), [
        '1 ETH → 3,000 USDC',
        'Cancelled',
      ]);
      expect(colourOf(tester, 'Received'), SwapPalette.dark.textTertiary);
    });

    testWidgets('counts running swaps and unread problems on the filters', (
      tester,
    ) async {
      await registry.start(quoteOf());
      await registry.start(quoteOf(id: 'q2'));
      await show(tester);

      Finder count(String filter) => find.descendant(
        of: find.ancestor(
          of: find.text(filter),
          matching: find.byType(InkWell),
        ),
        matching: find.byType(SwapCountDot),
      );
      expect(tester.widget<SwapCountDot>(count('Active')).count, 2);
      expect(count('Needs attention'), findsNothing);
      expect(find.text('Preparing swap'), findsNWidgets(2));

      routed.lastStarted!.push(
        snapshotOf(
          id: 'routed-2',
          outcome: failed(SwapFailureReason.routeFailed),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.widget<SwapCountDot>(count('Active')).count, 1);
      expect(tester.widget<SwapCountDot>(count('Needs attention')).count, 1);
      expect(count('Completed'), findsNothing);
      expect(find.text('Preparing swap'), findsOneWidget);
    });
  });
}

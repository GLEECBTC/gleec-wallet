import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/execution/swap_execution_view.dart';
import 'package:web_dex/views/swap/motion/swap_motion.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

import 'swap_motion_fakes.dart';
import 'swap_surface_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the moments that mark news of a swap: one quiet ring for a swap
/// that completes on screen, one haptic matched to each outcome, and nothing
/// at all for a swap that is only being reopened.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('news of a swap on screen', () {
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

    Future<FakeHandle> open(
      WidgetTester tester,
      SwapExecutionSnapshot snapshot, {
      SwapExecutionSnapshot? initial,
      bool reduceMotion = false,
      bool settle = true,
    }) async {
      final handle = FakeHandle(snapshot);
      routed.resumable[snapshot.id] = handle;
      await pumpSurface(
        tester,
        SwapExecutionView(
          id: snapshot.id,
          context: initial == null
              ? SwapExecutionContext.flow
              : SwapExecutionContext.activity,
          initial: initial,
        ),
        services: services,
        swap: swap,
        shell: shell,
        wrap: [
          if (reduceMotion)
            (child) => Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: child,
              ),
            ),
        ],
        settle: settle,
      );
      await tester.pump();
      await tester.pump();
      return handle;
    }

    Future<void> hear(
      WidgetTester tester,
      FakeHandle handle,
      SwapExecutionSnapshot next,
    ) async {
      handle.push(next);
      await tester.pump();
      await tester.pump();
    }

    RenderObject heroRing(WidgetTester tester) => tester.renderObject(
      find
          .descendant(
            of: find.descendant(
              of: find.byType(SwapStatusHero),
              matching: find.byType(SwapPulse),
            ),
            matching: find.byType(CustomPaint),
          )
          .first,
    );

    testWidgets('a swap completing on screen rings once, with one success '
        'haptic', (tester) async {
      final played = recordHaptics(tester);
      final handle = await open(tester, snapshotOf());
      await tester.pumpAndSettle();

      await hear(tester, handle, snapshotOf(outcome: completed()));
      await tester.pump(SwapMotion.ring ~/ 2);
      expect(heroRing(tester), paints..rrect(style: PaintingStyle.stroke));
      expect(played, ['HapticFeedbackType.successNotification']);

      await tester.pumpAndSettle();
      await hear(
        tester,
        handle,
        snapshotOf(outcome: completed(), sourceTxHash: '0xsource'),
      );
      await tester.pumpAndSettle();
      expect(played, hasLength(1));
      expect(
        heroRing(tester),
        isNot(paints..rrect(style: PaintingStyle.stroke)),
      );
    });

    testWidgets('reopening a finished swap plays nothing', (tester) async {
      final played = recordHaptics(tester);
      await open(tester, snapshotOf(outcome: completed()), settle: false);
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpAndSettle();
      expect(played, isEmpty);
    });

    testWidgets('a snapshot from history the engine answers as finished '
        'plays nothing', (tester) async {
      final played = recordHaptics(tester);
      await open(
        tester,
        snapshotOf(outcome: completed()),
        initial: snapshotOf(),
        settle: false,
      );
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpAndSettle();
      expect(played, isEmpty);
    });

    final outcomes = <String, (SwapExecutionOutcome, String)>{
      'refunded': (
        const SwapExecutionOutcome(kind: SwapOutcomeKind.refunded),
        'HapticFeedbackType.lightImpact',
      ),
      'short of the minimum': (
        const SwapExecutionOutcome(kind: SwapOutcomeKind.partialBelowMinimum),
        'HapticFeedbackType.warningNotification',
      ),
      'another token': (
        const SwapExecutionOutcome(kind: SwapOutcomeKind.partialOtherToken),
        'HapticFeedbackType.warningNotification',
      ),
      'cancelled': (
        const SwapExecutionOutcome(kind: SwapOutcomeKind.cancelled),
        'HapticFeedbackType.selectionClick',
      ),
      'not matched': (
        const SwapExecutionOutcome(kind: SwapOutcomeKind.noMatch),
        'HapticFeedbackType.lightImpact',
      ),
      'failed, funds safe': (
        failed(SwapFailureReason.priceMoved),
        'HapticFeedbackType.warningNotification',
      ),
      'failed after sending': (
        failed(SwapFailureReason.reverted),
        'HapticFeedbackType.errorNotification',
      ),
    };

    for (final MapEntry(key: name, value: (outcome, haptic))
        in outcomes.entries) {
      testWidgets('$name: one matching haptic and no ring', (tester) async {
        final played = recordHaptics(tester);
        final handle = await open(tester, snapshotOf());
        await tester.pumpAndSettle();

        await hear(tester, handle, snapshotOf(outcome: outcome));
        await tester.pump(SwapMotion.ring ~/ 2);
        expect(played, [haptic]);
        expect(
          heroRing(tester),
          isNot(paints..rrect(style: PaintingStyle.stroke)),
        );
        await tester.pumpAndSettle();
      });
    }

    testWidgets('waiting on the user: a warning haptic, and the route button '
        'pulses twice then stops', (tester) async {
      final played = recordHaptics(tester);
      final handle = await open(tester, snapshotOf());
      await tester.pumpAndSettle();

      await hear(
        tester,
        handle,
        reshaped(
          snapshotOf(stage: SwapProgressStage.actionRequired),
          evidence: const SwapEvidence(
            executionId: 'swap-1',
            providerExplorerUrl: 'https://route.example/status/1',
          ),
        ),
      );
      expect(played, ['HapticFeedbackType.warningNotification']);

      final button = find.ancestor(
        of: find.text('Open route page'),
        matching: find.byType(SwapPulse),
      );
      expect(button, findsOneWidget);
      await tester.pump(SwapMotion.screen + SwapMotion.beat ~/ 2);
      expect(
        tester.renderObject(
          find.descendant(of: button, matching: find.byType(CustomPaint)).first,
        ),
        paints..rrect(style: PaintingStyle.stroke),
      );
      await tester.pumpAndSettle();
      expect(played, hasLength(1));
    });

    testWidgets('a step completing plays one selection click', (tester) async {
      final played = recordHaptics(tester);
      final handle = await open(tester, snapshotOf());
      await tester.pumpAndSettle();

      await hear(
        tester,
        handle,
        snapshotOf(stage: SwapProgressStage.awaitingDelivery),
      );
      await tester.pumpAndSettle();
      expect(played, ['HapticFeedbackType.selectionClick']);
    });

    testWidgets('a peer-to-peer refund starting completes no step', (
      tester,
    ) async {
      SwapExecutionSnapshot peerToPeer(SwapProgressStage stage) => snapshotOf(
        source: SwapLiquiditySource.atomic,
        routeKind: SwapRouteKind.direct,
        stage: stage,
        stages: const [],
      );
      final played = recordHaptics(tester);
      final handle = await open(
        tester,
        peerToPeer(SwapProgressStage.exchanging),
      );
      await tester.pumpAndSettle();

      await hear(tester, handle, peerToPeer(SwapProgressStage.refunding));
      await tester.pumpAndSettle();
      expect(played, isEmpty);
    });

    testWidgets('news that moves nothing on plays no haptic', (tester) async {
      final played = recordHaptics(tester);
      final handle = await open(tester, snapshotOf());
      await tester.pumpAndSettle();

      await hear(tester, handle, snapshotOf(sourceTxHash: '0xsource'));
      await tester.pumpAndSettle();
      expect(played, isEmpty);
    });

    testWidgets('with less motion: no ring, and the haptic still plays', (
      tester,
    ) async {
      final played = recordHaptics(tester);
      final handle = await open(tester, snapshotOf(), reduceMotion: true);
      await tester.pumpAndSettle();

      await hear(tester, handle, snapshotOf(outcome: completed()));
      expect(tester.hasRunningAnimations, isFalse);
      expect(played, ['HapticFeedbackType.successNotification']);
    });

    testWidgets('no haptic plays while the app is in the background', (
      tester,
    ) async {
      final played = recordHaptics(tester);
      final handle = await open(tester, snapshotOf());
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );

      await hear(tester, handle, snapshotOf(outcome: completed()));
      expect(played, isEmpty);
    });
  });
}

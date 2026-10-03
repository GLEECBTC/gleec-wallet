import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/common/swap_copy.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/execution/swap_execution_view.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

import 'swap_accessibility_checks.dart';
import 'swap_common_ui_fakes.dart';
import 'swap_surface_ui_fakes.dart';
import 'swap_test_fixtures.dart';

const _leave = 'You can leave this screen. The swap continues in Activity.';
const _untilSent =
    'You can leave this screen, but keep Gleec open and signed in until the '
    'swap is sent. Closing it before then stops the swap.';
const _untilSentWeb =
    'You can leave this screen, but keep Gleec open in this tab, and signed '
    'in, until the swap is sent. Closing the tab before then stops the swap.';
const _keepOpen =
    'You can leave this screen, but keep Gleec open and signed in until the '
    'swap finishes. The swap runs on this device, and pauses while Gleec is '
    'closed.';
const _keepOpenWeb =
    'You can leave this screen, but keep Gleec open in this tab, and signed '
    "in, until the swap finishes. The swap runs in this tab, and pauses while "
    "it's closed.";
const _refund =
    'Keep Gleec open and signed in: it sends your refund from this device '
    'once the refund unlocks. If Gleec is closed then, the refund goes out '
    'when you next sign in.';
const _refundWeb =
    'Keep Gleec open in this tab, and signed in: it sends your refund once '
    'the refund unlocks. If the tab is closed then, the refund goes out when '
    'you next sign in here.';

/// Covers what a running swap says about leaving its screen, or Gleec: a
/// peer-to-peer swap runs on this device to the end, a routed one only until
/// its transaction is out.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the note on leaving', () {
    useEnglishCopy();

    final networks = SwapNetworks([eth, usdc, btc, gleec]);
    ({String message, IconData icon}) noteOf(
      SwapExecutionSnapshot snapshot, {
      bool web = false,
    }) => SwapExecutionCopy(snapshot, networks).leaveNote(web: web);

    SwapExecutionSnapshot atomic(SwapProgressStage stage) => snap(
      source: SwapLiquiditySource.atomic,
      routeKind: SwapRouteKind.direct,
      stage: stage,
      stages: const [],
    );

    test('a routed swap needs Gleec until its transaction is out', () {
      for (final stage in [
        SwapProgressStage.preparing,
        SwapProgressStage.approving,
        SwapProgressStage.signing,
        SwapProgressStage.sending,
      ]) {
        final early = snap(stage: stage, fundsMovement: SwapFundsMovement.none);
        expect(noteOf(early).message, _untilSent, reason: '$stage');
        expect(noteOf(early, web: true).message, _untilSentWeb);
      }
    });

    test('and not once it is', () {
      for (final stage in [
        SwapProgressStage.confirming,
        SwapProgressStage.bridging,
        SwapProgressStage.awaitingDelivery,
        SwapProgressStage.refunding,
        SwapProgressStage.actionRequired,
      ]) {
        expect(noteOf(snap(stage: stage)).message, _leave, reason: '$stage');
        expect(noteOf(snap(stage: stage), web: true).message, _leave);
      }
      final sending = snap(
        stage: SwapProgressStage.sending,
        evidence: const SwapEvidence(
          executionId: 'swap-1',
          sourceTxHash: '0xsource',
        ),
      );
      expect(noteOf(sending).message, _leave);
    });

    test('a stage this build does not know goes by what was sent', () {
      expect(noteOf(snap(stage: SwapProgressStage.unknown)).message, _leave);
      expect(
        noteOf(
          snap(
            stage: SwapProgressStage.unknown,
            fundsMovement: SwapFundsMovement.none,
          ),
        ).message,
        _untilSent,
      );
    });

    test('a peer-to-peer swap needs Gleec to the end', () {
      for (final stage in [
        SwapProgressStage.matching,
        SwapProgressStage.sending,
        SwapProgressStage.confirming,
        SwapProgressStage.exchanging,
      ]) {
        expect(noteOf(atomic(stage)).message, _keepOpen, reason: '$stage');
        expect(noteOf(atomic(stage), web: true).message, _keepOpenWeb);
      }
    });

    test('its refund goes out from this device once it unlocks', () {
      final refunding = atomic(SwapProgressStage.refunding);
      expect(noteOf(refunding).message, _refund);
      expect(noteOf(refunding, web: true).message, _refundWeb);
    });

    test('shows where the swap runs while it needs Gleec open', () {
      final early = snap(
        stage: SwapProgressStage.preparing,
        fundsMovement: SwapFundsMovement.none,
      );
      expect(noteOf(early).icon, Icons.devices_rounded);
      expect(noteOf(early, web: true).icon, Icons.web_asset_rounded);
      expect(
        noteOf(atomic(SwapProgressStage.exchanging)).icon,
        Icons.devices_rounded,
      );
      expect(
        noteOf(snap(stage: SwapProgressStage.bridging)).icon,
        Icons.schedule_rounded,
      );
    });

    test('a peer-to-peer refund names the lock, not a route', () {
      expect(
        SwapExecutionCopy(
          atomic(SwapProgressStage.refunding),
          networks,
        ).hero.body,
        'Your payment is locked until the refund unlocks. Then it comes back '
        'to your wallet.',
      );
      expect(
        SwapExecutionCopy(
          snap(stage: SwapProgressStage.refunding),
          networks,
        ).hero.body,
        'The route is returning your funds. Gleec will keep tracking.',
      );
    });
  });

  group('on the progress screen', () {
    late FakeExecutor atomic;
    late SwapExecutionRegistry registry;
    late SurfaceServices services;
    late RecordingSwapBloc swap;
    late SwapShellController shell;

    setUpAll(loadSurfaceCopy);

    setUp(() {
      atomic = FakeExecutor(SwapLiquiditySource.atomic);
      registry = SwapExecutionRegistry(
        executors: [atomic],
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

    Future<void> show(
      WidgetTester tester,
      SwapProgressStage stage, {
      double textScale = 1,
    }) async {
      final running = snapshotOf(
        id: 'swap-${stage.name}',
        source: SwapLiquiditySource.atomic,
        routeKind: SwapRouteKind.direct,
        stage: stage,
        stages: const [],
      );
      atomic.resumable[running.id] = FakeHandle(running);
      await pumpSurface(
        tester,
        SwapExecutionView(id: running.id, context: SwapExecutionContext.flow),
        services: services,
        swap: swap,
        shell: shell,
        size: Size(375, 1400 * textScale),
        wrap: [
          (child) => Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child,
            ),
          ),
        ],
      );
    }

    Finder note(String text) => find.descendant(
      of: find.byType(SwapCallout),
      matching: find.text(text),
    );

    testWidgets('a peer-to-peer swap asks for Gleec to stay open', (
      tester,
    ) async {
      await show(tester, SwapProgressStage.exchanging);

      expect(note(_keepOpen), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SwapCallout),
          matching: find.byIcon(Icons.devices_rounded),
        ),
        findsOneWidget,
      );
      expect(find.text(_leave), findsNothing);
      await expectSwapAccessible(tester);
    });

    testWidgets('its refund says the payment is locked, and who sends it', (
      tester,
    ) async {
      await show(tester, SwapProgressStage.refunding);

      expect(note(_refund), findsOneWidget);
      expect(
        find.text(
          'Your payment is locked until the refund unlocks. Then it comes '
          'back to your wallet.',
        ),
        findsOneWidget,
      );
      await expectSwapAccessible(tester);
    });

    testWidgets('the notes fit at 200% text on a phone', (tester) async {
      for (final stage in [
        SwapProgressStage.exchanging,
        SwapProgressStage.refunding,
      ]) {
        await show(tester, stage, textScale: 2);
        await expectSwapAccessible(tester, largeText: true);
      }
    });
  });
}

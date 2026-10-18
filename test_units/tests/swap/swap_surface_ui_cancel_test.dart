import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/execution/swap_execution_view.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

import 'swap_accessibility_checks.dart';
import 'swap_surface_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Cancelling a running swap: only while nothing has been sent, only after
/// the user confirms, and honestly when the engine says no.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('cancelling a swap', () {
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

    SwapExecutionSnapshot cancellable({List<String> approvals = const []}) =>
        snapshotOf(
          stage: SwapProgressStage.preparing,
          fundsMovement: SwapFundsMovement.none,
          canCancel: true,
          approvalTxHashes: approvals,
        );

    Future<FakeHandle> follow(WidgetTester tester, FakeHandle handle) async {
      routed.resumable[handle.id] = handle;
      await pumpSurface(
        tester,
        SwapExecutionView(id: handle.id, context: SwapExecutionContext.flow),
        services: services,
        swap: swap,
        shell: shell,
      );
      return handle;
    }

    Finder cancelButton() => find.byKey(const Key('swap-cancel'));

    Finder inDialog(String text) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(text),
    );

    Future<void> askToCancel(WidgetTester tester) async {
      await tester.tap(cancelButton());
      await tester.pumpAndSettle();
    }

    Future<void> confirm(WidgetTester tester) async {
      await tester.tap(inDialog('Cancel swap'));
      await tester.pumpAndSettle();
    }

    bool pressable(WidgetTester tester) =>
        tester
            .widget<TextButton>(
              find.descendant(
                of: cancelButton(),
                matching: find.byType(TextButton),
              ),
            )
            .onPressed !=
        null;

    testWidgets('asks first, and keeping the swap cancels nothing', (
      tester,
    ) async {
      final handle = await follow(tester, FakeHandle(cancellable()));

      await askToCancel(tester);
      expect(inDialog('Cancel swap?'), findsOneWidget);
      expect(
        inDialog('Nothing has been sent. You can safely cancel now.'),
        findsOneWidget,
      );
      await expectSwapAccessible(tester);

      await tester.tap(inDialog('Keep swapping'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(handle.cancelCalls, 0);
      expect(cancelButton(), findsOneWidget);
    });

    testWidgets('confirming stops the swap', (tester) async {
      final handle = await follow(tester, FakeHandle(cancellable()));

      await askToCancel(tester);
      await confirm(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(handle.cancelCalls, 1);
    });

    testWidgets('warns that an approved permission stays on-chain', (
      tester,
    ) async {
      await follow(tester, FakeHandle(cancellable(approvals: ['0xapproval'])));

      await askToCancel(tester);

      expect(
        inDialog(
          "The swap hasn't been sent. The permission already approved stays "
          'on-chain, and its network fee is spent.',
        ),
        findsOneWidget,
      );
      expect(
        inDialog('Nothing has been sent. You can safely cancel now.'),
        findsNothing,
      );
    });

    testWidgets('shows the cancel under way, and it cannot be pressed twice', (
      tester,
    ) async {
      final handle = GatedHandle(cancellable());
      await follow(tester, handle);

      await askToCancel(tester);
      await tester.tap(inDialog('Cancel swap'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.descendant(of: cancelButton(), matching: find.text('Cancelling…')),
        findsOneWidget,
      );
      expect(pressable(tester), isFalse);

      handle.cancelGate.complete();
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: cancelButton(), matching: find.text('Cancel swap')),
        findsOneWidget,
      );
      expect(pressable(tester), isTrue);
      expect(handle.cancelCalls, 1);
    });

    final refusals = <String, (Object, String)>{
      'already sent': (
        const SwapCancelRefusedException(SwapCancelRefusal.alreadySent),
        "This swap was already sent to the network, so it can't be cancelled. "
            'It continues to completion.',
      ),
      'a peer-to-peer exchange': (
        const SwapCancelRefusedException(SwapCancelRefusal.notSupported),
        "A peer-to-peer exchange can't be stopped once matched. If the other "
            "side doesn't complete, your funds are refunded automatically.",
      ),
      'the answer was lost': (
        StateError('socket closed'),
        "We couldn't confirm the cancellation. The status below stays "
            'accurate.',
      ),
    };

    for (final MapEntry(key: why, value: (error, message))
        in refusals.entries) {
      testWidgets('a refused cancel says why: $why', (tester) async {
        final handle = FakeHandle(cancellable())..cancelError = error;
        await follow(tester, handle);

        await askToCancel(tester);
        await confirm(tester);

        expect(find.text(message), findsOneWidget);
        expect(
          tester.getSemantics(find.text(message)),
          isSemantics(isLiveRegion: true),
        );
      });
    }

    testWidgets('a swap that already finished refuses without a warning', (
      tester,
    ) async {
      final handle = FakeHandle(cancellable())
        ..cancelError = const SwapCancelRefusedException(
          SwapCancelRefusal.alreadyFinished,
        );
      await follow(tester, handle);

      await askToCancel(tester);
      await confirm(tester);

      expect(handle.cancelCalls, 1);
      for (final (_, message) in refusals.values) {
        expect(find.text(message), findsNothing);
      }
    });

    testWidgets('offers no cancel once the swap was sent', (tester) async {
      final handle = await follow(tester, FakeHandle(cancellable()));
      expect(cancelButton(), findsOneWidget);

      handle.push(snapshotOf(stage: SwapProgressStage.sending));
      await tester.pumpAndSettle();

      expect(cancelButton(), findsNothing);
      expect(find.text('Sending on Ethereum'), findsWidgets);
    });

    testWidgets('a cancel confirmed after the screen closed does nothing', (
      tester,
    ) async {
      final showing = ValueNotifier(true);
      addTearDown(showing.dispose);
      final handle = FakeHandle(cancellable());
      routed.resumable[handle.id] = handle;
      await pumpSurface(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: showing,
          builder: (context, show, _) => show
              ? SwapExecutionView(
                  id: handle.id,
                  context: SwapExecutionContext.flow,
                )
              : const SizedBox(),
        ),
        services: services,
        swap: swap,
        shell: shell,
      );

      await askToCancel(tester);
      showing.value = false;
      await tester.pump();
      await confirm(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(handle.cancelCalls, 0);
    });
  });
}

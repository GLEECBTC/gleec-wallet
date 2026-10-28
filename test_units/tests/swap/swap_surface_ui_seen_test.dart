import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/execution/swap_execution_view.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

import 'swap_surface_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// A swap that needs attention keeps its marks — on the Swap menu, in
/// Activity and on the tab — until the user has had it in front of them
/// finished, not merely opened it while it ran.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const away = [AppLifecycleState.inactive, AppLifecycleState.hidden];
  const back = [AppLifecycleState.inactive, AppLifecycleState.resumed];

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

  final failure = snapshotOf(outcome: failed(SwapFailureReason.routeFailed));

  Future<FakeHandle> open(
    WidgetTester tester,
    SwapExecutionSnapshot snapshot,
  ) async {
    final handle = FakeHandle(snapshot);
    routed.resumable[snapshot.id] = handle;
    await pumpSurface(
      tester,
      SwapExecutionView(
        id: snapshot.id,
        context: SwapExecutionContext.activity,
      ),
      services: services,
      swap: swap,
      shell: shell,
    );
    return handle;
  }

  Future<void> go(WidgetTester tester, List<AppLifecycleState> states) async {
    for (final state in states) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
  }

  int unseen() => registry.unacknowledgedAttentionCount;

  testWidgets('a failure that lands on screen is seen', (tester) async {
    final handle = await open(tester, snapshotOf());

    handle.push(failure);
    await tester.pumpAndSettle();

    expect(find.text('WHAT HAPPENED?'), findsOneWidget);
    expect(unseen(), 0);
  });

  testWidgets('a finished swap opened from Activity is seen at once', (
    tester,
  ) async {
    await open(tester, failure);

    expect(unseen(), 0);
  });

  testWidgets('a swap opened while it ran still counts once it fails '
      'after the screen closed', (tester) async {
    final handle = await open(tester, snapshotOf());
    await tester.pumpWidget(const SizedBox());

    handle.push(failure);
    await tester.pump();

    expect(unseen(), 1);
  });

  testWidgets('a failure that lands in a background tab counts until the '
      'user is back', (tester) async {
    final handle = await open(tester, snapshotOf());
    await go(tester, away);
    addTearDown(() => go(tester, back));

    handle.push(failure);
    await tester.pump();
    await tester.pump();
    expect(unseen(), 1);

    await go(tester, back);
    expect(unseen(), 0);
  });

  testWidgets('a failure that lands under another screen counts until that '
      'screen goes', (tester) async {
    final covered = ValueNotifier(true);
    addTearDown(covered.dispose);
    final handle = FakeHandle(snapshotOf());
    routed.resumable['swap-1'] = handle;
    await pumpSurface(
      tester,
      ValueListenableBuilder<bool>(
        valueListenable: covered,
        builder: (context, covered, child) =>
            TickerMode(enabled: !covered, child: child!),
        child: const SwapExecutionView(
          id: 'swap-1',
          context: SwapExecutionContext.activity,
        ),
      ),
      services: services,
      swap: swap,
      shell: shell,
    );

    handle.push(failure);
    await tester.pump();
    expect(unseen(), 1);

    covered.value = false;
    await tester.pump();
    expect(unseen(), 0);
  });

  testWidgets('a swap waiting on the user stays marked while shown', (
    tester,
  ) async {
    await open(tester, snapshotOf(stage: SwapProgressStage.actionRequired));

    expect(unseen(), 1);
  });
}

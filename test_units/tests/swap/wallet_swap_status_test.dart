import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/shared/swap/swap_execution_presentation.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_session_draft.dart';
import 'package:web_dex/views/swap/execution/swap_execution_view.dart';
import 'package:web_dex/views/swap/execution/swap_timeline_view.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_main/wallet_swap_status.dart';

import 'swap_surface_ui_fakes.dart';
import 'swap_test_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('wallet swap continuity', () {
    late FakeExecutor executor;
    late SwapExecutionRegistry registry;
    late SurfaceServices services;
    late RecordingSwapBloc swap;
    late SwapShellController shell;

    setUpAll(loadSurfaceCopy);
    setUp(() {
      executor = FakeExecutor(SwapLiquiditySource.routed);
      registry = testSwapRegistry(
        executors: [executor],
        inFlight: () async => const [],
      );
      services = SurfaceServices(registry);
      swap = RecordingSwapBloc(registry);
      shell = SwapShellController();
      useFreshRoutingState();
    });
    tearDown(() async {
      await services.dispose();
      await registry.dispose();
      await swap.close();
      shell.dispose();
      resetSurfaceCopy();
    });

    Future<FakeHandle> start() async {
      await registry.start(quoteOf(), registry.beginSubmission());
      return executor.lastStarted!;
    }

    testWidgets('one row opens its execution; several open Activity', (
      tester,
    ) async {
      final first = await start();
      await pumpSurface(tester, const WalletSwapStatus(), services: services);
      await tester.tap(find.byKey(const Key('wallet-swap-status')));
      expect(services.takePendingOpen(), (
        id: first.id,
        source: SwapLiquiditySource.routed,
      ));
      expect(routingState.selectedMenu, MainMenuValue.dex);

      await start();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(services.presentation.walletEntries, hasLength(2));
      expect(
        find.text('2 swaps to follow'),
        findsOneWidget,
        reason: textsOf(tester, find.byType(WalletSwapStatus)).toString(),
      );
      await tester.tap(find.byKey(const Key('wallet-swap-status')));
      expect(services.takePendingActivity(), isTrue);
      expect(services.takePendingOpen(), isNull);
    });

    testWidgets('completion stays discoverable until the receipt is seen', (
      tester,
    ) async {
      final handle = await start();
      await pumpSurface(tester, const WalletSwapStatus(), services: services);
      services.presentation.markSeen(handle.latest);
      final done = snapshotOf(id: handle.id, outcome: completed());
      handle.push(done);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('wallet-swap-status')), findsOneWidget);
      expect(
        find.text('Received'),
        findsOneWidget,
        reason: textsOf(tester, find.byType(WalletSwapStatus)).toString(),
      );
      services.presentation.markSeen(done);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('wallet-swap-status')), findsNothing);
    });

    testWidgets('receiving needs source transfer evidence on every surface', (
      tester,
    ) async {
      final handle = await start();
      handle.push(
        snapshotOf(
          id: handle.id,
          stage: SwapProgressStage.awaitingDelivery,
          fundsMovement: SwapFundsMovement.uncertain,
        ),
      );
      await pumpSurface(tester, const WalletSwapStatus(), services: services);
      expect(find.text('Checking transfer'), findsOneWidget);
      await pumpSurface(
        tester,
        SwapExecutionView(id: handle.id, context: SwapExecutionContext.flow),
        services: services,
        swap: swap,
        shell: shell,
      );
      expect(find.text('Checking transfer'), findsOneWidget);
      expect(find.byType(SwapTimelineView), findsNothing);
      await expandSurfaceDetails(tester);
      expect(find.byType(SwapTimelineView), findsNothing);
    });

    testWidgets('progress starts compact and leaves the execution running', (
      tester,
    ) async {
      final handle = await start();
      await pumpSurface(
        tester,
        SwapExecutionView(id: handle.id, context: SwapExecutionContext.flow),
        services: services,
        swap: swap,
        shell: shell,
      );
      expect(find.byType(SwapTimelineView), findsNothing);
      await tester.tap(find.byKey(const Key('swap-back-to-wallet')));
      expect(routingState.selectedMenu, MainMenuValue.wallet);
      expect(registry.activeCount, 1);
      expect(handle.cancelCalls, 0);
    });

    testWidgets(
      'receipt remains exact during fresh balance read and opens received asset',
      (tester) async {
        final balance = Completer<bool>();
        var reads = 0;
        services.refreshBalances = (_) {
          reads++;
          return balance.future;
        };
        final handle = await start();
        await pumpSurface(
          tester,
          SwapExecutionView(id: handle.id, context: SwapExecutionContext.flow),
          services: services,
          swap: swap,
          shell: shell,
        );
        final done = snapshotOf(
          id: handle.id,
          outcome: completed(amount: '3001'),
        );
        handle.push(done);
        await tester.pumpAndSettle();
        expect(find.text('You received 3,001 USDC'), findsOneWidget);
        expect(find.text('Updating balance'), findsOneWidget);
        expect(reads, 1);
        handle.push(done);
        await tester.pumpAndSettle();
        expect(reads, 1);
        balance.complete(true);
        await tester.pumpAndSettle();
        expect(find.text('Updating balance'), findsNothing);
        await tester.tap(find.byKey(const Key('swap-view-asset')));
        expect(routingState.selectedMenu, MainMenuValue.wallet);
        expect(routingState.walletState.selectedCoin, usdc.id);
      },
    );

    test('old balance refresh cannot complete a new wallet session', () async {
      final balance = Completer<bool>();
      services.refreshBalances = (_) => balance.future;
      final done = snapshotOf(outcome: completed());
      final work = services.presentation.refreshReceipt(done);
      expect(
        services.presentation.balanceStatus(done.id),
        SwapReceiptBalanceStatus.updating,
      );
      final identity = services.presentation.sessionIdentity;
      services.presentation.reset();
      balance.complete(true);
      await work;
      expect(services.presentation.balanceStatus(done.id), isNull);
      expect(services.presentation.sessionIdentity, isNot(identity));
    });

    test('effects are claimed independently per swap and once per event', () {
      final first = snapshotOf(outcome: completed());
      final second = snapshotOf(id: 'swap-2', outcome: completed());
      expect(services.presentation.claimMoment(first), isTrue);
      expect(services.presentation.claimMoment(first), isFalse);
      expect(services.presentation.claimMoment(second), isTrue);
      expect(services.presentation.claimMoment(second), isFalse);
    });

    test(
      'a draft stays in its session and stale disposal cannot restore it',
      () {
        final drafts = SwapSessionDraft();
        final session = drafts.session;
        const draft = (
          pay: 'ETH',
          receive: 'BTC',
          input: '25.50',
          fiat: true,
          slippage: 0.5,
        );
        drafts.remember(session, draft);
        expect(drafts.read(session), draft);
        drafts.reset();
        final next = drafts.session;
        drafts.remember(session, draft);
        expect(drafts.read(session), isNull);
        expect(drafts.read(next), isNull);
        drafts.remember(next, draft);
        drafts.remember(next, null);
        expect(drafts.read(next), isNull);
      },
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/views/swap/notices/swap_notices.dart';

import 'swap_accessibility_checks.dart';
import 'swap_surface_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Swaps finish while the user is elsewhere: the app says so wherever they
/// are, with a way back to the swap, and marks the Swap menu entry.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('swap notices', () {
    late FakeExecutor routed;
    late SwapExecutionRegistry registry;
    late SurfaceServices services;

    setUpAll(loadSurfaceCopy);

    setUp(() {
      routed = FakeExecutor(SwapLiquiditySource.routed);
      registry = SwapExecutionRegistry(
        executors: [routed],
        inFlight: () async => const [],
      );
      services = SurfaceServices(registry);
      useFreshRoutingState();
    });

    tearDown(() async {
      await registry.dispose();
      await services.dispose();
      resetSurfaceCopy();
    });

    Future<void> show(
      WidgetTester tester, {
      bool withServices = true,
      List<SurfaceWrap> wrap = const [],
    }) => pumpSurface(
      tester,
      const SwapNoticeListener(child: Text('the wallet')),
      services: withServices ? services : null,
      wrap: wrap,
    );

    Future<FakeHandle> start() async {
      await registry.start(quoteOf());
      return routed.lastStarted!;
    }

    Future<void> finish(
      WidgetTester tester,
      FakeHandle handle,
      SwapExecutionSnapshot end,
    ) async {
      handle.push(end);
      await tester.pumpAndSettle();
    }

    SwapExecutionOutcome received({String? amount, AssetId? asset}) =>
        SwapExecutionOutcome(
          kind: SwapOutcomeKind.completed,
          receivedAmount: amount == null ? null : d(amount),
          receivedAsset: asset,
        );

    testWidgets('says what arrived, and View opens the swap', (tester) async {
      await show(tester);
      final handle = await start();

      await finish(
        tester,
        handle,
        snapshotOf(
          id: 'routed-1',
          outcome: completed(amount: '3001.999'),
        ),
      );

      expect(
        find.text('Swap complete: you received 3,001.99 USDC'),
        findsOneWidget,
      );
      expect(find.text('the wallet'), findsOneWidget);
      await expectSwapAccessible(tester);

      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();

      expect(services.takePendingOpen(), (
        id: 'routed-1',
        source: SwapLiquiditySource.routed,
      ));
      expect(routingState.selectedMenu, MainMenuValue.dex);
    });

    final deliveries = <String, (SwapExecutionSnapshot, String)>{
      'without an amount, names the token': (
        snapshotOf(
          id: 'routed-1',
          outcome: received(asset: weth),
        ),
        'Swap complete: you received WETH',
      ),
      'without the delivered token, names the one asked for': (
        snapshotOf(
          id: 'routed-1',
          outcome: received(amount: '5'),
        ),
        'Swap complete: you received 5 USDC',
      ),
      'for a token the wallet does not list, uses its ticker': (
        reshaped(snapshotOf(id: 'routed-1', outcome: received()), noTo: true),
        'Swap complete: you received USDC-ERC20',
      ),
    };

    for (final MapEntry(key: name, value: (end, message))
        in deliveries.entries) {
      testWidgets('a completion $name', (tester) async {
        await show(tester);
        await finish(tester, await start(), end);

        expect(find.text(message), findsOneWidget);
      });
    }

    testWidgets('says when a finished swap needs attention', (tester) async {
      await show(tester);
      await finish(
        tester,
        await start(),
        snapshotOf(
          id: 'routed-1',
          outcome: failed(SwapFailureReason.routeFailed),
        ),
      );

      expect(find.text('A swap needs your attention'), findsOneWidget);
      expect(find.text('View'), findsOneWidget);
    });

    testWidgets('says a refund came back, without asking for attention', (
      tester,
    ) async {
      await show(tester);
      await finish(
        tester,
        await start(),
        snapshotOf(
          id: 'routed-1',
          outcome: const SwapExecutionOutcome(kind: SwapOutcomeKind.refunded),
        ),
      );

      expect(
        find.text('Swap refunded: your ETH was returned on Ethereum.'),
        findsOneWidget,
      );
      expect(find.text('A swap needs your attention'), findsNothing);
      expect(registry.unacknowledgedAttentionCount, 0);
    });

    testWidgets('says when a running swap needs the user to act', (
      tester,
    ) async {
      await show(tester);
      await finish(
        tester,
        await start(),
        snapshotOf(id: 'routed-1', stage: SwapProgressStage.actionRequired),
      );

      expect(find.text('A swap needs action to continue'), findsOneWidget);
    });

    testWidgets('stays quiet about a swap already on screen', (tester) async {
      await show(tester);
      services.viewing.add('routed-1');

      await finish(
        tester,
        await start(),
        snapshotOf(id: 'routed-1', outcome: completed()),
      );

      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('stays quiet where nothing can show a notice', (tester) async {
      await tester.pumpWidget(
        RepositoryProvider<SwapServices>.value(
          value: services,
          child: const SwapNoticeListener(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text('the wallet'),
            ),
          ),
        ),
      );

      await finish(
        tester,
        await start(),
        snapshotOf(id: 'routed-1', outcome: completed()),
      );

      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('the wallet'), findsOneWidget);
    });

    testWidgets('without swap services, only shows the app', (tester) async {
      await show(tester, withServices: false);

      await finish(
        tester,
        await start(),
        snapshotOf(id: 'routed-1', outcome: completed()),
      );

      expect(find.text('the wallet'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    group('the Swap menu mark', () {
      Widget mark() => SwapAttentionBuilder(
        builder: (context, attention) => Text('attention: $attention'),
      );

      testWidgets('is off without swap services', (tester) async {
        await pumpSurface(tester, mark());

        expect(find.text('attention: false'), findsOneWidget);
      });

      testWidgets('shows while a finished swap waits to be seen', (
        tester,
      ) async {
        await pumpSurface(tester, mark(), services: services);
        expect(find.text('attention: false'), findsOneWidget);

        await finish(
          tester,
          await start(),
          snapshotOf(
            id: 'routed-1',
            outcome: failed(SwapFailureReason.routeFailed),
          ),
        );
        expect(find.text('attention: true'), findsOneWidget);

        registry.acknowledge('routed-1');
        await tester.pumpAndSettle();
        expect(find.text('attention: false'), findsOneWidget);
      });
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/common/swap_links.dart';
import 'package:web_dex/views/swap/execution/swap_evidence_sheet.dart';
import 'package:web_dex/views/swap/execution/swap_execution_view.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

import 'swap_surface_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// A swap screen opens only https pages and email, wherever the link came
/// from.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const refused = [
    'javascript:alert(1)',
    'http://route.example/status/1',
    'intent://route.example/status/1#Intent;scheme=x;end',
    'file:///etc/hosts',
    'data:text/html,<p>route</p>',
    'https:///status/1',
    'route.example/status/1',
  ];

  group('links from a swap screen', () {
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
      shell = SwapShellController(initial: SwapDestination.activity);
      useFreshRoutingState();
    });

    tearDown(() async {
      await swap.close();
      await registry.dispose();
      await services.dispose();
      shell.dispose();
      resetSurfaceCopy();
    });

    SwapEvidence routeAt(String url) => SwapEvidence(
      executionId: 'swap-1',
      sourceTxHash: '0xsource',
      providerExplorerUrl: url,
    );

    Future<void> open(WidgetTester tester, String url) async {
      await pumpSurface(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => openSwapLink(context, url),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('opens an https page and an email', (tester) async {
      final launcher = recordUrlLaunches();

      await open(tester, 'https://route.example/status/1');
      await open(tester, 'mailto:info@gleec.com');

      expect(launcher.launched, [
        'https://route.example/status/1',
        'mailto:info@gleec.com',
      ]);
      expect(find.text("Couldn't open the link"), findsNothing);
    });

    for (final url in refused) {
      testWidgets('never launches $url, and offers it to copy', (tester) async {
        final launcher = recordUrlLaunches();

        await open(tester, url);

        expect(launcher.launched, isEmpty);
        expect(find.text("Couldn't open the link"), findsOneWidget);
        expect(find.text(url), findsOneWidget);
      });

      testWidgets('a swap waiting on the user offers no route page at $url', (
        tester,
      ) async {
        final snapshot = reshaped(
          snapshotOf(stage: SwapProgressStage.actionRequired),
          evidence: routeAt(url),
        );
        routed.resumable[snapshot.id] = FakeHandle(snapshot);
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

        expect(find.text('Open route page'), findsNothing);
      });

      testWidgets('the evidence offers no route status page at $url', (
        tester,
      ) async {
        await pumpSurface(
          tester,
          SwapEvidenceSheet(
            snapshot: reshaped(snapshotOf(), evidence: routeAt(url)),
            services: services,
          ),
          services: services,
        );

        expect(find.text('ROUTE STATUS'), findsNothing);
        expect(find.text('Open route status page'), findsNothing);
        expect(find.text('SOURCE TRANSACTION'), findsOneWidget);
      });
    }
  });
}

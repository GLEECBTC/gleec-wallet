import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/common/swap_timeline.dart';
import 'package:web_dex/views/swap/execution/swap_execution_view.dart';
import 'package:web_dex/views/swap/execution/swap_timeline_view.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

import 'swap_accessibility_checks.dart';
import 'swap_common_ui_fakes.dart';
import 'swap_surface_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the link under each step of a swap's timeline: to the step's own
/// transaction on its network's explorer, or to the route's status page.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('step links', () {
    useEnglishCopy();

    final networks = SwapNetworks([eth, usdc, btc, gleec]);
    final asked = <String, AssetId?>{};
    setUp(asked.clear);

    Uri? explorer(AssetId? asset, String hash) {
      asked[hash] = asset;
      return Uri.parse('https://explorer.example/tx/$hash');
    }

    const prepare = SwapRouteStage(kind: SwapRouteStageKind.prepare);
    final reset = SwapRouteStage(
      kind: SwapRouteStageKind.resetApproval,
      asset: usdc,
    );
    final approve = SwapRouteStage(
      kind: SwapRouteStageKind.approve,
      asset: usdc,
    );
    final send = SwapRouteStage(kind: SwapRouteStageKind.send, asset: usdc);
    final bridge = SwapRouteStage(
      kind: SwapRouteStageKind.bridge,
      network: 'Base',
      asset: eth,
    );
    final convert = SwapRouteStage(
      kind: SwapRouteStageKind.convert,
      asset: eth,
    );
    final receive = SwapRouteStage(
      kind: SwapRouteStageKind.receive,
      asset: eth,
    );
    SwapApprovalRequirement approval({required bool resets}) =>
        SwapApprovalRequirement(
          asset: usdc,
          exactAmount: d('1'),
          resetsFirst: resets,
        );
    const routePage = 'https://route.example/status/1';
    final arrived = SwapExecutionOutcome(
      kind: SwapOutcomeKind.completed,
      receivedAmount: d('0.3'),
      receivedAsset: eth,
    );

    List<String?> links(
      SwapExecutionSnapshot snapshot, {
      bool withExplorer = true,
    }) => [
      for (final step in SwapTimeline.of(
        snapshot,
        networks,
        explorer: withExplorer ? explorer : null,
      ))
        switch (step.link) {
          null => null,
          final link => '${link.route ? 'route' : 'tx'} ${link.url}',
        },
    ];
    String tx(String hash) => 'tx https://explorer.example/tx/$hash';

    SwapExecutionSnapshot routed({
      SwapProgressStage? stage = SwapProgressStage.awaitingDelivery,
      SwapExecutionOutcome? outcome,
      List<SwapRouteStage>? stages,
      bool resets = true,
      List<String> approvals = const ['0xreset', '0xapprove'],
      String? route = routePage,
    }) => snap(
      from: usdc,
      to: eth,
      routeKind: SwapRouteKind.crossChain,
      stage: stage,
      outcome: outcome,
      stages: stages ?? [prepare, reset, approve, send, bridge, receive],
      approval: approval(resets: resets),
      evidence: SwapEvidence(
        executionId: 'swap-1',
        approvalTxHashes: approvals,
        sourceTxHash: '0xsource',
        destinationTxHash: outcome == null ? null : '0xdestination',
        providerExplorerUrl: route,
      ),
    );

    test('links each step to its transaction on its network', () {
      expect(links(routed(outcome: arrived)), [
        null,
        tx('0xreset'),
        tx('0xapprove'),
        tx('0xsource'),
        'route $routePage',
        tx('0xdestination'),
      ]);
      expect(asked, {
        '0xreset': usdc,
        '0xapprove': usdc,
        '0xsource': usdc,
        '0xdestination': eth,
      });
    });

    test('gives a reset the first approval and the approval the latest', () {
      expect(links(routed(approvals: ['0xreset'])).sublist(1, 3), [
        tx('0xreset'),
        null,
      ]);
      expect(
        links(
          routed(
            resets: false,
            stages: [prepare, approve, send, bridge, receive],
            approvals: ['0xfirst', '0xreplaced'],
          ),
        )[1],
        tx('0xreplaced'),
      );
    });

    test('finds the delivery on the asset the swap paid out', () {
      links(
        routed(
          outcome: SwapExecutionOutcome(
            kind: SwapOutcomeKind.partialOtherToken,
            receivedAmount: d('1'),
            receivedAsset: weth,
          ),
        ),
      );
      expect(asked['0xdestination'], weth);
    });

    test('links nothing a step has not got to yet', () {
      final preparing = snap(stage: SwapProgressStage.preparing);
      expect(links(preparing), [null, null, null]);
      expect(asked, isEmpty);
    });

    test('keeps only the route page where no explorer is known', () {
      final unknown = [null, null, null, null, 'route $routePage', null];
      expect(links(routed(outcome: arrived), withExplorer: false), unknown);
      expect(
        [
          for (final step in SwapTimeline.of(
            routed(outcome: arrived),
            networks,
            explorer: (asset, hash) => null,
          ))
            step.link?.route,
        ],
        [null, null, null, null, true, null],
      );
    });

    test('offers the route page on its first leg only', () {
      expect(
        links(
          routed(
            stages: [prepare, send, convert, bridge, convert, receive],
            approvals: const [],
          ),
        ),
        [null, tx('0xsource'), 'route $routePage', null, null, null],
      );
    });

    test('leaves the route page to the button below while the route waits '
        'on the user', () {
      expect(links(routed(stage: SwapProgressStage.actionRequired))[4], isNull);
    });

    test('skips a route address that is not a secure web page', () {
      for (final address in [
        'route-42',
        'http://route.example/status/1',
        'javascript:alert(1)',
      ]) {
        expect(links(routed(route: address))[4], isNull, reason: address);
      }
    });

    test("links a peer-to-peer swap's payments, not the exchange", () {
      final atomic = snap(
        source: SwapLiquiditySource.atomic,
        stages: const [],
        outcome: completed(),
        evidence: const SwapEvidence(
          executionId: 'swap-1',
          sourceTxHash: '0xpaid',
          destinationTxHash: '0xspent',
        ),
      );
      expect(links(atomic), [null, tx('0xpaid'), null, tx('0xspent')]);
      expect(asked, {'0xpaid': eth, '0xspent': usdc});
    });
  });

  group('a step link on screen', () {
    useSwapUi();

    final sent = Uri.parse('https://etherscan.io/tx/0x1');

    List<SwapTimelineStep> steps({SwapTimelineLink? link}) => [
      SwapTimelineStep(
        title: 'Send ETH',
        detail: 'Sent on Ethereum',
        status: SwapStepStatus.done,
        link: link,
      ),
      const SwapTimelineStep(
        title: 'Receive USDC',
        detail: 'On Ethereum',
        status: SwapStepStatus.current,
      ),
    ];

    Future<void> show(
      WidgetTester tester, {
      SwapTimelineLink? link,
      bool animate = false,
      bool reduceMotion = false,
      bool settle = true,
    }) => pumpSwapUi(
      tester,
      SwapTimelineView(
        steps: steps(link: link),
        animate: animate,
      ),
      media: (
        textScale: 1,
        boldText: false,
        reduceMotion: reduceMotion,
        announces: false,
      ),
      settle: settle,
    );

    testWidgets("opens the step's transaction", (tester) async {
      final launcher = recordUrlLaunches();
      await show(tester, link: SwapTimelineLink.transaction(sent));

      await tester.tap(find.text('View on Explorer'));
      await tester.pumpAndSettle();

      expect(launcher.launched, [sent.toString()]);
    });

    testWidgets("opens the route's status page", (tester) async {
      final launcher = recordUrlLaunches();
      await show(
        tester,
        link: SwapTimelineLink.route(Uri.parse('https://scan.li.fi/tx/0x1')),
      );

      await tester.tap(find.text('Open route status page'));
      await tester.pumpAndSettle();

      expect(launcher.launched, ['https://scan.li.fi/tx/0x1']);
    });

    testWidgets('names its step to screen readers, which can press it', (
      tester,
    ) async {
      final launcher = recordUrlLaunches();
      await show(tester, link: SwapTimelineLink.transaction(sent));

      final label = tester.getSemantics(find.byType(SwapTimelineView)).label;
      expect(label, contains('Completed: Send ETH. Sent on Ethereum'));
      expect(label, isNot(contains('View on Explorer')));
      await expectSwapAccessible(tester);

      tester.semantics.tap(
        find.semantics.byLabel('View on Explorer: Send ETH'),
      );
      await tester.pumpAndSettle();
      expect(launcher.launched, [sent.toString()]);
    });

    testWidgets('eases in a link that arrives live, whole from the first '
        'frame', (tester) async {
      final launcher = recordUrlLaunches();
      await show(tester, animate: true);
      await show(
        tester,
        link: SwapTimelineLink.transaction(sent),
        animate: true,
        settle: false,
      );
      expect(tester.hasRunningAnimations, isTrue);

      await tester.tap(find.text('View on Explorer'));
      await tester.pumpAndSettle();
      expect(launcher.launched, [sent.toString()]);
    });

    testWidgets('shows a link at once otherwise', (tester) async {
      await show(tester);
      await show(
        tester,
        link: SwapTimelineLink.transaction(sent),
        settle: false,
      );
      expect(tester.hasRunningAnimations, isFalse);

      await show(tester, animate: true, reduceMotion: true);
      await show(
        tester,
        link: SwapTimelineLink.transaction(sent),
        animate: true,
        reduceMotion: true,
        settle: false,
      );
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('on the progress page', () {
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

    testWidgets('links the sent transaction from its step', (tester) async {
      final launcher = recordUrlLaunches();
      services.explorer['0xsource'] = Uri.parse(
        'https://etherscan.io/tx/0xsource',
      );
      final running = snapshotOf(sourceTxHash: '0xsource');
      routed.resumable[running.id] = FakeHandle(running);
      await pumpSurface(
        tester,
        SwapExecutionView(
          id: running.id,
          context: SwapExecutionContext.activity,
        ),
        services: services,
        swap: swap,
        shell: shell,
      );

      await tester.tap(find.text('View on Explorer'));
      await tester.pumpAndSettle();

      expect(launcher.launched, ['https://etherscan.io/tx/0xsource']);
      expect(services.explorerAsked, {'0xsource': eth});
    });
  });
}

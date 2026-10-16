import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/common/swap_links.dart';
import 'package:web_dex/views/swap/execution/swap_evidence_sheet.dart';
import 'package:web_dex/views/swap/execution/swap_execution_view.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

import 'swap_accessibility_checks.dart';
import 'swap_surface_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// A link on a swap screen the device cannot open, offered to copy instead.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a link the device cannot open', () {
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

    Future<void> showSwap(
      WidgetTester tester,
      SwapExecutionSnapshot snapshot,
    ) async {
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
    }

    Future<void> showEvidence(WidgetTester tester) => pumpSurface(
      tester,
      SwapEvidenceSheet(
        snapshot: reshaped(
          snapshotOf(),
          evidence: const SwapEvidence(
            executionId: 'swap-1',
            sourceTxHash: '0xsource',
            providerExplorerUrl: 'https://route.example/status/1',
          ),
        ),
        services: services,
      ),
      services: services,
    );

    Future<void> tapText(WidgetTester tester, String text) async {
      await tester.ensureVisible(find.text(text).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(text).first);
      await tester.pumpAndSettle();
    }

    Finder inDialog(String text) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(text),
    );

    Future<void> tapInDialog(WidgetTester tester, String text) async {
      await tester.tap(inDialog(text));
      await tester.pumpAndSettle();
    }

    void expectOffered(String url) {
      expect(find.text("Couldn't open the link"), findsOneWidget);
      expect(
        find.text('Copy it and open it in your browser instead.'),
        findsOneWidget,
      );
      expect(find.text(url), findsOneWidget);
    }

    testWidgets('from a finished swap, offers the explorer link to copy', (
      tester,
    ) async {
      _refuseUrlLaunches();
      final copied = recordClipboard();
      services.explorer['0xsource'] = Uri.parse('https://etherscan.io/tx/0x1');
      await showSwap(
        tester,
        snapshotOf(
          fundsMovement: SwapFundsMovement.feesOnly,
          sourceTxHash: '0xsource',
          outcome: failed(SwapFailureReason.reverted),
        ),
      );

      await tapText(tester, 'View on Explorer');

      expectOffered('https://etherscan.io/tx/0x1');
      await expectSwapAccessible(tester);
      await tapInDialog(tester, 'Copy');
      expect(copied, ['https://etherscan.io/tx/0x1']);
      expect(inDialog('Link copied'), findsOneWidget);
      await tapText(tester, 'Close');
      expect(find.text("Couldn't open the link"), findsNothing);
    });

    testWidgets('from a swap waiting on the user, offers the route page', (
      tester,
    ) async {
      _refuseUrlLaunches();
      await showSwap(
        tester,
        reshaped(
          snapshotOf(stage: SwapProgressStage.actionRequired),
          evidence: const SwapEvidence(
            executionId: 'swap-1',
            providerExplorerUrl: 'https://route.example/status/1',
          ),
        ),
      );

      await tapText(tester, 'Open route page');

      expectOffered('https://route.example/status/1');
    });

    testWidgets('from the evidence, offers a transaction on its explorer', (
      tester,
    ) async {
      _refuseUrlLaunches();
      services.explorer['0xsource'] = Uri.parse('https://etherscan.io/tx/0x1');
      await showEvidence(tester);

      await tapText(tester, 'View on Explorer');

      expectOffered('https://etherscan.io/tx/0x1');
    });

    testWidgets('from the evidence, offers the route status page', (
      tester,
    ) async {
      _refuseUrlLaunches();
      await showEvidence(tester);

      await tapText(tester, 'Open route status page');

      expectOffered('https://route.example/status/1');
    });

    testWidgets('without an email app, support still gets the details, and '
        'the address to send them to', (tester) async {
      _refuseUrlLaunches();
      final copied = recordClipboard();
      await showEvidence(tester);

      await tapText(tester, 'Contact Gleec support');

      expect(copied.single, startsWith('Swap ID: swap-1\n'));
      expect(find.text("Couldn't open your email app"), findsOneWidget);
      expect(
        find.text('Email this address from any mail app instead.'),
        findsOneWidget,
      );
      expect(find.text('info@gleec.com'), findsOneWidget);
      expect(find.textContaining('mailto:'), findsNothing);
      await expectSwapAccessible(tester);

      await tapInDialog(tester, 'Copy');
      expect(copied.last, 'info@gleec.com');
      expect(inDialog('Email address copied'), findsOneWidget);
      await tapInDialog(tester, 'Copy details for support');
      expect(copied.last, copied.first);
      expect(inDialog('Swap details copied'), findsOneWidget);
    });

    testWidgets('a launch the platform fails says so the same way', (
      tester,
    ) async {
      _refuseUrlLaunches(throws: true);
      await showEvidence(tester);

      await tapText(tester, 'Open route status page');

      expectOffered('https://route.example/status/1');
    });

    testWidgets('an address it cannot decode falls back to the link', (
      tester,
    ) async {
      await pumpSurface(tester, const SwapLinkFailedDialog(url: 'mailto:%E9'));
      expectOffered('mailto:%E9');
    });

    testWidgets('names an encoded address, and falls back to the link for '
        'one without', (tester) async {
      await pumpSurface(
        tester,
        const SwapLinkFailedDialog(url: 'mailto:info%40gleec.com'),
      );
      expect(find.text('info@gleec.com'), findsOneWidget);

      await pumpSurface(
        tester,
        const SwapLinkFailedDialog(url: 'mailto:?to=info@gleec.com'),
      );
      expectOffered('mailto:?to=info@gleec.com');
    });

    testWidgets('a link opens even when asking first would say no, as '
        'Android does for mailto:', (tester) async {
      final launcher = _useUrlLauncher(_DenyingUrlLauncher());
      recordClipboard();
      await showEvidence(tester);

      await tapText(tester, 'Contact Gleec support');

      expect(launcher.launched, [
        'mailto:info@gleec.com?subject=GLEEC%20Wallet%20Support',
      ]);
      expect(find.text("Couldn't open your email app"), findsNothing);
    });

    testWidgets('a link that opens asks nothing more', (tester) async {
      final launcher = recordUrlLaunches();
      await showEvidence(tester);

      await tapText(tester, 'Open route status page');

      expect(launcher.launched, ['https://route.example/status/1']);
      expect(find.text("Couldn't open the link"), findsNothing);
    });
  });
}

/// Says no to `canLaunch`, as Android 11+ does for a scheme the manifest
/// doesn't declare, yet opens links all the same.
class _DenyingUrlLauncher extends RecordingUrlLauncher {
  @override
  Future<bool> canLaunch(String url) async => false;
}

/// A device that fails to open links: the launch reports failure, or with
/// [throws], throws as Android does with nothing to handle the link.
class _RefusingUrlLauncher extends _DenyingUrlLauncher {
  _RefusingUrlLauncher({required this.throws});

  final bool throws;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async =>
      throws ? throw PlatformException(code: 'ACTIVITY_NOT_FOUND') : false;
}

T _useUrlLauncher<T extends UrlLauncherPlatform>(T launcher) {
  final previous = UrlLauncherPlatform.instance;
  UrlLauncherPlatform.instance = launcher;
  addTearDown(() => UrlLauncherPlatform.instance = previous);
  return launcher;
}

void _refuseUrlLaunches({bool throws = false}) =>
    _useUrlLauncher(_RefusingUrlLauncher(throws: throws));

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/views/swap/common/swap_format.dart';
import 'package:web_dex/views/swap/execution/swap_evidence_sheet.dart';

import 'swap_accessibility_checks.dart';
import 'swap_surface_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// The proof a swap left behind: identifiers, transactions and links, ready
/// to copy for support.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('swap evidence', () {
    late SwapExecutionRegistry registry;
    late SurfaceServices services;

    setUpAll(loadSurfaceCopy);

    setUp(() {
      registry = SwapExecutionRegistry(
        executors: const [],
        inFlight: () async => const [],
      );
      services = SurfaceServices(registry);
    });

    tearDown(() async {
      await registry.dispose();
      await services.dispose();
      resetSurfaceCopy();
    });

    final started = DateTime.utc(2026, 9, 24, 12);
    final updated = DateTime.utc(2026, 9, 24, 12, 5);

    SwapExecutionSnapshot proven({
      SwapExecutionOutcome? outcome,
      List<SwapGasSpent> gas = const [],
    }) => reshaped(
      snapshotOf(outcome: outcome),
      createdAt: started,
      updatedAt: updated,
      evidence: SwapEvidence(
        executionId: 'swap-1',
        approvalTxHashes: const ['0xapprove1', '0xapprove2'],
        sourceTxHash: '0xsource',
        destinationTxHash: '0xdestination',
        providerExplorerUrl: 'https://route.example/status/1',
        providerRequestId: 'req-42',
        rawState: 'PENDING',
        gasSpent: gas,
      ),
    );

    Future<void> show(WidgetTester tester, SwapExecutionSnapshot snapshot) =>
        pumpSurface(
          tester,
          SwapEvidenceSheet(snapshot: snapshot, services: services),
          services: services,
        );

    Future<void> tapText(WidgetTester tester, String text) async {
      await tester.ensureVisible(find.text(text).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(text).first);
      await tester.pumpAndSettle();
    }

    testWidgets('lists what identifies the swap', (tester) async {
      await show(tester, reshaped(snapshotOf(), createdAt: started));

      expect(find.text('Swap evidence'), findsOneWidget);
      expect(
        find.text(
          'Details saved for this swap. Support can use them to investigate.',
        ),
        findsOneWidget,
      );
      for (final label in ['SWAP ID', 'ROUTE', 'STARTED', 'FROM', 'TO']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('swap-1'), findsOneWidget);
      expect(find.text('1 ETH → 3,000 USDC'), findsOneWidget);
      expect(find.text(SwapFormat.time(started)), findsOneWidget);
      expect(
        find.text('0x5520D7F51C8e3108FA2d9C6220bF4Aa8F9c17B91'),
        findsNWidgets(2),
      );
      expect(find.text('LAST UPDATE'), findsNothing);
      await expectSwapAccessible(tester);
    });

    testWidgets('says plainly when nothing was signed or broadcast', (
      tester,
    ) async {
      await show(
        tester,
        reshaped(snapshotOf(), noFromAddress: true, noToAddress: true),
      );

      expect(find.text('SOURCE TRANSACTION'), findsOneWidget);
      expect(
        find.text('No transaction was signed or broadcast.'),
        findsOneWidget,
      );
      for (final label in ['STARTED', 'LAST UPDATE', 'FROM', 'TO']) {
        expect(find.text(label), findsNothing, reason: label);
      }
      expect(find.text('View on Explorer'), findsNothing);
    });

    testWidgets('lists every transaction, linked where the network has one', (
      tester,
    ) async {
      final launcher = recordUrlLaunches();
      services.explorer = {
        '0xapprove1': Uri.parse('https://etherscan.io/tx/0xapprove1'),
        '0xsource': Uri.parse('https://etherscan.io/tx/0xsource'),
        '0xdestination': Uri.parse('https://etherscan.io/tx/0xdestination'),
      };
      await show(
        tester,
        proven(
          outcome: SwapExecutionOutcome(
            kind: SwapOutcomeKind.partialOtherToken,
            receivedAmount: d('1'),
            receivedAsset: weth,
          ),
        ),
      );

      expect(find.text('APPROVAL TRANSACTIONS'), findsNWidgets(2));
      expect(find.text('SOURCE TRANSACTION'), findsOneWidget);
      expect(find.text('DESTINATION TRANSACTION'), findsOneWidget);
      expect(
        find.text('No transaction was signed or broadcast.'),
        findsNothing,
      );
      expect(find.text('View on Explorer'), findsNWidgets(3));
      expect(services.explorerAsked, {
        '0xapprove1': eth,
        '0xapprove2': eth,
        '0xsource': eth,
        '0xdestination': weth,
      });

      await tapText(tester, 'View on Explorer');

      expect(launcher.launched, ['https://etherscan.io/tx/0xapprove1']);
    });

    testWidgets('finds the delivery on the asset the swap was for', (
      tester,
    ) async {
      await show(tester, proven());

      expect(services.explorerAsked['0xdestination'], usdc);
    });

    testWidgets('links the route status page and the support reference', (
      tester,
    ) async {
      final launcher = recordUrlLaunches();
      await show(tester, proven());

      expect(find.text('ROUTE STATUS'), findsOneWidget);
      expect(find.text('SUPPORT REFERENCE'), findsOneWidget);
      expect(find.text('req-42'), findsOneWidget);
      expect(find.text('LAST UPDATE'), findsOneWidget);
      expect(find.text(SwapFormat.time(updated)), findsOneWidget);

      await tapText(tester, 'Open route status page');

      expect(launcher.launched, ['https://route.example/status/1']);
    });

    testWidgets('shows the network fees paid, rounded up', (tester) async {
      await show(
        tester,
        proven(
          gas: [
            SwapGasSpent(ticker: 'ETH', amount: d('0.0012345678'), asset: eth),
            SwapGasSpent(ticker: 'MATIC', amount: d('0.5')),
          ],
        ),
      );

      expect(find.text('NETWORK FEES PAID'), findsOneWidget);
      expect(find.text('0.001235 ETH'), findsOneWidget);
      expect(find.text('0.5 MATIC'), findsOneWidget);
    });

    testWidgets('leaves out fees nobody reported', (tester) async {
      await show(tester, proven());

      expect(find.text('NETWORK FEES PAID'), findsNothing);
    });

    testWidgets('copies everything support needs in one go', (tester) async {
      final copied = recordClipboard();
      await show(tester, proven());

      await tapText(tester, 'Copy details for support');

      expect(copied, [
        'Swap ID: swap-1\n'
            'Route: 1 ETH → 3,000 USDC\n'
            'Status: Confirming on Ethereum\n'
            'Started: 2026-09-24T12:00:00.000Z\n'
            'Last update: 2026-09-24T12:05:00.000Z\n'
            'Approval transactions: 0xapprove1\n'
            'Approval transactions: 0xapprove2\n'
            'Source transaction: 0xsource\n'
            'Destination transaction: 0xdestination\n'
            'Support reference: req-42\n'
            'state: PENDING',
      ]);
      expect(find.text('Swap details copied'), findsOneWidget);
    });

    testWidgets('contacting support copies the details, then opens contact', (
      tester,
    ) async {
      final copied = recordClipboard();
      final launcher = recordUrlLaunches();
      await show(tester, proven());

      await tapText(tester, 'Contact Gleec support');

      expect(copied.single, startsWith('Swap ID: swap-1\n'));
      expect(launcher.launched, [
        'mailto:info@gleec.com?subject=GLEEC%20Wallet%20Support',
      ]);
      expect(find.text('Swap details copied'), findsOneWidget);
    });

    testWidgets('copies one identifier on its own', (tester) async {
      final copied = recordClipboard();
      await show(tester, proven());

      await tapText(tester, 'Copy');

      expect(copied, ['swap-1']);
      expect(find.text('Swap ID copied'), findsOneWidget);
    });

    testWidgets('opens over the swap and closes again', (tester) async {
      await pumpSurface(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showSwapEvidenceSheet(
              context,
              snapshot: proven(),
              services: services,
            ),
            child: const Text('open'),
          ),
        ),
        services: services,
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Swap evidence'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Swap evidence'), findsNothing);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/execution/swap_execution_view.dart';
import 'package:web_dex/views/swap/execution/swap_timeline_view.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

import 'swap_accessibility_checks.dart';
import 'swap_surface_ui_fakes.dart';
import 'swap_test_fixtures.dart';

typedef _Failure = ({
  SwapExecutionSnapshot snapshot,
  String title,
  String body,
  String funds,
  List<String> actions,
});

/// Every failure reason answers what happened, where the funds are and what
/// can be done now — and never says nothing was sent when funds may have
/// moved.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a failed swap', () {
    late FakeExecutor routed;
    late FakeExecutor atomic;
    late SwapExecutionRegistry registry;
    late SurfaceServices services;
    late RecordingSwapBloc swap;
    late SwapShellController shell;

    setUpAll(loadSurfaceCopy);

    setUp(() {
      routed = FakeExecutor(SwapLiquiditySource.routed);
      atomic = FakeExecutor(SwapLiquiditySource.atomic);
      registry = SwapExecutionRegistry(
        executors: [routed, atomic],
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

    const none = SwapFundsMovement.none;
    const feesOnly = SwapFundsMovement.feesOnly;
    const uncertain = SwapFundsMovement.uncertain;
    const sent = SwapFundsMovement.sent;
    const unchanged = 'Your balance is unchanged.';
    const unverified =
        "Last confirmed location: 1 ETH on Ethereum. The current location isn't "
        'verified yet.';
    const notSure =
        "We can't confirm whether the transaction was sent. Check the explorer "
        'before trying again.';
    const support = 'Contact Gleec support';

    SwapExecutionSnapshot failure(
      SwapFailureReason reason,
      SwapFundsMovement movement, {
      SwapExecutionFailure? detail,
      String? sourceTx,
      SwapLiquiditySource source = SwapLiquiditySource.routed,
    }) => snapshotOf(
      source: source,
      fundsMovement: movement,
      sourceTxHash: sourceTx,
      outcome: detail == null
          ? failed(reason)
          : SwapExecutionOutcome(kind: SwapOutcomeKind.failed, failure: detail),
    );

    final failures = <String, _Failure>{
      'price moved, with a fresh quote': (
        snapshot: failure(
          SwapFailureReason.priceMoved,
          none,
          detail: SwapExecutionFailure(
            reason: SwapFailureReason.priceMoved,
            nextStep: SwapNextStep.requote,
            freshQuote: quoteOf(guaranteed: '2900'),
          ),
        ),
        title: 'Price changed',
        body: 'The price moved below your minimum before anything was sent.',
        funds: unchanged,
        actions: ['Accept updated quote', 'Try again'],
      ),
      'price moved, without a fresh quote': (
        snapshot: failure(SwapFailureReason.priceMoved, none),
        title: 'Price changed',
        body: 'The price moved below your minimum before anything was sent.',
        funds: unchanged,
        actions: ['Try again'],
      ),
      'short of balance': (
        snapshot: failure(
          SwapFailureReason.insufficientBalance,
          none,
          detail: SwapExecutionFailure(
            reason: SwapFailureReason.insufficientBalance,
            nextStep: SwapNextStep.fixAndRetry,
            shortfallAsset: eth,
            shortfallAvailable: d('1.5'),
            shortfallRequired: d('2'),
          ),
        ),
        title: 'Not enough balance',
        body:
            'The swap needed 2 ETH but this address had 1.5 ETH. Nothing was '
            'swapped.',
        funds: unchanged,
        actions: ['Try again'],
      ),
      'short of a coin the wallet does not list': (
        snapshot: failure(
          SwapFailureReason.insufficientBalance,
          none,
          detail: SwapExecutionFailure(
            reason: SwapFailureReason.insufficientBalance,
            nextStep: SwapNextStep.fixAndRetry,
            shortfallTicker: 'GAS',
            shortfallAvailable: d('0.1'),
            shortfallRequired: d('0.25'),
          ),
        ),
        title: 'Not enough balance',
        body:
            'The swap needed 0.25 GAS but this address had 0.1 GAS. Nothing '
            'was swapped.',
        funds: unchanged,
        actions: ['Try again'],
      ),
      'short of balance, amounts unknown': (
        snapshot: failure(SwapFailureReason.insufficientBalance, none),
        title: 'Not enough balance',
        body: unchanged,
        funds: unchanged,
        actions: ['Try again'],
      ),
      'permission failed': (
        snapshot: failure(SwapFailureReason.approvalFailed, feesOnly),
        title: 'Token permission failed',
        body:
            "The approval didn't complete, so nothing was swapped. Its "
            'network fee may be spent.',
        funds: "Your ETH didn't leave. Network fees were spent.",
        actions: ['Try again'],
      ),
      'reverted': (
        snapshot: failure(
          SwapFailureReason.reverted,
          feesOnly,
          sourceTx: '0xs',
        ),
        title: 'Transaction reverted',
        body:
            "The network rejected this transaction. Your ETH didn't leave; the "
            'network fee was spent.',
        funds: "Your ETH didn't leave. Network fees were spent.",
        actions: ['Try again', 'View on Explorer'],
      ),
      'reverted, with no transaction to show': (
        snapshot: failure(SwapFailureReason.reverted, feesOnly),
        title: 'Transaction reverted',
        body:
            "The network rejected this transaction. Your ETH didn't leave; the "
            'network fee was spent.',
        funds: "Your ETH didn't leave. Network fees were spent.",
        actions: ['Try again'],
      ),
      'not confirmed': (
        snapshot: failure(
          SwapFailureReason.notConfirmed,
          uncertain,
          sourceTx: '0xs',
        ),
        title: 'Still waiting for confirmation',
        body:
            "The transaction was sent but hasn't confirmed yet. It may still "
            'confirm — check the explorer before trying again.',
        funds: unverified,
        actions: ['View on Explorer', support],
      ),
      'not confirmed, with no transaction to show': (
        snapshot: failure(SwapFailureReason.notConfirmed, uncertain),
        title: 'Still waiting for confirmation',
        body:
            "The transaction was sent but hasn't confirmed yet. It may still "
            'confirm — check the explorer before trying again.',
        funds: unverified,
        actions: [support],
      ),
      'declined before sending': (
        snapshot: failure(SwapFailureReason.walletRejected, none),
        title: 'Request declined',
        body: 'Nothing was sent for this step.',
        funds: unchanged,
        actions: ['Try again'],
      ),
      'declined, maybe after sending': (
        snapshot: failure(SwapFailureReason.walletRejected, uncertain),
        title: 'Request declined',
        body: notSure,
        funds: unverified,
        actions: [support],
      ),
      'route failed after funds left': (
        snapshot: failure(SwapFailureReason.routeFailed, sent),
        title: 'Gleec support is needed',
        body:
            'Your funds left Ethereum, but the route reported a failure '
            'without a refund. Share the evidence with support.',
        funds: unverified,
        actions: [support],
      ),
      'a stale route stopped by the safety check': (
        snapshot: failure(
          SwapFailureReason.safetyCheck,
          none,
          detail: const SwapExecutionFailure(
            reason: SwapFailureReason.safetyCheck,
            nextStep: SwapNextStep.retry,
            retryable: true,
          ),
        ),
        title: 'Swap blocked by a safety check',
        body: 'Gleec stopped this route before signing. Nothing was sent.',
        funds: unchanged,
        actions: ['Try again'],
      ),
      'a route the safety check blocked for good': (
        snapshot: failure(SwapFailureReason.safetyCheck, none),
        title: 'Swap blocked by a safety check',
        body: 'Gleec stopped this route before signing. Nothing was sent.',
        funds: unchanged,
        actions: [support],
      ),
      'no confirmed price': (
        snapshot: failure(SwapFailureReason.quoteUnavailable, none),
        title: "The price couldn't be confirmed",
        body: 'Nothing was sent. Get a fresh quote to try again.',
        funds: unchanged,
        actions: ['Try again'],
      ),
      'no confirmed price, maybe after sending': (
        snapshot: failure(SwapFailureReason.quoteUnavailable, sent),
        title: "The price couldn't be confirmed",
        body: notSure,
        funds: unverified,
        actions: [support],
      ),
      'a restart before sending': (
        snapshot: failure(SwapFailureReason.restarted, none),
        title: 'Stopped when Gleec restarted',
        body: 'Nothing was swapped. You can start again safely.',
        funds: unchanged,
        actions: ['Try again'],
      ),
      'a restart after sending': (
        snapshot: failure(SwapFailureReason.restarted, sent),
        title: 'Stopped when Gleec restarted',
        body: notSure,
        funds: unverified,
        actions: [support],
      ),
      'a peer-to-peer exchange with funds locked': (
        snapshot: failure(
          SwapFailureReason.exchangeFailed,
          sent,
          source: SwapLiquiditySource.atomic,
        ),
        title: "The exchange didn't complete",
        body: 'Open it in Advanced for the full log and recovery options.',
        funds:
            'Locked in the exchange on Ethereum until it completes or '
            'refunds.',
        actions: ['Open in Advanced', support],
      ),
      'a peer-to-peer exchange that never sent': (
        snapshot: failure(
          SwapFailureReason.exchangeFailed,
          none,
          source: SwapLiquiditySource.atomic,
        ),
        title: "The exchange didn't complete",
        body: 'Nothing was sent. You can try again.',
        funds: unchanged,
        actions: ['Try again'],
      ),
      'an engine error before sending': (
        snapshot: failure(SwapFailureReason.internal, none),
        title: 'Something went wrong',
        body: 'Nothing was sent. Try again.',
        funds: unchanged,
        actions: ['Try again'],
      ),
      'an engine error, maybe after sending': (
        snapshot: failure(SwapFailureReason.internal, uncertain),
        title: 'Something went wrong',
        body: notSure,
        funds: unverified,
        actions: [support],
      ),
      'a status this build does not know': (
        snapshot: failure(SwapFailureReason.unknown, uncertain),
        title: "We're reviewing an unfamiliar status",
        body:
            'Gleec will keep tracking. Share the evidence with support if this '
            'persists.',
        funds: unverified,
        actions: [support],
      ),
      'a failure with no reason at all': (
        snapshot: snapshotOf(
          outcome: const SwapExecutionOutcome(kind: SwapOutcomeKind.failed),
        ),
        title: "We're reviewing an unfamiliar status",
        body:
            'Gleec will keep tracking. Share the evidence with support if this '
            'persists.',
        funds: unverified,
        actions: [support],
      ),
    };

    /// Phrases that promise the funds never moved.
    const safeClaims = [
      'nothing was sent',
      'nothing was swapped',
      "didn't leave",
      'balance is unchanged',
      'before anything was sent',
      'start again safely',
    ];

    String answer(WidgetTester tester, String eyebrow) => tester
        .widgetList<SwapQuestion>(find.byType(SwapQuestion))
        .singleWhere((question) => question.eyebrow == eyebrow)
        .body!;

    for (final MapEntry(key: name, value: failure) in failures.entries) {
      testWidgets('$name: "${failure.title}", then ${failure.actions}', (
        tester,
      ) async {
        final snapshot = failure.snapshot;
        final executor = snapshot.source == SwapLiquiditySource.atomic
            ? atomic
            : routed;
        executor.resumable[snapshot.id] = FakeHandle(snapshot);
        await pumpSurface(
          tester,
          SwapExecutionView(
            id: snapshot.id,
            source: snapshot.source,
            context: SwapExecutionContext.activity,
          ),
          services: services,
          swap: swap,
          shell: shell,
        );

        final hero = tester.widget<SwapStatusHero>(find.byType(SwapStatusHero));
        expect((hero.title, hero.body), (failure.title, failure.body));
        expect(answer(tester, 'What happened?'), failure.body);
        expect(answer(tester, 'Where are the funds?'), failure.funds);
        expect(
          tester
              .widgetList<SwapButton>(find.byType(SwapButton))
              .map((button) => button.label),
          failure.actions,
        );

        if (snapshot.fundsMovement == uncertain ||
            snapshot.fundsMovement == sent) {
          final shown = tester
              .widgetList<Text>(find.byType(Text))
              .map((text) => (text.data ?? '').toLowerCase());
          for (final claim in safeClaims) {
            expect(shown.where((text) => text.contains(claim)), isEmpty);
          }
        }
        await expectSwapAccessible(tester);
      });
    }

    testWidgets('a price move compares the old minimum with the new one', (
      tester,
    ) async {
      final snapshot = failures['price moved, with a fresh quote']!.snapshot;
      routed.resumable[snapshot.id] = FakeHandle(snapshot);
      await pumpSurface(
        tester,
        SwapExecutionView(id: snapshot.id, context: SwapExecutionContext.flow),
        services: services,
        swap: swap,
        shell: shell,
      );

      final callout = tester.widget<SwapCallout>(find.byType(SwapCallout));
      expect(callout.message, 'Minimum was 2,985 USDC. Now 2,900 USDC.');
      expect(callout.tone, SwapTone.warning);
    });

    testWidgets('the timeline marks the step that failed', (tester) async {
      final snapshot = failure(SwapFailureReason.routeFailed, sent);
      routed.resumable[snapshot.id] = FakeHandle(snapshot);
      await pumpSurface(
        tester,
        SwapExecutionView(id: snapshot.id, context: SwapExecutionContext.flow),
        services: services,
        swap: swap,
        shell: shell,
      );

      final label = tester.getSemantics(find.byType(SwapTimelineView)).label;
      expect(label, contains('Completed: Sending on Ethereum.'));
      expect(label, contains('Error: Receive USDC.'));
      expect(find.byIcon(Icons.priority_high_rounded), findsOneWidget);
    });

    testWidgets('a permission left behind is part of where the funds are', (
      tester,
    ) async {
      final snapshot = snapshotOf(
        fundsMovement: feesOnly,
        approvalRemains: true,
        outcome: failed(SwapFailureReason.approvalFailed),
      );
      routed.resumable[snapshot.id] = FakeHandle(snapshot);
      await pumpSurface(
        tester,
        SwapExecutionView(id: snapshot.id, context: SwapExecutionContext.flow),
        services: services,
        swap: swap,
        shell: shell,
      );

      expect(
        answer(tester, 'Where are the funds?'),
        "Your ETH didn't leave. Network fees were spent. An exact permission "
        'for 1 ETH remains on-chain.',
      );
      expect(find.byType(SwapCallout), findsNothing);
    });
  });
}

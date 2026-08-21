import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/widgets/swap_progress_view.dart';
import 'package:web_dex/views/swap/widgets/swap_quote_summary.dart';

/// Covers what the swap screens are allowed to say about someone's money.
///
/// These are not cosmetic assertions. Each one corresponds to a way the screen
/// could quietly mislead: overstating what will arrive, presenting an
/// incomplete fee as exact, or calling a refund a success.
void main() {
  final usdt = AssetId(
    id: 'USDT-PLG20',
    name: 'USDT',
    symbol: AssetSymbol(assetConfigId: 'USDT-PLG20'),
    chainId: AssetChainId(chainId: 137),
    derivationPath: null,
    subClass: CoinSubClass.erc20,
  );
  final usdc = AssetId(
    id: 'USDC-ERC20',
    name: 'USDC',
    symbol: AssetSymbol(assetConfigId: 'USDC-ERC20'),
    chainId: AssetChainId(chainId: 1),
    derivationPath: null,
    subClass: CoinSubClass.erc20,
  );

  SwapQuote quoteOf({
    String expected = '100.21',
    String guaranteed = '99.71',
    bool undisclosed = false,
    List<SwapQuoteCost> costs = const [],
  }) => SwapQuote(
    source: SwapLiquiditySource.routed,
    from: usdt,
    to: usdc,
    sellAmount: Decimal.parse('100.5'),
    expectedReceive: Decimal.parse(expected),
    guaranteedReceive: Decimal.parse(guaranteed),
    costs: costs,
    quotedAt: DateTime(2026),
    hasUndisclosedCosts: undisclosed,
    providerLabel: 'Stargate V2',
  );

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );

  group('quote summary', () {
    testWidgets('headlines the guaranteed amount, not the estimate', (
      tester,
    ) async {
      await pump(tester, SwapQuoteSummary(quote: quoteOf()));

      final headline = tester.widget<Text>(
        find.byKey(const Key('swap-guaranteed-receive')),
      );
      // Leading with 100.21 would promise an amount neither source
      // guarantees, and the gap is exactly where complaints come from.
      expect(headline.data, contains('99.71'));
      expect(find.textContaining('You receive at least'), findsOneWidget);
    });

    testWidgets('names the venue so the route is not hidden', (tester) async {
      await pump(tester, SwapQuoteSummary(quote: quoteOf()));

      expect(find.textContaining('Stargate V2'), findsOneWidget);
    });
  });

  group('cost breakdown', () {
    testWidgets('warns when a known cost is missing from the total', (
      tester,
    ) async {
      await pump(tester, SwapCostBreakdown(quote: quoteOf(undisclosed: true)));

      expect(find.byKey(const Key('swap-undisclosed-costs')), findsOneWidget);
    });

    testWidgets('stays quiet when the costs are complete', (tester) async {
      await pump(tester, SwapCostBreakdown(quote: quoteOf()));

      expect(find.byKey(const Key('swap-undisclosed-costs')), findsNothing);
    });

    testWidgets('marks a fee that is already deducted', (tester) async {
      await pump(
        tester,
        SwapCostBreakdown(
          quote: quoteOf(
            costs: [
              SwapQuoteCost(
                label: 'Provider fee',
                amount: Decimal.parse('0.05'),
                tokenLabel: 'USDT-PLG20',
                isDeductedFromReceive: true,
              ),
            ],
          ),
        ),
      );

      // Without this the same fee reads as an extra charge on top of the
      // receive amount the user was just shown.
      expect(find.textContaining('already deducted'), findsOneWidget);
    });
  });

  group('progress', () {
    UnifiedSwapProgress progressOf({
      required SwapPhase phase,
      bool canCancel = false,
      bool isSuccess = false,
      String? headline,
      String? detail,
      bool fundsUntouched = false,
    }) => UnifiedSwapProgress(
      id: 'u',
      source: SwapLiquiditySource.routed,
      phase: phase,
      canCancel: canCancel,
      isSuccess: isSuccess,
      headline: headline,
      detail: detail,
      fundsUntouched: fundsUntouched,
    );

    testWidgets('offers cancel only while it is actually possible', (
      tester,
    ) async {
      await pump(
        tester,
        SwapProgressView(
          progress: progressOf(phase: SwapPhase.preparing, canCancel: true),
          onCancel: () {},
          onDone: () {},
        ),
      );
      expect(find.byKey(const Key('swap-cancel')), findsOneWidget);

      await pump(
        tester,
        SwapProgressView(
          progress: progressOf(phase: SwapPhase.settling),
          onCancel: () {},
          onDone: () {},
        ),
      );
      // Showing a cancel button that KDF will refuse is worse than showing
      // none: it implies the swap can still be stopped.
      expect(find.byKey(const Key('swap-cancel')), findsNothing);
    });

    testWidgets('does not present a refund as a completed swap', (
      tester,
    ) async {
      await pump(
        tester,
        SwapProgressView(
          progress: progressOf(
            phase: SwapPhase.finished,
            headline: 'Swap refunded',
            detail:
                'The swap did not happen. 99.10 USDT-PLG20 was returned to '
                'you.',
          ),
          onCancel: () {},
          onDone: () {},
        ),
      );

      expect(find.text('Swap refunded'), findsOneWidget);
      expect(find.textContaining('did not happen'), findsOneWidget);
      expect(find.textContaining('You received'), findsNothing);
    });

    testWidgets('does not present a partial fill as complete', (tester) async {
      await pump(
        tester,
        SwapProgressView(
          progress: progressOf(
            phase: SwapPhase.finished,
            headline: 'Partly filled',
            detail:
                'You received 40 USDC-ERC20, which is not the full amount you '
                'asked for.',
          ),
          onCancel: () {},
          onDone: () {},
        ),
      );

      expect(find.text('Partly filled'), findsOneWidget);
      expect(find.textContaining('not the full amount'), findsOneWidget);
    });

    testWidgets('claims funds are safe only when the contract says so', (
      tester,
    ) async {
      await pump(
        tester,
        SwapProgressView(
          progress: progressOf(
            phase: SwapPhase.failed,
            detail: 'The bridge reported a failure.',
          ),
          onCancel: () {},
          onDone: () {},
        ),
      );

      // The one claim that must never be guessed.
      expect(find.textContaining('balance is unchanged'), findsNothing);
      expect(
        find.textContaining('Check the transaction details'),
        findsOneWidget,
      );
    });

    testWidgets('says so plainly when nothing was sent', (tester) async {
      await pump(
        tester,
        SwapProgressView(
          progress: progressOf(
            phase: SwapPhase.failed,
            detail: 'The price moved.',
            fundsUntouched: true,
          ),
          onCancel: () {},
          onDone: () {},
        ),
      );

      expect(find.textContaining('balance is unchanged'), findsOneWidget);
    });
  });
}

// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';
import 'package:web_dex/views/swap/entry/swap_entry_view.dart';

import 'swap_entry_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the signed-out form's button and notes where connecting a wallet
/// is not the next step: an expired or failed price is offered again, a
/// block a wallet cannot lift keeps the button off, and a price shown
/// before fees says so whatever else is shown.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpSwapUi();

  const beforeFees =
      'This price is before fees. Connect a wallet to see fees and swap.';

  late RecordingSwapBloc swap;
  late FakeSwapServices services;

  setUp(() {
    swap = RecordingSwapBloc();
    services = FakeSwapServices(activated: {});
  });

  tearDown(() => swap.close());

  Future<void> pump(
    WidgetTester tester,
    UnifiedSwapState state, {
    bool settle = true,
  }) async {
    swap.emit(state);
    await pumpSwapUi(
      tester,
      SwapEntryView(onConnectWallet: () {}),
      bloc: swap,
      services: services,
      settle: settle,
    );
  }

  SwapQuote offer({String? expectedUsd = '2990'}) => quoteOf(
    id: 'atomic',
    source: SwapLiquiditySource.atomic,
    routeKind: SwapRouteKind.direct,
    order: null,
    expected: '2990',
    guaranteed: '2990',
    fees: const [],
    pricing: pricingOf(
      expected: expectedUsd,
      minimum: expectedUsd,
      network: null,
      swap: null,
      complete: false,
    ),
  );

  UnifiedSwapState signedOut({
    SwapFormIssue issue = SwapFormIssue.signedOut,
    SwapEvaluationStatus evaluation = SwapEvaluationStatus.idle,
    SwapQuote? option,
    SwapQuoteFailure? failure,
    bool loadingAssets = false,
  }) {
    final quotes = option == null
        ? null
        : UnifiedSwapQuotes(
            ranked: const [],
            unrankable: [option],
            failures: const [],
          );
    return UnifiedSwapState(
      loadingAssets: loadingAssets,
      catalog: SwapCatalog(
        sources: swapTestCatalog.sources,
        activated: const {},
      ),
      pay: eth,
      receive: usdc,
      inputText: '1',
      signedIn: false,
      issue: issue,
      evaluation: evaluation,
      quotes: quotes,
      selectedId: option?.id,
      failure: failure,
      failures: [?failure],
    );
  }

  Future<void> press(WidgetTester tester) async {
    await tester.tap(swapPrimaryAction);
    await tester.pumpAndSettle();
  }

  group('the button', () {
    testWidgets('refreshes an expired look', (tester) async {
      await pump(
        tester,
        signedOut(evaluation: SwapEvaluationStatus.expired, option: offer()),
      );

      expect(swapPrimaryLabel(tester), 'Refresh quote');
      await press(tester);
      expect(swap.events, [const UnifiedSwapEvaluationRequested()]);
    });

    testWidgets('tries the order book again after it could not answer', (
      tester,
    ) async {
      await pump(
        tester,
        signedOut(
          evaluation: SwapEvaluationStatus.failed,
          failure: const SwapQuoteFailure(
            source: SwapLiquiditySource.atomic,
            kind: SwapQuoteFailureKind.serviceError,
          ),
        ),
      );

      expect(swapPrimaryLabel(tester), 'Try again');
      await press(tester);
      expect(swap.events, [const UnifiedSwapEvaluationRequested()]);
    });

    for (final kind in [
      SwapQuoteFailureKind.tradingBlocked,
      SwapQuoteFailureKind.clockInvalid,
    ]) {
      testWidgets('stays off for ${kind.name}, which a wallet cannot lift', (
        tester,
      ) async {
        await pump(
          tester,
          signedOut(
            evaluation: SwapEvaluationStatus.failed,
            failure: SwapQuoteFailure(
              source: SwapLiquiditySource.atomic,
              kind: kind,
            ),
          ),
        );

        expect(swapPrimaryLabel(tester), 'Review swap');
        expect(swapButtonEnabled(tester, find.text('Review swap')), isFalse);
      });
    }

    testWidgets('steers away from the same asset on both sides', (
      tester,
    ) async {
      await pump(tester, signedOut(issue: SwapFormIssue.sameAsset));

      expect(swapPrimaryLabel(tester), 'Choose another asset');
    });

    testWidgets('connects while a price is being checked', (tester) async {
      // The skeleton animates, so the frame never settles.
      await pump(
        tester,
        signedOut(evaluation: SwapEvaluationStatus.checking),
        settle: false,
      );

      expect(swapPrimaryLabel(tester), 'Connect wallet');
    });
  });

  group('the notes', () {
    testWidgets('say before fees when the receive side has no dollar price', (
      tester,
    ) async {
      await pump(
        tester,
        signedOut(
          evaluation: SwapEvaluationStatus.ready,
          option: offer(expectedUsd: null),
        ),
      );

      expect(find.text(beforeFees), findsOneWidget);
      // That warning says costs remain available, which a look lacks.
      expect(find.textContaining('costs remain available'), findsNothing);
    });

    testWidgets('say before fees beside a high price impact', (tester) async {
      await pump(
        tester,
        signedOut(
          evaluation: SwapEvaluationStatus.ready,
          option: offer(expectedUsd: '2000'),
        ),
      );

      expect(find.textContaining('High price impact'), findsOneWidget);
      expect(find.text(beforeFees), findsOneWidget);
    });

    testWidgets('say before fees on an expired look', (tester) async {
      await pump(
        tester,
        signedOut(evaluation: SwapEvaluationStatus.expired, option: offer()),
      );

      expect(find.text(beforeFees), findsOneWidget);
    });

    testWidgets('never name "this wallet" while none is signed in', (
      tester,
    ) async {
      await pump(
        tester,
        signedOut(issue: SwapFormIssue.amountMissing, loadingAssets: true),
      );

      expect(find.textContaining('this wallet'), findsNothing);
      expect(
        find.text('Connect a wallet to see balances and swap.'),
        findsOneWidget,
      );
    });
  });
}

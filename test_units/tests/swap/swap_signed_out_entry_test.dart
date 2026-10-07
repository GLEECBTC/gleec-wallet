// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';
import 'package:web_dex/views/swap/common/swap_failure_copy.dart';
import 'package:web_dex/views/swap/common/swap_format.dart';
import 'package:web_dex/views/swap/entry/swap_entry_view.dart';

import 'swap_common_ui_fakes.dart' show useEnglishCopy;
import 'swap_entry_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers what the swap form says before sign-in: an order-book price, shown
/// as before fees; why a cross-network price needs a wallet; and a button
/// that always connects one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const waiting = SwapQuoteFailure(
    source: SwapLiquiditySource.routed,
    kind: SwapQuoteFailureKind.signedOut,
  );
  const noOffer = SwapQuoteFailure(
    source: SwapLiquiditySource.atomic,
    kind: SwapQuoteFailureKind.noRoute,
  );

  group('the form', () {
    setUpSwapUi();

    late RecordingSwapBloc swap;
    late FakeSwapServices services;
    late int connects;

    setUp(() {
      swap = RecordingSwapBloc();
      services = FakeSwapServices(activated: {});
      connects = 0;
    });

    tearDown(() => swap.close());

    Future<void> pump(WidgetTester tester, UnifiedSwapState state) async {
      swap.emit(state);
      await pumpSwapUi(
        tester,
        SwapEntryView(onConnectWallet: () => connects++),
        bloc: swap,
        services: services,
      );
    }

    // An order-book offer read without a wallet: no fees, so no total.
    final offer = quoteOf(
      id: 'atomic',
      source: SwapLiquiditySource.atomic,
      routeKind: SwapRouteKind.direct,
      order: null,
      expected: '2990',
      guaranteed: '2990',
      fees: const [],
      pricing: pricingOf(
        expected: '2990',
        minimum: '2990',
        network: null,
        swap: null,
        complete: false,
      ),
    );

    UnifiedSwapState signedOut({
      SwapFormIssue issue = SwapFormIssue.signedOut,
      String input = '1',
      SwapEvaluationStatus evaluation = SwapEvaluationStatus.idle,
      SwapQuote? option,
      SwapQuoteFailure? failure,
      List<SwapQuoteFailure> failures = const [],
    }) {
      final quotes = option == null
          ? null
          : UnifiedSwapQuotes(
              ranked: const [],
              unrankable: [option],
              failures: failures,
            );
      return UnifiedSwapState(
        loadingAssets: false,
        catalog: SwapCatalog(
          sources: swapTestCatalog.sources,
          activated: const {},
        ),
        pay: eth,
        receive: usdc,
        inputText: input,
        signedIn: false,
        issue: issue,
        evaluation: evaluation,
        quotes: quotes,
        selectedId: option?.id,
        failure: failure,
        failures: failures,
      );
    }

    testWidgets('shows an order-book price before fees, and connects', (
      tester,
    ) async {
      await pump(
        tester,
        signedOut(evaluation: SwapEvaluationStatus.ready, option: offer),
      );

      final receive = SwapFormat.amount(offer.expectedReceive);
      expect(find.text(receive), findsOneWidget);
      expect(
        find.text(
          'This price is before fees. Connect a wallet to see fees and swap.',
        ),
        findsOneWidget,
      );
      expect(find.text('Incomplete'), findsOneWidget);
      expect(find.text('Review swap'), findsNothing);
      expect(swapPrimaryLabel(tester), 'Connect wallet');

      await tester.tap(swapPrimaryAction);
      await tester.pumpAndSettle();
      expect(connects, 1);
      expect(swap.events, isEmpty);
    });

    testWidgets('with routes to check too, says a wallet adds them', (
      tester,
    ) async {
      await pump(
        tester,
        signedOut(
          evaluation: SwapEvaluationStatus.ready,
          option: offer,
          failures: [waiting],
        ),
      );

      expect(
        find.text(
          'This order-book price is before fees. Connect a wallet to see '
          'fees and compare cross-network prices.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('This price is before fees'), findsNothing);
    });

    testWidgets('a pair only routes can price asks for a wallet calmly', (
      tester,
    ) async {
      await pump(
        tester,
        signedOut(
          evaluation: SwapEvaluationStatus.failed,
          failure: waiting,
          failures: [waiting],
        ),
      );

      expect(
        find.text(
          'Connect a wallet to see cross-network prices for this pair.',
        ),
        findsOneWidget,
      );
      // A next step, not an error.
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
      expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
      expect(swapPrimaryLabel(tester), 'Connect wallet');
    });

    testWidgets('no order-book offer leaves the routes to check', (
      tester,
    ) async {
      await pump(
        tester,
        signedOut(
          evaluation: SwapEvaluationStatus.failed,
          failure: noOffer,
          failures: [noOffer, waiting],
        ),
      );

      expect(
        find.text(
          'No order-book offer fits this amount right now. Connect a wallet '
          'to check cross-network prices.',
        ),
        findsOneWidget,
      );
      expect(swapPrimaryLabel(tester), 'Connect wallet');
    });

    testWidgets('an amount problem still shows, and the button connects', (
      tester,
    ) async {
      await pump(
        tester,
        signedOut(issue: SwapFormIssue.amountZero, input: '0'),
      );

      expect(find.text('Amount must be greater than 0.'), findsOneWidget);
      expect(swapPrimaryLabel(tester), 'Connect wallet');
    });

    testWidgets('before an amount, it says what a wallet adds', (tester) async {
      await pump(
        tester,
        signedOut(issue: SwapFormIssue.amountMissing, input: ''),
      );

      expect(
        find.text('Connect a wallet to see balances and swap.'),
        findsOneWidget,
      );
      expect(swapPrimaryLabel(tester), 'Connect wallet');
      expect(swapButtonEnabled(tester, find.text('Connect wallet')), isTrue);
    });

    testWidgets('a pair that cannot be swapped still steers elsewhere', (
      tester,
    ) async {
      await pump(tester, signedOut(issue: SwapFormIssue.pairUnsupported));

      expect(swapPrimaryLabel(tester), 'Choose another asset');
    });

    group('1INCH from Avalanche to KuCoin Chain, as reported', () {
      final avax = assetOf(
        'AVAX',
        subClass: CoinSubClass.avx20,
        chainId: 43114,
      );
      final kcs = assetOf('KCS', subClass: CoinSubClass.krc20, chainId: 321);
      final pay = assetOf(
        '1INCH-AVX20',
        subClass: CoinSubClass.avx20,
        parent: avax,
        chainId: 43114,
      );
      final receive = assetOf(
        '1INCH-KRC20',
        subClass: CoinSubClass.krc20,
        parent: kcs,
        chainId: 321,
      );
      // Routes reach Avalanche but not KuCoin Chain: the order book alone
      // can trade the pair.
      final catalog = SwapCatalog(
        sources: [
          SwapSourceAssets(
            source: SwapLiquiditySource.atomic,
            onceActive: {pay, receive},
          ),
          SwapSourceAssets(
            source: SwapLiquiditySource.routed,
            onceActive: {pay},
          ),
        ],
        activated: const {},
      );

      UnifiedSwapState reported({
        required SwapEvaluationStatus evaluation,
        SwapQuote? option,
        SwapQuoteFailure? failure,
      }) => signedOut(
        input: '1233',
        evaluation: evaluation,
        option: option,
        failure: failure,
        failures: [?failure],
      ).copyWith(pay: pay, receive: receive, catalog: catalog);

      setUp(() {
        services.known = [avax, kcs, pay, receive];
        services.prices = {pay: d('0.1015'), receive: d('0.1015')};
      });

      const onKcc =
          "1INCH on KuCoin Chain trades only on the order book, so there's no "
          'cross-network option.';

      testWidgets('with no offer, says so and names the network', (
        tester,
      ) async {
        await pump(
          tester,
          reported(evaluation: SwapEvaluationStatus.failed, failure: noOffer),
        );

        expect(
          find.text('No swap is available for this amount and pair right now.'),
          findsOneWidget,
        );
        expect(find.text(onKcc), findsOneWidget);
        // A wallet would not add an offer; the order book may.
        expect(swapPrimaryLabel(tester), 'Try again');
      });

      testWidgets('the other way round, names the same network', (
        tester,
      ) async {
        await pump(
          tester,
          reported(
            evaluation: SwapEvaluationStatus.failed,
            failure: noOffer,
          ).copyWith(pay: receive, receive: pay),
        );

        expect(find.text(onKcc), findsOneWidget);
      });

      testWidgets('with an offer, shows what it would pay', (tester) async {
        final match = quoteOf(
          id: 'atomic',
          source: SwapLiquiditySource.atomic,
          routeKind: SwapRouteKind.direct,
          order: null,
          from: pay,
          to: receive,
          sell: '1233',
          expected: '1230',
          guaranteed: '1230',
          fees: const [],
          pricing: pricingOf(
            pay: '125.15',
            expected: '124.84',
            minimum: '124.84',
            network: null,
            swap: null,
            complete: false,
          ),
        );
        await pump(
          tester,
          reported(evaluation: SwapEvaluationStatus.ready, option: match),
        );

        expect(find.text(SwapFormat.amount(d('1230'))), findsOneWidget);
        expect(find.text(r'$124.84'), findsOneWidget);
        expect(
          find.text(
            'This price is before fees. Connect a wallet to see fees and '
            'swap.',
          ),
          findsOneWidget,
        );
        expect(swapPrimaryLabel(tester), 'Connect wallet');
      });
    });
  });

  group('the copy', () {
    useEnglishCopy();

    final avax = assetOf('AVAX', subClass: CoinSubClass.avx20, chainId: 43114);
    final kcs = assetOf('KCS', subClass: CoinSubClass.krc20, chainId: 321);
    final inchOnAvax = assetOf(
      '1INCH-AVX20',
      subClass: CoinSubClass.avx20,
      parent: avax,
      chainId: 43114,
    );
    final inchOnKcc = assetOf(
      '1INCH-KRC20',
      subClass: CoinSubClass.krc20,
      parent: kcs,
      chainId: 321,
    );
    final networks = SwapNetworks([avax, kcs, inchOnAvax, inchOnKcc]);
    final orderBookOnly = SwapPairSupport(
      sources: const {SwapLiquiditySource.atomic},
      routesUnavailableFor: inchOnKcc,
    );
    const onKcc =
        "1INCH on KuCoin Chain trades only on the order book, so there's no "
        'cross-network option.';

    test('names the network when both sides share a ticker', () {
      final copy = SwapFailureCopy.of(
        noOffer,
        inchOnAvax,
        receive: inchOnKcc,
        all: const [noOffer],
        support: orderBookOnly,
        networks: networks,
      );

      expect(
        copy.message,
        'No swap is available for this amount and pair right now.',
      );
      expect(copy.detail, onKcc);
    });

    test('names it the same way when the pay side is the limited one', () {
      final copy = SwapFailureCopy.of(
        noOffer,
        inchOnKcc,
        receive: inchOnAvax,
        all: const [noOffer],
        support: orderBookOnly,
        networks: networks,
      );

      expect(copy.detail, onKcc);
    });

    test('routes waiting for a wallet are a next step, not an error', () {
      final copy = SwapFailureCopy.of(waiting, eth, all: const [waiting]);

      expect(
        copy.message,
        'Connect a wallet to see cross-network prices for this pair.',
      );
      expect(copy.action, SwapEntryAction.connect);
    });
  });
}

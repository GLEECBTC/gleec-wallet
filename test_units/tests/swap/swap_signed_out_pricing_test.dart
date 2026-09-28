import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_preferences.dart';
import 'package:web_dex/shared/swap/swap_pricing.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/swap/swap_terms_repository.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';

import 'swap_bloc_fakes.dart' show ScriptedQuoteSource;
import 'swap_test_fixtures.dart';

/// Covers the swap form before sign-in. Nothing is active, but KDF reads the
/// order book from coin configs alone, so the order book prices the swap as
/// a look. Cross-network routes need an active coin, so they wait for a
/// wallet.
void main() {
  final clock = DateTime(2026, 9, 24, 12);
  final paxg = assetOf('PAXG-ERC20', parent: eth);
  final all = [eth, usdc, btc, paxg];

  late ScriptedQuoteSource routed;
  late ScriptedQuoteSource atomic;

  // An order-book offer: no fees read, as when nothing is active.
  List<SwapQuoteResult> offer(SwapQuoteRequest request) => [
    SwapQuoteAvailable(
      quoteOf(
        id: 'atomic',
        source: SwapLiquiditySource.atomic,
        routeKind: SwapRouteKind.direct,
        order: null,
        from: request.from,
        to: request.to,
        sell: request.amount.toString(),
        fees: const [],
        quotedAt: clock,
        pricing: const SwapQuotePricing(),
      ),
    ),
  ];

  setUp(() {
    routed = ScriptedQuoteSource(
      SwapLiquiditySource.routed,
      respond: (request) => [
        SwapQuoteAvailable(
          quoteOf(
            id: 'routed',
            from: request.from,
            to: request.to,
            sell: request.amount.toString(),
            quotedAt: clock,
          ),
        ),
      ],
    )..tradable = {eth, usdc, paxg};
    atomic = ScriptedQuoteSource(SwapLiquiditySource.atomic, respond: offer)
      ..tradable = {eth, usdc, btc};
  });

  group('the form', () {
    late SwapExecutionRegistry registry;
    late List<FakeExecutor> executors;

    setUp(() {
      executors = [
        FakeExecutor(SwapLiquiditySource.routed),
        FakeExecutor(SwapLiquiditySource.atomic),
      ];
      registry = SwapExecutionRegistry(
        executors: executors,
        inFlight: () async => const [],
      );
    });

    tearDown(() => registry.dispose());

    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await pumpEventQueue(times: 30);
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
    }

    UnifiedSwapCapabilitiesChanged signedIn(bool value) =>
        UnifiedSwapCapabilitiesChanged(
          tradingEnabled: true,
          clockValid: true,
          signedIn: value,
        );

    late DateTime now;
    // What the app's wallet reads return: nothing without a wallet.
    late bool walletSignedIn;
    Completer<void>? balanceGate;
    Completer<void>? addressGate;

    setUp(() {
      now = clock;
      balanceGate = null;
      addressGate = null;
    });

    Future<UnifiedSwapBloc> open(
      String pay,
      String receive, {
      String amount = '1',
      bool signedInAtStart = false,
      Duration refresh = const Duration(hours: 1),
    }) async {
      walletSignedIn = signedInAtStart;
      final storage = MemoryStorage();
      final bloc =
          UnifiedSwapBloc(
              repository: UnifiedSwapRepository(
                sources: [routed, atomic],
                pricing: SwapPricingService(
                  FakePriceSource({eth: d('3000'), usdc: d('1')}),
                ),
                activatedAssets: () async =>
                    signedInAtStart ? {...all} : <AssetId>{},
              ),
              registry: registry,
              terms: SwapTermsRepository(
                walletKey: () async => 'w',
                storage: storage,
              ),
              preferences: SwapPreferences(
                walletKey: () async => 'w',
                storage: storage,
              ),
              spendableBalance: (asset) async {
                final signedIn = walletSignedIn;
                await balanceGate?.future;
                return signedIn ? d('10') : null;
              },
              addressOf: (asset) async {
                final signedIn = walletSignedIn;
                await addressGate?.future;
                return signedIn ? '0xwallet' : null;
              },
              resolveAsset: (ticker) => {for (final a in all) a.id: a}[ticker],
              now: () => now,
              debounce: Duration.zero,
              refreshInterval: refresh,
            )
            ..add(signedIn(signedInAtStart))
            ..add(const UnifiedSwapStarted())
            ..add(
              UnifiedSwapIntentApplied(
                pay: pay,
                receive: receive,
                amount: amount,
              ),
            );
      await settle();
      addTearDown(bloc.close);
      return bloc;
    }

    test('prices from the order book, as a look it cannot review', () async {
      final bloc = await open('ETH', 'USDC-ERC20');

      expect(bloc.state.issue, SwapFormIssue.signedOut);
      expect(bloc.state.evaluation, SwapEvaluationStatus.ready);
      expect(bloc.state.selectedQuote!.source, SwapLiquiditySource.atomic);
      expect(atomic.requests.last.indicative, isTrue);
      expect(routed.requests, isEmpty);
      expect(bloc.state.failures.single.kind, SwapQuoteFailureKind.signedOut);
      expect(bloc.state.canReview, isFalse);

      bloc.add(const UnifiedSwapReviewOpened());
      await settle();
      expect(bloc.state.view, UnifiedSwapView.form);
    });

    test('checks the amount before asking for a wallet', () async {
      final bloc = await open('BTC', 'ETH', amount: '0.123456789');
      expect(bloc.state.issue, SwapFormIssue.tooManyDecimals);

      bloc.add(const UnifiedSwapAmountChanged('0'));
      await settle();
      expect(bloc.state.issue, SwapFormIssue.amountZero);
      expect(atomic.requests, isEmpty);
    });

    test('a pair only routes trade says they wait for a wallet', () async {
      final bloc = await open('ETH', 'PAXG-ERC20');

      expect(bloc.state.evaluation, SwapEvaluationStatus.failed);
      expect(bloc.state.failure!.kind, SwapQuoteFailureKind.signedOut);
      expect(bloc.state.issue, SwapFormIssue.signedOut);
      expect(routed.requests, isEmpty);
    });

    test('keeps an order-book price fresh while it is looked at', () async {
      final bloc = await open(
        'ETH',
        'USDC-ERC20',
        refresh: const Duration(milliseconds: 20),
      );
      final asked = atomic.requests.length;

      await Future<void>.delayed(const Duration(milliseconds: 80));
      await settle();

      expect(atomic.requests.length, greaterThan(asked));
      expect(routed.requests, isEmpty);
      expect(bloc.state.evaluation, SwapEvaluationStatus.ready);
    });

    test('prices an expired look again when the form is shown again', () async {
      // Every offer is already past its lifetime, so it expires at once.
      now = clock.add(SwapQuote.lifetime * 2);
      final bloc = await open('ETH', 'USDC-ERC20');
      expect(bloc.state.evaluation, SwapEvaluationStatus.expired);
      final asked = atomic.requests.length;

      bloc
        ..add(const UnifiedSwapVisibilityChanged(visible: false))
        ..add(const UnifiedSwapVisibilityChanged(visible: true));
      await settle();

      expect(atomic.requests.length, asked + 1);
    });

    test(
      'signing in drops the signed-out price and reads the wallet',
      () async {
        final bloc = await open('ETH', 'USDC-ERC20');
        expect(bloc.state.selectedQuote, isNotNull);
        expect(bloc.state.balance, isNull);

        walletSignedIn = true;
        bloc.add(signedIn(true));
        await settle();

        expect(bloc.state.quotes, isNull);
        expect(bloc.state.selectedQuote, isNull);
        expect(bloc.state.failures, isEmpty);
        expect(bloc.state.evaluation, SwapEvaluationStatus.idle);
        expect(bloc.state.balance, d('10'));
        expect(bloc.state.payAddress, '0xwallet');
        // Nothing is active yet: the catalog was read signed out.
        expect(bloc.state.issue, SwapFormIssue.assetInactive);
        expect(bloc.state.canReview, isFalse);
      },
    );

    test('a price still in flight at sign-in is dropped on arrival', () async {
      atomic.gate = Completer<void>();
      final bloc = await open('ETH', 'USDC-ERC20');
      expect(bloc.state.evaluation, SwapEvaluationStatus.checking);

      bloc.add(signedIn(true));
      await settle();
      atomic.gate!.complete();
      await settle();

      expect(bloc.state.quotes, isNull);
      expect(bloc.state.evaluation, SwapEvaluationStatus.idle);
    });

    test(
      "signing out drops the wallet's price and data, and looks again",
      () async {
        final bloc = await open('ETH', 'USDC-ERC20', signedInAtStart: true);
        expect(bloc.state.issue, isNull);
        expect(bloc.state.quotes!.options, hasLength(2));
        expect(bloc.state.balance, d('10'));
        expect(bloc.state.payAddress, '0xwallet');
        final routedAsked = routed.requests.length;

        walletSignedIn = false;
        bloc.add(signedIn(false));
        await settle();

        expect(routed.requests.length, routedAsked);
        expect(atomic.requests.last.signedOut, isTrue);
        expect(bloc.state.issue, SwapFormIssue.signedOut);
        expect(bloc.state.selectedQuote!.source, SwapLiquiditySource.atomic);
        expect(bloc.state.balance, isNull);
        expect(bloc.state.payAddress, isNull);
        expect(bloc.state.receiveAddress, isNull);
      },
    );

    test("signing out hides the wallet's balance before any read", () async {
      final bloc = await open('ETH', 'USDC-ERC20', signedInAtStart: true);
      final read = balanceGate = Completer<void>();

      walletSignedIn = false;
      bloc.add(signedIn(false));
      await settle();

      expect(bloc.state.balance, isNull);
      expect(bloc.state.payAddress, isNull);
      read.complete();
      await settle();
      expect(bloc.state.balance, isNull);
    });

    test('an address read in flight at sign-out is dropped', () async {
      final stale = addressGate = Completer<void>();
      final bloc = await open('ETH', 'USDC-ERC20', signedInAtStart: true);

      addressGate = null;
      walletSignedIn = false;
      bloc.add(signedIn(false));
      await settle();
      stale.complete();
      await settle();

      expect(bloc.state.payAddress, isNull);
      expect(bloc.state.receiveAddress, isNull);
    });

    test('a Max still working at sign-out is dropped', () async {
      final bloc = await open('ETH', 'USDC-ERC20', signedInAtStart: true);
      final gate = Completer<void>();
      for (final source in [routed, atomic]) {
        source
          ..maxGate = gate
          ..max = SwapMaxAmount(amount: d('9'), reservedForFees: d('1'));
      }
      bloc.add(const UnifiedSwapMaxRequested());
      await settle();

      walletSignedIn = false;
      bloc.add(signedIn(false));
      await settle();
      gate.complete();
      await settle();

      expect(bloc.state.maxApplied, isNull);
      expect(bloc.state.inputText, '1');
    });

    test('a balance read in flight at sign-out is dropped', () async {
      final stale = balanceGate = Completer<void>();
      final bloc = await open('ETH', 'USDC-ERC20', signedInAtStart: true);

      balanceGate = null;
      walletSignedIn = false;
      bloc.add(signedIn(false));
      await settle();
      stale.complete();
      await settle();

      expect(bloc.state.balance, isNull);
      expect(bloc.state.issue, SwapFormIssue.signedOut);
    });

    test("a signed-in price in flight at sign-out is dropped", () async {
      routed.gate = Completer<void>();
      final bloc = await open('ETH', 'USDC-ERC20', signedInAtStart: true);
      expect(bloc.state.evaluation, SwapEvaluationStatus.checking);

      walletSignedIn = false;
      bloc.add(signedIn(false));
      await settle();
      routed.gate!.complete();
      await settle();

      expect(bloc.state.selectedQuote!.source, SwapLiquiditySource.atomic);
      expect(bloc.state.quotes!.options, hasLength(1));
    });

    test('signing out closes the review, so Start cannot run', () async {
      final requote = Completer<void>();
      routed.requoteGate = requote;
      atomic.requoteGate = requote;
      final bloc = await open('ETH', 'USDC-ERC20', signedInAtStart: true);
      bloc.add(const UnifiedSwapReviewOpened());
      await settle();
      expect(bloc.state.view, UnifiedSwapView.review);

      // Start is re-pricing when the wallet signs out.
      bloc.add(const UnifiedSwapStartRequested());
      await settle();
      walletSignedIn = false;
      bloc.add(signedIn(false));
      await settle();
      requote.complete();
      await settle();

      expect(bloc.state.view, UnifiedSwapView.form);
      expect(bloc.state.review, isNull);
      expect(bloc.state.activeExecutionId, isNull);
      expect(executors.expand((e) => e.started), isEmpty);
      // Back on the form, it is priced again as a look.
      expect(atomic.requests.last.signedOut, isTrue);
      expect(bloc.state.evaluation, SwapEvaluationStatus.ready);
    });

    test(
      'a re-price from before a sign-out never starts a later review',
      () async {
        final requote = Completer<void>();
        routed.requoteGate = requote;
        atomic.requoteGate = requote;
        final bloc = await open('ETH', 'USDC-ERC20', signedInAtStart: true);
        bloc.add(const UnifiedSwapReviewOpened());
        await settle();
        bloc.add(const UnifiedSwapStartRequested());
        await settle();

        // Out and back in, and a new review is open before the old answer.
        walletSignedIn = false;
        bloc.add(signedIn(false));
        await settle();
        walletSignedIn = true;
        bloc.add(signedIn(true));
        await settle();
        bloc.add(const UnifiedSwapReviewOpened());
        await settle();
        expect(bloc.state.view, UnifiedSwapView.review);
        requote.complete();
        await settle();

        expect(executors.expand((e) => e.started), isEmpty);
        expect(bloc.state.review!.status, SwapReviewStatus.ready);
      },
    );

    test("signing out drops a Max the wallet's balance set", () async {
      final bloc = await open('ETH', 'USDC-ERC20', signedInAtStart: true);
      for (final source in [routed, atomic]) {
        source.max = SwapMaxAmount(amount: d('9'), reservedForFees: d('1'));
      }
      bloc.add(const UnifiedSwapMaxRequested());
      await settle();
      expect(bloc.state.maxApplied, isNotNull);

      walletSignedIn = false;
      bloc.add(signedIn(false));
      await settle();

      expect(bloc.state.maxApplied, isNull);
    });
  });
}

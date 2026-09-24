import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_preferences.dart';
import 'package:web_dex/shared/swap/swap_pricing.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/swap/swap_terms_repository.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';

import 'swap_test_fixtures.dart';

/// Covers the swap form's rules. Most follow from one fact: the user commits
/// money against a number that moves — so nothing starts against a price
/// they have not seen, a stale answer never wins, and a start whose answer
/// was lost is never repeated.
void main() {
  late FakeQuoteSource routed;
  late FakeQuoteSource atomic;
  late FakeExecutor routedExecutor;
  late SwapExecutionRegistry registry;
  late MemoryStorage storage;
  late Map<AssetId, Decimal> balances;
  late DateTime clock;
  late List<({AssetId asset, Decimal usdValue})> holdings;

  AssetId? resolve(String ticker) => {
    for (final a in [eth, usdc, btc, gleec]) a.id: a,
  }[ticker];

  List<SwapQuoteResult> pricedFor(SwapQuoteRequest request) => [
    SwapQuoteAvailable(
      quoteOf(
        id: 'routed-${request.amount}',
        from: request.from,
        to: request.to,
        sell: request.amount.toString(),
        quotedAt: clock,
        pricing: const SwapQuotePricing(),
      ),
    ),
  ];

  UnifiedSwapBloc build() {
    final prices = FakePriceSource({eth: d('3000'), usdc: d('1')});
    return UnifiedSwapBloc(
      repository: UnifiedSwapRepository(
        sources: [routed, atomic],
        pricing: SwapPricingService(prices),
      ),
      registry: registry,
      terms: SwapTermsRepository(
        walletKey: () async => 'wallet',
        storage: storage,
      ),
      preferences: SwapPreferences(
        walletKey: () async => 'wallet',
        storage: storage,
      ),
      spendableBalance: (asset) async => balances[asset],
      addressOf: (asset) async => '0xaddress',
      resolveAsset: resolve,
      holdings: () async => holdings,
      now: () => clock,
      debounce: Duration.zero,
      evaluationTimeout: const Duration(seconds: 2),
      refreshInterval: const Duration(hours: 1),
      rateLimitPause: const Duration(milliseconds: 30),
    );
  }

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await pumpEventQueue(times: 30);
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  setUp(() {
    clock = DateTime(2026, 9, 24, 12);
    routed = FakeQuoteSource(SwapLiquiditySource.routed, respond: pricedFor);
    atomic = FakeQuoteSource(
      SwapLiquiditySource.atomic,
      results: [
        rejected(
          SwapQuoteFailureKind.pairUnsupported,
          source: SwapLiquiditySource.atomic,
        ),
      ],
    );
    routedExecutor = FakeExecutor(SwapLiquiditySource.routed);
    registry = SwapExecutionRegistry(
      executors: [routedExecutor, FakeExecutor(SwapLiquiditySource.atomic)],
      inFlight: () async => const [],
    );
    storage = MemoryStorage();
    balances = {eth: d('2'), usdc: d('5000'), btc: d('1')};
    holdings = [];
  });

  tearDown(() => registry.dispose());

  Future<UnifiedSwapBloc> ready({String amount = '1'}) async {
    final bloc = build()
      ..add(const UnifiedSwapStarted())
      ..add(
        UnifiedSwapIntentApplied(
          pay: 'ETH',
          receive: 'USDC-ERC20',
          amount: amount,
        ),
      );
    await settle();
    return bloc;
  }

  group('opening pair', () {
    test('opens on the pair last swapped', () async {
      await SwapPreferences(
        walletKey: () async => 'wallet',
        storage: storage,
      ).rememberPair(btc, eth);
      final bloc = build()..add(const UnifiedSwapStarted());
      await settle();

      expect(bloc.state.pay, btc);
      expect(bloc.state.receive, eth);
      await bloc.close();
    });

    test('otherwise pairs the largest holding with a stablecoin', () async {
      holdings = [
        (asset: btc, usdValue: d('10')),
        (asset: eth, usdValue: d('6000')),
      ];
      final bloc = build()..add(const UnifiedSwapStarted());
      await settle();

      expect(bloc.state.pay, eth);
      expect(bloc.state.receive, usdc);
      await bloc.close();
    });

    test('an intent wins over the default pair', () async {
      holdings = [(asset: eth, usdValue: d('6000'))];
      final bloc = build()
        ..add(const UnifiedSwapStarted())
        ..add(const UnifiedSwapIntentApplied(pay: 'BTC'));
      await settle();

      expect(bloc.state.pay, btc);
      await bloc.close();
    });
  });

  group('validation', () {
    Future<SwapFormIssue?> issueFor(String text, {AssetId? pay}) async {
      final bloc = build()
        ..add(
          UnifiedSwapIntentApplied(pay: (pay ?? eth).id, receive: 'USDC-ERC20'),
        );
      await settle();
      bloc.add(UnifiedSwapAmountChanged(text));
      await settle();
      final issue = bloc.state.issue;
      await bloc.close();
      return issue;
    }

    test('names what is wrong with the amount', () async {
      expect(await issueFor(''), SwapFormIssue.amountMissing);
      expect(await issueFor('1..2'), SwapFormIssue.amountMalformed);
      expect(await issueFor('0'), SwapFormIssue.amountZero);
      expect(await issueFor('3'), SwapFormIssue.insufficient);
      expect(
        await issueFor('0.123456789', pay: btc),
        SwapFormIssue.tooManyDecimals,
      );
      expect(await issueFor('1.5'), isNull);
    });

    test('checks the network fee can be paid when selling a token', () async {
      balances[eth] = d('0.0001');
      routed.respond = (request) => [
        SwapQuoteAvailable(
          quoteOf(
            from: usdc,
            to: eth,
            sell: request.amount.toString(),
            quotedAt: clock,
          ),
        ),
      ];
      final bloc = build()
        ..add(
          const UnifiedSwapIntentApplied(
            pay: 'USDC-ERC20',
            receive: 'ETH',
            amount: '100',
          ),
        );
      await settle();

      expect(bloc.state.issue, SwapFormIssue.insufficientForFees);
      expect(bloc.state.canReview, isFalse);
      await bloc.close();
    });
  });

  group('evaluation', () {
    test('prices the intent and preselects an option', () async {
      final bloc = await ready();

      expect(bloc.state.evaluation, SwapEvaluationStatus.ready);
      expect(bloc.state.selectedQuote!.sellAmount, d('1'));
      expect(bloc.state.canReview, isTrue);
      await bloc.close();
    });

    test('a stale answer never replaces a newer intent', () async {
      final bloc = await ready();
      routed.gate = Completer<void>();
      bloc.add(const UnifiedSwapAmountChanged('0.5'));
      await settle();
      bloc.add(const UnifiedSwapAmountChanged('0.25'));
      await settle();
      final seen = <UnifiedSwapState>[];
      final sub = bloc.stream.listen(seen.add);

      routed.gate!.complete();
      await settle();

      expect(bloc.state.selectedQuote!.sellAmount, d('0.25'));
      expect(
        seen.where((s) => s.selectedQuote?.sellAmount == d('0.5')),
        isEmpty,
      );
      await sub.cancel();
      await bloc.close();
    });

    test('explains why nothing could be priced', () async {
      routed.respond = null;
      routed.results = [rejected(SwapQuoteFailureKind.noRoute)];
      final bloc = await ready();

      expect(bloc.state.evaluation, SwapEvaluationStatus.failed);
      expect(bloc.state.failure!.kind, SwapQuoteFailureKind.noRoute);
      await bloc.close();
    });

    test('a rate limit pauses, then retries the default route only', () async {
      routed.respond = null;
      routed.results = [rejected(SwapQuoteFailureKind.rateLimited)];
      final bloc = await ready();
      expect(bloc.state.rateLimitedUntil, isNotNull);

      routed.respond = pricedFor;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await settle();

      expect(bloc.state.evaluation, SwapEvaluationStatus.ready);
      expect(routed.requests.last.orders, {SwapQuoteOrder.cheapest});
      await bloc.close();
    });

    test('an old quote expires instead of being reviewed', () async {
      final bloc = build()
        ..add(
          const UnifiedSwapIntentApplied(
            pay: 'ETH',
            receive: 'USDC-ERC20',
            amount: '1',
          ),
        );
      // The provider answered, but the answer is older than a quote's life.
      routed.respond = (request) => [
        SwapQuoteAvailable(
          quoteOf(
            sell: '1',
            quotedAt: clock.subtract(const Duration(minutes: 2)),
          ),
        ),
      ];
      await settle();

      expect(bloc.state.evaluation, SwapEvaluationStatus.expired);
      expect(bloc.state.canReview, isFalse);
      await bloc.close();
    });

    test('nothing is priced while trading is unavailable', () async {
      final bloc = build()
        ..add(
          const UnifiedSwapCapabilitiesChanged(
            tradingEnabled: false,
            clockValid: true,
          ),
        )
        ..add(
          const UnifiedSwapIntentApplied(
            pay: 'ETH',
            receive: 'USDC-ERC20',
            amount: '1',
          ),
        );
      await settle();

      expect(routed.requests, isEmpty);
      expect(bloc.state.canReview, isFalse);
      await bloc.close();
    });
  });

  group('amount entry', () {
    test('switching sides clears an amount in the old denomination', () async {
      final bloc = await ready();
      bloc.add(const UnifiedSwapSidesSwitched());
      await settle();

      expect(bloc.state.pay, usdc);
      expect(bloc.state.inputText, '');
      await bloc.close();
    });

    test('fiat entry converts at the current price', () async {
      final bloc = await ready();
      bloc.add(const UnifiedSwapAmountModeToggled());
      await settle();
      expect(bloc.state.amountMode, SwapAmountMode.fiat);
      expect(bloc.state.inputText, '3000');

      bloc.add(const UnifiedSwapAmountChanged('1500'));
      await settle();
      expect(bloc.amountOf(bloc.state), d('0.5'));
      await bloc.close();
    });

    test('Max keeps what the network fee needs', () async {
      routed.max = SwapMaxAmount(
        amount: d('1.99'),
        reservedForFees: d('0.01'),
        feeAsset: eth,
      );
      final bloc = await ready();
      bloc.add(const UnifiedSwapMaxRequested());
      await settle();

      expect(bloc.state.inputText, '1.99');
      expect(bloc.state.maxApplied!.reservedForFees, d('0.01'));
      await bloc.close();
    });
  });

  group('review and start', () {
    Future<UnifiedSwapBloc> inReview() async {
      final bloc = await ready();
      bloc.add(const UnifiedSwapReviewOpened());
      await settle();
      return bloc;
    }

    test('a first routed swap presents the provider terms', () async {
      final bloc = await inReview();

      expect(bloc.state.view, UnifiedSwapView.review);
      expect(bloc.state.review!.termsRequired, isTrue);
      await bloc.close();
    });

    test('starting records the terms and starts the re-priced swap', () async {
      final bloc = await inReview();
      bloc.add(const UnifiedSwapStartRequested());
      await settle();

      expect(routed.requoted, hasLength(1));
      expect(routedExecutor.started, hasLength(1));
      expect(bloc.state.view, UnifiedSwapView.progress);
      expect(bloc.state.activeExecutionId, isNotNull);
      expect(
        await SwapTermsRepository(
          walletKey: () async => 'wallet',
          storage: storage,
        ).hasAccepted(),
        isTrue,
      );
      await bloc.close();
    });

    test('a lower minimum stops for old-versus-new consent', () async {
      final bloc = await inReview();
      routed.requoteResult = SwapQuoteAvailable(
        quoteOf(id: 'fresh', guaranteed: '2900', quotedAt: clock),
      );
      bloc.add(const UnifiedSwapStartRequested());
      await settle();

      final review = bloc.state.review!;
      expect(review.status, SwapReviewStatus.materialUpdate);
      expect(review.previous!.guaranteedReceive, d('2985'));
      expect(review.quote.guaranteedReceive, d('2900'));
      expect(routedExecutor.started, isEmpty);

      bloc.add(const UnifiedSwapStartRequested());
      await settle();
      expect(routedExecutor.started.single.guaranteedReceive, d('2900'));
      await bloc.close();
    });

    test('changed steps go back to a fresh evaluation', () async {
      final bloc = await inReview();
      routed.requoteResult = SwapQuoteAvailable(
        quoteOf(
          routeKind: SwapRouteKind.crossChain,
          quotedAt: clock,
          stages: [
            const SwapRouteStage(kind: SwapRouteStageKind.prepare),
            SwapRouteStage(kind: SwapRouteStageKind.send, asset: eth),
            SwapRouteStage(kind: SwapRouteStageKind.bridge, asset: usdc),
            SwapRouteStage(kind: SwapRouteStageKind.receive, asset: usdc),
          ],
        ),
      );
      bloc.add(const UnifiedSwapStartRequested());
      await settle();

      expect(bloc.state.view, UnifiedSwapView.form);
      expect(bloc.state.structuralNotice, isTrue);
      expect(routedExecutor.started, isEmpty);
      await bloc.close();
    });

    test('leaving the review while re-pricing never starts', () async {
      final bloc = await inReview();
      routed.requoteGate = Completer<void>();
      bloc.add(const UnifiedSwapStartRequested());
      await settle();
      expect(bloc.state.review!.status, SwapReviewStatus.revalidating);

      bloc.add(const UnifiedSwapReviewClosed());
      await settle();
      routed.requoteGate!.complete();
      await settle();

      expect(routedExecutor.started, isEmpty);
      expect(bloc.state.view, UnifiedSwapView.form);
      await bloc.close();
    });

    test('a refused start says so and allows another try', () async {
      routedExecutor.startError = const SwapStartRejectedException(
        SwapStartRejection.insufficientBalance,
      );
      final bloc = await inReview();
      bloc.add(const UnifiedSwapStartRequested());
      await settle();

      expect(bloc.state.review!.status, SwapReviewStatus.rejected);
      await bloc.close();
    });

    test('a lost start answer never offers another start', () async {
      routedExecutor.startError = TimeoutException('lost');
      final bloc = await inReview();
      bloc.add(const UnifiedSwapStartRequested());
      await settle();

      expect(bloc.state.review!.status, SwapReviewStatus.unconfirmed);
      expect(bloc.state.review!.canStart, isFalse);

      bloc.add(const UnifiedSwapStartRequested());
      await settle();
      expect(routedExecutor.started, hasLength(1));
      await bloc.close();
    });

    test('a consented fresh quote starts without another review', () async {
      final bloc = await ready();
      bloc.add(
        UnifiedSwapFreshQuoteAccepted(
          quoteOf(id: 'fresh', guaranteed: '2950', quotedAt: clock),
        ),
      );
      await settle();

      expect(routedExecutor.started.single.id, 'fresh');
      expect(bloc.state.view, UnifiedSwapView.progress);
      await bloc.close();
    });
  });
}

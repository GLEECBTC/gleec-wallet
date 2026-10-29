import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/shared/swap/routed_swap_source.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

import 'swap_src_fakes.dart';
import 'swap_test_fixtures.dart';

void main() {
  late SrcRoutedSwaps manager;
  late DateTime now;

  RoutedSwapOffer offer(String amount, {String gas = '0.01'}) => offerOf(
    sell: amount,
    guaranteed: '123.456',
    networkFees: [
      RoutedSwapNetworkFee(
        ticker: eth.id,
        assetId: eth,
        amount: d('0.0001'),
        requiredBalance: d(gas),
      ),
    ],
    quotedAt: now,
  );

  RoutedSwapQuoteSource source({
    Duration timeout = const Duration(seconds: 1),
  }) => RoutedSwapQuoteSource(
    manager,
    networks: () => SwapNetworks([eth, usdc]),
    now: () => now,
    timeout: timeout,
  );

  Future<SwapMaxAmount?> maximum(
    RoutedSwapQuoteSource source,
  ) => source.maxAmount(
    from: eth,
    to: usdc,
    // Deliberately not the source-address balance. KDF's quote is authoritative.
    balance: d('100'),
  );

  Matcher unavailable(SwapQuoteFailureKind kind) => throwsA(
    isA<SwapMaxUnavailableException>().having(
      (error) => error.failure.kind,
      'failure kind',
      kind,
    ),
  );

  setUp(() {
    now = DateTime(2026, 10, 28, 12);
    manager = SrcRoutedSwaps()
      ..maximum = offer('0.99')
      ..respond = (call) => offer('${call.amount}');
  });

  test(
    'release default reprices native Max and preserves the complete offer',
    () async {
      final routed = source();
      final max = (await maximum(routed))!;
      expect(manager.maxCalls, 1);
      expect(manager.quotes.single.amount, d('0.98'));
      expect(max.amount, d('0.98'));
      expect(max.reservedForFees, d('0.02'));
      expect(max.quote!.guaranteedReceive, d('123.456'));
      expect((max.quote!.payload! as RoutedSwapOffer).sellAmount, max.amount);
      expect(max.quote!.requiredGasBalance, d('0.01'));
      expect(
        max.quote!.withPricing(const SwapQuotePricing()).maxRetainedBalance,
        d('0.02'),
      );
      final cached = await maximum(routed);
      expect(cached, max);
      expect(manager.maxCalls, 1);
      expect(manager.quotes, hasLength(1));
    },
  );

  test(
    'higher fees trigger a bounded reduction and a newly priced minimum',
    () async {
      manager.respond = (call) => offer('${call.amount}', gas: '0.02');
      final max = (await maximum(source()))!;
      expect(manager.quotes.map((call) => call.amount), [d('0.98'), d('0.96')]);
      expect(max.amount, d('0.96'));
      expect(max.reservedForFees, d('0.04'));
      expect(max.quote!.requiredGasBalance, d('0.02'));
    },
  );

  test('falling fees never increase the proposed principal', () async {
    manager.respond = (call) => offer('${call.amount}', gas: '0.005');
    final max = (await maximum(source()))!;
    expect(max.amount, d('0.98'));
    expect(max.reservedForFees, d('0.02'));
    expect(manager.quotes, hasLength(1));
  });

  test(
    'changing fees stop after three exact quotes without returning a fallback',
    () async {
      manager.respond = (call) => offer(
        '${call.amount}',
        gas: '${d('0.01') * d('${manager.quotes.length + 1}')}',
      );
      await expectLater(
        maximum(source()),
        unavailable(SwapQuoteFailureKind.serviceError),
      );
      expect(manager.quotes, hasLength(3));
    },
  );

  for (final missingInMax in [true, false]) {
    test('missing funding fails closed, max=$missingInMax', () async {
      if (missingInMax) {
        manager.maximum = offerOf(sell: '0.99');
      } else {
        manager.respond = (call) => offerOf(sell: '${call.amount}');
      }
      await expectLater(
        maximum(source()),
        unavailable(SwapQuoteFailureKind.serviceError),
      );
      expect(manager.quotes, hasLength(missingInMax ? 0 : 1));
    });
  }

  test(
    'insufficient room for the reserve does not quote zero or full balance',
    () async {
      manager.maximum = offer('0.005');
      await expectLater(
        maximum(source()),
        unavailable(SwapQuoteFailureKind.serviceError),
      );
      expect(manager.quotes, isEmpty);
    },
  );

  test(
    'provider minimum failure is preserved instead of increasing amount',
    () async {
      manager.quoteError = const RoutedSwapNoRouteException(
        message: 'below provider minimum',
      );
      await expectLater(
        maximum(source()),
        unavailable(SwapQuoteFailureKind.noRoute),
      );
      expect(manager.quotes, hasLength(1));
    },
  );

  test(
    'rate limiting during repricing pauses the whole quote source',
    () async {
      manager.quoteError = const RoutedSwapRateLimitedException(
        message: 'quota',
      );
      final routed = source();
      await expectLater(
        maximum(routed),
        unavailable(SwapQuoteFailureKind.rateLimited),
      );
      await expectLater(
        maximum(routed),
        unavailable(SwapQuoteFailureKind.rateLimited),
      );
      expect(manager.maxCalls, 1);
      expect(manager.quotes, hasLength(1));
    },
  );

  test(
    'exact amount and token Max do not apply native reserve policy',
    () async {
      final routed = source();
      await routed.quote(
        SwapQuoteRequest(from: eth, to: usdc, amount: d('0.5')),
      );
      expect(manager.maxCalls, 0);
      expect(manager.quotes.single.amount, d('0.5'));
      manager.maximum = offerOf(from: usdc, to: eth, sell: '123');
      final max = (await routed.maxAmount(
        from: usdc,
        to: eth,
        balance: d('123'),
      ))!;
      expect(max.amount, d('123'));
      expect(max.quote!.maxRetainedBalance, isNull);
      expect(manager.quotes, hasLength(1));
    },
  );

  test(
    'Max refresh uses a new budget and alternatives use its reduced amount',
    () async {
      final routed = source();
      await maximum(routed);
      now = now.add(const Duration(seconds: 16));
      manager.maximum = offer('0.89');
      final result = await routed.quote(
        SwapQuoteRequest(
          from: eth,
          to: usdc,
          amount: d('0.98'),
          maxSource: SwapLiquiditySource.routed,
          orders: {SwapQuoteOrder.cheapest, SwapQuoteOrder.fastest},
        ),
      );
      expect(manager.maxCalls, 2);
      expect(manager.quotes.last.amount, d('0.88'));
      expect(
        (result.first as SwapQuoteAvailable).quote.maxRetainedBalance,
        d('0.02'),
      );
    },
  );

  test(
    'fresh quote supplies the minimum and gas costs, not the Max probe',
    () async {
      manager.maximum = offerOf(
        sell: '0.99',
        guaranteed: '999',
        networkFees: offer('0.99').networkFees,
      );
      final max = (await maximum(source()))!;
      expect(max.quote!.guaranteedReceive, d('123.456'));
      final accepted = max.quote!.payload! as RoutedSwapOffer;
      expect(accepted.route.toMinimum.amount, '123.456');
      expect(accepted.route.from.amount, '0.98');
    },
  );

  test(
    'included fees are not reserved twice; additional fees are covered',
    () async {
      manager.respond = (call) => offerOf(
        sell: '${call.amount}',
        networkFees: offer('${call.amount}').networkFees,
        costs: [
          RoutedSwapCost(
            label: 'included',
            amount: d('0.05'),
            kind: RoutedSwapCostKind.providerFee,
            isDeductedFromReceive: true,
            assetId: eth,
          ),
          RoutedSwapCost(
            label: 'on top',
            amount: d('0.003'),
            kind: RoutedSwapCostKind.providerFee,
            isDeductedFromReceive: false,
            assetId: eth,
          ),
        ],
      );
      final max = (await maximum(source()))!;
      expect(manager.quotes.map((c) => c.amount), [d('0.98'), d('0.977')]);
      expect(max.reservedForFees, d('0.023'));
      expect(max.quote!.fundingOnTopIn(eth), d('0.013'));
      expect(max.quote!.costOnTopIn(eth), d('0.003'));
    },
  );

  test(
    'incorrect principal in an exact response cannot reach review',
    () async {
      manager.respond = (_) => offer('0.99');
      await expectLater(
        maximum(source()),
        unavailable(SwapQuoteFailureKind.serviceError),
      );
      expect(manager.quotes, hasLength(1));
    },
  );

  test(
    'amounts use decimal arithmetic through the smallest native unit',
    () async {
      manager.maximum = offer('0.006123456789012345', gas: '0.00004');
      manager.respond = (call) => offerOf(
        sell: '${call.amount}',
        networkFees: [
          RoutedSwapNetworkFee(
            ticker: eth.id,
            assetId: eth,
            amount: d('0.00002'),
            requiredBalance: d('0.00004'),
          ),
        ],
      );
      // The initial estimate must be below its required funding.
      manager.maximum = offerOf(
        sell: '0.006123456789012345',
        networkFees: manager
            .respond!((
              from: eth,
              to: usdc,
              amount: d('1'),
              slippage: null,
              order: null,
            ))
            .networkFees,
      );
      final max = (await maximum(source()))!;
      expect(max.amount, d('0.006083456789012345'));
      expect(max.reservedForFees, d('0.00008'));
      expect(max.amount + max.reservedForFees, d('0.006163456789012345'));
    },
  );

  test('late exact reply after timeout cannot trigger a second reduction', () {
    fakeAsync((async) {
      manager.quoteGate = Completer<RoutedSwapOffer>();
      Object? failure;
      maximum(source()).then<void>(
        (_) => fail('unexpected Max'),
        onError: (Object error) {
          failure = error;
        },
      );
      async.flushMicrotasks();
      expect(manager.quotes, hasLength(1));
      async.elapse(const Duration(seconds: 4));
      expect(failure, isA<SwapMaxUnavailableException>());
      manager.quoteGate!.complete(offer('0.98', gas: '0.02'));
      async.flushMicrotasks();
      expect(manager.quotes, hasLength(1));
    });
  });

  test('a late Max response cannot start repricing after timeout', () {
    fakeAsync((async) {
      manager.maxGate = Completer<RoutedSwapOffer>();
      Object? failure;
      maximum(source()).then<void>(
        (_) => fail('unexpected Max'),
        onError: (Object error) {
          failure = error;
        },
      );
      async.elapse(const Duration(seconds: 4));
      expect(failure, isA<SwapMaxUnavailableException>());
      manager.maxGate!.complete(offer('0.99'));
      async.flushMicrotasks();
      expect(manager.quotes, isEmpty);
    });
  });
}

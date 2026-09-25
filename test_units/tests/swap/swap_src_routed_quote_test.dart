import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/routed_swap_source.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

import 'swap_src_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers how the aggregator is asked for prices: which route, at which
/// slippage, how alternatives are merged, how its errors read, and how its
/// small request budget is spent.
void main() {
  late SrcRoutedSwaps manager;
  late DateTime clock;

  setUp(() {
    manager = SrcRoutedSwaps();
    clock = DateTime(2026, 9, 24, 12);
  });

  RoutedSwapQuoteSource source({
    bool Function(AssetId from, AssetId to)? tradingAllowed,
    Duration timeout = const Duration(seconds: 20),
  }) => RoutedSwapQuoteSource(
    manager,
    networks: () => SwapNetworks([eth, usdc]),
    tradingAllowed: tradingAllowed,
    timeout: timeout,
    now: () => clock,
  );

  SwapQuoteRequest request({
    String amount = '1',
    Set<SwapQuoteOrder> orders = const {SwapQuoteOrder.cheapest},
    double? slippage,
  }) => SwapQuoteRequest(
    from: eth,
    to: usdc,
    amount: d(amount),
    orders: orders,
    slippage: slippage,
  );

  SwapQuote available(SwapQuoteResult result) =>
      (result as SwapQuoteAvailable).quote;

  SwapQuoteFailure failure(SwapQuoteResult result) =>
      (result as SwapQuoteRejected).failure;

  group('asking the aggregator', () {
    test('the cheapest route is asked at KDF\'s default slippage', () async {
      final [result] = await source().quote(request());

      expect(manager.quotes.single, (
        from: eth,
        to: usdc,
        amount: d('1'),
        slippage: 0.005,
        order: null,
      ));
      expect(available(result).id, 'routed-cheapest');
      expect(available(result).order, SwapQuoteOrder.cheapest);
    });

    test(
      'the fastest route is asked for by name, at the chosen slippage',
      () async {
        final [result] = await source().quote(
          request(orders: {SwapQuoteOrder.fastest}, slippage: 0.01),
        );

        expect(manager.quotes.single.order, RoutedSwapOrder.fastest);
        expect(manager.quotes.single.slippage, 0.01);
        expect(available(result).id, 'routed-fastest');
        expect(available(result).order, SwapQuoteOrder.fastest);
      },
    );

    test('a request naming no route prices the cheapest', () async {
      final results = await source().quote(request().withOrders(const {}));

      expect(results, hasLength(1));
      expect(manager.quotes.single.order, isNull);
    });

    test('a trading restriction answers without asking', () async {
      final [result] = await source(
        tradingAllowed: (from, to) => false,
      ).quote(request());

      expect(failure(result).kind, SwapQuoteFailureKind.tradingBlocked);
      expect(failure(result).source, SwapLiquiditySource.routed);
      expect(manager.quotes, isEmpty);
    });

    test('an allowed pair is asked as usual', () async {
      await source(tradingAllowed: (from, to) => true).quote(request());

      expect(manager.quotes, hasLength(1));
    });
  });

  group('alternatives', () {
    final both = {SwapQuoteOrder.cheapest, SwapQuoteOrder.fastest};

    test('the same route under two orders is one option', () async {
      final results = await source().quote(request(orders: both));

      expect(manager.quotes, hasLength(2));
      expect(results.map((r) => available(r).id), ['routed-cheapest']);
    });

    test('different tools are separate options', () async {
      manager.respond = (call) => offerOf(
        toolKey: call.order == RoutedSwapOrder.fastest ? 'fast' : 'tool',
      );

      final results = await source().quote(request(orders: both));

      expect(results.map((r) => available(r).id), [
        'routed-cheapest',
        'routed-fastest',
      ]);
    });

    test('the same tool at another minimum is another option', () async {
      manager.respond = (call) => offerOf(
        guaranteed: call.order == RoutedSwapOrder.fastest ? '2970' : '2985',
      );

      final results = await source().quote(request(orders: both));

      expect(results.map((r) => available(r).guaranteedReceive), [
        d('2985'),
        d('2970'),
      ]);
    });

    test('a failed alternative is dropped when another route priced', () async {
      manager.respond = (call) => call.order == RoutedSwapOrder.fastest
          ? throw const RoutedSwapNoRouteException(message: 'no fast route')
          : offerOf();

      final results = await source().quote(request(orders: both));

      expect(results.map((r) => available(r).id), ['routed-cheapest']);
    });

    test('when every route fails, the first failure explains it', () async {
      manager.respond = (call) => call.order == RoutedSwapOrder.fastest
          ? throw const RoutedSwapTransportException(detail: 'x', message: 'x')
          : throw const RoutedSwapNoRouteException(message: 'no route');

      final [result] = await source().quote(request(orders: both));

      expect(failure(result).kind, SwapQuoteFailureKind.noRoute);
    });
  });

  group('errors', () {
    test('a typed contract error becomes its entry state', () async {
      manager.quoteError = const RoutedSwapPairNotSupportedException(
        from: 'ETH',
        to: 'USDC-ERC20',
        reason: 'not listed',
        message: 'pair not supported',
      );

      final [result] = await source().quote(request());

      expect(failure(result).kind, SwapQuoteFailureKind.pairUnsupported);
      expect(failure(result).detail, 'PairNotSupported: pair not supported');
    });

    test('an unexpected error is unknown, and kept for support', () async {
      manager.quoteError = StateError('socket closed');

      final [result] = await source().quote(request());

      expect(failure(result).kind, SwapQuoteFailureKind.unknown);
      expect(failure(result).detail, contains('socket closed'));
    });

    test('a quote that takes too long times out', () async {
      manager.hangQuotes = true;

      final [result] = await source(timeout: Duration.zero).quote(request());

      expect(failure(result).kind, SwapQuoteFailureKind.timeout);
      expect(failure(result).source, SwapLiquiditySource.routed);
    });
  });

  group('the request budget', () {
    test('an identical request within 15 seconds reuses the reply', () async {
      manager.respond = (call) => offerOf(quotedAt: clock);
      final routed = source();
      final [first] = await routed.quote(request());
      clock = clock.add(const Duration(seconds: 15));
      final [again] = await routed.quote(request());

      expect(manager.quotes, hasLength(1));
      expect(available(again).quotedAt, available(first).quotedAt);

      clock = clock.add(const Duration(seconds: 1));
      await routed.quote(request());
      await routed.quote(request(amount: '2'));
      expect(manager.quotes, hasLength(3));
    });

    test('a rate limit pauses every request until it passes', () async {
      manager.quoteError = const RoutedSwapRateLimitedException(
        message: 'slow down',
        providerRequestId: 'req-9',
      );
      final routed = source();

      final [limited] = await routed.quote(request());
      final [waiting] = await routed.quote(request(amount: '3'));

      final until = clock.add(const Duration(seconds: 30));
      expect(failure(limited).kind, SwapQuoteFailureKind.rateLimited);
      expect(failure(limited).retryAt, until);
      expect(failure(limited).providerRequestId, 'req-9');
      expect(failure(limited).detail, 'RateLimited: slow down');
      expect(failure(waiting).kind, SwapQuoteFailureKind.rateLimited);
      expect(failure(waiting).retryAt, until);
      expect(manager.quotes, hasLength(1));

      clock = until;
      manager.quoteError = null;
      final [after] = await routed.quote(request());
      expect(after, isA<SwapQuoteAvailable>());
      expect(manager.quotes, hasLength(2));
    });

    test('each limit in a row waits twice as long, up to 10 minutes', () async {
      manager.quoteError = const RoutedSwapRateLimitedException(message: 'x');
      final routed = source();
      final waits = <int>[];

      for (var i = 0; i < 7; i++) {
        final [result] = await routed.quote(request());
        final retryAt = failure(result).retryAt!;
        waits.add(retryAt.difference(clock).inSeconds);
        clock = retryAt;
      }

      expect(waits, [30, 60, 120, 240, 480, 600, 600]);
    });

    test('a reply resets the wait to its shortest', () async {
      final routed = source();
      manager.quoteError = const RoutedSwapRateLimitedException(message: 'x');
      await routed.quote(request());
      clock = clock.add(const Duration(seconds: 30));
      manager.quoteError = null;
      await routed.quote(request());

      manager.quoteError = const RoutedSwapRateLimitedException(message: 'x');
      final [result] = await routed.quote(request(amount: '2'));

      expect(failure(result).retryAt, clock.add(const Duration(seconds: 30)));
    });
  });

  group('requote', () {
    test('asks again for the quote\'s own route and slippage', () async {
      final fast = routedQuoteFromOffer(
        offerOf(order: RoutedSwapOrder.fastest, slippage: 0.02),
        networks: SwapNetworks([eth, usdc]),
      );

      final result = await source().requote(fast);

      expect(manager.quotes.single.order, RoutedSwapOrder.fastest);
      expect(manager.quotes.single.slippage, 0.02);
      expect(available(result).order, SwapQuoteOrder.fastest);
    });

    test(
      'a quote naming neither is asked as cheapest, at the default',
      () async {
        await source().requote(quoteOf(order: null, sell: '2'));

        expect(manager.quotes.single, (
          from: eth,
          to: usdc,
          amount: d('2'),
          slippage: 0.005,
          order: null,
        ));
      },
    );
  });
}

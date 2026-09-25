import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

import 'swap_bloc_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers comparing routes: the fastest route is priced only once someone
/// opens a comparison, only when there is something to compare, and never
/// for an intent the user has left.
void main() {
  SwapQuoteResult route(
    SwapBlocHarness h,
    SwapQuoteRequest request,
    SwapQuoteOrder order, {
    String? minimum,
  }) => SwapQuoteAvailable(
    quoteOf(
      id: order.name,
      order: order,
      sell: request.amount.toString(),
      guaranteed:
          minimum ?? (order == SwapQuoteOrder.fastest ? '2980' : '2985'),
      quotedAt: h.now(),
    ),
  );

  /// Answers only the orders asked for.
  void offerAsked(SwapBlocHarness h, {String? fastMinimum}) {
    h.routed.respond = (request) => [
      for (final order in request.orders)
        route(
          h,
          request,
          order,
          minimum: order == SwapQuoteOrder.fastest ? fastMinimum : null,
        ),
    ];
  }

  swapBlocTest('adds the fastest route once, ranked with the rest', (h) {
    offerAsked(h);
    final bloc = h.open();
    final states = h.record(bloc);
    bloc.add(const UnifiedSwapAlternativesRequested());
    h.settle();

    expect(states.first.checkingAlternatives, isTrue);
    expect(bloc.state.checkingAlternatives, isFalse);
    expect(h.routed.requests.last.orders, {SwapQuoteOrder.fastest});
    expect(bloc.state.options.map((q) => q.id), ['cheapest', 'fastest']);
    expect(bloc.state.selectedId, 'cheapest');

    bloc.add(const UnifiedSwapAlternativesRequested());
    h.settle();
    expect(h.routed.requests, hasLength(2));
  });

  swapBlocTest('asked for before prices arrive, it comes with them', (h) {
    offerAsked(h);
    final bloc = h.open(
      bloc: h.build(debounce: const Duration(milliseconds: 500)),
    )..add(const UnifiedSwapAmountChanged('0.5'));
    h.settle();
    bloc.add(const UnifiedSwapAlternativesRequested());
    h.elapse(const Duration(milliseconds: 500));

    expect(h.routed.requests, hasLength(2));
    expect(h.routed.requests.last.orders, {
      SwapQuoteOrder.cheapest,
      SwapQuoteOrder.fastest,
    });
    expect(bloc.state.options.map((q) => q.id), ['cheapest', 'fastest']);
  });

  swapBlocTest('an order-book price alone has nothing to compare', (h) {
    h.routed
      ..respond = null
      ..results = [rejected(SwapQuoteFailureKind.noRoute)];
    h.atomic.results = [
      SwapQuoteAvailable(
        quoteOf(
          id: 'book',
          source: SwapLiquiditySource.atomic,
          routeKind: SwapRouteKind.direct,
          order: null,
          quotedAt: h.now(),
        ),
      ),
    ];
    final bloc = h.open()..add(const UnifiedSwapAlternativesRequested());
    h.settle();

    expect(h.routed.requests, hasLength(1));
    expect(bloc.state.checkingAlternatives, isFalse);
    expect(bloc.state.options.single.id, 'book');
  });

  swapBlocTest('options that include the fastest route need nothing', (h) {
    h.routed.respond = (request) => [
      for (final order in SwapQuoteOrder.values) route(h, request, order),
    ];
    final bloc = h.open()..add(const UnifiedSwapAlternativesRequested());
    h.settle();

    expect(h.routed.requests, hasLength(1));
    expect(bloc.state.options, hasLength(2));
  });

  swapBlocTest('a fastest route that is the cheapest one is not repeated', (h) {
    offerAsked(h, fastMinimum: '2985');
    final bloc = h.open()..add(const UnifiedSwapAlternativesRequested());
    h.settle();

    expect(h.routed.requests, hasLength(2));
    expect(bloc.state.options.map((q) => q.id), ['cheapest']);
    expect(bloc.state.checkingAlternatives, isFalse);
  });

  swapBlocTest('alternatives that take too long add nothing', (h) {
    offerAsked(h);
    final bloc = h.open();
    h.routed.gate = Completer<void>();
    bloc.add(const UnifiedSwapAlternativesRequested());
    h.elapse(const Duration(seconds: 24));
    expect(bloc.state.checkingAlternatives, isTrue);

    h.elapse(const Duration(seconds: 1));

    expect(bloc.state.checkingAlternatives, isFalse);
    expect(bloc.state.options.map((q) => q.id), ['cheapest']);
  });

  swapBlocTest('alternatives for an amount since changed are dropped', (h) {
    offerAsked(h);
    final bloc = h.open();
    h.routed.gate = Completer<void>();
    bloc.add(const UnifiedSwapAlternativesRequested());
    h.settle();
    bloc.add(const UnifiedSwapAmountChanged('0.5'));
    h.settle();

    h.routed.gate!.complete();
    h.routed.gate = null;
    h.settle();

    expect(bloc.state.checkingAlternatives, isFalse);
    expect(bloc.state.options.map((q) => q.id), ['cheapest']);
    expect(bloc.state.selectedQuote!.sellAmount, d('0.5'));
  });
}

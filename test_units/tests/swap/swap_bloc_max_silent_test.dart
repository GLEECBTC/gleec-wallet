import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

import 'swap_bloc_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers Max when the order book never answers: beside another source it
/// is given the form's 25 s for one price, then whatever the other answered
/// is applied.
void main() {
  const budget = Duration(seconds: 25);

  SwapMaxAmount maxOf(String amount) =>
      SwapMaxAmount(amount: d(amount), reservedForFees: d('0.01'));

  swapBlocTest('an order book that never answers leaves the routed Max', (h) {
    h.routed
      ..respond = null
      ..results = [rejected(SwapQuoteFailureKind.noRoute)]
      ..max = maxOf('1.99');
    h.atomic
      ..max = maxOf('1.995')
      ..maxGate = Completer<void>();
    final bloc = h.open();
    expect(bloc.state.selectedQuote, isNull);

    bloc.add(const UnifiedSwapMaxRequested());
    h.elapse(budget);

    expect(bloc.state.checkingMax, isFalse);
    expect(bloc.state.inputText, '1.99');
    expect(bloc.state.maxApplied, maxOf('1.99'));
  });

  swapBlocTest('a selected but silent order book leaves the routed Max', (h) {
    h.routed.max = maxOf('1.99');
    h.atomic
      ..max = maxOf('1.995')
      ..maxGate = Completer<void>()
      ..respond = (request) => [
        SwapQuoteAvailable(
          quoteOf(
            id: 'atomic',
            source: SwapLiquiditySource.atomic,
            routeKind: SwapRouteKind.direct,
            from: request.from,
            to: request.to,
            sell: request.amount.toString(),
            guaranteed: '2995',
            quotedAt: h.now(),
          ),
        ),
      ];
    final bloc = h.open()..add(const UnifiedSwapOptionSelected('atomic'));
    h.settle();
    expect(bloc.state.selectedQuote!.source, SwapLiquiditySource.atomic);

    bloc.add(const UnifiedSwapMaxRequested());
    h.elapse(budget);

    expect(bloc.state.checkingMax, isFalse);
    expect(bloc.state.inputText, '1.99');
    expect(bloc.state.maxApplied, maxOf('1.99'));
  });
}

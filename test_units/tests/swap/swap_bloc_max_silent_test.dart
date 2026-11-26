import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/views/swap/common/swap_failure_copy.dart';

import 'swap_bloc_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers Max when the order book never answers: beside another source it
/// is given the form's 25 s for one price, then whatever the other answered
/// is applied, or both reasons are told.
///
/// Without a loaded translation, copy renders as its key, so these assert
/// which message was chosen rather than its English.
void main() {
  const budget = Duration(seconds: 25);

  SwapMaxAmount maxOf(String amount) =>
      SwapMaxAmount(amount: d(amount), reservedForFees: d('0.01'));

  /// What the form says about the failure the bloc is showing.
  String copyOf(UnifiedSwapBloc bloc) => SwapFailureCopy.of(
    bloc.state.failure!,
    bloc.state.pay,
    receive: bloc.state.receive,
    all: bloc.state.failures,
  ).message;

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

  group('a silent order book is told beside the aggregator\'s answer', () {
    for (final (kind, copy) in [
      (SwapQuoteFailureKind.noRoute, LocaleKeys.swapErrorNoRouteCrossNetwork),
      (
        SwapQuoteFailureKind.rateLimited,
        LocaleKeys.swapErrorRateLimitedBookUnchecked,
      ),
    ]) {
      swapBlocTest('when that is ${kind.name}', (h) {
        h.routed.maxError = SwapMaxUnavailableException(
          SwapQuoteFailure(source: SwapLiquiditySource.routed, kind: kind),
        );
        h.atomic.maxGate = Completer<void>();
        final bloc = h.open()..add(const UnifiedSwapMaxRequested());
        h.elapse(budget);

        expect(bloc.state.checkingMax, isFalse);
        expect(bloc.state.evaluation, SwapEvaluationStatus.failed);
        expect(bloc.state.failure!.kind, kind);
        expect(
          bloc.state.failures.map((f) => (f.source, f.kind)),
          containsAll([
            (SwapLiquiditySource.routed, kind),
            (SwapLiquiditySource.atomic, SwapQuoteFailureKind.timeout),
          ]),
        );
        expect(copyOf(bloc), copy);
      });
    }
  });
}

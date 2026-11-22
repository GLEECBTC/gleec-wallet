import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

import 'swap_bloc_fakes.dart';
import 'swap_test_fixtures.dart';

void main() {
  swapBlocTest('first quote is usable while another source is outstanding', (
    h,
  ) {
    final slower = h.atomic.gate = Completer<void>();
    h.atomic.results = [
      SwapQuoteAvailable(
        quoteOf(
          id: 'better-later',
          source: SwapLiquiditySource.atomic,
          expected: '3200',
          guaranteed: '3190',
        ),
      ),
    ];
    final bloc = h.open();
    expect(bloc.state.selectedId, 'routed-1');
    expect(bloc.state.quotesPending, isTrue);
    expect(bloc.state.canReview, isTrue);
    expect(bloc.state.quotes!.canClaimBestNetReturn, isFalse);
    slower.complete();
    h.settle();
    expect(bloc.state.selectedId, 'routed-1');
    expect(bloc.state.quotes!.byId('better-later'), isNotNull);
    expect(bloc.state.quotesPending, isFalse);
    expect(bloc.state.pricingPending, isFalse);
  });

  swapBlocTest('a late comparison cannot replace the open review', (h) {
    final slower = h.atomic.gate = Completer<void>();
    h.atomic.results = [
      SwapQuoteAvailable(
        quoteOf(
          id: 'later',
          source: SwapLiquiditySource.atomic,
          expected: '3200',
          guaranteed: '3190',
        ),
      ),
    ];
    final bloc = h.inReview();
    expect(bloc.state.review!.quote.id, 'routed-1');
    slower.complete();
    h.settle();
    expect(bloc.state.view, UnifiedSwapView.review);
    expect(bloc.state.review!.quote.id, 'routed-1');
    expect(bloc.state.quotesPending, isFalse);
  });

  swapBlocTest('late replies for an edited amount cannot replace its quote', (
    h,
  ) {
    final previous = h.atomic.gate = Completer<void>();
    final bloc = h.open();
    h.atomic.gate = null;
    bloc.add(const UnifiedSwapAmountChanged('0.5'));
    h.settle();
    expect(bloc.state.selectedQuote!.sellAmount, d('0.5'));
    previous.complete();
    h.settle();
    expect(bloc.state.inputText, '0.5');
    expect(bloc.state.selectedQuote!.sellAmount, d('0.5'));
  });

  group('a Review asked for while its terms are read', () {
    swapBlocTest('opens on the same offer once another source has arrived', (
      h,
    ) {
      final slower = h.atomic.gate = Completer<void>();
      h.atomic.results = [
        SwapQuoteAvailable(
          quoteOf(
            id: 'later',
            source: SwapLiquiditySource.atomic,
            expected: '3200',
            guaranteed: '3190',
          ),
        ),
      ];
      final bloc = h.open();
      final tapped = bloc.state.selectedQuote!;
      h.termsGate = Completer<void>();
      bloc.add(const UnifiedSwapReviewOpened());
      h.settle();
      expect(bloc.state.view, UnifiedSwapView.form);

      // Every arrival prices the options again, as new instances.
      slower.complete();
      h.settle();
      expect(bloc.state.selectedQuote, isNot(same(tapped)));
      h.termsGate!.complete();
      h.settle();

      expect(bloc.state.view, UnifiedSwapView.review);
      expect(bloc.state.review!.quote.id, tapped.id);
      expect(bloc.state.review!.quote.quotedAt, tapped.quotedAt);
      expect(
        bloc.state.review!.quote.guaranteedReceive,
        tapped.guaranteedReceive,
      );
    });

    swapBlocTest('never opens on terms priced since the tap', (h) {
      final bloc = h.open();
      h.termsGate = Completer<void>();
      bloc.add(const UnifiedSwapReviewOpened());
      h.settle();

      // The same option id, at a lower minimum than the one tapped.
      h.routed.respond = (request) => [
        SwapQuoteAvailable(
          quoteOf(
            id: 'routed-${request.amount}',
            sell: '${request.amount}',
            guaranteed: '2900',
            quotedAt: h.now(),
          ),
        ),
      ];
      bloc.add(const UnifiedSwapEvaluationRequested(quiet: true));
      h.settle();
      expect(bloc.state.selectedQuote!.guaranteedReceive, d('2900'));
      h.termsGate!.complete();
      h.settle();

      expect(bloc.state.view, UnifiedSwapView.form);
      expect(bloc.state.review, isNull);
    });
  });
}

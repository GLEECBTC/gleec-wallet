import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

import 'swap_bloc_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers pricing the form: debounced, bounded in time, kept fresh without
/// ever letting a failed refresh or a stale answer replace what is shown.
void main() {
  /// Offers one routed option per id, the first the best.
  void offer(SwapBlocHarness h, List<String> ids) {
    h.routed.respond = (request) => [
      for (final (i, id) in ids.indexed)
        SwapQuoteAvailable(
          quoteOf(
            id: id,
            from: request.from,
            to: request.to,
            sell: request.amount.toString(),
            guaranteed: '${2985 - i * 5}',
            quotedAt: h.now(),
          ),
        ),
    ];
  }

  SwapQuoteResult rateLimited({DateTime? retryAt}) => SwapQuoteRejected(
    SwapQuoteFailure(
      source: SwapLiquiditySource.routed,
      kind: SwapQuoteFailureKind.rateLimited,
      retryAt: retryAt,
    ),
  );

  swapBlocTest('typing prices only the amount the user settles on', (h) {
    final bloc = h.open(
      bloc: h.build(debounce: const Duration(milliseconds: 500)),
    );
    for (final text in ['0.5', '0.52', '0.525']) {
      bloc.add(UnifiedSwapAmountChanged(text));
      h.elapse(const Duration(milliseconds: 300));
    }
    expect(h.routed.requests, hasLength(1));

    h.elapse(const Duration(milliseconds: 200));

    expect(h.routed.requests.map((r) => r.amount), [d('1'), d('0.525')]);
    expect(bloc.state.selectedQuote!.sellAmount, d('0.525'));
  });

  group('an answer that never comes', () {
    swapBlocTest('fails as a timeout at the time limit', (h) {
      h.routed.gate = Completer<void>();
      final bloc = h.open();
      expect(bloc.state.evaluation, SwapEvaluationStatus.checking);

      h.elapse(const Duration(seconds: 25));

      expect(bloc.state.evaluation, SwapEvaluationStatus.failed);
      expect(
        bloc.state.failure,
        const SwapQuoteFailure(
          source: SwapLiquiditySource.routed,
          kind: SwapQuoteFailureKind.timeout,
        ),
      );
      expect(bloc.state.failures, [bloc.state.failure]);
    });

    swapBlocTest('is ignored once the amount has changed', (h) {
      h.routed.gate = Completer<void>();
      final bloc = h.open();
      h.elapse(const Duration(seconds: 10));
      bloc.add(const UnifiedSwapAmountChanged('0.5'));

      h.elapse(const Duration(seconds: 15));
      expect(bloc.state.evaluation, SwapEvaluationStatus.checking);

      h.elapse(const Duration(seconds: 10));
      expect(bloc.state.evaluation, SwapEvaluationStatus.failed);
    });
  });

  swapBlocTest('sources that answer nothing read as an unknown failure', (h) {
    h.routed.respond = (_) => const [];
    h.atomic.results = const [];
    final bloc = h.open();

    expect(bloc.state.evaluation, SwapEvaluationStatus.failed);
    expect(bloc.state.failure!.kind, SwapQuoteFailureKind.unknown);
  });

  group('choosing an option', () {
    swapBlocTest('a pick survives a refresh while it is still offered', (h) {
      offer(h, ['best', 'other']);
      final bloc = h.open()..add(const UnifiedSwapOptionSelected('other'));
      h.settle();
      expect(bloc.state.manuallySelected, isTrue);

      h.elapse(const Duration(seconds: 30));
      expect(h.routed.requests, hasLength(2));
      expect(bloc.state.selectedId, 'other');
      expect(bloc.state.manuallySelected, isTrue);

      offer(h, ['best']);
      h.elapse(const Duration(seconds: 30));
      expect(bloc.state.selectedId, 'best');
      expect(bloc.state.manuallySelected, isFalse);
    });

    swapBlocTest('an option not on offer cannot be chosen', (h) {
      final unpriced = h.build()
        ..add(const UnifiedSwapOptionSelected('routed-1'));
      final bloc = h.open()..add(const UnifiedSwapOptionSelected('gone'));
      h.settle();

      expect(unpriced.state.selectedId, isNull);
      expect(bloc.state.selectedId, 'routed-1');
    });

    swapBlocTest('choosing the preselected option is not a manual pick', (h) {
      offer(h, ['best', 'other']);
      final bloc = h.open()
        ..add(const UnifiedSwapOptionSelected('other'))
        ..add(const UnifiedSwapOptionSelected('best'));
      h.settle();

      expect(bloc.state.selectedId, 'best');
      expect(bloc.state.manuallySelected, isFalse);
    });

    swapBlocTest('a chosen fastest route is priced again on refresh', (h) {
      h.routed.respond = (request) => [
        SwapQuoteAvailable(quoteOf(id: 'cheap', quotedAt: h.now())),
        SwapQuoteAvailable(
          quoteOf(
            id: 'fast',
            order: SwapQuoteOrder.fastest,
            guaranteed: '2980',
            quotedAt: h.now(),
          ),
        ),
      ];
      final bloc = h.open()..add(const UnifiedSwapOptionSelected('fast'));
      h.elapse(const Duration(seconds: 30));

      expect(h.routed.requests.last.orders, {
        SwapQuoteOrder.cheapest,
        SwapQuoteOrder.fastest,
      });
      expect(bloc.state.selectedId, 'fast');
    });
  });

  group('a refresh that fails', () {
    swapBlocTest('keeps the options already shown', (h) {
      final bloc = h.open();
      final shown = bloc.state.selectedQuote;
      h.routed
        ..respond = null
        ..results = [rejected(SwapQuoteFailureKind.serviceError)];

      h.elapse(const Duration(seconds: 30));

      expect(h.routed.requests, hasLength(2));
      expect(bloc.state.evaluation, SwapEvaluationStatus.ready);
      expect(bloc.state.selectedQuote, shown);
      expect(bloc.state.failure, isNull);
    });

    swapBlocTest('on a rate limit pauses, and lets the options expire', (h) {
      final bloc = h.open();
      h.routed
        ..respond = null
        ..results = [rateLimited()];

      h.elapse(const Duration(seconds: 30));
      expect(bloc.state.rateLimitedUntil, h.start.add(SwapQuote.lifetime));
      expect(bloc.state.selectedQuote, isNotNull);

      h.elapse(const Duration(seconds: 30));
      expect(h.routed.requests, hasLength(2));
      expect(bloc.state.rateLimitedUntil, isNull);
      expect(bloc.state.evaluation, SwapEvaluationStatus.expired);
    });
  });

  group('a rate limit', () {
    swapBlocTest('is waited out until the time the source gives', (h) {
      final retryAt = h.start.add(const Duration(seconds: 90));
      h.routed.respond = (_) => [rateLimited(retryAt: retryAt)];
      final bloc = h.open();
      expect(bloc.state.evaluation, SwapEvaluationStatus.failed);
      expect(bloc.state.rateLimitedUntil, retryAt);

      h.routed.respond = h.priced;
      h.elapse(const Duration(seconds: 89));
      expect(h.routed.requests, hasLength(1));

      h.elapse(const Duration(seconds: 1));
      expect(h.routed.requests, hasLength(2));
      expect(bloc.state.evaluation, SwapEvaluationStatus.ready);
      expect(bloc.state.rateLimitedUntil, isNull);
    });

    swapBlocTest('whose retry time has passed is retried at once', (h) {
      final past = h.start.subtract(const Duration(seconds: 1));
      var calls = 0;
      h.routed.respond = (request) =>
          calls++ == 0 ? [rateLimited(retryAt: past)] : h.priced(request);
      final bloc = h.open();

      expect(h.routed.requests, hasLength(2));
      expect(bloc.state.evaluation, SwapEvaluationStatus.ready);
    });

    swapBlocTest('that ends while the app is hidden waits for the user', (h) {
      h.routed.respond = (_) => [rateLimited()];
      final bloc = h.open()
        ..add(const UnifiedSwapForegroundChanged(foreground: false));
      h.routed.respond = h.priced;

      h.elapse(const Duration(seconds: 30));

      expect(bloc.state.rateLimitedUntil, isNull);
      expect(h.routed.requests, hasLength(1));
      expect(bloc.state.evaluation, SwapEvaluationStatus.failed);
    });
  });
}

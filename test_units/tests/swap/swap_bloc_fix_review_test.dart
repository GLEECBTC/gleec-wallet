import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

import 'swap_bloc_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers a price checked again in the review: a refresh that finds it
/// unchanged is ready to start, and every price under review, updated
/// numbers included, expires on its own clock and is re-priced before
/// anything starts.
void main() {
  /// A re-price with the numbers first reviewed, priced now.
  SwapQuoteAvailable unchanged(SwapBlocHarness h) =>
      SwapQuoteAvailable(quoteOf(id: 'fresh', quotedAt: h.now()));

  /// A re-price whose lower minimum needs consent, priced now.
  SwapQuoteAvailable lower(SwapBlocHarness h) => SwapQuoteAvailable(
    quoteOf(id: 'lower', guaranteed: '2900', quotedAt: h.now()),
  );

  group('a refresh that finds the price unchanged', () {
    swapBlocTest('is ready, and starting re-prices that price first', (h) {
      final bloc = h.inReview();
      h.elapse(SwapQuote.lifetime);
      h.routed.requoteResult = unchanged(h);
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      expect(bloc.state.review!.status, SwapReviewStatus.ready);
      expect(h.routedExecutor.started, isEmpty);

      bloc.add(const UnifiedSwapStartRequested());
      h.settle();

      expect(h.routed.requoted, hasLength(2));
      expect(h.routedExecutor.started.single.id, 'fresh');
      expect(bloc.state.view, UnifiedSwapView.progress);
    });

    swapBlocTest('expires again a minute after it was priced', (h) {
      final bloc = h.inReview();
      h.elapse(SwapQuote.lifetime);
      h.routed.requoteResult = unchanged(h);
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();

      h.elapse(SwapQuote.lifetime - const Duration(seconds: 1));
      expect(bloc.state.review!.status, SwapReviewStatus.ready);

      h.elapse(const Duration(seconds: 1));
      expect(bloc.state.review!.status, SwapReviewStatus.expired);
      expect(bloc.state.review!.quote.id, 'fresh');
    });

    swapBlocTest('after a refused start clears the refusal, starting nothing', (
      h,
    ) {
      h.routedExecutor.startError = const SwapStartRejectedException(
        SwapStartRejection.quoteStale,
        detail: 'stale',
      );
      final bloc = h.inReview()..add(const UnifiedSwapStartRequested());
      h.settle();
      expect(bloc.state.review!.status, SwapReviewStatus.rejected);

      h.routed.requoteResult = unchanged(h);
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();

      expect(bloc.state.review!.status, SwapReviewStatus.ready);
      expect(bloc.state.review!.rejectionDetail, isNull);
      expect(h.routedExecutor.started, hasLength(1));
    });

    swapBlocTest('after a failed re-price keeps the terms to accept', (h) {
      final bloc = h.inReview();
      h.routed.requoteResult = rejected(SwapQuoteFailureKind.serviceError);
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      expect(bloc.state.review!.status, SwapReviewStatus.revalidationFailed);

      h.routed.requoteResult = unchanged(h);
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();

      expect(bloc.state.review!.status, SwapReviewStatus.ready);
      expect(bloc.state.review!.termsRequired, isTrue);
      expect(h.routedExecutor.started, isEmpty);
    });
  });

  group('updated numbers', () {
    swapBlocTest('accepted current updates revalidate before one start', (h) {
      final bloc = h.inReview();
      final original = bloc.state.review!.quote;
      final update = lower(h);
      h.routed.requoteResult = update;
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      expect(bloc.state.review!.status, SwapReviewStatus.materialUpdate);
      final acceptedUpdate = bloc.state.review!.quote;
      expect(h.routedExecutor.started, isEmpty);
      h.elapse(SwapQuote.lifetime - const Duration(seconds: 1));

      // Accepting the displayed update still refreshes executable funding
      // and quote validity; it never submits the earlier transaction blindly.
      final refreshed = lower(h);
      h.routed.requoteResult = refreshed;
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();

      expect(h.routed.requoted, [original, acceptedUpdate]);
      final submitted = h.routedExecutor.started.single;
      expect(submitted.id, refreshed.quote.id);
      expect(submitted.quotedAt, refreshed.quote.quotedAt);
      expect(submitted.guaranteedReceive, acceptedUpdate.guaranteedReceive);
      expect(bloc.state.view, UnifiedSwapView.progress);
    });

    swapBlocTest('expire a minute after they were priced', (h) {
      final bloc = h.inReview();
      h.elapse(const Duration(seconds: 30));
      h.routed.requoteResult = lower(h);
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();

      h.elapse(const Duration(seconds: 59));
      expect(bloc.state.review!.status, SwapReviewStatus.materialUpdate);

      h.elapse(const Duration(seconds: 1));
      expect(bloc.state.review!.status, SwapReviewStatus.expired);
      expect(bloc.state.review!.canStart, isFalse);
    });

    swapBlocTest('once expired are refreshed against the numbers agreed', (h) {
      final bloc = h.inReview();
      final agreed = bloc.state.review!.quote;
      h.routed.requoteResult = lower(h);
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      h.elapse(SwapQuote.lifetime);

      h.routed.requoteResult = unchanged(h);
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();

      expect(h.routed.requoted, [agreed, agreed]);
      expect(bloc.state.review!.status, SwapReviewStatus.ready);
      expect(bloc.state.review!.previous, isNull);
      expect(h.routedExecutor.started, isEmpty);
    });

    swapBlocTest('accepted after they went stale unseen are re-priced', (h) {
      final bloc = h.inReview();
      h.routed.requoteResult = lower(h);
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      // The device slept past the numbers' minute: no timer has run.
      h.skew = SwapQuote.lifetime;
      expect(bloc.state.review!.status, SwapReviewStatus.materialUpdate);

      h.routed.requoteResult = unchanged(h);
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();

      expect(h.routed.requoted, hasLength(2));
      expect(h.routedExecutor.started.single.id, 'fresh');
    });

    swapBlocTest('stale and moved again ask for consent once more', (h) {
      final bloc = h.inReview();
      h.routed.requoteResult = lower(h);
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      h.skew = SwapQuote.lifetime;

      h.routed.requoteResult = lower(h);
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();

      expect(bloc.state.review!.status, SwapReviewStatus.materialUpdate);
      expect(bloc.state.review!.quote.quotedAt, h.now());
      expect(h.routedExecutor.started, isEmpty);
    });
  });

  group('numbers accepted for a swap the engine stopped', () {
    /// Accepts [agreed] for a routed swap started before, so with the
    /// provider's terms accepted then.
    UnifiedSwapBloc accept(SwapBlocHarness h, SwapQuote agreed) {
      h.resolve(h.terms.recordAcceptance(at: h.now()));
      final bloc = h.open()..add(UnifiedSwapFreshQuoteAccepted(agreed));
      h.settle();
      return bloc;
    }

    swapBlocTest('are priced again before they start, as any start is', (h) {
      final agreed = quoteOf(id: 'agreed', quotedAt: h.now());
      final bloc = accept(h, agreed);

      expect(h.routed.requoted, [agreed]);
      expect(h.routedExecutor.started.single.id, 'agreed');
      expect(bloc.state.view, UnifiedSwapView.progress);
    });

    swapBlocTest('that moved again since are asked about once more', (h) {
      h.routed.requoteResult = lower(h);
      final bloc = accept(h, quoteOf(id: 'agreed', quotedAt: h.now()));

      expect(h.routedExecutor.started, isEmpty);
      expect(bloc.state.review!.status, SwapReviewStatus.materialUpdate);
      expect(bloc.state.review!.previous!.id, 'agreed');
    });

    swapBlocTest('the wallet can no longer pay are not started', (h) {
      h.balances[eth] = d('0.5');
      final bloc = accept(h, quoteOf(id: 'agreed', quotedAt: h.now()));

      expect(h.routedExecutor.started, isEmpty);
      expect(bloc.state.review!.status, SwapReviewStatus.revalidationFailed);
      expect(
        bloc.state.review!.revalidationFailure!.kind,
        SwapQuoteFailureKind.insufficientFunds,
      );
    });

    swapBlocTest('for another pair are measured against its own balance', (h) {
      h
        ..balances[btc] = d('0.01')
        ..resolve(h.terms.recordAcceptance(at: h.now()));
      final bloc = h.open(pay: 'BTC', receive: 'ETH', amount: '0.01')
        ..add(
          UnifiedSwapFreshQuoteAccepted(
            quoteOf(id: 'agreed', quotedAt: h.now()),
          ),
        );
      h.settle();

      expect(h.routedExecutor.started.single.id, 'agreed');
      expect(bloc.state.view, UnifiedSwapView.progress);
    });

    swapBlocTest('wait for Start beside terms not accepted yet', (h) {
      final agreed = quoteOf(id: 'agreed', quotedAt: h.now());
      final bloc = h.open()..add(UnifiedSwapFreshQuoteAccepted(agreed));
      h.settle();

      expect(bloc.state.review!.status, SwapReviewStatus.ready);
      expect(bloc.state.review!.termsRequired, isTrue);
      expect(h.routed.requoted, isEmpty);
      expect(h.routedExecutor.started, isEmpty);

      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      expect(h.routed.requoted, [agreed]);
      expect(h.routedExecutor.started.single.id, 'agreed');
    });

    swapBlocTest('once stale open as expired, to be refreshed first', (h) {
      final agreed = quoteOf(id: 'agreed', quotedAt: h.now());
      final bloc = h.open();
      h.elapse(SwapQuote.lifetime);
      bloc.add(UnifiedSwapFreshQuoteAccepted(agreed));
      h.settle();

      expect(bloc.state.view, UnifiedSwapView.review);
      expect(bloc.state.review!.status, SwapReviewStatus.expired);
      expect(h.routedExecutor.started, isEmpty);

      h.routed.requoteResult = unchanged(h);
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();

      expect(h.routed.requoted, [agreed]);
      expect(bloc.state.review!.status, SwapReviewStatus.ready);
    });
  });

  group('the price under review', () {
    swapBlocTest('of an option priced later than the rest keeps its time', (h) {
      h.routed.respond = (request) => [
        SwapQuoteAvailable(
          quoteOf(
            id: 'older',
            quotedAt: h.now().subtract(const Duration(seconds: 20)),
          ),
        ),
        SwapQuoteAvailable(
          quoteOf(id: 'newer', guaranteed: '2980', quotedAt: h.now()),
        ),
      ];
      final bloc = h.open();
      expect(bloc.state.selectedId, 'older');
      bloc
        ..add(const UnifiedSwapOptionSelected('newer'))
        ..add(const UnifiedSwapReviewOpened());
      h.settle();

      h.elapse(const Duration(seconds: 59));
      expect(bloc.state.review!.status, SwapReviewStatus.ready);

      h.elapse(const Duration(seconds: 1));
      expect(bloc.state.review!.status, SwapReviewStatus.expired);
    });

    swapBlocTest('that expires while re-priced is left to the re-price', (h) {
      final bloc = h.inReview();
      h.elapse(const Duration(seconds: 59));
      h.routed
        ..requoteGate = Completer<void>()
        ..requoteResult = unchanged(h);
      bloc.add(const UnifiedSwapStartRequested());
      h.elapse(const Duration(seconds: 1));
      expect(bloc.state.review!.status, SwapReviewStatus.revalidating);

      h.routed.requoteGate!.complete();
      h.settle();

      expect(h.routedExecutor.started.single.id, 'fresh');
    });
  });

  group('the balance the order book says its fees need', () {
    /// [pay] for BTC on the order book, which must hold [required] of [pay]
    /// for a network fee estimated at [fee].
    SwapQuote holding(
      SwapBlocHarness h,
      String required, {
      AssetId? pay,
      String sell = '1',
      String fee = '0.002',
    }) => SwapQuote(
      id: 'book',
      source: SwapLiquiditySource.atomic,
      routeKind: SwapRouteKind.direct,
      from: pay ?? eth,
      to: btc,
      sellAmount: d(sell),
      expectedReceive: d('0.05'),
      guaranteedReceive: d('0.05'),
      fees: [feeOf(amount: fee, usd: null, asset: pay ?? eth)],
      stages: const [],
      requiredFeeBalances: {pay ?? eth: d(required)},
      quotedAt: h.now(),
    );

    /// The review of [quote], the only offer, re-pricing as [fresh].
    UnifiedSwapBloc reviewing(
      SwapBlocHarness h,
      SwapQuote quote,
      SwapQuote fresh,
    ) {
      h.prices.prices[btc] = d('60000');
      h.routed
        ..respond = null
        ..results = [rejected(SwapQuoteFailureKind.noRoute)];
      h.atomic
        ..respond = ((_) => [SwapQuoteAvailable(quote)])
        ..requoteResult = SwapQuoteAvailable(fresh);
      final bloc = h.open(
        pay: quote.from.id,
        receive: 'BTC',
        amount: '${quote.sellAmount}',
      )..add(const UnifiedSwapReviewOpened());
      h.settle();
      expect(bloc.state.review!.quote.requiredFeeBalances, isNotEmpty);
      return bloc;
    }

    swapBlocTest('rising a little with gas starts without asking again', (h) {
      final bloc = reviewing(h, holding(h, '0.0021'), holding(h, '0.00211'))
        ..add(const UnifiedSwapStartRequested());
      h.settle();

      expect(
        h.atomicExecutor.started.single.requiredFeeBalances[eth],
        d('0.00211'),
      );
      expect(bloc.state.view, UnifiedSwapView.progress);
    });

    swapBlocTest('rising by more than costs may drift asks first', (h) {
      final bloc = reviewing(h, holding(h, '0.0021'), holding(h, '0.003'))
        ..add(const UnifiedSwapStartRequested());
      h.settle();

      expect(bloc.state.review!.status, SwapReviewStatus.materialUpdate);
      expect(h.atomicExecutor.started, isEmpty);
    });

    for (final (required, asks) in [('0.000105', false), ('0.00012', true)]) {
      swapBlocTest('in a coin with no price, $required up from 0.0001 '
          '${asks ? 'asks first' : 'starts'}', (h) {
        SwapQuote quote(String needed) =>
            holding(h, needed, pay: gleec, sell: '0.5', fee: '0.0001');
        final bloc = reviewing(h, quote('0.0001'), quote(required))
          ..add(const UnifiedSwapStartRequested());
        h.settle();

        expect(h.atomicExecutor.started, asks ? isEmpty : hasLength(1));
        expect(
          bloc.state.review?.status,
          asks ? SwapReviewStatus.materialUpdate : isNull,
        );
      });
    }

    swapBlocTest('rising a little past what the wallet holds still stops', (h) {
      h.balances[eth] = d('1.0021');
      final bloc = reviewing(h, holding(h, '0.0021'), holding(h, '0.00211'))
        ..add(const UnifiedSwapStartRequested());
      h.settle();

      expect(bloc.state.review!.status, SwapReviewStatus.revalidationFailed);
      expect(
        bloc.state.review!.revalidationFailure!.kind,
        SwapQuoteFailureKind.insufficientFunds,
      );
      expect(h.atomicExecutor.started, isEmpty);
    });
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_order_book_offers.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

import 'swap_bloc_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers a pair only the order book trades: whether anyone offers it is
/// known before an amount, a pair no one offers is checked again until
/// someone does, and an answer is dropped once the form has moved on.
void main() {
  final some = SwapOrderBookOffers([SwapOfferBand(d('0.5'), d('2'))]);
  const none = SwapOrderBookOffers();

  /// Only the order book trades GLEEC, so ETH → GLEEC is its alone.
  void orderBookOnly(SwapBlocHarness h) {
    h.routed.tradable = {eth, usdc, btc};
    h.atomic.respond = (request) => [
      SwapQuoteAvailable(
        quoteOf(
          id: 'atomic',
          source: SwapLiquiditySource.atomic,
          routeKind: SwapRouteKind.direct,
          from: request.from,
          to: request.to,
          sell: request.amount.toString(),
          quotedAt: h.now(),
        ),
      ),
    ];
  }

  group('before an amount', () {
    swapBlocTest('a pair no one offers says so, and prices nothing', (h) {
      orderBookOnly(h);
      h.atomic.pairOffers = {(eth, gleec): none};

      final bloc = h.open(receive: 'GLEEC');

      expect(bloc.state.issue, SwapFormIssue.noOffers);
      expect(bloc.state.evaluation, SwapEvaluationStatus.idle);
      expect(bloc.state.hints.watching, isTrue);
      expect(h.atomic.requests, isEmpty);
    });

    swapBlocTest('signed out, it says so before asking for a wallet', (h) {
      orderBookOnly(h);
      h.atomic.pairOffers = {(eth, gleec): none};

      final bloc = h.build()
        ..add(
          const UnifiedSwapCapabilitiesChanged(
            tradingEnabled: true,
            clockValid: true,
            signedIn: false,
          ),
        )
        ..add(const UnifiedSwapStarted())
        ..add(const UnifiedSwapIntentApplied(pay: 'ETH', receive: 'GLEEC'));
      h.settle();

      expect(bloc.state.issue, SwapFormIssue.noOffers);
    });

    swapBlocTest('a pair both sources trade never waits on offers', (h) {
      h.atomic.pairOffers = {(eth, usdc): none};

      final bloc = h.open();

      expect(bloc.state.issue, isNull);
      expect(bloc.state.evaluation, SwapEvaluationStatus.ready);
      expect(h.atomic.offersCalls, isEmpty);
    });

    swapBlocTest('offers that cannot be read block nothing', (h) {
      orderBookOnly(h);

      final bloc = h.open(receive: 'GLEEC');

      expect(bloc.state.issue, isNull);
      expect(bloc.state.evaluation, SwapEvaluationStatus.ready);
    });

    swapBlocTest('offers are kept to say what they take', (h) {
      orderBookOnly(h);
      h.atomic.pairOffers = {(eth, gleec): some};

      final bloc = h.open(receive: 'GLEEC', amount: '');

      expect(bloc.state.hints.offersFor(eth, gleec), some);
      expect(bloc.state.issue, SwapFormIssue.amountMissing);
    });

    swapBlocTest('who trades each chosen asset is counted once', (h) {
      orderBookOnly(h);
      h.atomic.offeredBy = {
        eth: {gleec: false},
        gleec: {btc: true},
      };

      final bloc = h.open(receive: 'GLEEC', amount: '');
      final counted = h.atomic.offeredCalls.length;
      bloc.add(const UnifiedSwapAmountChanged('1'));
      h.settle();

      expect(bloc.state.hints.payCounts, SwapOfferCounts(eth, {gleec: false}));
      expect(
        bloc.state.hints.receiveCounts,
        SwapOfferCounts(gleec, {btc: true}),
      );
      expect(h.atomic.offeredCalls.length, counted);
    });
  });

  group('a pair no one offers', () {
    swapBlocTest('is checked every 30 s, and priced once someone offers', (h) {
      orderBookOnly(h);
      h.atomic.pairOffers = {(eth, gleec): none};
      final bloc = h.open(receive: 'GLEEC');
      final reads = h.atomic.offersCalls.length;

      h.elapse(const Duration(seconds: 30));
      expect(h.atomic.offersCalls.length, reads + 1);
      expect(bloc.state.issue, SwapFormIssue.noOffers);

      h.atomic.pairOffers = {(eth, gleec): some};
      h.elapse(const Duration(seconds: 30));

      expect(bloc.state.issue, isNull);
      expect(bloc.state.hints.watching, isFalse);
      expect(bloc.state.evaluation, SwapEvaluationStatus.ready);
      expect(bloc.state.selectedQuote?.source, SwapLiquiditySource.atomic);
    });

    swapBlocTest('stops being checked at the idle limit, and says so', (h) {
      orderBookOnly(h);
      h.atomic.pairOffers = {(eth, gleec): none};
      final bloc = h.open(receive: 'GLEEC');

      h.elapse(const Duration(minutes: 5));
      final reads = h.atomic.offersCalls.length;
      h.elapse(const Duration(minutes: 5));

      expect(bloc.state.hints.watching, isFalse);
      expect(h.atomic.offersCalls.length, reads);
    });

    swapBlocTest('pauses while hidden, and is checked once shown', (h) {
      orderBookOnly(h);
      h.atomic.pairOffers = {(eth, gleec): none};
      final bloc = h.open(receive: 'GLEEC')
        ..add(const UnifiedSwapVisibilityChanged(visible: false));
      h.settle();
      final reads = h.atomic.offersCalls.length;

      h.elapse(const Duration(minutes: 2));
      expect(h.atomic.offersCalls.length, reads);

      bloc.add(const UnifiedSwapVisibilityChanged(visible: true));
      h.settle();
      expect(h.atomic.offersCalls.length, reads + 1);
      expect(bloc.state.hints.watching, isTrue);
    });

    swapBlocTest('a check by hand counts who trades each asset again', (h) {
      orderBookOnly(h);
      h.atomic
        ..pairOffers = {(eth, gleec): none}
        ..offeredBy = {eth: {}, gleec: {}};
      final bloc = h.open(receive: 'GLEEC');
      final counted = h.atomic.offeredCalls.length;

      bloc.add(const UnifiedSwapOffersRequested(recount: true));
      h.settle();
      expect(h.atomic.offeredCalls.length, counted + 2);

      h.elapse(const Duration(seconds: 30));
      expect(h.atomic.offeredCalls.length, counted + 2);
    });

    swapBlocTest('found by a quote that misses, turns into this state', (h) {
      orderBookOnly(h);
      h.atomic.respond = (_) => [
        const SwapQuoteRejected(
          SwapQuoteFailure(
            source: SwapLiquiditySource.atomic,
            kind: SwapQuoteFailureKind.noRoute,
            offers: none,
          ),
        ),
      ];

      final bloc = h.open(receive: 'GLEEC');

      expect(bloc.state.issue, SwapFormIssue.noOffers);
      expect(bloc.state.hints.watching, isTrue);
    });

    swapBlocTest('is checked again, counted anew, after a finished swap', (h) {
      orderBookOnly(h);
      h.atomic.pairOffers = {(eth, gleec): some};
      final bloc = h.open(receive: 'GLEEC');
      final reads = h.atomic.offersCalls.length;
      final counted = h.atomic.offeredCalls.length;

      bloc.add(const UnifiedSwapResetRequested());
      h.settle();

      expect(h.atomic.offersCalls.length, reads + 1);
      expect(h.atomic.offeredCalls.length, counted + 2);
    });
  });

  group('an answer the form has moved on from', () {
    swapBlocTest('for another pair is dropped', (h) {
      orderBookOnly(h);
      h.atomic
        ..pairOffers = {(eth, gleec): none}
        ..offersGate = Completer<void>();
      final bloc = h.open(receive: 'GLEEC')
        ..add(UnifiedSwapReceiveAssetChanged(usdc));
      h.settle();

      h.atomic.offersGate!.complete();
      h.settle();

      expect(bloc.state.receive, usdc);
      expect(bloc.state.issue, isNull);
      expect(bloc.state.hints.offersFor(eth, gleec), isNull);
    });

    swapBlocTest('for another wallet is dropped', (h) {
      orderBookOnly(h);
      h.atomic
        ..pairOffers = {(eth, gleec): none}
        ..offersGate = Completer<void>();
      final bloc = h.open(receive: 'GLEEC')
        ..add(
          const UnifiedSwapCapabilitiesChanged(
            tradingEnabled: true,
            clockValid: true,
            signedIn: false,
          ),
        );
      h.settle();
      final pending = h.atomic.offersGate!;
      h.atomic.offersGate = null;
      h.atomic.pairOffers = {(eth, gleec): some};
      h.settle();

      pending.complete();
      h.settle();

      expect(bloc.state.hints.offersFor(eth, gleec), some);
      expect(bloc.state.issue, isNot(SwapFormIssue.noOffers));
    });

    swapBlocTest('never arms a check after close', (h) {
      orderBookOnly(h);
      h.atomic.pairOffers = {(eth, gleec): none};
      final bloc = h.open(receive: 'GLEEC');
      unawaited(bloc.close());
      h.settle();
      final reads = h.atomic.offersCalls.length;

      h.elapse(const Duration(minutes: 1));

      expect(h.atomic.offersCalls.length, reads);
    });
  });

  swapBlocTest('with trading unavailable, nothing is read', (h) {
    orderBookOnly(h);
    h.atomic.pairOffers = {(eth, gleec): none};
    final bloc = h.build()
      ..add(
        const UnifiedSwapCapabilitiesChanged(
          tradingEnabled: false,
          clockValid: true,
        ),
      );
    h.open(bloc: bloc, receive: 'GLEEC');

    expect(h.atomic.offersCalls, isEmpty);
    expect(bloc.state.issue, isNot(SwapFormIssue.noOffers));
  });
}

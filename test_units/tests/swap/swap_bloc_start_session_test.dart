import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

import 'swap_bloc_fakes.dart';
import 'swap_test_fixtures.dart';

const _signedOut = UnifiedSwapCapabilitiesChanged(
  tradingEnabled: true,
  clockValid: true,
  signedIn: false,
);

const _signedIn = UnifiedSwapCapabilitiesChanged(
  tradingEnabled: true,
  clockValid: true,
);

/// The terms acceptances recorded so far, under any wallet.
Iterable<String> _acceptances(SwapBlocHarness h) => h.storage.values.keys.where(
  (key) => key.startsWith('routed_swap_terms_acceptance_v1'),
);

/// A routed review whose Start is held while its terms are recorded.
UnifiedSwapBloc _startingWithTermsHeld(SwapBlocHarness h) {
  final bloc = h.inReview();
  h.termsGate = Completer<void>();
  bloc.add(const UnifiedSwapStartRequested());
  h.settle();
  expect(bloc.state.review!.status, SwapReviewStatus.starting);
  return bloc;
}

/// Selling ETH for BTC on the order book.
SwapQuote _book(SwapBlocHarness h, {String sell = '1'}) => quoteOf(
  id: 'book',
  source: SwapLiquiditySource.atomic,
  routeKind: SwapRouteKind.direct,
  order: null,
  from: eth,
  to: btc,
  sell: sell,
  expected: '0.05',
  guaranteed: '0.05',
  fees: [feeOf()],
  refundReserve: '0.002',
  quotedAt: h.now(),
);

/// Makes the order book the only source.
void _onlyTheBook(SwapBlocHarness h) {
  h.prices.prices[btc] = d('60000');
  h.routed
    ..respond = null
    ..results = [rejected(SwapQuoteFailureKind.noRoute)];
  h.atomic.respond = (request) => [
    SwapQuoteAvailable(_book(h, sell: '${request.amount}')),
  ];
}

/// Opens the review of the order book's offer with the Start re-price held.
UnifiedSwapBloc _bookStartingWithRepriceHeld(SwapBlocHarness h) {
  _onlyTheBook(h);
  final bloc = h.open(receive: 'BTC')..add(const UnifiedSwapReviewOpened());
  h.settle();
  expect(bloc.state.review!.quote.source, SwapLiquiditySource.atomic);
  h.atomic.requoteGate = Completer<void>();
  bloc.add(const UnifiedSwapStartRequested());
  h.settle();
  return bloc;
}

/// Covers a confirmed start that is still waiting, on its re-price or on its
/// terms being recorded: it is sent only while its form is open and the
/// wallet session it was confirmed in holds.
void main() {
  group('a start held while its terms are recorded', () {
    swapBlocTest('is sent when nothing changed meanwhile', (h) {
      final bloc = _startingWithTermsHeld(h);

      h.termsGate!.complete();
      h.settle();

      expect(h.routedExecutor.started, hasLength(1));
      expect(bloc.state.view, UnifiedSwapView.progress);
      expect(_acceptances(h), ['routed_swap_terms_acceptance_v1:wallet']);
    });

    swapBlocTest('is not sent once the form closes', (h) {
      final bloc = _startingWithTermsHeld(h);
      unawaited(bloc.close());
      h.settle();

      h.termsGate!.complete();
      h.settle();

      expect(h.routedExecutor.started, isEmpty);
    });

    swapBlocTest('is not sent once the wallet signs out', (h) {
      final bloc = _startingWithTermsHeld(h)..add(_signedOut);
      h.settle();

      h.termsGate!.complete();
      h.settle();

      expect(h.routedExecutor.started, isEmpty);
      expect(bloc.state.view, UnifiedSwapView.form);
      expect(bloc.state.review, isNull);
    });

    swapBlocTest('is not sent after signing out and into the same wallet', (h) {
      final bloc = _startingWithTermsHeld(h)..add(_signedOut);
      h.settle();
      unawaited(h.registry.reset());
      bloc.add(_signedIn);
      h.settle();

      h.termsGate!.complete();
      h.settle();

      expect(h.routedExecutor.started, isEmpty);
    });

    swapBlocTest('is not sent once the session it was confirmed in ends', (h) {
      final bloc = _startingWithTermsHeld(h);
      unawaited(h.registry.reset());
      h.settle();

      h.termsGate!.complete();
      h.settle();

      expect(h.routedExecutor.started, isEmpty);
      expect(bloc.state.review, isNull);
    });

    swapBlocTest('that fails returns to the form, starting nothing', (h) {
      final bloc = _startingWithTermsHeld(h);

      h.termsGate!.completeError(StateError('signing out'));
      h.settle();

      expect(h.routedExecutor.started, isEmpty);
      expect(bloc.state.view, UnifiedSwapView.form);
      expect(bloc.state.review, isNull);
    });

    swapBlocTest('records no terms for the wallet signed in meanwhile', (h) {
      final bloc = _startingWithTermsHeld(h)..add(_signedOut);
      h.settle();
      unawaited(h.registry.reset());
      h.wallet = 'another-wallet';
      bloc.add(_signedIn);
      h.settle();

      h.termsGate!.complete();
      h.settle();

      expect(_acceptances(h), isEmpty);
    });
  });

  group('a start held while it is re-priced', () {
    swapBlocTest('is not sent once the form closes', (h) {
      final bloc = h.inReview();
      h.routed.requoteGate = Completer<void>();
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      unawaited(bloc.close());
      h.settle();

      h.routed.requoteGate!.complete();
      h.settle();

      expect(h.routedExecutor.started, isEmpty);
      expect(_acceptances(h), isEmpty);
    });

    swapBlocTest('on the order book is not sent once the form closes', (h) {
      final bloc = _bookStartingWithRepriceHeld(h);
      unawaited(bloc.close());
      h.settle();

      h.atomic.requoteGate!.complete();
      h.settle();

      expect(h.atomicExecutor.started, isEmpty);
    });

    swapBlocTest('on the order book is not sent once the session ends', (h) {
      final bloc = _bookStartingWithRepriceHeld(h);
      unawaited(h.registry.reset());
      h.settle();

      h.atomic.requoteGate!.complete();
      h.settle();

      expect(h.atomicExecutor.started, isEmpty);
      expect(bloc.state.review, isNull);
    });

    swapBlocTest('from a stopped swap is not sent once the form closes', (h) {
      _onlyTheBook(h);
      final bloc = h.open(receive: 'BTC');
      h.atomic.requoteGate = Completer<void>();
      bloc.add(UnifiedSwapFreshQuoteAccepted(_book(h)));
      h.settle();
      unawaited(bloc.close());
      h.settle();

      h.atomic.requoteGate!.complete();
      h.settle();

      expect(h.atomicExecutor.started, isEmpty);
    });
  });
}

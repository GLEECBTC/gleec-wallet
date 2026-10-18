import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';

import 'swap_bloc_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the ways into a start, each of which must hold: none while trading
/// is off, and none for a review that has been left or replaced.
void main() {
  const tradingOff = UnifiedSwapCapabilitiesChanged(
    tradingEnabled: false,
    clockValid: true,
  );

  group('with trading turned off', () {
    swapBlocTest('an open review returns to the form, starting nothing', (h) {
      final bloc = h.inReview()..add(tradingOff);
      h.settle();

      expect(bloc.state.view, UnifiedSwapView.form);
      expect(bloc.state.review, isNull);

      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      expect(h.routed.requoted, isEmpty);
      expect(h.routedExecutor.started, isEmpty);
    });

    swapBlocTest('a re-price under way is not started', (h) {
      final bloc = h.inReview();
      h.routed.requoteGate = Completer<void>();
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      bloc.add(tradingOff);
      h.settle();

      h.routed.requoteGate!.complete();
      h.settle();

      expect(h.routedExecutor.started, isEmpty);
      expect(bloc.state.view, UnifiedSwapView.form);
    });

    swapBlocTest('a start recording the terms stops before the engine', (h) {
      final bloc = h.inReview();
      h.termsGate = Completer<void>();
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      expect(bloc.state.review!.status, SwapReviewStatus.starting);
      bloc.add(tradingOff);
      h.settle();

      h.termsGate!.complete();
      h.settle();

      expect(h.routedExecutor.started, isEmpty);
      expect(bloc.state.view, UnifiedSwapView.form);
      expect(bloc.state.review, isNull);
    });

    swapBlocTest('a start the engine then refuses is not priced again', (h) {
      h.routedExecutor
        ..gate = Completer<void>()
        ..startError = const SwapStartRejectedException(
          SwapStartRejection.notAvailable,
        );
      final bloc = h.inReview()..add(const UnifiedSwapStartRequested());
      h.settle();
      bloc.add(tradingOff);
      h.routedExecutor.gate!.complete();
      h.settle();
      expect(bloc.state.review!.status, SwapReviewStatus.rejected);

      bloc.add(const UnifiedSwapStartRequested());
      h.settle();

      expect(h.routed.requoted, hasLength(1));
    });

    swapBlocTest('a new price accepted from a stopped swap is not started', (
      h,
    ) {
      final bloc = h.open()
        ..add(tradingOff)
        ..add(
          UnifiedSwapFreshQuoteAccepted(
            quoteOf(id: 'agreed', quotedAt: h.now()),
          ),
        );
      h.settle();

      expect(h.routedExecutor.started, isEmpty);
      expect(bloc.state.view, UnifiedSwapView.form);
    });
  });

  group('a start re-pricing', () {
    swapBlocTest('is dropped once a link changes the pair and another review '
        'opens', (h) {
      final bloc = h.inReview();
      h.routed.requoteGate = Completer<void>();
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      // Back in the browser, to a link for half as much, then its review.
      bloc.add(
        const UnifiedSwapIntentApplied(
          pay: 'ETH',
          receive: 'USDC-ERC20',
          amount: '0.5',
        ),
      );
      h.settle();
      bloc.add(const UnifiedSwapReviewOpened());
      h.settle();
      expect(bloc.state.review!.quote.sellAmount, d('0.5'));

      h.routed.requoteGate!.complete();
      h.settle();

      expect(h.routedExecutor.started, isEmpty);
      expect(bloc.state.review!.status, SwapReviewStatus.ready);
      expect(bloc.state.review!.quote.sellAmount, d('0.5'));
    });

    swapBlocTest('keeps a new price accepted meanwhile from starting too', (h) {
      final bloc = h.inReview();
      h.routed.requoteGate = Completer<void>();
      h.routedExecutor.gate = Completer<void>();
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      bloc.add(
        UnifiedSwapFreshQuoteAccepted(quoteOf(id: 'agreed', quotedAt: h.now())),
      );
      h.settle();
      expect(bloc.state.review!.status, SwapReviewStatus.revalidating);

      h.routed.requoteGate!.complete();
      h.settle();
      h.routedExecutor.gate!.complete();
      h.settle();

      expect(h.routedExecutor.started, hasLength(1));
      expect(h.routedExecutor.started.single.id, isNot('agreed'));
    });
  });

  swapBlocTest('a new price accepted after a start that may be running is '
      'refused', (h) {
    h.routedExecutor.startError = SwapStartUnconfirmedException(
      TimeoutException('lost'),
    );
    final bloc = h.inReview()..add(const UnifiedSwapStartRequested());
    h.settle();
    expect(bloc.state.review!.status, SwapReviewStatus.unconfirmed);
    h.routedExecutor.startError = null;

    bloc.add(
      UnifiedSwapFreshQuoteAccepted(quoteOf(id: 'agreed', quotedAt: h.now())),
    );
    h.settle();

    expect(h.routedExecutor.started, hasLength(1));
    expect(bloc.state.review?.status, SwapReviewStatus.unconfirmed);
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

import 'swap_bloc_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers what keeps a price fresh and what stops it: the refresh and
/// expiry timers, being on screen, trading availability, and balances.
void main() {
  group('refreshing', () {
    swapBlocTest('timers that fire with nothing priced change nothing', (h) {
      final bloc = h.build();
      final states = h.record(bloc);
      for (final kind in UnifiedSwapTimerKind.values) {
        bloc.add(UnifiedSwapTimerFired(kind));
      }
      h.settle();

      expect(states, everyElement(const UnifiedSwapState()));
      expect(bloc.state, const UnifiedSwapState());
      expect(h.routed.requests, isEmpty);
    });

    swapBlocTest('an idle form stops re-pricing, and prices on return', (h) {
      final bloc = h.open(bloc: h.build(idleLimit: const Duration(minutes: 2)));
      h.elapse(const Duration(minutes: 2));
      expect(h.routed.requests, hasLength(4));

      h.elapse(const Duration(minutes: 1));
      expect(h.routed.requests, hasLength(4));
      expect(bloc.state.evaluation, SwapEvaluationStatus.expired);

      bloc.add(const UnifiedSwapVisibilityChanged(visible: true));
      h.settle();
      expect(h.routed.requests, hasLength(5));
      expect(bloc.state.evaluation, SwapEvaluationStatus.ready);
    });

    swapBlocTest('a hidden form waits, and resumes when shown again', (h) {
      final bloc = h.open()
        ..add(const UnifiedSwapVisibilityChanged(visible: false));
      h.elapse(const Duration(seconds: 10));
      bloc.add(const UnifiedSwapVisibilityChanged(visible: true));
      h.elapse(const Duration(seconds: 29));
      expect(h.routed.requests, hasLength(1));

      h.elapse(const Duration(seconds: 1));
      expect(h.routed.requests, hasLength(2));
      expect(bloc.state.evaluation, SwapEvaluationStatus.ready);
    });

    swapBlocTest(
      'a price shown again late in its life is renewed before it expires',
      (h) {
        final bloc = h.open()
          ..add(const UnifiedSwapVisibilityChanged(visible: false));
        h.elapse(const Duration(seconds: 45));
        bloc.add(const UnifiedSwapVisibilityChanged(visible: true));
        h.elapse(const Duration(seconds: 20));

        expect(bloc.state.evaluation, SwapEvaluationStatus.ready);
      },
    );

    swapBlocTest('a price that aged while the device slept is renewed', (h) {
      final bloc = h.open()
        ..add(const UnifiedSwapForegroundChanged(foreground: false));
      h.settle();
      h.skew = const Duration(minutes: 3);
      bloc.add(const UnifiedSwapForegroundChanged(foreground: true));
      h.settle();

      expect(h.routed.requests, hasLength(2));
      expect(bloc.state.selectedQuote!.quotedAt, h.now());
    });

    swapBlocTest('coming back to the review leaves its price alone', (h) {
      final bloc = h.inReview()
        ..add(const UnifiedSwapVisibilityChanged(visible: false));
      h.settle();
      h.skew = const Duration(minutes: 3);
      bloc.add(const UnifiedSwapVisibilityChanged(visible: true));
      h.settle();

      expect(h.routed.requests, hasLength(1));
      expect(bloc.state.view, UnifiedSwapView.review);
    });

    swapBlocTest('a refresh due during a rate-limit pause waits', (h) {
      final bloc = h.open(
        bloc: h.build(refreshInterval: const Duration(seconds: 10)),
      );
      h.routed
        ..respond = null
        ..results = [rejected(SwapQuoteFailureKind.rateLimited)];
      h.elapse(const Duration(seconds: 10));
      expect(bloc.state.rateLimitedUntil, isNotNull);

      bloc
        ..add(const UnifiedSwapVisibilityChanged(visible: false))
        ..add(const UnifiedSwapVisibilityChanged(visible: true));
      h.elapse(const Duration(seconds: 19));

      expect(h.routed.requests, hasLength(2));
    });

    swapBlocTest('the review is never re-priced behind the user', (h) {
      final bloc = h.inReview();
      h.elapse(const Duration(seconds: 59));
      expect(h.routed.requests, hasLength(1));
      expect(bloc.state.review!.status, SwapReviewStatus.ready);

      h.elapse(const Duration(seconds: 1));
      expect(bloc.state.review!.status, SwapReviewStatus.expired);
      expect(bloc.state.review!.canStart, isFalse);
    });
  });

  group('trading availability', () {
    swapBlocTest('an unchanged report changes nothing', (h) {
      final bloc = h.open();
      final states = h.record(bloc);
      bloc.add(
        const UnifiedSwapCapabilitiesChanged(
          tradingEnabled: true,
          clockValid: true,
        ),
      );
      h.settle();

      expect(states, isEmpty);
      expect(h.routed.requests, hasLength(1));
    });

    swapBlocTest('trading switched back on prices the form at once', (h) {
      final bloc = h.open()
        ..add(
          const UnifiedSwapCapabilitiesChanged(
            tradingEnabled: false,
            clockValid: true,
          ),
        );
      h.settle();
      expect(bloc.state.canReview, isFalse);

      bloc.add(
        const UnifiedSwapCapabilitiesChanged(
          tradingEnabled: true,
          clockValid: true,
        ),
      );
      h.settle();

      expect(h.routed.requests, hasLength(2));
      expect(bloc.state.canReview, isTrue);
    });

    swapBlocTest('a clock report is kept, and only the form prices', (h) {
      final bloc = h.inReview()
        ..add(
          const UnifiedSwapCapabilitiesChanged(
            tradingEnabled: true,
            clockValid: false,
          ),
        );
      h.settle();

      expect(bloc.state.clockValid, isFalse);
      expect(h.routed.requests, hasLength(1));
    });
  });

  group('balances and addresses', () {
    swapBlocTest('fresh balances check the amount again', (h) {
      final bloc = h.open();
      h.balances[eth] = d('0.5');
      bloc.add(const UnifiedSwapBalancesRefreshed());
      h.settle();

      expect(bloc.state.balance, d('0.5'));
      expect(bloc.state.issue, SwapFormIssue.insufficient);
    });

    swapBlocTest('a balance that cannot be read is unknown, not zero', (h) {
      h.unreadableBalances.add(eth);
      final bloc = h.open();

      expect(bloc.state.balance, isNull);
      expect(bloc.state.issue, isNull);
      expect(bloc.state.canReview, isTrue);
    });

    swapBlocTest('a balance read for a replaced asset is dropped', (h) {
      final bloc = h.open();
      final states = h.record(bloc);
      h
        ..balanceGate = Completer<void>()
        ..balances[eth] = d('0.123');
      bloc
        ..add(const UnifiedSwapBalancesRefreshed())
        ..add(UnifiedSwapPayAssetChanged(btc));
      h.settle();

      h.balanceGate!.complete();
      h.settle();

      expect(bloc.state.balance, d('1'));
      expect(states.where((s) => s.balance == d('0.123')), isEmpty);
    });

    swapBlocTest('an address that cannot be read is left out', (h) {
      h.unreadableAddresses.add(usdc);
      final bloc = h.open();

      expect(bloc.state.payAddress, 'address-of-ETH');
      expect(bloc.state.receiveAddress, isNull);
    });
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';

import 'swap_bloc_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the ways into a start, each of which must hold: none while trading
/// is off.
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
}

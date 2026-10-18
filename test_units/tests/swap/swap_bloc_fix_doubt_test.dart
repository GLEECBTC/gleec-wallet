import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';

import 'swap_bloc_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers a start that may be running, unanswered or with its answer lost:
/// its review stays until the answer is seen, and a lost answer leads only to
/// Activity, never back to a form that could start the same swap twice.
void main() {
  /// ETH for USDC, asked to start; the engine answers when the gate opens.
  UnifiedSwapBloc starting(SwapBlocHarness h) {
    h.routedExecutor.gate = Completer<void>();
    final bloc = h.inReview()..add(const UnifiedSwapStartRequested());
    h.settle();
    expect(bloc.state.review!.status, SwapReviewStatus.starting);
    return bloc;
  }

  /// ETH for USDC, started, with the engine's answer lost.
  UnifiedSwapBloc unconfirmed(SwapBlocHarness h) {
    h.routedExecutor.startError = SwapStartUnconfirmedException(
      TimeoutException('lost'),
    );
    final bloc = h.inReview()..add(const UnifiedSwapStartRequested());
    h.settle();
    expect(bloc.state.review!.status, SwapReviewStatus.unconfirmed);
    return bloc;
  }

  // Each as the form beside an open review sends it: a close, then the edit.
  final edits = <String, UnifiedSwapEvent>{
    'a new asset to pay with': UnifiedSwapPayAssetChanged(btc),
    'a new asset to receive': UnifiedSwapReceiveAssetChanged(btc),
    'switching sides': const UnifiedSwapSidesSwitched(),
    'a pair from a link': const UnifiedSwapIntentApplied(
      pay: 'BTC',
      receive: 'ETH',
    ),
    'a follow-up swap': UnifiedSwapFollowUpRequested(
      pay: usdc,
      receive: eth,
      amount: '2950',
    ),
  };

  group('while the engine is asked to start', () {
    for (final MapEntry(key: name, value: edit) in edits.entries) {
      swapBlocTest('$name waits for the answer', (h) {
        final bloc = starting(h)
          ..add(const UnifiedSwapReviewClosed())
          ..add(edit);
        h.settle();
        expect(bloc.state.view, UnifiedSwapView.review);
        expect((bloc.state.pay, bloc.state.receive), (eth, usdc));

        h.routedExecutor.gate!.complete();
        h.settle();

        expect(bloc.state.view, UnifiedSwapView.progress);
        expect(bloc.state.activeExecutionId, 'routed-1');
      });
    }

    swapBlocTest('an edit leaves a refusal on screen', (h) {
      h.routedExecutor.startError = const SwapStartRejectedException(
        SwapStartRejection.notAvailable,
        detail: 'pair paused',
      );
      final bloc = starting(h)
        ..add(const UnifiedSwapReviewClosed())
        ..add(const UnifiedSwapSidesSwitched());
      h.settle();

      h.routedExecutor.gate!.complete();
      h.settle();

      expect(bloc.state.review!.status, SwapReviewStatus.rejected);
      expect(bloc.state.review!.rejectionDetail, 'pair paused');
    });

    swapBlocTest('a reset sent from Activity keeps a lost answer on screen', (
      h,
    ) {
      h.routedExecutor.startError = SwapStartUnconfirmedException(
        TimeoutException('lost'),
      );
      final bloc = starting(h)..add(const UnifiedSwapResetRequested());
      h.settle();

      h.routedExecutor.gate!.complete();
      h.settle();

      expect(bloc.state.view, UnifiedSwapView.review);
      expect(bloc.state.review!.status, SwapReviewStatus.unconfirmed);
    });

    swapBlocTest('numbers accepted from Activity start no second swap', (h) {
      final bloc = starting(h)
        ..add(
          UnifiedSwapFreshQuoteAccepted(
            quoteOf(id: 'other', quotedAt: h.now()),
          ),
        );
      h.settle();

      h.routedExecutor.gate!.complete();
      h.settle();

      expect(h.routedExecutor.started.map((quote) => quote.id), ['routed-1']);
      expect(bloc.state.activeExecutionId, 'routed-1');
    });
  });

  group('once its answer is lost', () {
    swapBlocTest('Back keeps the warning on screen', (h) {
      final bloc = unconfirmed(h)..add(const UnifiedSwapReviewClosed());
      h.settle();

      expect(bloc.state.view, UnifiedSwapView.review);
      expect(bloc.state.review!.status, SwapReviewStatus.unconfirmed);
    });

    for (final MapEntry(key: name, value: edit) in edits.entries) {
      swapBlocTest('$name is ignored', (h) {
        final bloc = unconfirmed(h)
          ..add(const UnifiedSwapReviewClosed())
          ..add(edit);
        h.settle();

        expect(bloc.state.view, UnifiedSwapView.review);
        expect(bloc.state.review!.status, SwapReviewStatus.unconfirmed);
        expect((bloc.state.pay, bloc.state.receive), (eth, usdc));
        expect(h.routedExecutor.started, hasLength(1));
      });
    }

    swapBlocTest('Activity leads on to a form with nothing to start', (h) {
      final bloc = unconfirmed(h)..add(const UnifiedSwapResetRequested());
      h.settle();

      expect(bloc.state.view, UnifiedSwapView.form);
      expect(bloc.state.review, isNull);
      expect((bloc.state.pay, bloc.state.receive), (eth, usdc));
      expect(bloc.state.inputText, isEmpty);
      expect(bloc.state.selectedQuote, isNull);
      expect(bloc.state.canReview, isFalse);
    });
  });

  swapBlocTest('a refused start can be left, since nothing was sent', (h) {
    h.routedExecutor.startError = const SwapStartRejectedException(
      SwapStartRejection.notAvailable,
    );
    final bloc = h.inReview()..add(const UnifiedSwapStartRequested());
    h.settle();

    bloc
      ..add(const UnifiedSwapReviewClosed())
      ..add(UnifiedSwapReceiveAssetChanged(btc));
    h.settle();

    expect(bloc.state.view, UnifiedSwapView.form);
    expect((bloc.state.pay, bloc.state.receive), (eth, btc));
    expect(bloc.state.review, isNull);
  });
}

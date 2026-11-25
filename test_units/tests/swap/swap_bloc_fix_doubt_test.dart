import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/services/wallet_access/wallet_operation_gate.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

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

  // The amount beside a swap that may be running: typed, Max, or its unit.
  final amountEdits = <String, UnifiedSwapEvent>{
    'a typed amount': const UnifiedSwapAmountChanged('0.5'),
    'Max': const UnifiedSwapMaxRequested(),
    'the unit switch': const UnifiedSwapAmountModeToggled(),
    'a suggested amount': UnifiedSwapAmountSuggested(d('0.25')),
  };

  for (final (stage, reach) in [
    ('asked to start', starting),
    ('with its answer lost', unconfirmed),
  ]) {
    for (final MapEntry(key: name, value: edit) in amountEdits.entries) {
      swapBlocTest('$name leaves the amount of a swap $stage', (h) {
        final bloc = reach(h);
        final before = bloc.state;
        bloc
          ..add(const UnifiedSwapReviewClosed())
          ..add(edit);
        h.settle();

        expect(bloc.state.inputText, before.inputText);
        expect(bloc.state.amountMode, before.amountMode);
        expect(bloc.state.maxRequested, isFalse);
        expect(bloc.state.review!.status, before.review!.status);
      });
    }
  }

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

  group('a start the app lock refuses before anything is sent', () {
    /// The app lock, open for the harness's wallet until a test blocks it.
    WalletOperationGate lockOf(SwapBlocHarness h) =>
        h.operationGate = WalletOperationGate()
          ..attachWallet('wallet', sessionIdentity: h, allowOperations: true);

    /// The review of [source]'s only offer, with its fakes.
    (UnifiedSwapBloc, FakeQuoteSource, GatedExecutor) reviewOf(
      SwapBlocHarness h,
      SwapLiquiditySource source,
    ) {
      if (source == SwapLiquiditySource.routed) {
        return (h.inReview(), h.routed, h.routedExecutor);
      }
      h.routed
        ..respond = null
        ..results = [rejected(SwapQuoteFailureKind.noRoute)];
      h.atomic.respond = (request) => [
        SwapQuoteAvailable(
          quoteOf(
            id: 'book',
            source: SwapLiquiditySource.atomic,
            routeKind: SwapRouteKind.direct,
            order: null,
            sell: '${request.amount}',
            quotedAt: h.now(),
          ),
        ),
      ];
      return (h.inReview(), h.atomic, h.atomicExecutor);
    }

    for (final (source, name) in [
      (SwapLiquiditySource.routed, 'a routed'),
      (SwapLiquiditySource.atomic, 'an order-book'),
    ]) {
      swapBlocTest('while $name start is re-priced', (h) {
        final lock = lockOf(h);
        final (bloc, quotes, executor) = reviewOf(h, source);
        quotes.requoteGate = Completer<void>();
        bloc.add(const UnifiedSwapStartRequested());
        h.settle();
        expect(bloc.state.review!.status, SwapReviewStatus.revalidating);

        lock.block();
        quotes.requoteGate!.complete();
        h.settle();

        expect(executor.started, isEmpty);
        expect(bloc.state.review!.status, SwapReviewStatus.rejected);
        expect(bloc.state.startInDoubt, isFalse);
      });

      swapBlocTest('as $name start reaches the engine', (h) {
        final lock = lockOf(h);
        final (bloc, _, executor) = reviewOf(h, source);
        final gate = executor.dispatchGate = Completer<void>();
        bloc.add(const UnifiedSwapStartRequested());
        h.settle();

        lock.block();
        gate.complete();
        h.settle();

        expect(executor.started, isEmpty);
        expect(bloc.state.review!.status, SwapReviewStatus.rejected);
        expect(bloc.state.startInDoubt, isFalse);
      });
    }

    swapBlocTest('is tried again only once unlocked, and by a new Start', (h) {
      final lock = lockOf(h);
      final (bloc, quotes, executor) = reviewOf(h, SwapLiquiditySource.routed);
      quotes.requoteGate = Completer<void>();
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      lock.block();
      quotes.requoteGate!.complete();
      h.settle();
      quotes.requoteGate = null;

      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      expect(bloc.state.review!.status, SwapReviewStatus.rejected);

      lock.allow(walletEntryId: 'wallet');
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      expect(bloc.state.review!.status, SwapReviewStatus.ready);
      expect(executor.started, isEmpty);

      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      expect(executor.started, hasLength(1));
      expect(bloc.state.view, UnifiedSwapView.progress);
    });

    swapBlocTest('leaves Review to be asked for again once unlocked', (h) {
      final lock = lockOf(h);
      final bloc = h.open();
      lock.block();

      bloc.add(const UnifiedSwapReviewOpened());
      h.settle();
      expect(bloc.state.view, UnifiedSwapView.form);
      expect(bloc.state.canReview, isTrue);

      lock.allow(walletEntryId: 'wallet');
      bloc.add(const UnifiedSwapReviewOpened());
      h.settle();
      expect(bloc.state.view, UnifiedSwapView.review);
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

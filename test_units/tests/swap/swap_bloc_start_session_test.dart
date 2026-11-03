import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/services/legal_documents/legal_documents_repository.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

import '../../support/legal_documents_fixture.dart';
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
  expect(bloc.state.review!.status, SwapReviewStatus.revalidating);
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
  group('a start during an actual consent storage write', () {
    for (final invalidation in [
      'close',
      'back',
      'reset',
      'registry',
      'session',
      'tab',
    ]) {
      swapBlocTest('cannot dispatch after $invalidation', (h) {
        final bloc = h.inReview();
        final gate = h.storage.consentWriteGate = Completer<void>();
        bloc.add(const UnifiedSwapStartRequested());
        h.settle();
        expect(h.storage.consentWrites, 1);
        expect(bloc.state.review!.status, SwapReviewStatus.revalidating);
        expect(h.routedExecutor.started, isEmpty);

        switch (invalidation) {
          case 'close':
            unawaited(bloc.close());
          case 'back':
            bloc.add(const UnifiedSwapReviewClosed());
          case 'reset':
            bloc.add(const UnifiedSwapResetRequested());
          case 'registry':
            unawaited(h.registry.reset());
          case 'tab':
            bloc.add(const UnifiedSwapVisibilityChanged(visible: false));
          case 'session':
            // Auth revokes synchronously; no BLoC notification/reset arrives.
            h.auth.sessions.invalidate();
        }
        h.settle();
        gate.complete();
        h.settle();
        expect(h.routedExecutor.started, isEmpty);
        expect(h.atomicExecutor.started, isEmpty);
      });
    }

    swapBlocTest('does not replace a newer review when the write completes', (
      h,
    ) {
      final bloc = h.inReview();
      final gate = h.storage.consentWriteGate = Completer<void>();
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      bloc.add(const UnifiedSwapReviewClosed());
      h.settle();
      bloc.add(const UnifiedSwapAmountChanged('0.5'));
      h.settle();
      bloc.add(const UnifiedSwapReviewOpened());
      h.settle();
      final replacement = bloc.state.review;
      expect(replacement!.quote.sellAmount, d('0.5'));
      gate.complete();
      h.settle();
      expect(bloc.state.review, replacement);
      expect(h.routedExecutor.started, isEmpty);
    });

    swapBlocTest('same-wallet reauthentication still revokes confirmation', (
      h,
    ) {
      final bloc = h.inReview();
      final walletId = h.auth.currentSession!.walletId;
      final gate = h.storage.consentWriteGate = Completer<void>();
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      h.auth.sessions
        ..invalidate()
        ..observe(KdfUser(walletId: walletId, isBip39Seed: true));
      gate.complete();
      h.settle();
      expect(h.routedExecutor.started, isEmpty);
    });
  });

  group('recovery confirmation awaiting legal preparation', () {
    for (final invalidation in [
      'reset',
      'amount',
      'review',
      'close',
      'session',
    ]) {
      swapBlocTest('cannot revive after $invalidation', (h) {
        final bloc = h.open();
        final gate = h.legalSnapshotGate = Completer<void>();
        bloc.add(
          UnifiedSwapFreshQuoteAccepted(
            quoteOf(id: 'old-recovery', quotedAt: h.now()),
          ),
        );
        h.settle();
        // Only the old read remains blocked; replacements load normally.
        h.legalSnapshotGate = null;
        switch (invalidation) {
          case 'reset':
            bloc.add(const UnifiedSwapResetRequested());
          case 'amount':
            bloc.add(const UnifiedSwapAmountChanged('0.5'));
          case 'review':
            bloc.add(const UnifiedSwapReviewOpened());
          case 'close':
            unawaited(bloc.close());
          case 'session':
            h.auth.sessions.invalidate();
        }
        h.settle();
        final replacement = bloc.state.review;
        gate.complete();
        h.settle();
        expect(h.routedExecutor.started, isEmpty);
        expect(bloc.state.review, replacement);
      });
    }
  });

  group('confirmation awaiting the execution dispatch boundary', () {
    swapBlocTest('can be cancelled before the executor sends', (h) {
      final bloc = h.inReview();
      final gate = h.routedExecutor.dispatchGate = Completer<void>();
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      expect(bloc.state.review!.status, SwapReviewStatus.revalidating);
      bloc.add(const UnifiedSwapReviewClosed());
      h.settle();
      gate.complete();
      h.settle();
      expect(h.routedExecutor.started, isEmpty);
      expect(bloc.state.view, UnifiedSwapView.form);
    });

    swapBlocTest('cannot use a revoked session before any app notification', (
      h,
    ) {
      final bloc = h.inReview();
      final gate = h.routedExecutor.dispatchGate = Completer<void>();
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      h.auth.sessions.invalidate();
      gate.complete();
      h.settle();
      expect(h.routedExecutor.started, isEmpty);
    });

    swapBlocTest('switching tabs revokes a start queued for dispatch', (h) {
      final bloc = h.inReview();
      final gate = h.routedExecutor.dispatchGate = Completer<void>();
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      bloc.add(const UnifiedSwapVisibilityChanged(visible: false));
      h.settle();
      bloc.add(const UnifiedSwapVisibilityChanged(visible: true));
      h.settle();
      gate.complete();
      h.settle();
      expect(h.routedExecutor.started, isEmpty);
      expect(bloc.state.view, UnifiedSwapView.form);
    });

    swapBlocTest('switching tabs preserves an already dispatched start', (h) {
      final bloc = h.inReview();
      final gate = h.routedExecutor.gate = Completer<void>();
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      expect(h.routedExecutor.started, hasLength(1));
      bloc.add(const UnifiedSwapVisibilityChanged(visible: false));
      h.settle();
      gate.complete();
      h.settle();
      expect(h.routedExecutor.started, hasLength(1));
      expect(h.registry.current, hasLength(1));
      expect(bloc.state.view, UnifiedSwapView.progress);
    });

    swapBlocTest('session invalidation clears old-wallet UI after dispatch', (
      h,
    ) {
      final bloc = h.inReview();
      final gate = h.routedExecutor.gate = Completer<void>();
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      expect(h.routedExecutor.started, hasLength(1));
      expect(bloc.state.review!.status, SwapReviewStatus.starting);
      final original = h.auth.currentSession!.walletId;
      h.auth.sessions.observe(
        KdfUser(
          walletId: WalletId(
            name: 'replacement',
            authOptions: original.authOptions,
          ),
          isBip39Seed: true,
        ),
      );
      unawaited(h.registry.reset());
      h.settle();
      expect(bloc.state.view, UnifiedSwapView.form);
      expect(bloc.state.review, isNull);
      expect(bloc.state.activeExecutionId, isNull);
      gate.complete();
      h.settle();
      expect(h.routedExecutor.started, hasLength(1));
      expect(bloc.state.view, UnifiedSwapView.form);
      expect(bloc.state.review, isNull);
      expect(h.registry.current, isEmpty);
      expect(
        h.storage.values.keys.where(
          (key) => key.startsWith('swap_last_pair_v1:'),
        ),
        isEmpty,
      );
      expect(h.routedExecutor.lastStarted!.cancelCalls, 0);
    });
    swapBlocTest('keeps tracking after closure once dispatch occurred', (h) {
      final bloc = h.inReview();
      final gate = h.routedExecutor.gate = Completer<void>();
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      expect(bloc.state.review!.status, SwapReviewStatus.starting);
      expect(h.routedExecutor.started, hasLength(1));
      unawaited(bloc.close());
      h.settle();
      gate.complete();
      h.settle();
      expect(h.routedExecutor.started, hasLength(1));
      expect(h.registry.current, hasLength(1));
      expect(h.storage.values.containsKey('swap_last_pair_v1:wallet'), isFalse);
    });
  });
  group('the session that opened the review', () {
    for (final source in ['routed', 'atomic']) {
      for (final sameWallet in [false, true]) {
        swapBlocTest(
          '$source rejects a later Start after sameWallet=$sameWallet',
          (h) {
            if (source == 'atomic') _onlyTheBook(h);
            final bloc = source == 'atomic'
                ? (h.open(receive: 'BTC')..add(const UnifiedSwapReviewOpened()))
                : h.inReview();
            h.settle();
            expect(bloc.state.review, isNotNull);
            final original = h.auth.currentSession!.walletId;
            h.auth.sessions
              ..invalidate()
              ..observe(
                KdfUser(
                  walletId: sameWallet
                      ? original
                      : WalletId(
                          name: 'replacement',
                          authOptions: original.authOptions,
                        ),
                  isBip39Seed: true,
                ),
              );
            // No signedIn=false event or registry-reset notification is needed.
            bloc.add(const UnifiedSwapStartRequested());
            h.settle();
            expect(h.routedExecutor.started, isEmpty);
            expect(h.atomicExecutor.started, isEmpty);
            expect(bloc.state.review, isNull);
          },
        );
      }
    }

    swapBlocTest('cannot finish opening after its session ends', (h) {
      final bloc = h.open();
      final gate = h.legalSnapshotGate = Completer<void>();
      bloc.add(const UnifiedSwapReviewOpened());
      h.settle();
      h.auth.sessions.invalidate();
      gate.complete();
      h.settle();
      expect(bloc.state.review, isNull);
      expect(h.routedExecutor.started, isEmpty);
    });

    swapBlocTest(
      'reads consent with its frozen wallet even if user data lags',
      (h) {
        h.resolve(h.terms.recordAcceptance(at: h.now()));
        h.wallet = 'stale-user-record';
        final bloc = h.inReview();
        expect(bloc.state.review!.termsRequired, isFalse);
        bloc.add(const UnifiedSwapStartRequested());
        h.settle();
        expect(h.routedExecutor.started, hasLength(1));
        expect(_acceptances(h), ['routed_swap_terms_acceptance_v1:wallet']);
      },
    );
  });
  swapBlocTest('a hidden form refuses a new normal Start event', (h) {
    final bloc = h.inReview();
    bloc.add(const UnifiedSwapVisibilityChanged(visible: false));
    h.settle();
    bloc.add(const UnifiedSwapStartRequested());
    h.settle();
    expect(h.routedExecutor.started, isEmpty);
    expect(h.routed.requoted, isEmpty);
    expect(bloc.state.review!.status, SwapReviewStatus.ready);
  });

  test(
    'a cancelled legal wait does not block the replacement confirmation',
    () {
      fakeAsync((async) {
        final response = Completer<http.Response>();
        final legal = LegalDocumentsRepository(
          storage: LegalFixtureStorage(populated: false),
          bypassGate: false,
          httpClient: MockClient((_) => response.future),
        );
        final h = SwapBlocHarness(async, legalDocuments: legal);
        try {
          final bloc = h.inReview();
          expect(bloc.state.review!.legalLoading, isTrue);
          bloc.add(const UnifiedSwapStartRequested());
          h.settle();
          bloc.add(const UnifiedSwapReviewClosed());
          h.settle();
          bloc.add(const UnifiedSwapAmountChanged('0.5'));
          h.settle();
          bloc.add(const UnifiedSwapReviewOpened());
          h.settle();
          expect(bloc.state.review!.quote.sellAmount, d('0.5'));
          bloc.add(const UnifiedSwapStartRequested());
          h.settle();
          response.complete(
            http.Response(
              '# Published terms',
              200,
              headers: {'content-type': 'text/markdown'},
            ),
          );
          h.settle();
          expect(h.routedExecutor.started, hasLength(1));
          expect(h.routedExecutor.started.single.sellAmount, d('0.5'));
          expect(bloc.state.view, UnifiedSwapView.progress);
        } finally {
          h.dispose();
        }
      });
    },
  );
}

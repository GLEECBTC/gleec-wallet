import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/services/legal_documents/legal_documents_repository.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';

import '../../support/legal_documents_fixture.dart';
import 'swap_bloc_fakes.dart';

/// The harness's wallet, signed in again.
const _wallet = KdfUser(
  walletId: WalletId(
    name: 'wallet',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
  ),
  isBip39Seed: true,
);

/// Covers a Start waiting on the provider's terms when its tab is left, and a
/// review asked for before the wallet session it would start in is ready,
/// including a form built before that session arrives.
void main() {
  test(
    'leaving the tab while Start waits for the terms returns to the form',
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

          bloc.add(const UnifiedSwapVisibilityChanged(visible: false));
          h.settle();
          expect(bloc.state.view, UnifiedSwapView.form);
          expect(bloc.state.review, isNull);

          response.complete(
            http.Response(
              '# Published terms',
              200,
              headers: {'content-type': 'text/markdown'},
            ),
          );
          h.settle();
          expect(h.routedExecutor.started, isEmpty);
        } finally {
          h.dispose();
        }
      });
    },
  );

  swapBlocTest('Review waits for the wallet session, then opens', (h) {
    final bloc = h.open();
    expect(bloc.state.canReview, isTrue);
    // Signed in, but the session has not reached the swap services yet.
    h.auth.sessions.invalidate();

    bloc.add(const UnifiedSwapReviewOpened());
    h.settle();
    expect(bloc.state.view, UnifiedSwapView.form);
    expect(bloc.state.sessionReady, isFalse);
    expect(bloc.state.canReview, isFalse);

    // The services reset the registry for each new session.
    h.auth.sessions.observe(_wallet);
    unawaited(h.registry.reset());
    h.settle();
    expect(bloc.state.sessionReady, isTrue);
    expect(bloc.state.canReview, isTrue);

    bloc.add(const UnifiedSwapReviewOpened());
    h.settle();
    expect(bloc.state.view, UnifiedSwapView.review);
  });

  swapBlocTest('a form built before the wallet session keeps Review off', (h) {
    // Signed in, but the session has not reached the swap services yet.
    h.auth.sessions.invalidate();
    final bloc = h.open();
    expect(bloc.state.sessionReady, isFalse);
    expect(bloc.state.canReview, isFalse);

    h.auth.sessions.observe(_wallet);
    unawaited(h.registry.reset());
    h.settle();
    expect(bloc.state.sessionReady, isTrue);
    expect(bloc.state.canReview, isTrue);
  });

  swapBlocTest('the registry accepts a start only in a current session', (h) {
    final registry = h.registry;
    expect(registry.acceptsSubmissions, isTrue);
    final submission = registry.beginSubmission();
    expect(registry.isCurrent(submission), isTrue);

    h.auth.sessions.invalidate();
    expect(registry.acceptsSubmissions, isFalse);
    expect(
      registry.beginSubmission,
      throwsA(isA<SwapStartRejectedException>()),
    );
    expect(registry.isCurrent(submission), isFalse);

    h.auth.sessions.observe(_wallet);
    expect(registry.acceptsSubmissions, isTrue);
    expect(registry.isCurrent(submission), isFalse);
  });
}

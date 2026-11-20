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
import 'swap_test_fixtures.dart';

/// The harness's wallet, signed in again.
const _wallet = KdfUser(
  walletId: WalletId(
    name: 'wallet',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
  ),
  isBip39Seed: true,
);

/// Covers a Start waiting on the provider's terms when its tab is left, a
/// review asked for before the wallet session it would start in is ready,
/// including a form built before that session arrives, and what a session
/// that begins mid-preparation or a restored draft leaves on the form.
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

  group('a wallet session that begins', () {
    swapBlocTest('while the assets load still prepares a restored pair', (h) {
      h.catalogGate = Completer<void>();
      final bloc = h.build()
        ..add(const UnifiedSwapStarted())
        ..add(
          const UnifiedSwapDraftRestored(
            pay: 'ETH',
            receive: 'USDC-ERC20',
            input: '1',
            amountMode: SwapAmountMode.token,
            slippage: swapDefaultSlippage,
          ),
        );
      h.settle();
      expect(bloc.state.loadingAssets, isTrue);

      unawaited(h.registry.reset());
      h.settle();
      h.catalogGate!.complete();
      h.settle();

      expect(bloc.state.loadingAssets, isFalse);
      expect(bloc.state.preparingAssets, isFalse);
      expect(bloc.state.canReview, isTrue);
    });

    swapBlocTest('while the assets load still opens on a default pair', (h) {
      h
        ..holdings = [(asset: eth, usdValue: d('6000'))]
        ..catalogGate = Completer<void>();
      final bloc = h.build()..add(const UnifiedSwapStarted());
      h.settle();

      unawaited(h.registry.reset());
      h.settle();
      h.catalogGate!.complete();
      h.settle();

      expect(bloc.state.loadingAssets, isFalse);
      expect((bloc.state.pay, bloc.state.receive), (eth, usdc));
      expect(bloc.state.preparingAssets, isFalse);
    });

    swapBlocTest('while a default pair is chosen chooses it again', (h) {
      h.holdingsGate = Completer<void>();
      final bloc = h.build()..add(const UnifiedSwapStarted());
      h.settle();
      expect(bloc.state.loadingAssets, isFalse);
      expect(bloc.state.pay, isNull);

      unawaited(h.registry.reset());
      h.elapse(const Duration(seconds: 1));

      expect((bloc.state.pay, bloc.state.receive), (eth, usdc));
      expect(bloc.state.preparingAssets, isFalse);
    });

    swapBlocTest('while a pair is prepared prepares it for that session', (h) {
      final bloc = h.open();
      h.balanceGate = Completer<void>();
      bloc.add(UnifiedSwapReceiveAssetChanged(btc));
      h.settle();
      expect(bloc.state.preparingAssets, isTrue);

      unawaited(h.registry.reset());
      h.settle();
      h.balanceGate!.complete();
      h.settle();

      expect(bloc.state.preparingAssets, isFalse);
      expect(bloc.state.preparationFailedAsset, isNull);
      expect(h.routed.requests.last.to, btc);
      expect(bloc.state.canReview, isTrue);
    });

    swapBlocTest('just after sign-in still gives an empty field its unit', (h) {
      final bloc = h.build()
        ..add(
          const UnifiedSwapCapabilitiesChanged(
            tradingEnabled: true,
            clockValid: true,
            signedIn: false,
          ),
        )
        ..add(const UnifiedSwapStarted())
        ..add(
          const UnifiedSwapIntentApplied(pay: 'ETH', receive: 'USDC-ERC20'),
        );
      h.settle();
      expect(bloc.state.amountMode, SwapAmountMode.token);

      bloc.add(
        const UnifiedSwapCapabilitiesChanged(
          tradingEnabled: true,
          clockValid: true,
        ),
      );
      unawaited(h.registry.reset());
      h.settle();

      expect(bloc.state.preparingAssets, isFalse);
      expect(bloc.state.amountMode, SwapAmountMode.fiat);
    });

    swapBlocTest('while the app is away is priced once it is back', (h) {
      final bloc = h.open()
        ..add(const UnifiedSwapForegroundChanged(foreground: false));
      h.settle();
      final asked = h.routed.requests.length;

      unawaited(h.registry.reset());
      h.settle();
      expect(h.routed.requests, hasLength(asked));
      expect(bloc.state.preparingAssets, isFalse);

      bloc.add(const UnifiedSwapForegroundChanged(foreground: true));
      h.settle();
      expect(bloc.state.canReview, isTrue);
    });

    swapBlocTest('clears a failed preparation its own reads make good', (h) {
      final bloc = h.open();
      h.unreadableBalances.add(eth);
      bloc.add(const UnifiedSwapBalancesRefreshed());
      h.settle();
      expect(bloc.state.preparationFailedAsset, eth);

      h.unreadableBalances.clear();
      unawaited(h.registry.reset());
      h.settle();

      expect(bloc.state.preparationFailedAsset, isNull);
      expect(bloc.state.canReview, isTrue);
    });
  });

  group('a session draft', () {
    UnifiedSwapDraftRestored draft({required String input}) =>
        UnifiedSwapDraftRestored(
          pay: 'ETH',
          receive: 'USDC-ERC20',
          input: input,
          amountMode: SwapAmountMode.token,
          slippage: 0.03,
        );

    swapBlocTest('left by a submitted swap restores no raised slippage', (h) {
      final bloc = h.build()
        ..add(const UnifiedSwapStarted())
        ..add(draft(input: ''));
      h.settle();

      expect((bloc.state.pay, bloc.state.receive), (eth, usdc));
      expect(bloc.state.slippage, swapDefaultSlippage);

      bloc.add(const UnifiedSwapAmountChanged('1'));
      h.settle();
      expect(h.routed.requests.last.slippage, swapDefaultSlippage);
    });

    swapBlocTest('of an amount not yet submitted keeps its slippage', (h) {
      final bloc = h.build()
        ..add(const UnifiedSwapStarted())
        ..add(draft(input: '1'));
      h.settle();

      expect(bloc.state.slippage, 0.03);
      expect(h.routed.requests.last.slippage, 0.03);
    });
  });
}

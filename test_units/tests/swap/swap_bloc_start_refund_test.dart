import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

import 'swap_bloc_fakes.dart';
import 'swap_test_fixtures.dart';

/// Selling [sell] of [from] for BTC on the order book, with [gas] ETH of fees
/// on top and [refund] ETH kept to refund it.
SwapQuote _book(
  SwapBlocHarness h, {
  AssetId? from,
  String sell = '1',
  String gas = '0.001',
  String? refund = '0.002',
  bool feesKnown = true,
}) => quoteOf(
  id: 'book-$gas',
  source: SwapLiquiditySource.atomic,
  routeKind: SwapRouteKind.direct,
  order: null,
  from: from ?? eth,
  to: btc,
  sell: sell,
  expected: '0.05',
  guaranteed: '0.05',
  fees: feesKnown ? [feeOf(amount: gas)] : const [],
  feesKnown: feesKnown,
  refundReserve: refund,
  quotedAt: h.now(),
);

/// Makes the order book the only source, with [held] ETH.
void _onlyTheBook(SwapBlocHarness h, String held) {
  h.balances[eth] = d(held);
  h.prices.prices[btc] = d('60000');
  h.routed
    ..respond = null
    ..results = [rejected(SwapQuoteFailureKind.noRoute)];
  h.atomic.respond = (request) => [
    SwapQuoteAvailable(_book(h, sell: '${request.amount}')),
  ];
}

/// Opens the form on [amount] of [pay] for BTC, then its review.
UnifiedSwapBloc _review(
  SwapBlocHarness h, {
  String pay = 'ETH',
  String amount = '1',
}) {
  final bloc = h.open(pay: pay, receive: 'BTC', amount: amount)
    ..add(const UnifiedSwapReviewOpened());
  h.settle();
  return bloc;
}

/// Presses Start, with the re-price answering [fresh], or the same quote.
void _start(SwapBlocHarness h, UnifiedSwapBloc bloc, [SwapQuote? fresh]) {
  h.atomic.requoteResult = fresh == null ? null : SwapQuoteAvailable(fresh);
  bloc.add(const UnifiedSwapStartRequested());
  h.settle();
}

/// Covers the start checking the re-priced swap against the balance as the
/// form did: KDF's own checks leave out the gas to refund it.
void main() {
  swapBlocTest('a re-price leaving too little to refund stops the start', (h) {
    // 1 ETH, 0.001 ETH of gas and 0.002 ETH to refund: all of 1.003 ETH.
    _onlyTheBook(h, '1.003');
    final bloc = _review(h);
    expect(bloc.state.review!.status, SwapReviewStatus.ready);

    // Gas rose 15%: KDF would start it, and a refund could then fail.
    _start(h, bloc, _book(h, gas: '0.00115', refund: '0.0023'));

    expect(h.atomicExecutor.started, isEmpty);
    final review = bloc.state.review!;
    expect(review.status, SwapReviewStatus.revalidationFailed);
    expect(review.revalidationRecovery, SwapRevalidationRecovery.backToForm);
    expect(
      review.revalidationFailure!.kind,
      SwapQuoteFailureKind.insufficientFunds,
    );
    expect(review.revalidationFailure!.asset, eth);

    // Back on the form, the same price says what it needs.
    h.atomic.respond = (_) => [
      SwapQuoteAvailable(_book(h, gas: '0.00115', refund: '0.0023')),
    ];
    bloc.add(const UnifiedSwapReviewClosed());
    h.settle();

    expect(bloc.state.view, UnifiedSwapView.form);
    expect(bloc.state.issue, SwapFormIssue.insufficient);
    expect(bloc.spendOf(bloc.state)!.refundReserve, d('0.0023'));
  });

  swapBlocTest('a re-price that still fits starts', (h) {
    _onlyTheBook(h, '1.0035');
    final bloc = _review(h);

    _start(h, bloc, _book(h, gas: '0.00115', refund: '0.0023'));

    expect(bloc.state.view, UnifiedSwapView.progress);
    expect(h.atomicExecutor.started.single.id, 'book-0.00115');
  });

  swapBlocTest('Max still starts when gas has risen since it was read', (h) {
    _onlyTheBook(h, '1.003');
    h.atomic.max = SwapMaxAmount(
      amount: d('1'),
      reservedForFees: d('0.003'),
      feeAsset: eth,
      coversRefund: true,
    );
    final bloc = h.open(receive: 'BTC', amount: '0.5')
      ..add(const UnifiedSwapMaxRequested());
    h.settle();
    expect(bloc.state.inputText, '1');
    bloc.add(const UnifiedSwapReviewOpened());
    h.settle();

    _start(h, bloc, _book(h, gas: '0.00115', refund: '0.0023'));

    expect(h.atomicExecutor.started.single.id, 'book-0.00115');
  });

  swapBlocTest('what the wallet holds is read again before the start', (h) {
    _onlyTheBook(h, '1.003');
    final bloc = _review(h);
    h.balances[eth] = d('1.0025');

    _start(h, bloc);

    expect(h.atomicExecutor.started, isEmpty);
    expect(bloc.state.balance, d('1.0025'));
    expect(bloc.state.review?.status, SwapReviewStatus.revalidationFailed);
  });

  swapBlocTest('a re-price without fees is held to the one reviewed', (h) {
    _onlyTheBook(h, '1.003');
    final bloc = _review(h);
    h.balances[eth] = d('1.0025');

    _start(h, bloc, _book(h, feesKnown: false, refund: null));

    expect(h.atomicExecutor.started, isEmpty);
    expect(bloc.state.review?.status, SwapReviewStatus.revalidationFailed);
  });

  swapBlocTest('a token whose network coin falls short stops too', (h) {
    // The 0.002 ETH of gas a token pays includes its refund.
    _onlyTheBook(h, '0.002');
    h.atomic.respond = (request) => [
      SwapQuoteAvailable(
        _book(h, from: usdc, sell: '${request.amount}', gas: '0.002'),
      ),
    ];
    final bloc = _review(h, pay: 'USDC-ERC20', amount: '100');
    expect(bloc.state.review!.status, SwapReviewStatus.ready);

    _start(h, bloc, _book(h, from: usdc, sell: '100', gas: '0.0024'));

    expect(h.atomicExecutor.started, isEmpty);
    expect(bloc.state.review?.status, SwapReviewStatus.revalidationFailed);
    expect(bloc.state.review?.revalidationFailure?.asset, eth);
  });

  swapBlocTest('a refreshed price that no longer fits is not offered', (h) {
    _onlyTheBook(h, '1.003');
    final bloc = _review(h);
    h.elapse(SwapQuote.lifetime);
    expect(bloc.state.review!.status, SwapReviewStatus.expired);

    _start(h, bloc, _book(h, gas: '0.00115', refund: '0.0023'));

    expect(bloc.state.review?.status, SwapReviewStatus.revalidationFailed);
  });

  swapBlocTest('a routed re-price whose fees no longer fit stops too', (h) {
    h.balances[eth] = d('1.0011');
    final bloc = h.inReview();
    h.routed.requoteResult = SwapQuoteAvailable(
      quoteOf(
        id: 'fresh',
        fees: [feeOf(amount: '0.0012')],
        quotedAt: h.now(),
      ),
    );

    bloc.add(const UnifiedSwapStartRequested());
    h.settle();

    expect(h.routedExecutor.started, isEmpty);
    expect(bloc.state.review?.status, SwapReviewStatus.revalidationFailed);
  });
}

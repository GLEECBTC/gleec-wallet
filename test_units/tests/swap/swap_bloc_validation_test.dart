import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

import 'swap_bloc_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the form's checks that depend on prices and fees rather than on
/// the typed text alone.
void main() {
  swapBlocTest('a dollar amount with no price to convert it is named', (h) {
    final bloc = h.open()..add(const UnifiedSwapAmountModeToggled());
    h.settle();
    h.prices.prices.remove(eth);

    bloc.add(const UnifiedSwapAmountChanged('100'));
    h.settle();

    expect(bloc.state.issue, SwapFormIssue.fiatUnavailable);
    expect(bloc.amountOf(bloc.state), isNull);
    expect(h.routed.requests, hasLength(1));
  });

  swapBlocTest('permission gas counts against the network coin', (h) {
    h.balances[eth] = d('0.0025');
    h.routed.respond = (request) => [
      SwapQuoteAvailable(
        quoteOf(
          from: usdc,
          to: eth,
          sell: request.amount.toString(),
          quotedAt: h.now(),
          fees: [
            feeOf(amount: '0.002', kind: SwapFeeKind.approvalNetwork),
            feeOf(),
          ],
        ),
      ),
    ];
    final bloc = h.open(pay: 'USDC-ERC20', receive: 'ETH', amount: '100');

    expect(bloc.state.selectedQuote, isNotNull);
    expect(bloc.state.issue, SwapFormIssue.insufficientForFees);
    expect(bloc.state.canReview, isFalse);
  });

  swapBlocTest(
    'a route fee is not counted as gas the network coin must cover',
    (h) {
      h.balances[eth] = d('0.0025');
      h.routed.respond = (request) => [
        SwapQuoteAvailable(
          quoteOf(
            from: usdc,
            to: eth,
            sell: request.amount.toString(),
            quotedAt: h.now(),
            fees: [
              feeOf(amount: '0.002', kind: SwapFeeKind.swap),
              feeOf(),
            ],
          ),
        ),
      ];
      final bloc = h.open(pay: 'USDC-ERC20', receive: 'ETH', amount: '100');

      expect(bloc.state.issue, isNull);
      expect(bloc.state.canReview, isTrue);
    },
  );

  swapBlocTest('a failed price keeps checking the amount itself', (h) {
    h.routed
      ..respond = null
      ..results = [rejected(SwapQuoteFailureKind.noRoute)];
    final bloc = h.open(amount: '3');

    expect(bloc.state.evaluation, SwapEvaluationStatus.failed);
    expect(bloc.state.issue, SwapFormIssue.insufficient);
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

import 'swap_bloc_fakes.dart';
import 'swap_test_fixtures.dart';

/// Exercises the boundaries between KDF Max/funding and the start/review fixes.
void main() {
  swapBlocTest(
    'a new required balance blocks Start even when estimated gas fits',
    (h) {
      h.balances[eth] = d('1.01');
      final bloc = h.inReview();
      h.routed.requoteResult = SwapQuoteAvailable(
        quoteOf(quotedAt: h.now(), requiredGasBalance: '0.02'),
      );
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();

      expect(h.routedExecutor.started, isEmpty);
      expect(bloc.state.review!.status, SwapReviewStatus.revalidationFailed);
      expect(
        bloc.state.review!.revalidationFailure!.kind,
        SwapQuoteFailureKind.insufficientFunds,
      );
    },
  );

  swapBlocTest('a replacement token quote checks its own native funding', (h) {
    final bloc = h.open(amount: '0.001');
    h.resolve(h.terms.recordAcceptance(at: h.now()));
    h.balances[eth] = d('0.005');
    bloc.add(
      UnifiedSwapFreshQuoteAccepted(
        quoteOf(
          from: usdc,
          to: eth,
          sell: '100',
          requiredGasBalance: '0.01',
          quotedAt: h.now(),
        ),
      ),
    );
    h.settle();

    expect(h.routed.requoted.single.from, usdc);
    expect(h.routedExecutor.started, isEmpty);
    expect(bloc.state.review!.revalidationFailure!.asset, eth);
    expect(bloc.state.review!.status, SwapReviewStatus.revalidationFailed);
  });

  swapBlocTest('changing slippage beside a Max review keeps Max as intent', (
    h,
  ) {
    h.routed.max = SwapMaxAmount(
      amount: d('1.99'),
      reservedForFees: d('0.01'),
      source: SwapLiquiditySource.routed,
    );
    final bloc = h.open()..add(const UnifiedSwapMaxRequested());
    h.settle();
    bloc.add(const UnifiedSwapReviewOpened());
    h.settle();
    final reviewed = bloc.state.review!.quote;

    bloc
      ..add(const UnifiedSwapSlippageChanged(0.01))
      ..add(const UnifiedSwapStartRequested());
    h.settle();

    expect(bloc.state.view, UnifiedSwapView.form);
    expect(bloc.state.review, isNull);
    expect(bloc.state.maxRequested, isTrue);
    expect(h.routed.requests.last.maxSource, SwapLiquiditySource.routed);
    expect(h.routed.requests.last.slippage, 0.01);
    expect(reviewed.slippage, isNot(0.01));
    expect(h.routedExecutor.started, isEmpty);
  });

  swapBlocTest('switching a Max source beside review closes the old review', (
    h,
  ) {
    h.routed.max = SwapMaxAmount(
      amount: d('1.99'),
      reservedForFees: d('0.01'),
      source: SwapLiquiditySource.routed,
    );
    h.atomic
      ..max = SwapMaxAmount(
        amount: d('1.98'),
        reservedForFees: d('0.02'),
        source: SwapLiquiditySource.atomic,
      )
      ..respond = (request) => [
        SwapQuoteAvailable(
          quoteOf(
            id: 'atomic',
            source: SwapLiquiditySource.atomic,
            sell: request.amount.toString(),
            guaranteed: '2900',
            quotedAt: h.now(),
          ),
        ),
      ];
    final bloc = h.open()..add(const UnifiedSwapMaxRequested());
    h.settle();
    bloc.add(const UnifiedSwapReviewOpened());
    h.settle();
    bloc
      ..add(const UnifiedSwapOptionSelected('atomic'))
      ..add(const UnifiedSwapStartRequested());
    h.settle();

    expect(bloc.state.view, UnifiedSwapView.form);
    expect(bloc.state.review, isNull);
    expect(bloc.state.selectedQuote!.source, SwapLiquiditySource.atomic);
    expect(bloc.state.inputText, '1.98');
    expect(bloc.state.maxRequested, isTrue);
    expect(h.routedExecutor.started, isEmpty);
    expect(h.atomicExecutor.started, isEmpty);
  });

  swapBlocTest('an identical manual amount exits Max while balances reload', (
    h,
  ) {
    h.routed.max = SwapMaxAmount(
      amount: d('1.99'),
      reservedForFees: d('0.01'),
      source: SwapLiquiditySource.routed,
    );
    final bloc = h.open()..add(const UnifiedSwapMaxRequested());
    h.settle();
    final gate = h.balanceGate = Completer<void>();
    bloc.add(UnifiedSwapAmountChanged(bloc.state.inputText));
    h.settle();
    expect(bloc.state.maxRequested, isFalse);
    expect(h.routed.requests.last.maxSource, isNull);
    gate.complete();
    h.settle();
    expect(bloc.state.maxRequested, isFalse);
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

import 'swap_bloc_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers what the user asks for: the two assets, the amount and its unit,
/// the slippage, and Max.
void main() {
  group('choosing assets', () {
    swapBlocTest('picking an asset already on its side changes nothing', (h) {
      final bloc = h.open()
        ..add(UnifiedSwapPayAssetChanged(eth))
        ..add(UnifiedSwapReceiveAssetChanged(usdc));
      h.settle();

      expect(bloc.state.inputText, '1');
      expect(bloc.state.evaluation, SwapEvaluationStatus.ready);
      expect(h.routed.requests, hasLength(1));
      expect(h.resolve(h.preferences.recentAssets()), isEmpty);
    });

    swapBlocTest('a new pay asset is remembered and clears the amount', (h) {
      final bloc = h.open()..add(UnifiedSwapPayAssetChanged(btc));
      h.settle();

      expect((bloc.state.pay, bloc.state.receive), (btc, usdc));
      expect(bloc.state.inputText, isEmpty);
      expect(bloc.state.quotes, isNull);
      expect(bloc.state.issue, SwapFormIssue.amountMissing);
      expect(bloc.state.balance, d('1'));
      expect(h.resolve(h.preferences.recentAssets()), ['BTC']);
    });

    swapBlocTest('paying with the asset being received swaps the sides', (h) {
      final bloc = h.open()..add(UnifiedSwapPayAssetChanged(usdc));
      h.settle();

      expect((bloc.state.pay, bloc.state.receive), (usdc, eth));
      expect(bloc.state.inputText, isEmpty);
      expect(bloc.state.feeBalance, d('2'));
    });

    swapBlocTest('a new receive asset keeps the amount and prices again', (h) {
      final bloc = h.open()..add(UnifiedSwapReceiveAssetChanged(btc));
      h.settle();

      expect((bloc.state.pay, bloc.state.receive), (eth, btc));
      expect(bloc.state.inputText, '1');
      expect(h.routed.requests.last.to, btc);
      expect(bloc.state.evaluation, SwapEvaluationStatus.ready);
      expect(h.resolve(h.preferences.recentAssets()), ['BTC']);
    });

    swapBlocTest('receiving the asset being paid swaps the sides', (h) {
      final bloc = h.open()..add(UnifiedSwapReceiveAssetChanged(eth));
      h.settle();

      expect((bloc.state.pay, bloc.state.receive), (usdc, eth));
      expect(bloc.state.inputText, isEmpty);
    });

    swapBlocTest('switching sides moves a lone asset across', (h) {
      final bloc = h.build();
      final states = h.record(bloc);
      bloc.add(const UnifiedSwapSidesSwitched());
      h.settle();
      expect(states, isEmpty);

      bloc.add(const UnifiedSwapIntentApplied(pay: 'ETH'));
      h.settle();
      expect(bloc.state.balance, d('2'));
      bloc.add(const UnifiedSwapSidesSwitched());
      h.settle();

      expect((bloc.state.pay, bloc.state.receive), (null, eth));
      expect(bloc.state.balance, isNull);
    });
  });

  group('amount unit', () {
    swapBlocTest('dollars and back again keep the amount traded', (h) {
      final bloc = h.open(amount: '0.5')
        ..add(const UnifiedSwapAmountModeToggled());
      h.settle();
      expect(bloc.state.amountMode, SwapAmountMode.fiat);
      expect(bloc.state.inputText, '1500');
      expect(bloc.amountOf(bloc.state), d('0.5'));

      bloc.add(const UnifiedSwapAmountModeToggled());
      h.settle();
      expect(bloc.state.amountMode, SwapAmountMode.token);
      expect(bloc.state.inputText, '0.5');
    });

    swapBlocTest('with nothing typed only the unit changes', (h) {
      final bloc = h.open(amount: '')
        ..add(const UnifiedSwapAmountModeToggled());
      h.settle();

      expect(bloc.state.amountMode, SwapAmountMode.fiat);
      expect(bloc.state.inputText, isEmpty);
    });

    swapBlocTest('stays in tokens without a pay asset or its price', (h) {
      final empty = h.build()..add(const UnifiedSwapAmountModeToggled());
      final unpriced = h.open(pay: 'BTC', receive: 'ETH')
        ..add(const UnifiedSwapAmountModeToggled());
      h.settle();

      expect(empty.state.amountMode, SwapAmountMode.token);
      expect(unpriced.state.amountMode, SwapAmountMode.token);
      expect(unpriced.state.inputText, '1');
    });
  });

  swapBlocTest('the slippage already in use does not price again', (h) {
    final bloc = h.open()
      ..add(const UnifiedSwapSlippageChanged(swapDefaultSlippage));
    h.settle();

    expect(h.routed.requests, hasLength(1));
    expect(bloc.state.evaluation, SwapEvaluationStatus.ready);
  });

  group('Max', () {
    SwapMaxAmount maxOf(String amount) =>
        SwapMaxAmount(amount: d(amount), reservedForFees: d('0.01'));

    swapBlocTest('does nothing without a known balance', (h) {
      h.balances.remove(eth);
      h.routed.max = maxOf('1.99');
      final bloc = h.open()..add(const UnifiedSwapMaxRequested());
      h.settle();

      expect(bloc.state.inputText, '1');
      expect(bloc.state.maxApplied, isNull);
    });

    swapBlocTest('without a receive asset fills the whole balance', (h) {
      final bloc = h.open(receive: null, amount: '0.1')
        ..add(const UnifiedSwapAmountModeToggled());
      h.settle();
      expect(bloc.state.amountMode, SwapAmountMode.fiat);

      bloc.add(const UnifiedSwapMaxRequested());
      h.settle();

      expect(bloc.state.inputText, '2');
      expect(bloc.state.amountMode, SwapAmountMode.token);
      expect(bloc.state.maxApplied, isNull);
    });

    swapBlocTest('keeps back what the selected route needs', (h) {
      h.routed.max = maxOf('1.99');
      h.atomic.max = maxOf('1.995');
      final bloc = h.open()..add(const UnifiedSwapMaxRequested());
      h.settle();

      expect(bloc.state.inputText, '1.99');
      expect(bloc.state.maxApplied, maxOf('1.99'));
      expect(h.routed.requests.last.amount, d('1.99'));
    });

    swapBlocTest('with no route selected takes the larger allowance', (h) {
      h.routed
        ..respond = null
        ..results = [rejected(SwapQuoteFailureKind.noRoute)]
        ..max = maxOf('1.99');
      h.atomic.max = maxOf('1.995');
      final bloc = h.open();
      expect(bloc.state.selectedQuote, isNull);

      bloc.add(const UnifiedSwapMaxRequested());
      h.settle();

      expect(bloc.state.inputText, '1.995');
      expect(bloc.state.maxApplied, maxOf('1.995'));
    });

    swapBlocTest('leaves the amount when no source can tell', (h) {
      final bloc = h.open()..add(const UnifiedSwapMaxRequested());
      h.settle();

      expect(bloc.state.inputText, '1');
      expect(bloc.state.maxApplied, isNull);
      expect(h.routed.requests, hasLength(1));
    });

    swapBlocTest('an allowance for a pair since changed is dropped', (h) {
      h.routed
        ..max = maxOf('1.99')
        ..maxGate = Completer<void>();
      final bloc = h.open()..add(const UnifiedSwapMaxRequested());
      h.settle();
      bloc.add(UnifiedSwapPayAssetChanged(btc));
      h.settle();

      h.routed.maxGate!.complete();
      h.settle();

      expect(bloc.state.pay, btc);
      expect(bloc.state.inputText, isEmpty);
      expect(bloc.state.maxApplied, isNull);
    });
  });
}

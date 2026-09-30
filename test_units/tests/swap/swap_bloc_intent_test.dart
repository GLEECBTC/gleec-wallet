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

    swapBlocTest("a new pay asset hides the old one's balance until read", (h) {
      final bloc = h.open(pay: 'USDC-ERC20', receive: 'ETH');
      expect((bloc.state.balance, bloc.state.feeBalance), (d('5000'), d('2')));
      final read = h.balanceGate = Completer<void>();
      bloc.add(UnifiedSwapPayAssetChanged(btc));
      h.settle();

      expect(bloc.state.pay, btc);
      expect(bloc.state.balance, isNull);
      expect(bloc.state.feeBalance, isNull);
      // A press already on its way does nothing with the old balance.
      bloc.add(const UnifiedSwapMaxRequested());
      h.settle();
      expect(bloc.state.inputText, isEmpty);
      expect(h.routed.maxCalls, 0);
      expect(h.atomic.maxCalls, 0);

      read.complete();
      h.settle();
      expect(bloc.state.balance, d('1'));
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

    swapBlocTest('a new receive asset keeps the balance throughout', (h) {
      final bloc = h.open(pay: 'USDC-ERC20', receive: 'ETH');
      final states = h.record(bloc);
      final read = h.balanceGate = Completer<void>();
      bloc.add(UnifiedSwapReceiveAssetChanged(btc));
      h.settle();
      expect(bloc.state.receive, btc);

      read.complete();
      h.settle();

      expect(states, isNotEmpty);
      for (final state in states) {
        expect((state.balance, state.feeBalance), (d('5000'), d('2')));
      }
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

  swapBlocTest('an amount the form offered is used in tokens at once', (h) {
    final bloc = h.open(amount: '0.1')
      ..add(const UnifiedSwapAmountModeToggled());
    h.settle();
    expect(bloc.state.amountMode, SwapAmountMode.fiat);

    bloc.add(UnifiedSwapAmountSuggested(d('0.5')));
    h.settle();

    expect(bloc.state.inputText, '0.5');
    expect(bloc.state.amountMode, SwapAmountMode.token);
    expect(bloc.state.evaluation, SwapEvaluationStatus.ready);
    expect(h.routed.requests.last.amount, d('0.5'));
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

    /// Holds the routed answer, [amount] or none, until the gate completes.
    Completer<void> holdMax(SwapBlocHarness h, {String? amount = '1.99'}) {
      final gate = Completer<void>();
      h.routed
        ..max = amount == null ? null : maxOf(amount)
        ..maxGate = gate;
      return gate;
    }

    swapBlocTest('shows the whole balance at once, and prices the answer', (h) {
      final gate = holdMax(h);
      final bloc = h.open()..add(const UnifiedSwapMaxRequested());
      h.settle();

      expect(bloc.state.inputText, '2');
      expect(bloc.state.checkingMax, isTrue);
      expect(bloc.state.quotes, isNull);
      // Not even a retry prices the whole balance meanwhile.
      bloc.add(const UnifiedSwapEvaluationRequested());
      h.settle();
      expect(h.routed.requests, hasLength(1));

      gate.complete();
      h.settle();

      expect(bloc.state.inputText, '1.99');
      expect(bloc.state.checkingMax, isFalse);
      expect(bloc.state.maxApplied, maxOf('1.99'));
      expect(h.routed.requests.last.amount, d('1.99'));
    });

    swapBlocTest('asks only the selected route what it needs kept', (h) {
      h.routed.max = maxOf('1.99');
      h.atomic.max = maxOf('1.995');
      final bloc = h.open()..add(const UnifiedSwapMaxRequested());
      h.settle();

      expect(bloc.state.inputText, '1.99');
      expect(bloc.state.maxApplied, maxOf('1.99'));
      expect(h.routed.requests.last.amount, d('1.99'));
      expect(h.atomic.maxCalls, 0);
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

    swapBlocTest('keeps the whole balance when no source can tell', (h) {
      final bloc = h.open()..add(const UnifiedSwapMaxRequested());
      h.settle();

      expect(bloc.state.inputText, '2');
      expect(bloc.state.checkingMax, isFalse);
      expect(bloc.state.maxApplied, isNull);
      expect(h.routed.requests.last.amount, d('2'));
    });

    swapBlocTest('stops waiting when pricing would have timed out', (h) {
      holdMax(h);
      final bloc = h.open()..add(const UnifiedSwapMaxRequested());
      h.elapse(const Duration(seconds: 25));

      expect(bloc.state.checkingMax, isFalse);
      expect(bloc.state.inputText, '2');
      expect(h.routed.requests.last.amount, d('2'));
    });

    for (final (name, edit) in [
      ('typed', const UnifiedSwapAmountChanged('0.5')),
      ('the form offered', UnifiedSwapAmountSuggested(d('0.5'))),
    ]) {
      swapBlocTest('an amount $name meanwhile wins', (h) {
        final gate = holdMax(h);
        final bloc = h.open()..add(const UnifiedSwapMaxRequested());
        h.settle();
        bloc.add(edit);
        h.settle();
        expect(bloc.state.checkingMax, isFalse);

        gate.complete();
        h.settle();

        expect(bloc.state.inputText, '0.5');
        expect(bloc.state.maxApplied, isNull);
        expect(h.routed.requests.last.amount, d('0.5'));
      });
    }

    swapBlocTest('a second press while it works asks once', (h) {
      final gate = holdMax(h);
      final bloc = h.open()
        ..add(const UnifiedSwapMaxRequested())
        ..add(const UnifiedSwapMaxRequested());
      h.settle();
      gate.complete();
      h.settle();

      expect(h.routed.maxCalls, 1);
      expect(bloc.state.inputText, '1.99');
    });

    swapBlocTest('only the latest press lands', (h) {
      final first = holdMax(h);
      final bloc = h.open()..add(const UnifiedSwapMaxRequested());
      h.settle();
      bloc.add(const UnifiedSwapAmountChanged('0.5'));
      h.settle();
      final second = holdMax(h, amount: '1.98');
      bloc.add(const UnifiedSwapMaxRequested());
      h.settle();

      first.complete();
      h.settle();
      expect(bloc.state.checkingMax, isTrue);
      expect(bloc.state.inputText, '2');

      second.complete();
      h.settle();
      expect(bloc.state.checkingMax, isFalse);
      expect(bloc.state.inputText, '1.98');
    });

    swapBlocTest('an answer for a pair since changed is dropped', (h) {
      final gate = holdMax(h);
      final bloc = h.open()..add(const UnifiedSwapMaxRequested());
      h.settle();
      bloc.add(UnifiedSwapPayAssetChanged(btc));
      h.settle();

      gate.complete();
      h.settle();

      expect(bloc.state.pay, btc);
      expect(bloc.state.inputText, isEmpty);
      expect(bloc.state.maxApplied, isNull);
      expect(bloc.state.checkingMax, isFalse);
    });

    swapBlocTest('a new asset to receive asks again for the new pair', (h) {
      final gate = holdMax(h);
      final bloc = h.open()..add(const UnifiedSwapMaxRequested());
      h.settle();
      bloc.add(UnifiedSwapReceiveAssetChanged(btc));
      h.settle();
      expect(bloc.state.checkingMax, isTrue);

      gate.complete();
      h.settle();

      expect(bloc.state.receive, btc);
      expect(bloc.state.inputText, '1.99');
      expect(bloc.state.maxApplied, maxOf('1.99'));
      expect(h.routed.maxCalls, 2);
      expect(h.routed.requests.last.to, btc);
    });

    swapBlocTest('a link to pay with another asset does not ask again', (h) {
      final gate = holdMax(h);
      final bloc = h.open()..add(const UnifiedSwapMaxRequested());
      h.settle();
      bloc.add(const UnifiedSwapIntentApplied(pay: 'BTC'));
      h.settle();

      gate.complete();
      h.settle();

      expect(bloc.state.pay, btc);
      expect(bloc.state.checkingMax, isFalse);
      expect(bloc.state.maxApplied, isNull);
      expect(h.routed.maxCalls, 1);
    });

    swapBlocTest('a link with an amount of its own drops it', (h) {
      final gate = holdMax(h);
      final bloc = h.open()..add(const UnifiedSwapMaxRequested());
      h.settle();
      bloc.add(const UnifiedSwapIntentApplied(receive: 'BTC', amount: '0.5'));
      h.settle();

      gate.complete();
      h.settle();

      expect(bloc.state.inputText, '0.5');
      expect(bloc.state.checkingMax, isFalse);
      expect(h.routed.maxCalls, 1);
    });

    swapBlocTest('an answer after the form was reset is dropped', (h) {
      final gate = holdMax(h);
      final bloc = h.open()..add(const UnifiedSwapMaxRequested());
      h.settle();
      bloc.add(const UnifiedSwapResetRequested());
      h.settle();

      gate.complete();
      h.settle();

      expect(bloc.state.inputText, isEmpty);
      expect(bloc.state.maxApplied, isNull);
      expect(bloc.state.checkingMax, isFalse);
    });

    swapBlocTest('the answer switches a dollar amount back to tokens', (h) {
      final gate = holdMax(h);
      final bloc = h.open()..add(const UnifiedSwapMaxRequested());
      h.settle();
      bloc.add(const UnifiedSwapAmountModeToggled());
      h.settle();
      expect(bloc.state.inputText, '6000');

      gate.complete();
      h.settle();

      expect(bloc.state.amountMode, SwapAmountMode.token);
      expect(bloc.state.inputText, '1.99');
    });

    swapBlocTest('with no answer, a switch to dollars meanwhile stays', (h) {
      final gate = holdMax(h, amount: null);
      final bloc = h.open()..add(const UnifiedSwapMaxRequested());
      h.settle();
      bloc.add(const UnifiedSwapAmountModeToggled());
      h.settle();

      gate.complete();
      h.settle();

      expect(bloc.state.amountMode, SwapAmountMode.fiat);
      expect(bloc.state.inputText, '6000');
      expect(h.routed.requests.last.amount, d('2'));
    });
  });
}

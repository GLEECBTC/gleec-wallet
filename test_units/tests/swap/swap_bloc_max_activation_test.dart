import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

import 'swap_bloc_fakes.dart';
import 'swap_test_fixtures.dart';

SwapMaxAmount _maxOf(String amount) =>
    SwapMaxAmount(amount: d(amount), reservedForFees: d('0.01'));

/// Covers Max asking again for the asset to receive: once it is activated, as
/// Max asked before could not read every fee it keeps back, and when it
/// changes, as Max is sized for its pair.
void main() {
  swapBlocTest('Max asks again once the asset to receive is active', (h) {
    h.routed.max = _maxOf('1.99');
    final bloc = h.open()..add(const UnifiedSwapMaxRequested());
    h.settle();
    expect(bloc.state.inputText, '1.99');

    h.routed.max = _maxOf('1.98');
    bloc.add(UnifiedSwapAssetActivated(usdc));
    h.settle();

    expect(bloc.state.inputText, '1.98');
    expect(bloc.state.maxApplied, _maxOf('1.98'));
    expect(h.routed.maxCalls, 2);
    expect(h.routed.requests.last.amount, d('1.98'));
  });

  swapBlocTest('an amount typed after Max stays when it is activated', (h) {
    h.routed.max = _maxOf('1.99');
    final bloc = h.open()..add(const UnifiedSwapMaxRequested());
    h.settle();
    bloc.add(const UnifiedSwapAmountChanged('1.5'));
    h.settle();

    bloc.add(UnifiedSwapAssetActivated(usdc));
    h.settle();

    expect(bloc.state.inputText, '1.5');
    expect(h.routed.maxCalls, 1);
    expect(h.routed.requests.last.amount, d('1.5'));
  });

  swapBlocTest('activating another asset does not ask Max again', (h) {
    h.routed.max = _maxOf('1.99');
    final bloc = h.open()..add(const UnifiedSwapMaxRequested());
    h.settle();

    bloc.add(UnifiedSwapAssetActivated(btc));
    h.settle();

    expect(bloc.state.inputText, '1.99');
    expect(h.routed.maxCalls, 1);
    expect(h.routed.requests.last.amount, d('1.99'));
  });

  swapBlocTest('Max asks again for a new asset to receive', (h) {
    h.routed.max = _maxOf('1.99');
    final bloc = h.open()..add(const UnifiedSwapMaxRequested());
    h.settle();

    h.routed.max = _maxOf('1.98');
    bloc.add(UnifiedSwapReceiveAssetChanged(btc));
    h.settle();

    expect(bloc.state.receive, btc);
    expect(bloc.state.inputText, '1.98');
    expect(bloc.state.maxApplied, _maxOf('1.98'));
    expect(h.routed.maxCalls, 2);
    expect(h.routed.requests.last.to, btc);
  });

  swapBlocTest('an amount typed after Max stays for a new asset to receive', (
    h,
  ) {
    h.routed.max = _maxOf('1.99');
    final bloc = h.open()..add(const UnifiedSwapMaxRequested());
    h.settle();
    bloc.add(const UnifiedSwapAmountChanged('1.5'));
    h.settle();

    bloc.add(UnifiedSwapReceiveAssetChanged(btc));
    h.settle();

    expect(bloc.state.inputText, '1.5');
    expect(h.routed.maxCalls, 1);
    expect(h.routed.requests.last.amount, d('1.5'));
  });
}

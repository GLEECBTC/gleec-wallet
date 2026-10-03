import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';

import 'swap_bloc_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers how the form opens: what can be traded, the pair it starts on,
/// and intents from deep links and other screens.
void main() {
  (AssetId?, AssetId?) openingPair(SwapBlocHarness h) {
    final bloc = h.build()..add(const UnifiedSwapStarted());
    h.settle();
    expect(bloc.state.loadingAssets, isFalse);
    return (bloc.state.pay, bloc.state.receive);
  }

  void tradeOnly(SwapBlocHarness h, Set<AssetId> assets) {
    h.routed.tradable = assets;
    h.atomic.tradable = assets;
  }

  swapBlocTest('a pair set while assets load is priced once they arrive', (h) {
    h.catalogGate = Completer<void>();
    final bloc = h.build()
      ..add(const UnifiedSwapStarted())
      ..add(
        const UnifiedSwapIntentApplied(
          pay: 'ETH',
          receive: 'USDC-ERC20',
          amount: '1',
        ),
      );
    h.settle();
    expect(bloc.state.loadingAssets, isTrue);
    expect(h.routed.requests, isEmpty);

    h.catalogGate!.complete();
    h.settle();

    expect(bloc.state.loadingAssets, isFalse);
    expect(h.routed.requests, hasLength(1));
    expect(bloc.state.evaluation, SwapEvaluationStatus.ready);
  });

  group('the opening pair', () {
    swapBlocTest('is empty with no last pair and nothing held', (h) {
      expect(openingPair(h), (null, null));
    });

    swapBlocTest('skips a last pair that no longer trades', (h) {
      h.resolve(h.preferences.rememberPair(gleec, eth));
      tradeOnly(h, {eth, usdc, btc});
      h.holdings = [
        (asset: eth, usdValue: d('6000')),
        (asset: btc, usdValue: d('60000')),
      ];

      expect(openingPair(h), (btc, usdc));
    });

    swapBlocTest('pairs a stablecoin held most with its network coin', (h) {
      h.holdings = [
        (asset: eth, usdValue: d('100')),
        (asset: usdc, usdValue: d('10000')),
      ];

      expect(openingPair(h), (usdc, eth));
    });

    swapBlocTest('pairs a stablecoin whose network coin cannot trade', (h) {
      tradeOnly(h, {usdc, btc});
      h.holdings = [(asset: usdc, usdValue: d('10000'))];

      expect(openingPair(h), (usdc, btc));
    });

    swapBlocTest('ignores holdings nothing can trade', (h) {
      tradeOnly(h, {eth, usdc});
      h.holdings = [
        (asset: gleec, usdValue: d('1000000')),
        (asset: eth, usdValue: d('6000')),
      ];

      expect(openingPair(h), (eth, usdc));
    });

    swapBlocTest('is empty when the holding has nothing to trade for', (h) {
      tradeOnly(h, {eth, btc});
      h.holdings = [(asset: eth, usdValue: d('6000'))];

      expect(openingPair(h), (null, null));
    });

    swapBlocTest('is empty when holdings cannot be read', (h) {
      h.holdingsError = StateError('offline');

      expect(openingPair(h), (null, null));
    });

    swapBlocTest('gives way to an intent that arrives meanwhile', (h) {
      h
        ..holdings = [(asset: eth, usdValue: d('6000'))]
        ..holdingsGate = Completer<void>();
      final bloc = h.build()..add(const UnifiedSwapStarted());
      h.settle();
      bloc.add(const UnifiedSwapIntentApplied(pay: 'BTC', receive: 'ETH'));
      h.settle();

      h.holdingsGate!.complete();
      h.settle();

      expect((bloc.state.pay, bloc.state.receive), (btc, eth));
    });
  });

  group('an intent', () {
    swapBlocTest('naming no known asset is ignored', (h) {
      h.holdings = [(asset: eth, usdValue: d('6000'))];
      final bloc = h.build()
        ..add(const UnifiedSwapIntentApplied(pay: 'NOPE', receive: 'NADA'))
        ..add(const UnifiedSwapStarted());
      h.settle();

      expect((bloc.state.pay, bloc.state.receive), (eth, usdc));
    });

    swapBlocTest('for the receive side keeps what is paid', (h) {
      final bloc = h.open()
        ..add(const UnifiedSwapIntentApplied(receive: 'BTC'));
      h.settle();

      expect((bloc.state.pay, bloc.state.receive), (eth, btc));
      expect(bloc.state.inputText, '1');
      expect(h.routed.requests.last.to, btc);
    });

    swapBlocTest('naming one asset twice keeps only the pay side', (h) {
      final bloc = h.build()
        ..add(const UnifiedSwapIntentApplied(pay: 'ETH', receive: 'ETH'));
      h.settle();

      expect((bloc.state.pay, bloc.state.receive), (eth, null));
    });

    swapBlocTest('to pay with the asset received names the conflict', (h) {
      final bloc = h.open()
        ..add(const UnifiedSwapIntentApplied(pay: 'USDC-ERC20'));
      h.settle();

      expect((bloc.state.pay, bloc.state.receive), (usdc, usdc));
      expect(bloc.state.issue, SwapFormIssue.sameAsset);
      expect(bloc.state.canReview, isFalse);
      expect(h.routed.requests, hasLength(1));
    });
  });
}

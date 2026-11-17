import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_preferences.dart';
import 'package:web_dex/shared/swap/swap_pricing.dart';

import 'swap_bloc_fakes.dart';
import 'swap_test_fixtures.dart';

void main() {
  test(
    'amount mode belongs to the wallet and never persists a spend amount',
    () async {
      final storage = MemoryStorage();
      var wallet = 'first';
      final preferences = SwapPreferences(
        walletKey: () async => wallet,
        storage: storage,
      );
      expect(await preferences.prefersFiatAmount(), isNull);
      await preferences.rememberFiatAmount(false);
      wallet = 'second';
      expect(await preferences.prefersFiatAmount(), isNull);
      await preferences.rememberFiatAmount(true);
      wallet = 'first';
      expect(await preferences.prefersFiatAmount(), isFalse);
      wallet = 'second';
      expect(await preferences.prefersFiatAmount(), isTrue);
    },
  );

  swapBlocTest(
    'an untouched priced field defaults to dollars before balances arrive',
    (h) {
      h.balanceGate = Completer<void>();
      final bloc = h.open(amount: null);
      expect(bloc.state.amountMode, SwapAmountMode.fiat);
      expect(bloc.state.preparingAssets, isTrue);
      expect(bloc.state.inputText, isEmpty);
      h.balanceGate!.complete();
      h.settle();
    },
  );

  swapBlocTest('explicit crypto preference is used for the next empty form', (
    h,
  ) {
    h.resolve(h.preferences.rememberFiatAmount(false));
    final bloc = h.open(amount: null);
    expect(bloc.state.amountMode, SwapAmountMode.token);
    bloc.add(const UnifiedSwapAmountModeToggled());
    h.settle();
    expect(h.resolve(h.preferences.prefersFiatAmount()), isTrue);
    final fresh = h.open(amount: null);
    expect(fresh.state.amountMode, SwapAmountMode.fiat);
    expect(fresh.state.inputText, isEmpty);
  });

  swapBlocTest('a late fiat price cannot reinterpret entered crypto', (h) {
    final prices = _GatedPrices();
    final bloc = h.open(amount: null, bloc: h.build(priceSource: prices));
    expect(bloc.state.amountMode, SwapAmountMode.token);
    bloc.add(const UnifiedSwapAmountChanged('0.25'));
    h.settle();
    prices.ready.complete();
    h.settle();
    expect(bloc.state.amountMode, SwapAmountMode.token);
    expect(bloc.state.inputText, '0.25');
    expect(bloc.amountOf(bloc.state), d('0.25'));
  });

  swapBlocTest(
    'missing conversion preserves the fiat draft through crypto fallback',
    (h) {
      final bloc = h.open(amount: '0.5')
        ..add(const UnifiedSwapAmountModeToggled());
      h.settle();
      expect(bloc.state.inputText, '1500');
      h.prices.prices.remove(eth);
      bloc.add(const UnifiedSwapAmountModeToggled());
      h.settle();
      expect(bloc.state.amountMode, SwapAmountMode.token);
      expect(bloc.state.inputText, isEmpty);
      bloc.add(const UnifiedSwapAmountModeToggled());
      h.settle();
      expect(bloc.state.amountMode, SwapAmountMode.fiat);
      expect(bloc.state.inputText, '1500');
      expect(bloc.state.issue, SwapFormIssue.fiatUnavailable);
    },
  );

  swapBlocTest(
    'quote enrichment cannot change a USD principal already quoted',
    (h) {
      final bloc = h.open(amount: null)
        ..add(const UnifiedSwapAmountChanged('300'));
      h.settle();
      expect(h.routed.requests.last.amount, d('0.1'));
      h.prices.prices[eth] = d('6000');
      expect(bloc.amountOf(bloc.state), d('0.1'));
      bloc.add(const UnifiedSwapAmountChanged('600'));
      h.settle();
      expect(h.routed.requests.last.amount, d('0.1'));
    },
  );
}

class _GatedPrices implements SwapPriceSource {
  final ready = Completer<void>();
  bool available = false;

  @override
  Decimal? usdPrice(AssetId asset) =>
      available ? (asset == eth ? d('3000') : d('1')) : null;

  @override
  Future<void> warm(Iterable<AssetId> assets) async {
    await ready.future;
    available = true;
  }
}

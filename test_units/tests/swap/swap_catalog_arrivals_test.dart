import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/routed_swap_source.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_pricing.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';

import 'swap_bloc_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers a catalog whose routed list is still on its way. KDF's first list
/// waits on the provider's networks with no deadline, so the form prices at
/// once on the wallet's estimate and takes KDF's list when it comes.
void main() {
  const routed = SwapLiquiditySource.routed;
  const atomic = SwapLiquiditySource.atomic;

  group('the aggregator', () {
    test('does not wait for KDF to list it first', () async {
      final kdf = _Kdf()..listed = {eth};
      final source = RoutedSwapQuoteSource(
        kdf,
        networks: () => SwapNetworks([eth, usdc, btc]),
      );

      final assets = await source.assets(
        known: {eth, usdc, btc},
        activated: {eth, usdc, btc},
      );
      // Every active asset on a served network, while KDF works.
      expect(assets.quotable, {eth, usdc});
      expect(kdf.calls, 1);

      kdf.gate.complete();
      expect((await assets.update!).quotable, {eth});
    });
  });

  group('the repository', () {
    late FakeQuoteSource routes;
    late UnifiedSwapRepository repository;
    late int arrivals;

    setUp(() {
      routes = FakeQuoteSource(routed, tradable: {eth, usdc});
      repository = UnifiedSwapRepository(
        sources: [
          routes,
          FakeQuoteSource(atomic, tradable: {eth}),
        ],
        pricing: SwapPricingService(FakePriceSource({})),
        activatedAssets: () async => {eth, usdc},
      );
      arrivals = 0;
      repository.arrivals.listen((_) => arrivals++);
    });

    test('a list that arrives late takes the estimate\'s place', () async {
      final list = Completer<SwapSourceAssets>();
      routes.update = list.future;
      final read = await repository.catalog();
      expect(repository.current, same(read));

      list.complete(const SwapSourceAssets(source: routed, quotable: {}));
      await pumpEventQueue();

      expect(repository.current!.of(routed)!.quotable, isEmpty);
      expect(repository.current!.of(atomic), read.of(atomic));
      expect(arrivals, 1);
    });

    test('a list that matches the estimate changes nothing', () async {
      routes.update = Future.value(
        SwapSourceAssets(source: routed, quotable: {eth, usdc}),
      );
      final read = await repository.catalog();
      await pumpEventQueue();

      expect(repository.current, same(read));
      expect(arrivals, 0);
    });

    test('a list that fails to arrive leaves the estimate', () async {
      final list = Completer<SwapSourceAssets>();
      routes.update = list.future;
      final read = await repository.catalog();

      list.completeError(StateError('KDF went away'));
      await pumpEventQueue();

      expect(repository.current, same(read));
      expect(arrivals, 0);
    });

    test('a later read outranks an earlier read\'s late list', () async {
      final list = Completer<SwapSourceAssets>();
      routes.update = list.future;
      await repository.catalog();
      routes
        ..update = null
        ..tradable = {eth};
      final later = await repository.catalog();

      list.complete(SwapSourceAssets(source: routed, quotable: {usdc}));
      await pumpEventQueue();

      expect(repository.current, same(later));
      expect(arrivals, 0);
    });

    test('a read that returns after a later one does not replace it', () async {
      final wallet = Completer<void>();
      var reads = 0;
      repository = UnifiedSwapRepository(
        sources: [routes],
        pricing: SwapPricingService(FakePriceSource({})),
        activatedAssets: () async {
          if (++reads == 1) await wallet.future;
          return {eth, usdc};
        },
      );

      final earlier = repository.catalog();
      final later = await repository.catalog();
      wallet.complete();
      await earlier;

      expect(repository.current, same(later));
    });
  });

  group('the form', () {
    swapBlocTest('prices at once, before the routed list arrives', (h) {
      h.routed.update = Completer<SwapSourceAssets>().future;
      final bloc = h.open();

      expect(bloc.state.loadingAssets, isFalse);
      expect(bloc.state.evaluation, SwapEvaluationStatus.ready);
      expect(h.routed.requests, hasLength(1));
    });

    swapBlocTest('a list that changes who can price the pair prices it', (h) {
      final list = Completer<SwapSourceAssets>();
      h.routed.update = list.future;
      final bloc = h.open();
      expect(h.atomic.requests, hasLength(1));

      // KDF routes none of the pair after all.
      list.complete(const SwapSourceAssets(source: routed));
      h.settle();

      expect(bloc.state.pairSupport!.sources, {atomic});
      expect(h.routed.requests, hasLength(1));
      expect(h.atomic.requests, hasLength(2));
    });

    swapBlocTest('a list that leaves the pair alone costs no request', (h) {
      final list = Completer<SwapSourceAssets>();
      h.routed.update = list.future;
      final bloc = h.open();

      list.complete(SwapSourceAssets(source: routed, quotable: {eth, usdc}));
      h.settle();

      expect(bloc.state.catalog.of(routed)!.quotable, {eth, usdc});
      expect(h.routed.requests, hasLength(1));
      expect(h.atomic.requests, hasLength(1));
    });

    swapBlocTest('a read that lands after a later one leaves the later list', (
      h,
    ) {
      final wallet = Completer<void>();
      h.catalogGate = wallet;
      final bloc = h.build()..add(const UnifiedSwapStarted());
      h.settle();
      h
        ..catalogGate = null
        ..routed.tradable = {eth};
      bloc.add(const UnifiedSwapCatalogRefreshRequested());
      h.settle();
      expect(bloc.state.catalog.of(routed)!.quotable, {eth});

      h.routed.tradable = {eth, usdc, btc};
      wallet.complete();
      h.settle();

      expect(bloc.state.catalog.of(routed)!.quotable, {eth});
    });

    swapBlocTest(
      'a refresh that lands after a later one leaves the later list',
      (h) {
        final bloc = h.open();
        final wallet = Completer<void>();
        h.catalogGate = wallet;
        bloc.add(const UnifiedSwapCatalogRefreshRequested());
        h.settle();
        h
          ..catalogGate = null
          ..routed.tradable = {eth, usdc};
        bloc.add(const UnifiedSwapCatalogRefreshRequested());
        h.settle();

        h.routed.tradable = {eth, usdc, btc};
        wallet.complete();
        h.settle();

        expect(bloc.state.catalog.of(routed)!.quotable, {eth, usdc});
      },
    );

    swapBlocTest('a list arriving does not keep an idle form pricing', (h) {
      final list = Completer<SwapSourceAssets>();
      h.routed.update = list.future;
      h.open(bloc: h.build(idleLimit: const Duration(minutes: 2)));
      h.elapse(const Duration(seconds: 90));

      list.complete(SwapSourceAssets(source: routed, quotable: {eth, usdc}));
      h.elapse(const Duration(seconds: 90));

      // Priced on opening and every 30 s until the idle limit, as always.
      expect(h.routed.requests, hasLength(4));
    });

    swapBlocTest('a list that lands during a review is kept, not priced', (h) {
      final list = Completer<SwapSourceAssets>();
      h.routed.update = list.future;
      final bloc = h.inReview();
      expect(bloc.state.view, UnifiedSwapView.review);
      final asked = h.routed.requests.length + h.atomic.requests.length;

      list.complete(const SwapSourceAssets(source: routed));
      h.settle();

      expect(bloc.state.catalog.of(routed)!.quotable, isEmpty);
      expect(h.routed.requests.length + h.atomic.requests.length, asked);
    });
  });
}

/// KDF's routed-swap manager, listing [listed] once [gate] opens.
class _Kdf implements RoutedSwapManager {
  final gate = Completer<void>();
  Set<AssetId> listed = {};
  int calls = 0;

  @override
  Future<Set<AssetId>> eligibleAssets({String? provider}) async {
    calls++;
    await gate.future;
    return listed;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/shared/swap/routed_swap_source.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_preferences.dart';
import 'package:web_dex/shared/swap/swap_pricing.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/swap/swap_terms_repository.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';

import 'swap_src_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers Max on a network's own coin when every route charges a provider
/// fee on top, paid in that coin with the gas, as Squid's gas receiver fee
/// is: what Max fills must pass the form's own check. Runs the real bloc,
/// repository and routed source over a scripted manager, with 2 ETH held,
/// 0.0005 ETH of gas and a 0.0012 ETH fee.
void main() {
  test('Max keeps back the fee of a route priced moments ago', () {
    _run((bloc, manager, async) {
      bloc.add(const UnifiedSwapMaxRequested());
      async.elapse(const Duration(seconds: 3));

      expect(manager.maxCalls, 0, reason: 'the quote for 1 ETH stood in');
      expect(bloc.state.inputText, '1.9973');
      expect(
        bloc.state.maxApplied!.reserveCovers,
        SwapMaxReserve.networkAndProviderFees,
      );
      expect(bloc.state.selectedQuote!.sellAmount, d('1.9973'));
      expect(bloc.state.issue, isNull);
      expect(bloc.state.canReview, isTrue);
    });
  });

  test('Max before the pair has a price fits the first time', () {
    _run(amount: '', (bloc, manager, async) {
      // KDF's probe as the pinned SDK makes it: three times the gas, and the
      // fee on top.
      manager.max = RoutedSwapMaxSell(
        amount: d('1.9973'),
        reservedForFees: d('0.0027'),
        feeAsset: eth,
        reservedForProviderFees: d('0.0012'),
      );
      bloc.add(const UnifiedSwapMaxRequested());
      async.elapse(const Duration(seconds: 3));

      expect(manager.maxCalls, 1);
      expect(bloc.state.inputText, '1.9973');
      expect(
        bloc.state.maxApplied!.reserveCovers,
        SwapMaxReserve.networkAndProviderFees,
      );
      expect(bloc.state.issue, isNull);
      expect(bloc.state.canReview, isTrue);
    });
  });
}

/// Opens the form on ETH -> USDC with [amount] and runs [script] on a fake
/// clock.
void _run(
  void Function(UnifiedSwapBloc bloc, SrcRoutedSwaps manager, FakeAsync async)
  script, {
  String amount = '1',
}) {
  fakeAsync((async) {
    final start = DateTime(2026, 10, 5, 12);
    DateTime now() => start.add(async.elapsed);
    final manager = SrcRoutedSwaps()
      ..eligible = {eth, usdc}
      ..respond = (call) => offerOf(
        from: call.from,
        to: call.to,
        sell: '${call.amount}',
        costs: [
          RoutedSwapCost(
            label: 'Network fee',
            amount: d('0.0005'),
            kind: RoutedSwapCostKind.gas,
            isDeductedFromReceive: false,
            assetId: eth,
          ),
          RoutedSwapCost(
            label: 'Gas receiver fee',
            amount: d('0.0012'),
            kind: RoutedSwapCostKind.providerFee,
            isDeductedFromReceive: false,
            assetId: eth,
          ),
        ],
        networkFees: [
          RoutedSwapNetworkFee(
            ticker: eth.id,
            assetId: eth,
            amount: d('0.0005'),
          ),
        ],
        quotedAt: now(),
      );
    final storage = MemoryStorage();
    final registry = SwapExecutionRegistry(
      executors: [FakeExecutor(SwapLiquiditySource.routed)],
      inFlight: () async => const [],
    );
    final bloc =
        UnifiedSwapBloc(
            repository: UnifiedSwapRepository(
              sources: [
                RoutedSwapQuoteSource(
                  manager,
                  networks: () => SwapNetworks([eth, usdc]),
                  now: now,
                ),
                FakeQuoteSource(
                  SwapLiquiditySource.atomic,
                  results: [
                    rejected(
                      SwapQuoteFailureKind.noRoute,
                      source: SwapLiquiditySource.atomic,
                    ),
                  ],
                ),
              ],
              pricing: SwapPricingService(
                FakePriceSource({eth: d('3000'), usdc: d('1')}),
              ),
              activatedAssets: () async => {eth, usdc},
            ),
            registry: registry,
            terms: SwapTermsRepository(
              walletKey: () async => 'w',
              storage: storage,
            ),
            preferences: SwapPreferences(
              walletKey: () async => 'w',
              storage: storage,
            ),
            spendableBalance: (asset) async =>
                asset == eth ? d('2') : d('5000'),
            addressOf: (asset) async => '0xaddress',
            resolveAsset: (ticker) => {eth.id: eth, usdc.id: usdc}[ticker],
            now: now,
          )
          ..add(const UnifiedSwapStarted())
          ..add(
            UnifiedSwapIntentApplied(
              pay: 'ETH',
              receive: 'USDC-ERC20',
              amount: amount,
            ),
          );
    async.elapse(const Duration(seconds: 2));
    script(bloc, manager, async);
    bloc.close();
    registry.dispose();
    async.flushMicrotasks();
  });
}

import 'package:decimal/decimal.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as rpc;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
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

import 'swap_test_fixtures.dart';

/// Counts what the swap form spends of the aggregator's request budget.
///
/// Without an API key the aggregator allows 75 quotes every two hours per
/// network address, so every request here is one a user may later miss.
/// Each scenario runs the real bloc, repository and routed source over a
/// manager that counts provider calls, on a fake clock.
void main() {
  test('an idle form stops re-pricing after five minutes', () {
    // Before: 2 routes every 30 s for as long as the form stayed open —
    // 42 requests in these ten minutes, and 4.2 more every minute after.
    final early = _run((bloc, async) {
      async.elapse(const Duration(minutes: 5));
    });
    final total = _run((bloc, async) {
      async.elapse(const Duration(minutes: 10));
    });
    expect(total, lessThanOrEqualTo(11));
    expect(total, early, reason: 'nothing after the idle limit');
  });

  test('a hidden app stops re-pricing at once', () {
    final calls = _run((bloc, async) {
      async.elapse(const Duration(minutes: 1));
      bloc.add(const UnifiedSwapForegroundChanged(foreground: false));
      async.elapse(const Duration(minutes: 9));
    });
    expect(calls, lessThanOrEqualTo(3));
  });

  test('typing prices the settled amount, cheapest route only', () {
    // Before: 2 — both routes for the final amount.
    final calls = _run(amount: '', (bloc, async) {
      for (final text in ['0.5', '0.52', '0.525']) {
        bloc.add(UnifiedSwapAmountChanged(text));
        async.elapse(const Duration(milliseconds: 300));
      }
      async.elapse(const Duration(seconds: 2));
    });
    expect(calls, 1);
  });

  test('Max on a native coin reuses the route it just priced', () {
    // Before: 3 — a probe at the full balance, then both routes.
    final calls = _run((bloc, async) {
      bloc.add(const UnifiedSwapMaxRequested());
      async.elapse(const Duration(seconds: 3));
    }, skipOpening: true);
    expect(calls, 1);
  });

  test('comparing prices the alternative once, then keeps it fresh', () {
    final compare = _run((bloc, async) {
      bloc.add(const UnifiedSwapAlternativesRequested());
      async.elapse(const Duration(seconds: 3));
    }, skipOpening: true);
    expect(compare, 1);
    final refreshed = _run((bloc, async) {
      bloc.add(const UnifiedSwapAlternativesRequested());
      async.elapse(const Duration(seconds: 31));
    }, skipOpening: true);
    expect(refreshed, 3, reason: 'one alternative, then both routes');
  });

  test('starting a quote seen moments ago re-prices from memory', () {
    // Before: 1. KDF still re-quotes inside init, on its own.
    final calls = _run((bloc, async) {
      bloc.add(const UnifiedSwapReviewOpened());
      async.elapse(const Duration(seconds: 1));
      bloc.add(const UnifiedSwapStartRequested());
      async.elapse(const Duration(seconds: 3));
    }, skipOpening: true);
    expect(calls, 0);
  });

  test('a price above the balance is asked for once, not kept fresh', () {
    // Before: nothing at all, as an amount above the balance was not priced.
    final calls = _run(amount: '5', (bloc, async) {
      async.elapse(const Duration(minutes: 2));
      bloc.add(const UnifiedSwapForegroundChanged(foreground: false));
      async.elapse(const Duration(minutes: 1));
      bloc.add(const UnifiedSwapForegroundChanged(foreground: true));
      async.elapse(const Duration(minutes: 7));
    });
    expect(calls, 1, reason: 'no refresh, and no re-price on coming back');
  });

  test('a rate limit is waited out, longer each time', () {
    final calls = _run(rateLimited: true, (bloc, async) {
      async.elapse(const Duration(minutes: 5));
    });
    // Asked at 0 s, then after pauses of 30 s, 60 s and 120 s: a request
    // made while limited is refused and still counts.
    expect(calls, lessThanOrEqualTo(4));
  });
}

/// Opens the form on ETH -> USDC, runs [script], and returns the provider
/// calls it cost. With [skipOpening], calls made while opening are not
/// counted.
int _run(
  void Function(UnifiedSwapBloc bloc, FakeAsync async) script, {
  String amount = '1',
  bool skipOpening = false,
  bool rateLimited = false,
}) {
  late int count;
  fakeAsync((async) {
    final start = DateTime(2026, 9, 24, 12);
    DateTime now() => start.add(async.elapsed);
    final manager = _CountingManager(now)..rateLimited = rateLimited;
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
    final opening = manager.calls;
    script(bloc, async);
    count = manager.calls - (skipOpening ? opening : 0);
    bloc.close();
    registry.dispose();
    async.flushMicrotasks();
  });
  return count;
}

/// A routed-swap manager that counts every call that would reach the
/// provider: each quote, and the probe a native Max makes.
class _CountingManager implements RoutedSwapManager {
  _CountingManager(this._now);

  final DateTime Function() _now;
  int calls = 0;

  /// Answers every quote with the provider's rate limit.
  bool rateLimited = false;

  @override
  Future<Set<AssetId>> eligibleAssets({String? provider}) async => {eth, usdc};

  @override
  Future<RoutedSwapOffer> quote({
    required AssetId from,
    required AssetId to,
    required Decimal amount,
    double? slippage,
    rpc.RoutedSwapOrder? order,
    String? provider,
  }) async {
    calls++;
    if (rateLimited) {
      throw const rpc.RoutedSwapRateLimitedException(message: 'slow down');
    }
    final route = rpc.RoutedSwapRoute.fromJson({
      'provider': 'lifi',
      'from': {'coin': from.id, 'amount': amount.toString()},
      'to': {
        'coin': to.id,
        'amount': (amount * d('2990')).toString(),
        'amount_min': (amount * d('2975')).toString(),
      },
      'tool': {'key': 'tool', 'name': 'Tool'},
      'kind': 'same_chain',
      'from_address': '0xaddress',
      'to_address': '0xaddress',
      'total_gas_costs': [
        {'coin': 'ETH', 'amount': '0.0005', 'amount_usd': '1.5'},
      ],
      'steps': [
        {'type': 'swap', 'tool': 'tool', 'chain_id': 1},
      ],
      'fee_costs': const <Object>[],
      'gas_costs': [
        {'coin': 'ETH', 'amount': '0.0005', 'amount_usd': '1.5'},
      ],
      'execution_duration_s': order == rpc.RoutedSwapOrder.fastest ? 10 : 30,
    });
    return RoutedSwapOffer(
      from: from,
      to: to,
      sellAmount: amount,
      expectedReceive: amount * d('2990'),
      guaranteedReceive: amount * d('2975'),
      kind: route.kind,
      costs: [
        RoutedSwapCost(
          label: 'Network fee',
          amount: d('0.0005'),
          kind: RoutedSwapCostKind.gas,
          isDeductedFromReceive: false,
          assetId: eth,
          usdValue: d('1.5'),
        ),
      ],
      networkFees: [
        RoutedSwapNetworkFee(
          ticker: 'ETH',
          assetId: eth,
          amount: d('0.0005'),
          usdValue: d('1.5'),
        ),
      ],
      legs: const [],
      quotedAt: _now(),
      provider: 'lifi',
      toolKey: order == rpc.RoutedSwapOrder.fastest ? 'fast' : 'tool',
      toolName: 'Tool',
      route: route,
      order: order,
      fromAddress: '0xaddress',
      toAddress: '0xaddress',
      estimatedDuration: const Duration(seconds: 30),
      slippage: slippage,
    );
  }

  @override
  Future<RoutedSwapMaxSell> maxSellAmount({
    required AssetId from,
    required AssetId to,
    required Decimal balance,
    double? slippage,
    rpc.RoutedSwapOrder? order,
    String? provider,
  }) async {
    if (!from.isChildAsset) calls++;
    return RoutedSwapMaxSell(
      amount: balance - d('0.0015'),
      reservedForFees: d('0.0015'),
      feeAsset: from,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

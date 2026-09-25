import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/atomic_swap_source.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_preferences.dart';
import 'package:web_dex/shared/swap/swap_pricing.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/swap/swap_terms_repository.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';

import 'swap_test_fixtures.dart';

/// Covers prices for more than the wallet holds: people look up what an
/// asset would fetch before they hold it, so such an amount is priced, and
/// never reviewed or started.
void main() {
  group('the form', () {
    late FakeQuoteSource routed;
    late SwapExecutionRegistry registry;
    late Map<AssetId, Decimal> balances;

    setUp(() {
      routed = FakeQuoteSource(
        SwapLiquiditySource.routed,
        respond: (request) => [
          SwapQuoteAvailable(
            quoteOf(
              from: request.from,
              to: request.to,
              sell: request.amount.toString(),
            ),
          ),
        ],
      );
      registry = SwapExecutionRegistry(
        executors: [FakeExecutor(SwapLiquiditySource.routed)],
        inFlight: () async => const [],
      );
      balances = {eth: d('2'), usdc: Decimal.zero};
    });

    tearDown(() => registry.dispose());

    Future<UnifiedSwapBloc> open(
      String pay,
      String receive,
      String amount,
    ) async {
      final storage = MemoryStorage();
      final bloc =
          UnifiedSwapBloc(
              repository: UnifiedSwapRepository(
                sources: [routed],
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
              spendableBalance: (asset) async => balances[asset],
              addressOf: (asset) async => '0xaddress',
              resolveAsset: (ticker) => {eth.id: eth, usdc.id: usdc}[ticker],
              // When quoteOf's quotes are made, so none has expired.
              now: () => DateTime(2026, 9, 24, 12),
              debounce: Duration.zero,
              refreshInterval: const Duration(hours: 1),
            )
            ..add(const UnifiedSwapStarted())
            ..add(
              UnifiedSwapIntentApplied(
                pay: pay,
                receive: receive,
                amount: amount,
              ),
            );
      for (var i = 0; i < 5; i++) {
        await pumpEventQueue(times: 30);
      }
      return bloc;
    }

    test('prices more than the balance, but never opens the review', () async {
      final bloc = await open('ETH', 'USDC-ERC20', '5');

      expect(bloc.state.issue, SwapFormIssue.insufficient);
      expect(bloc.state.selectedQuote, isNotNull);
      expect(routed.requests.last.indicative, isTrue);
      expect(bloc.state.canReview, isFalse);

      bloc.add(const UnifiedSwapReviewOpened());
      await pumpEventQueue(times: 30);
      expect(bloc.state.view, UnifiedSwapView.form);
      await bloc.close();
    });

    test('an amount the wallet holds is priced as before', () async {
      final bloc = await open('ETH', 'USDC-ERC20', '1');

      expect(routed.requests.last.indicative, isFalse);
      expect(bloc.state.canReview, isTrue);
      await bloc.close();
    });

    test('a token with none of its network coin is still not priced', () async {
      // The engine cannot price it: the approval estimate needs gas.
      balances[eth] = Decimal.zero;
      final bloc = await open('USDC-ERC20', 'ETH', '5');

      expect(bloc.state.issue, SwapFormIssue.noFeeBalance);
      expect(routed.requests, isEmpty);
      await bloc.close();
    });

    test('a dollar amount rounded under the balance keeps it closed', () async {
      // The option still sells the typed amount, 100.004, which the dollar
      // figure rounds down to 100.00.
      balances[usdc] = d('100.0035');
      final bloc = await open('USDC-ERC20', 'ETH', '100.004');
      expect(bloc.state.selectedQuote!.sellAmount, d('100.004'));

      bloc.add(const UnifiedSwapAmountModeToggled());
      await pumpEventQueue(times: 30);

      expect(bloc.state.amountMode, SwapAmountMode.fiat);
      expect(bloc.state.issue, SwapFormIssue.insufficient);
      expect(bloc.state.canReview, isFalse);
      await bloc.close();
    });

    test(
      'a failed re-price drops a fee issue it can no longer explain',
      () async {
        balances[eth] = d('0.0001');
        balances[usdc] = d('500');
        final bloc = await open('USDC-ERC20', 'ETH', '100');
        expect(bloc.state.issue, SwapFormIssue.insufficientForFees);

        routed
          ..respond = null
          ..results = [rejected(SwapQuoteFailureKind.serviceError)];
        bloc.add(const UnifiedSwapEvaluationRequested());
        await pumpEventQueue(times: 30);

        expect(bloc.state.evaluation, SwapEvaluationStatus.failed);
        expect(bloc.state.issue, isNull);
        await bloc.close();
      },
    );
  });

  group('the order book', () {
    late _Trading trading;

    setUp(() => trading = _Trading());

    AtomicSwapQuoteSource source() => AtomicSwapQuoteSource(
      trading: trading,
      networks: () => SwapNetworks([eth, btc]),
    );

    SwapQuoteRequest request({required bool indicative}) => SwapQuoteRequest(
      from: btc,
      to: eth,
      amount: d('1'),
      indicative: indicative,
    );

    test('prices more than the balance from the order alone', () async {
      final [result] = await source().quote(request(indicative: true));

      final quote = (result as SwapQuoteAvailable).quote;
      expect(quote.guaranteedReceive, d('20'));
      expect(quote.fees, isEmpty);
      expect(trading.preimages, 0);

      // No fees read is not the same as no fees: never a $0 total, never
      // ranked against an option that shows its costs.
      final priced = SwapPricingService(
        FakePriceSource({eth: d('3000'), btc: d('60000')}),
      ).price(quote);
      expect(priced.pricing.totalCostUsd, isNull);
      expect(priced.isRankable, isFalse);
    });

    test('an amount the wallet should hold still checks its fees', () async {
      final [result] = await source().quote(request(indicative: false));

      expect(
        (result as SwapQuoteRejected).failure.kind,
        SwapQuoteFailureKind.insufficientFunds,
      );
      expect(trading.preimages, 1);
    });
  });
}

/// One BTC bid at 20 ETH, and a preimage that finds the balance short.
class _Trading implements TradingManager {
  int preimages = 0;

  @override
  Future<OrderbookResponse> getOrderbook({
    required String base,
    required String rel,
  }) async => OrderbookResponse(
    mmrpc: '2.0',
    base: base,
    rel: rel,
    bids: [
      OrderInfo(
        price: NumericValue(decimal: '20'),
        baseMinVolume: NumericValue(decimal: '0.01'),
        baseMaxVolume: NumericValue(decimal: '5'),
      ),
    ],
    asks: const [],
    numBids: 1,
    numAsks: 0,
    timestamp: 0,
  );

  @override
  Future<TradePreimageResponse> tradePreimage({
    required String base,
    required String rel,
    required SwapMethod swapMethod,
    String? volume,
    bool? max,
    String? price,
  }) async {
    preimages++;
    throw const TradePreimageRpcErrorNotSufficientBalanceException(
      coin: 'BTC',
      available: BigDecimal('0'),
      required: BigDecimal('1.0001'),
    );
  }

  @override
  Future<MinTradingVolumeResponse> minTradingVolume({required String coin}) =>
      throw UnimplementedError();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

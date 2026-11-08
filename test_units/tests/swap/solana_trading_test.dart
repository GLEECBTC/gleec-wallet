import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/mm2/mm2.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/mm2/mm2_api/rpc/sell/sell_request.dart' as legacy_sell;
import 'package:web_dex/mm2/mm2_api/rpc/setprice/setprice_request.dart'
    as legacy_price;
import 'package:web_dex/mm2/mm2_api/rpc/market_maker_bot/market_maker_bot_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/market_maker_bot/market_maker_bot_parameters.dart';
import 'package:web_dex/mm2/mm2_api/rpc/market_maker_bot/trade_coin_pair_config.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/bloc/coins_bloc/asset_coin_extension.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/mm2/mm2_api/rpc/best_orders/best_orders.dart' as legacy;
import 'package:web_dex/model/orderbook/order.dart';
import 'package:web_dex/shared/swap/atomic_swap_source.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/trading/trading_asset_policy.dart';
import 'package:web_dex/shared/utils/utils.dart';

import 'swap_bloc_fakes.dart';
import 'swap_src_fakes.dart';
import 'swap_test_fixtures.dart';

void main() {
  final sol = assetOf('SOL-DEV', subClass: CoinSubClass.solana, decimals: 9);
  final spl = assetOf(
    'USDC-SOL-DEV',
    subClass: CoinSubClass.solanaToken,
    parent: sol,
    decimals: 6,
  );
  final testBtc = assetOf('BTC-TEST', subClass: CoinSubClass.utxo, decimals: 8);
  Asset native({
    bool testnet = true,
    bool walletOnly = false,
    String node = 'https://api.devnet.solana.com',
  }) => Asset(
    id: sol,
    protocol: SolanaProtocol.fromJson({
      'is_testnet': testnet,
      'nodes': [
        {'url': node},
      ],
      'explorer_url': 'https://explorer.solana.com/',
      'explorer_tx_url': 'tx/{HASH}?cluster=devnet',
      'explorer_address_url': 'address/{ADDRESS}?cluster=devnet',
    }),
    isWalletOnly: walletOnly,
    signMessagePrefix: null,
  );
  Asset token({String program = SolanaTokenProtocol.classicTokenProgramId}) =>
      Asset(
        id: spl,
        protocol: SolanaTokenProtocol.fromJson({
          'is_testnet': true,
          'protocol': {
            'type': 'SOLANATOKEN',
            'protocol_data': {
              'platform': sol.id,
              'mint_address': 'Mint',
              'program_id': program,
              'decimals': 6,
            },
          },
        }),
        isWalletOnly: false,
        signMessagePrefix: null,
      );
  final utxo = Asset(
    id: testBtc,
    protocol: UtxoProtocol.fromJson({
      'is_testnet': true,
    }, subClass: CoinSubClass.utxo),
    isWalletOnly: false,
    signMessagePrefix: null,
  );
  final mainnetBtc = Asset(
    id: btc,
    protocol: UtxoProtocol.fromJson({
      'is_testnet': false,
    }, subClass: CoinSubClass.utxo),
    isWalletOnly: false,
    signMessagePrefix: null,
  );
  late Map<String, Asset> catalog;
  late SolanaCapabilities capabilities;
  late TradingAssetPolicy policy;
  setUp(() {
    catalog = {
      sol.id: native(),
      spl.id: token(),
      testBtc.id: utxo,
      btc.id: mainnetBtc,
    };
    capabilities = const SolanaCapabilities(
      enabled: true,
      devnetTradingEnabled: true,
    );
    policy = TradingAssetPolicy(
      assetOf: (id) => catalog[id],
      solanaCapabilities: () => capabilities,
    );
  });

  test(
    'devnet trading requires current engine, catalog, nodes and both networks',
    () {
      expect(policy.allowsPair(sol.id, testBtc.id), isTrue);
      expect(policy.allowsPair(testBtc.id, spl.id), isTrue);
      expect(policy.allowsPair(sol.id, btc.id), isFalse);
      expect(policy.allowsPair(sol.id, 'UNKNOWN'), isFalse);
      capabilities = const SolanaCapabilities(enabled: true);
      expect(policy.allowsPair(sol.id, testBtc.id), isFalse);
      capabilities = const SolanaCapabilities(
        enabled: true,
        devnetTradingEnabled: true,
      );
      catalog[sol.id] = native(walletOnly: true);
      expect(policy.allowsPair(spl.id, testBtc.id), isFalse);
      catalog[sol.id] = native(testnet: false);
      expect(policy.allowsPair(sol.id, testBtc.id), isFalse);
      catalog[sol.id] = native(node: 'https://api.mainnet-beta.solana.com');
      expect(policy.allowsPair(sol.id, testBtc.id), isFalse);
      catalog[sol.id] = native();
      catalog[spl.id] = token(program: SolanaTokenProtocol.token2022ProgramId);
      expect(policy.allowsPair(spl.id, testBtc.id), isFalse);
      expect(canTradeAssetId(sol), isFalse);
      expect(canTradeAssetPair('SOL-DEV', 'BTC-TEST'), isFalse);
    },
  );

  test(
    'final dispatch refuses disabled Solana and restored bot starts while stop remains available',
    () async {
      capabilities = const SolanaCapabilities();
      final transport = _TradingTransport();
      final api = Mm2Api(
        mm2: MM2(),
        tradingTransport: transport.call,
        sdk: _UnusedTradingSdk(),
        tradingPolicy: policy,
      );
      addTearDown(api.dispose);
      await expectLater(
        api.sellOrThrow(
          legacy_sell.SellRequest(
            base: sol.id,
            rel: testBtc.id,
            volume: Rational.one,
            price: Rational.one,
            orderType: legacy_sell.SellBuyOrderType.fillOrKill,
          ),
        ),
        throwsA(isA<TradePreflightRejected>()),
      );
      final maker = await api.setprice(
        legacy_price.SetPriceRequest(
          base: sol.id,
          rel: testBtc.id,
          volume: Rational.one,
          price: Rational.one,
        ),
      );
      expect(maker!['error'], isA<TradePreflightRejected>());
      final request = MarketMakerBotRequest(
        id: 1,
        params: MarketMakerBotParameters(
          tradeCoinPairs: {
            'sol-test': TradeCoinPairConfig(
              name: 'sol-test',
              baseCoinId: sol.id,
              relCoinId: testBtc.id,
              spread: '1.01',
            ),
          },
        ),
      );
      await expectLater(
        api.startStopMarketMakerBot(request),
        throwsA(isA<TradePreflightRejected>()),
      );
      expect(transport.sent, isEmpty);
      await api.startStopMarketMakerBot(
        request.copyWith(method: 'stop_simple_market_maker_bot'),
      );
      expect(transport.sent, ['stop_simple_market_maker_bot']);
    },
  );

  test(
    'catalog policy is rechecked after asynchronous preparation before transport',
    () async {
      final transport = _TradingTransport();
      scheduleMicrotask(() {
        catalog[testBtc.id] = utxo.copyWith(isWalletOnly: true);
      });
      final api = Mm2Api(
        mm2: MM2(),
        tradingTransport: transport.call,
        sdk: _UnusedTradingSdk(),
        tradingPolicy: policy,
      );
      addTearDown(api.dispose);
      await expectLater(
        api.sellOrThrow(
          legacy_sell.SellRequest(
            base: testBtc.id,
            rel: btc.id,
            volume: Rational.one,
            price: Rational.one,
            orderType: legacy_sell.SellBuyOrderType.fillOrKill,
          ),
        ),
        throwsA(isA<TradePreflightRejected>()),
      );
      expect(transport.sent, isEmpty);
    },
  );

  test(
    'Shielded orderbook conversion retains authoritative own-order identity',
    () {
      final order = Order.fromOrderInfo(
        OrderInfo(
          price: NumericValue(decimal: '1'),
          baseMaxVolume: NumericValue(decimal: '3'),
          isMine: true,
          pubkey: 'p2p-identity',
          uuid: 'own-offer',
        ),
        base: sol.id,
        rel: testBtc.id,
        direction: OrderDirection.ask,
      );
      final best = legacy.BestOrder.fromOrder(order, sol.id);
      expect(best.address.addressType, legacy.AddressType.shielded);
      expect(best.address.addressData, isNull);
      expect(best.isMine, isTrue);
      expect(best.pubkey, 'p2p-identity');
    },
  );

  test('legacy explorer preserves base58 case and devnet query placement', () {
    final coin = native().toCoin();
    expect(
      getTxExplorerUrl(coin, 'aBcDEF'),
      'https://explorer.solana.com/tx/aBcDEF?cluster=devnet',
    );
    expect(
      getAddressExplorerUrl(coin, 'AbCd'),
      'https://explorer.solana.com/address/AbCd?cluster=devnet',
    );
  });

  PreimageTotalFee total(String coin, String required) => PreimageTotalFee(
    coin: coin,
    amount: required,
    amountFraction: Fraction(numer: '0', denom: '1'),
    amountRat: Rational.zero,
    requiredBalance: required,
    requiredBalanceFraction: Fraction(numer: '0', denom: '1'),
    requiredBalanceRat: Rational.zero,
  );

  test(
    'SPL receive quote carries SOL funding without adding it twice',
    () async {
      final trading = SrcTrading()
        ..preimage = TradePreimageResponse(
          mmrpc: '2.0',
          totalFees: [total(sol.id, '0.025')],
          relCoinFee: coinFeeOf(sol.id, '0.005'),
        );
      final source = AtomicSwapQuoteSource(
        trading: trading,
        networks: () => SwapNetworks([sol, spl, testBtc]),
        assetAllowed: policy.allowsAsset,
        tradingAllowed: (from, to) => policy.allowsPair(from.id, to.id),
      );
      final result =
          (await source.quote(
                SwapQuoteRequest(from: testBtc, to: spl, amount: d('1')),
              )).single
              as SwapQuoteAvailable;
      final quote = result.quote;
      expect(quote.requiredFeeBalances, {sol: d('0.025')});
      expect(quote.fundingOnTopIn(sol), d('0.025'));
      expect(quote.fundingAssets, contains(sol));
      expect(
        quote.withPricing(const SwapQuotePricing()).requiredFeeBalances,
        quote.requiredFeeBalances,
      );
      expect(
        (await source.maxAmount(
          from: testBtc,
          to: spl,
          balance: d('1'),
        ))!.coversRefund,
        isFalse,
      );
      trading.preimage = TradePreimageResponse(
        mmrpc: '2.0',
        totalFees: [total('UNKNOWN', '1')],
      );
      expect(
        (await source.quote(
          SwapQuoteRequest(from: testBtc, to: spl, amount: d('1')),
        )).single,
        isA<SwapQuoteRejected>(),
      );
    },
  );

  SwapQuote fundedQuote(
    DateTime now, {
    String required = '0.025',
    AssetId? feeAsset,
  }) => SwapQuote(
    id: 'solana',
    source: SwapLiquiditySource.atomic,
    routeKind: SwapRouteKind.direct,
    from: btc,
    to: spl,
    sellAmount: d('0.1'),
    expectedReceive: d('10'),
    guaranteedReceive: d('10'),
    fees: const [],
    stages: const [],
    requiredFeeBalances: {feeAsset ?? sol: d(required)},
    quotedAt: now,
  );

  swapBlocTest(
    'missing SOL on receive side blocks review; fresh balance permits it',
    (h) {
      h.extraAssets.addAll([sol, spl]);
      h.balances[sol] = d('0.01');
      h.balances[spl] = d('0');
      h.atomic.tradable = {btc, sol, spl};
      h.atomic.respond = (_) => [SwapQuoteAvailable(fundedQuote(h.now()))];
      final bloc = h.open(pay: btc.id, receive: spl.id, amount: '0.1');
      expect(bloc.state.issue, SwapFormIssue.insufficientForFees);
      expect(bloc.state.insufficientFeeAsset, sol);
      expect(bloc.state.canReview, isFalse);
      h.balances[sol] = d('0.03');
      bloc.add(const UnifiedSwapBalancesRefreshed());
      h.settle();
      expect(bloc.state.canReview, isTrue);
    },
  );

  swapBlocTest(
    'unknown receive-side funding offers retry and cannot open review',
    (h) {
      h.extraAssets.addAll([sol, spl]);
      h.balances[spl] = d('0');
      h.unreadableBalances.add(sol);
      h.atomic.tradable = {btc, sol, spl};
      h.atomic.respond = (_) => [SwapQuoteAvailable(fundedQuote(h.now()))];
      final bloc = h.open(pay: btc.id, receive: spl.id, amount: '0.1');
      expect(bloc.state.canReview, isFalse);
      expect(bloc.state.fundingBalances[sol], isNull);
      h.unreadableBalances.remove(sol);
      h.balances[sol] = d('0.03');
      bloc.add(const UnifiedSwapBalancesRefreshed());
      h.settle();
      expect(bloc.state.fundingReady, isTrue);
      expect(bloc.state.canReview, isTrue);
    },
  );

  swapBlocTest(
    'confirmation rechecks receiving SOL and cannot start after it is spent',
    (h) {
      h.extraAssets.addAll([sol, spl]);
      h.balances[sol] = d('0.03');
      h.balances[spl] = d('0');
      h.atomic.tradable = {btc, sol, spl};
      h.atomic.respond = (_) => [SwapQuoteAvailable(fundedQuote(h.now()))];
      final bloc = h.open(pay: btc.id, receive: spl.id, amount: '0.1');
      bloc.add(const UnifiedSwapReviewOpened());
      h.settle();
      h.balances[sol] = d('0.01');
      h.atomic.requoteResult = SwapQuoteAvailable(fundedQuote(h.now()));
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      expect(bloc.state.review!.status, SwapReviewStatus.revalidationFailed);
      expect(bloc.state.review!.revalidationFailure!.asset, sol);
      expect(h.atomicExecutor.started, isEmpty);
    },
  );
  swapBlocTest('failed receiving funding refresh refuses confirmation', (h) {
    h.extraAssets.addAll([sol, spl]);
    h.balances[sol] = d('0.03');
    h.balances[spl] = d('0');
    h.atomic.tradable = {btc, sol, spl};
    h.atomic.respond = (_) => [SwapQuoteAvailable(fundedQuote(h.now()))];
    final bloc = h.open(pay: btc.id, receive: spl.id, amount: '0.1');
    bloc.add(const UnifiedSwapReviewOpened());
    h.settle();
    h.unreadableBalances.add(sol);
    h.atomic.requoteResult = SwapQuoteAvailable(fundedQuote(h.now()));
    bloc.add(const UnifiedSwapStartRequested());
    h.settle();
    expect(bloc.state.review!.status, SwapReviewStatus.revalidationFailed);
    expect(
      bloc.state.review!.revalidationFailure!.kind,
      SwapQuoteFailureKind.serviceError,
    );
    expect(h.atomicExecutor.started, isEmpty);
  });

  swapBlocTest(
    'accepting higher funding refreshes again and asks about another rise',
    (h) {
      h.extraAssets.addAll([sol, spl]);
      h.balances[sol] = d('1');
      h.balances[spl] = d('0');
      h.atomic.tradable = {btc, sol, spl};
      h.atomic.respond = (_) => [SwapQuoteAvailable(fundedQuote(h.now()))];
      final bloc = h.open(pay: btc.id, receive: spl.id, amount: '0.1');
      bloc.add(const UnifiedSwapReviewOpened());
      h.settle();
      h.atomic.requoteResult = SwapQuoteAvailable(
        fundedQuote(h.now(), required: '0.03'),
      );
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      expect(bloc.state.review!.status, SwapReviewStatus.materialUpdate);
      h.atomic.requoteResult = SwapQuoteAvailable(
        fundedQuote(h.now(), required: '0.04'),
      );
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      expect(bloc.state.review!.status, SwapReviewStatus.materialUpdate);
      expect(bloc.state.review!.previous!.requiredFeeBalances[sol], d('0.03'));
      expect(h.atomicExecutor.started, isEmpty);
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      expect(
        h.atomicExecutor.started.single.requiredFeeBalances[sol],
        d('0.04'),
      );
    },
  );

  swapBlocTest(
    'a newly introduced funding currency is read before confirming',
    (h) {
      h.extraAssets.addAll([sol, spl]);
      h.balances[sol] = d('1');
      h.balances[spl] = d('0');
      h.atomic.tradable = {btc, sol, spl};
      h.atomic.respond = (_) => [SwapQuoteAvailable(fundedQuote(h.now()))];
      final bloc = h.open(pay: btc.id, receive: spl.id, amount: '0.1');
      bloc.add(const UnifiedSwapReviewOpened());
      h.settle();
      h.balances[gleec] = d('0');
      h.atomic.requoteResult = SwapQuoteAvailable(
        fundedQuote(h.now(), feeAsset: gleec),
      );
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      expect(bloc.state.review!.status, SwapReviewStatus.revalidationFailed);
      expect(bloc.state.review!.revalidationFailure!.asset, gleec);
      expect(h.atomicExecutor.started, isEmpty);
    },
  );
}

class _UnusedTradingSdk extends Fake implements KomodoDefiSdk {}

class _TradingTransport {
  final sent = <String>[];

  Future<Map<String, dynamic>> call(dynamic request) async {
    final method = request.method as String;
    sent.add(method);
    return {'result': <String, dynamic>{}};
  }
}

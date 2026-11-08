import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart' show Locale;
// No public API loads or resets the package's global translations.
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/mm2/mm2.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/mm2/mm2_api/rpc/market_maker_bot/market_maker_bot_parameters.dart';
import 'package:web_dex/mm2/mm2_api/rpc/market_maker_bot/market_maker_bot_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/market_maker_bot/trade_coin_pair_config.dart';
import 'package:web_dex/mm2/mm2_api/rpc/sell/sell_request.dart' as legacy;
import 'package:web_dex/mm2/mm2_api/rpc/setprice/setprice_request.dart'
    as legacy;
import 'package:web_dex/shared/trading/trading_asset_policy.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_bot/market_maker_bot_error.dart';
import 'package:web_dex/shared/swap/routed_swap_source.dart';
import 'package:web_dex/shared/swap/routed_swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

import 'swap_src_fakes.dart';
import 'swap_src_sdk_fakes.dart';
import 'swap_test_fixtures.dart';

final _sol = assetOf('SOL-DEV', subClass: CoinSubClass.solana, decimals: 9);
final _btc = assetOf('BTC-TEST', subClass: CoinSubClass.utxo, decimals: 8);

PreimageTotalFee _total(String coin, String required) => PreimageTotalFee(
  coin: coin,
  amount: required,
  amountFraction: Fraction(numer: '0', denom: '1'),
  amountRat: Rational.zero,
  requiredBalance: required,
  requiredBalanceFraction: Fraction(numer: '0', denom: '1'),
  requiredBalanceRat: Rational.zero,
);

void main() => group('Solana trade dispatch', _tests);

void _tests() {
  late _PreflightSdk sdk;
  late Mm2Api api;
  late TradingAssetPolicy policy;
  late List<String> dispatched;
  Completer<void>? transportGate;

  setUp(() {
    sdk = _PreflightSdk();
    sdk.assets.add(
      Asset(
        id: _sol,
        protocol: SolanaProtocol.fromJson({
          'is_testnet': true,
          'nodes': [
            {'url': 'https://api.devnet.solana.com'},
          ],
        }),
        isWalletOnly: false,
        signMessagePrefix: null,
      ),
    );
    sdk.assets.add(assetFor(_btc, protocol: SrcProtocol(testnet: true)));
    sdk.balances.known.addAll({_sol: balanceOf('2'), _btc: balanceOf('2')});
    policy = TradingAssetPolicy(
      assetOf: (id) => sdk.assets.available.values
          .where((asset) => asset.id.id == id)
          .firstOrNull,
      solanaCapabilities: () =>
          const SolanaCapabilities(enabled: true, devnetTradingEnabled: true),
    );
    dispatched = [];
    transportGate = null;
    api = Mm2Api(
      mm2: MM2(),
      sdk: sdk,
      tradingPolicy: policy,
      tradingTransport: (dynamic request) async {
        await transportGate?.future;
        RpcDispatchGuard.ensureCurrent(request.method as String);
        dispatched.add(request.method as String);
        return {'result': <String, dynamic>{}};
      },
    );
    addTearDown(api.dispose);
  });

  legacy.SellRequest sell({
    String? reviewed,
    String? reviewedReceive,
    bool Function()? current,
  }) => legacy.SellRequest(
    base: _btc.id,
    rel: _sol.id,
    volume: Rational.one,
    price: Rational.one,
    orderType: legacy.SellBuyOrderType.fillOrKill,
    reviewedFeeRequirements: reviewed == null
        ? null
        : {_sol.id: Rational.parse(reviewed)},
    isQuoteCurrent: current,
    reviewedReceiveFees: reviewedReceive == null
        ? null
        : {_sol.id: Rational.parse(reviewedReceive)},
  );

  test(
    'higher final funding requires another review; unchanged fees submit',
    () async {
      final request = sell(reviewed: '0.01');
      sdk.client.fees = [_total(_sol.id, '0.02')];
      await expectLater(
        api.sellOrThrow(request),
        throwsA(isA<TradePreflightRejected>()),
      );
      expect(dispatched, isEmpty);
      sdk.client.fees = [_total(_sol.id, '0.01')];
      await api.sellOrThrow(request);
      expect(dispatched, ['sell']);
      request.userpass = 'test';
      expect(request.toJson().keys, isNot(contains('reviewedFeeRequirements')));
      expect(request.toJson().keys, isNot(contains('isQuoteCurrent')));
    },
  );

  test(
    'final funding aggregates currencies and always checks sold principal',
    () async {
      sdk.client.fees = [_total(_sol.id, '0.6'), _total(_sol.id, '0.6')];
      sdk.balances.known[_sol] = balanceOf('1');
      await expectLater(
        api.sellOrThrow(sell()),
        throwsA(isA<TradePreflightRejected>()),
      );
      sdk.client.fees = [_total(_sol.id, '0.01')];
      sdk.balances.known[_btc] = balanceOf('0.5');
      await expectLater(
        api.sellOrThrow(sell()),
        throwsA(isA<TradePreflightRejected>()),
      );
      expect(dispatched, isEmpty);
      expect(sdk.balances.refreshed, contains(_btc));
    },
  );

  test('freshness and catalog are rechecked after funding awaits', () async {
    var current = true;
    final gate = sdk.balances.gate = Completer<void>();
    final waiting = api.sellOrThrow(sell(current: () => current));
    await pumpEventQueue();
    current = false;
    gate.complete();
    await expectLater(waiting, throwsA(isA<TradePreflightRejected>()));
    expect(dispatched, isEmpty);

    final nextGate = sdk.balances.gate = Completer<void>();
    final next = api.sellOrThrow(sell());
    await pumpEventQueue();
    sdk.assets.add(sdk.assets.available[_sol]!.copyWith(isWalletOnly: true));
    nextGate.complete();
    await expectLater(next, throwsA(isA<TradePreflightRejected>()));
    expect(dispatched, isEmpty);
  });

  for (final hangPreimage in [true, false]) {
    test(
      'a stalled ${hangPreimage ? 'preimage' : 'balance'} never submits later',
      () {
        fakeAsync((async) {
          final gate = Completer<void>();
          if (hangPreimage) {
            sdk.client.gate = gate;
          } else {
            sdk.balances.gate = gate;
          }
          Object? failure;
          unawaited(
            api
                .sellOrThrow(sell())
                .then<void>(
                  (_) => fail('Unexpected dispatch'),
                  onError: (Object error) {
                    failure = error;
                  },
                ),
          );
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 16));
          expect(failure, isA<TradePreflightRejected>());
          gate.complete();
          async.flushMicrotasks();
          expect(dispatched, isEmpty);
        });
      },
    );
  }

  test(
    'manual Solana maker/taker work but restored automation cannot restart',
    () async {
      expect(policy.allowsPair(_btc.id, _sol.id), isTrue);
      expect(policy.allowsMarketMakerPair(_btc.id, _sol.id), isFalse);
      final maker = await api.setprice(
        legacy.SetPriceRequest(
          base: _btc.id,
          rel: _sol.id,
          volume: Rational.one,
          price: Rational.one,
        ),
      );
      expect(maker!['error'], isNull);
      await api.sellOrThrow(sell());
      final restored = MarketMakerBotRequest(
        id: 1,
        params: MarketMakerBotParameters(
          tradeCoinPairs: {
            'sol-test': TradeCoinPairConfig(
              name: 'sol-test',
              baseCoinId: _btc.id,
              relCoinId: _sol.id,
              spread: '1.01',
            ),
          },
        ),
      );
      await expectLater(
        api.startStopMarketMakerBot(restored),
        throwsA(isA<TradePreflightRejected>()),
      );
      await api.startStopMarketMakerBot(
        restored.copyWith(method: 'stop_simple_market_maker_bot'),
      );
      expect(dispatched, ['setprice', 'sell', 'stop_simple_market_maker_bot']);
    },
  );

  test(
    'Solana never enters routed catalogs, quotes, Max or execution',
    () async {
      final manager = SrcRoutedSwaps()..eligible = {_sol, _btc};
      final source = RoutedSwapQuoteSource(
        manager,
        networks: () => SwapNetworks([_sol, _btc]),
        isCandidate: (_) => true,
        tradingAllowed: (_, _) => true,
      );
      final catalog = await source.assets(
        known: {_sol, _btc},
        activated: {_sol, _btc},
      );
      expect(catalog.quotable, isNot(contains(_sol)));
      expect((await catalog.update)!.quotable, isNot(contains(_sol)));
      final quote = quoteOf(
        from: _btc,
        to: _sol,
        payload: offerOf(from: _btc, to: _sol),
      );
      expect(
        (await source.quote(
          SwapQuoteRequest(from: _btc, to: _sol, amount: d('1')),
        )).single,
        isA<SwapQuoteRejected>(),
      );
      expect(await source.requote(quote), isA<SwapQuoteRejected>());
      await expectLater(
        source.maxAmount(from: _btc, to: _sol, balance: d('1')),
        throwsA(isA<SwapMaxUnavailableException>()),
      );
      expect(manager.quotes, isEmpty);
      expect(manager.maxCalls, 0);
      await expectLater(
        RoutedSwapExecutor(
          manager,
          networks: () => SwapNetworks([_sol, _btc]),
        ).start(quote, authorization: testSwapAuthorization()),
        throwsA(isA<SwapStartRejectedException>()),
      );
    },
  );

  test(
    'higher receive deductions cannot reduce the reviewed minimum at dispatch',
    () async {
      sdk.client.receiveFee = coinFeeOf(_sol.id, '0.02', fromVolume: true);
      await expectLater(
        api.sellOrThrow(sell(reviewedReceive: '0.01')),
        throwsA(isA<TradePreflightRejected>()),
      );
      expect(dispatched, isEmpty);
      sdk.client.receiveFee = coinFeeOf(_sol.id, '0.01', fromVolume: true);
      await api.sellOrThrow(sell(reviewedReceive: '0.01'));
      expect(dispatched, ['sell']);
    },
  );

  test('a catalog read failure remains a certain local refusal', () async {
    sdk.assets.broken = true;
    await expectLater(
      api.sellOrThrow(sell()),
      throwsA(isA<TradePreflightRejected>()),
    );
    expect(dispatched, isEmpty);
  });

  test(
    'Solana automation refusal resolves localized copy through its wrapper',
    () {
      Localization.load(
        const Locale('en'),
        translations: Translations({
          'solanaMarketMakerUnavailable': 'Translated manual-order guidance',
        }),
      );
      addTearDown(() => Localization.load(const Locale('en')));
      expect(
        marketMakerErrorMessage(const SolanaMarketMakerUnavailable()),
        'Translated manual-order guidance',
      );
      expect(
        marketMakerErrorMessage(
          const TradePreflightRejected(SolanaMarketMakerUnavailable()),
        ),
        'Translated manual-order guidance',
      );
    },
  );

  test(
    'final transport guard rejects expiry and policy changes after credentials wait',
    () async {
      var current = true;
      transportGate = Completer<void>();
      final waiting = api.sellOrThrow(sell(current: () => current));
      await pumpEventQueue();
      current = false;
      transportGate!.complete();
      await expectLater(waiting, throwsA(isA<TradePreflightRejected>()));
      expect(dispatched, isEmpty);

      transportGate = Completer<void>();
      final next = api.sellOrThrow(sell());
      await pumpEventQueue();
      sdk.assets.add(sdk.assets.available[_sol]!.copyWith(isWalletOnly: true));
      transportGate!.complete();
      await expectLater(next, throwsA(isA<TradePreflightRejected>()));
      expect(dispatched, isEmpty);
    },
  );
}

class _PreflightSdk extends Fake implements KomodoDefiSdk {
  @override
  final SrcAssets assets = SrcAssets();
  @override
  final _PreflightBalances balances = _PreflightBalances();
  @override
  final _PreflightClient client = _PreflightClient();
}

class _PreflightBalances extends SrcBalances {
  Completer<void>? gate;
  final refreshed = <AssetId>[];

  @override
  Future<BalanceInfo> getBalance(
    AssetId assetId, {
    bool forceRefresh = false,
  }) async {
    expect(forceRefresh, isTrue);
    refreshed.add(assetId);
    await gate?.future;
    return known[assetId]!;
  }
}

class _PreflightClient implements ApiClient {
  List<PreimageTotalFee> fees = [_total(_sol.id, '0.01')];
  Completer<void>? gate;
  PreimageCoinFee? receiveFee;

  @override
  Future<JsonMap> executeRpc(JsonMap request) async {
    expect(request['method'], 'trade_preimage');
    await gate?.future;
    return TradePreimageResponse(
      mmrpc: '2.0',
      totalFees: fees,
      relCoinFee: receiveFee,
    ).toJson();
  }
}

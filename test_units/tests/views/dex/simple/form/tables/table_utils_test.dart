import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart'
    show AssetChainId, AssetId, CoinSubClass;
import 'package:komodo_defi_types/src/assets/asset_symbol.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/mm2/mm2_api/rpc/best_orders/best_orders.dart';
import 'package:web_dex/model/authorize_mode.dart';
import 'package:web_dex/model/cex_price.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/coin_type.dart';
import 'package:web_dex/views/dex/simple/form/tables/table_utils.dart';

class _TableTestCoinsRepo implements CoinsRepo {
  _TableTestCoinsRepo(this._byAbbr);

  final Map<String, Coin> _byAbbr;

  @override
  Coin? getCoin(String abbr) => _byAbbr[abbr];

  @override
  double? getUsdPriceForAmount(num amount, String coinAbbr) => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnrestrictedTradingStatusBloc implements TradingStatusBloc {
  @override
  TradingStatusState get state => TradingStatusLoadSuccess();

  @override
  Stream<TradingStatusState> get stream =>
      Stream<TradingStatusState>.value(state).asBroadcastStream();

  @override
  Future<void> close() async {}

  @override
  void add(TradingStatusEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _wrapForTableUtilsTest({
  required Map<String, Coin> coinsForRepo,
  required Widget child,
}) {
  return MultiRepositoryProvider(
    providers: [
      RepositoryProvider<CoinsRepo>.value(
        value: _TableTestCoinsRepo(coinsForRepo),
      ),
    ],
    child: BlocProvider<TradingStatusBloc>.value(
      value: _UnrestrictedTradingStatusBloc(),
      child: child,
    ),
  );
}

Coin _buildCoin(
  String abbr, {
  double usdPrice = 0,
  bool walletOnly = false,
  bool isTestCoin = false,
  int priority = 0,
}) {
  final assetId = AssetId(
    id: abbr,
    name: '$abbr Coin',
    symbol: AssetSymbol(assetConfigId: abbr),
    chainId: AssetChainId(chainId: 1),
    derivationPath: null,
    subClass: CoinSubClass.utxo,
  );

  return Coin(
    type: CoinType.utxo,
    abbr: abbr,
    id: assetId,
    name: '$abbr Coin',
    explorerUrl: 'https://example.com/$abbr',
    explorerTxUrl: 'https://example.com/$abbr/tx',
    explorerAddressUrl: 'https://example.com/$abbr/address',
    protocolType: 'UTXO',
    protocolData: null,
    isTestCoin: isTestCoin,
    logoImageUrl: null,
    coingeckoId: null,
    fallbackSwapContract: null,
    priority: priority,
    state: CoinState.active,
    swapContractAddress: null,
    walletOnly: walletOnly,
    mode: CoinMode.standard,
    usdPrice: CexPrice(
      assetId: assetId,
      price: Decimal.parse(usdPrice.toString()),
      change24h: Decimal.zero,
      lastUpdated: DateTime.fromMillisecondsSinceEpoch(0),
    ),
  );
}

BestOrder _buildOrder(String coin, int price) {
  return BestOrder(
    price: Rational.fromInt(price),
    maxVolume: Rational.fromInt(1),
    minVolume: Rational.fromInt(1),
    coin: coin,
    address: OrderAddress.transparent(coin.toLowerCase()),
    uuid: '$coin-$price',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildOrderCoinCaches', () {
    testWidgets('creates aligned caches for orders and coins', (tester) async {
      final btc = _buildCoin('BTC', usdPrice: 30_000);
      final kmd = _buildCoin('KMD', usdPrice: 1);
      final coins = {'BTC': btc, 'KMD': kmd};
      Coin? coinLookup(String abbr) => coins[abbr];

      final orders = <String, List<BestOrder>>{
        'BTC-KMD': [_buildOrder('BTC', 1)],
        'KMD-BTC': [_buildOrder('KMD', 2)],
      };

      late ({
        Map<AssetId, BestOrder> ordersByAssetId,
        Map<AssetId, Coin> coinsByAssetId,
        Map<String, AssetId> assetIdByAbbr,
      })
      caches;

      await tester.pumpWidget(
        MaterialApp(
          home: _wrapForTableUtilsTest(
            coinsForRepo: coins,
            child: Builder(
              builder: (context) {
                caches = buildOrderCoinCaches(
                  context,
                  orders,
                  coinLookup: coinLookup,
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(caches.ordersByAssetId.length, 2);
      expect(caches.coinsByAssetId.length, 2);
      expect(caches.assetIdByAbbr['BTC'], btc.assetId);
      expect(caches.ordersByAssetId[btc.assetId]?.uuid, 'BTC-1');
    });
  });

  group('prepareOrdersForTable', () {
    testWidgets('sorts by fiat value and filters wallet/test coins', (
      tester,
    ) async {
      final btc = _buildCoin('BTC', usdPrice: 30_000);
      final kmd = _buildCoin('KMD', usdPrice: 1, walletOnly: true);
      final tbtc = _buildCoin('TBTC', usdPrice: 25_000, isTestCoin: true);
      final coins = {'BTC': btc, 'KMD': kmd, 'TBTC': tbtc};
      Coin? coinLookup(String abbr) => coins[abbr];

      final orders = <String, List<BestOrder>>{
        'BTC-KMD': [_buildOrder('BTC', 1)],
        'KMD-BTC': [_buildOrder('KMD', 2)],
        'TBTC-KMD': [_buildOrder('TBTC', 3)],
      };

      late List<BestOrder> sorted;

      await tester.pumpWidget(
        MaterialApp(
          home: _wrapForTableUtilsTest(
            coinsForRepo: coins,
            child: Builder(
              builder: (context) {
                sorted = prepareOrdersForTable(
                  context,
                  orders,
                  null,
                  AuthorizeMode.noLogin,
                  testCoinsEnabled: false,
                  coinLookup: coinLookup,
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(sorted, hasLength(1));
      expect(sorted.single.coin, 'BTC');
    });

    testWidgets('uses fewer coin lookups than the legacy approach', (
      tester,
    ) async {
      final btc = _buildCoin('BTC', usdPrice: 30_000);
      final kmd = _buildCoin('KMD', usdPrice: 1);
      final coins = {'BTC': btc, 'KMD': kmd};

      final orders = <String, List<BestOrder>>{
        'pair-1': [_buildOrder('BTC', 1)],
        'pair-2': [_buildOrder('KMD', 100)],
      };

      final legacyCalls = <String, int>{};
      final optimisedCalls = <String, int>{};

      Coin? legacyLookup(String abbr) {
        legacyCalls[abbr] = (legacyCalls[abbr] ?? 0) + 1;
        return coins[abbr];
      }

      Coin? optimisedLookup(String abbr) {
        optimisedCalls[abbr] = (optimisedCalls[abbr] ?? 0) + 1;
        return coins[abbr];
      }

      List<BestOrder> legacyPrepare(
        Map<String, List<BestOrder>> input,
        Coin? Function(String) lookup,
      ) {
        final result = <BestOrder>[];
        input.forEach((_, list) {
          if (list.isEmpty) return;
          final order = list.first;
          final coin = lookup(order.coin);
          if (coin == null) return;
          result.add(order);
        });
        result.sort((a, b) {
          final coinA = lookup(a.coin);
          final coinB = lookup(b.coin);
          final fiatA =
              a.price.toDouble() * (coinA?.usdPrice?.price?.toDouble() ?? 0.0);
          final fiatB =
              b.price.toDouble() * (coinB?.usdPrice?.price?.toDouble() ?? 0.0);
          return fiatB.compareTo(fiatA);
        });
        return result;
      }

      legacyPrepare(orders, legacyLookup);

      await tester.pumpWidget(
        MaterialApp(
          home: _wrapForTableUtilsTest(
            coinsForRepo: coins,
            child: Builder(
              builder: (context) {
                prepareOrdersForTable(
                  context,
                  orders,
                  null,
                  AuthorizeMode.noLogin,
                  coinLookup: optimisedLookup,
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(legacyCalls['BTC']! > optimisedCalls['BTC']!, isTrue);
      expect(legacyCalls['KMD']! > optimisedCalls['KMD']!, isTrue);
    });
  });
}

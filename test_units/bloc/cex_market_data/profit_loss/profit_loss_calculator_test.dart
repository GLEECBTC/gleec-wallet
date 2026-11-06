import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/profit_loss_calculator.dart';

final _asset = AssetId(
  id: 'BTCZ',
  name: 'BitcoinZ',
  symbol: AssetSymbol(assetConfigId: 'BTCZ'),
  chainId: AssetChainId(chainId: 0),
  derivationPath: null,
  subClass: CoinSubClass.utxo,
);

Transaction _transaction(String id, DateTime timestamp, int netChange) =>
    Transaction(
      id: id,
      internalId: id,
      assetId: _asset,
      balanceChanges: BalanceChanges(
        netChange: Decimal.fromInt(netChange),
        receivedByMe: Decimal.fromInt(netChange > 0 ? netChange : 0),
        spentByMe: Decimal.fromInt(netChange < 0 ? -netChange : 0),
        totalAmount: Decimal.fromInt(netChange.abs()),
      ),
      timestamp: timestamp,
      confirmations: 1,
      blockHeight: 1,
      from: const ['from-address'],
      to: const ['to-address'],
      txHash: 'hash-$id',
    );

class _MarketData implements MarketDataManager {
  _MarketData(this.prices);

  final Map<DateTime, Decimal> prices;
  final requested = <DateTime>[];

  @override
  Future<Map<DateTime, Decimal>> fiatPriceHistory(
    AssetId assetId,
    List<DateTime> dates, {
    QuoteCurrency quoteCurrency = Stablecoin.usdt,
  }) async {
    requested.addAll(dates);
    return prices;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sdk implements KomodoDefiSdk {
  _Sdk(this.marketData);

  @override
  final _MarketData marketData;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DateTime _utcToday() {
  final now = DateTime.now().toUtc();
  return DateTime.utc(now.year, now.month, now.day);
}

void main() {
  group('ProfitLossCalculator', () {
    final firstPricedDay = DateTime.utc(2025, 11, 7);
    final pricedSaleDay = DateTime.utc(2025, 11, 15);

    test('prices a buy older than the history at the nearest date', () async {
      final calculator = ProfitLossCalculator(
        _Sdk(
          _MarketData({
            firstPricedDay: Decimal.one,
            pricedSaleDay: Decimal.fromInt(2),
            _utcToday(): Decimal.fromInt(3),
          }),
        ),
      );

      final profitLosses = await calculator.getProfitFromTransactions(
        [
          _transaction('buy', DateTime.utc(2024, 6, 1, 12), 10),
          _transaction('sell', pricedSaleDay.add(const Duration(hours: 8)), -4),
        ],
        coinId: _asset,
        fiatCoinId: 'USDT',
      );

      // The buy takes the first known price, $1. Selling 4 at $2 realizes
      // $4; the 6 left are worth $3 each against their $6 cost.
      expect(profitLosses.map((p) => p.profitLoss), [20.0, 16.0]);
    });

    test('uses the latest-dated price when today has none', () async {
      final calculator = ProfitLossCalculator(
        _Sdk(
          _MarketData({
            pricedSaleDay: Decimal.fromInt(2),
            firstPricedDay: Decimal.one,
          }),
        ),
      );

      final profitLosses = await calculator.getProfitFromTransactions(
        [_transaction('buy', firstPricedDay, 10)],
        coinId: _asset,
        fiatCoinId: 'USDT',
      );

      expect(profitLosses.single.profitLoss, 10.0);
    });

    test('throws an exception when no price history comes back', () async {
      final calculator = ProfitLossCalculator(_Sdk(_MarketData({})));

      await expectLater(
        calculator.getProfitFromTransactions(
          [_transaction('buy', firstPricedDay, 10)],
          coinId: _asset,
          fiatCoinId: 'USDT',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('asks the price history for UTC dates', () async {
      final marketData = _MarketData({firstPricedDay: Decimal.one});
      final calculator = ProfitLossCalculator(_Sdk(marketData));

      await calculator.getProfitFromTransactions(
        [_transaction('buy', DateTime(2025, 11, 7, 23, 30), 10)],
        coinId: _asset,
        fiatCoinId: 'USDT',
      );

      expect(marketData.requested, hasLength(2));
      expect(marketData.requested.every((date) => date.isUtc), isTrue);
    });
  });
}

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

Transaction _transaction(
  String id,
  DateTime timestamp,
  num netChange, {
  int blockHeight = 1,
}) => Transaction(
  id: id,
  internalId: id,
  assetId: _asset,
  balanceChanges: BalanceChanges(
    netChange: Decimal.parse('$netChange'),
    receivedByMe: Decimal.parse('${netChange > 0 ? netChange : 0}'),
    spentByMe: Decimal.parse('${netChange < 0 ? -netChange : 0}'),
    totalAmount: Decimal.parse('${netChange.abs()}'),
  ),
  timestamp: timestamp,
  confirmations: 1,
  blockHeight: blockHeight,
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

    test(
      'does not invent a cost basis for a buy older than the history',
      () async {
        final calculator = ProfitLossCalculator(
          _Sdk(
            _MarketData({
              firstPricedDay: Decimal.one,
              pricedSaleDay: Decimal.fromInt(2),
              _utcToday(): Decimal.fromInt(3),
            }),
          ),
        );

        await expectLater(
          calculator.getProfitFromTransactions(
            [
              _transaction('buy', DateTime.utc(2024, 6, 1, 12), 10),
              _transaction(
                'sell',
                pricedSaleDay.add(const Duration(hours: 8)),
                -4,
              ),
            ],
            coinId: _asset,
            fiatCoinId: 'USDT',
          ),
          throwsA(isA<ProfitLossPriceUnavailable>()),
        );
      },
    );

    test('fractional sales can exactly liquidate a holding', () async {
      final calculator = RealisedProfitLossCalculator(
        _Sdk(
          _MarketData({
            firstPricedDay: Decimal.one,
            pricedSaleDay: Decimal.fromInt(2),
          }),
        ),
      );
      final result = await calculator.getProfitFromTransactions(
        [
          _transaction('buy', firstPricedDay, 0.3),
          _transaction('sell-1', pricedSaleDay, -0.1),
          _transaction(
            'sell-2',
            pricedSaleDay.add(const Duration(hours: 1)),
            -0.2,
          ),
        ],
        coinId: _asset,
        fiatCoinId: 'USDT',
      );
      expect(result.last.profitLoss, closeTo(0.3, 1e-12));
    });

    test('realized FIFO sales use the price of each consumed lot', () async {
      final calculator = RealisedProfitLossCalculator(
        _Sdk(
          _MarketData({
            firstPricedDay: Decimal.one,
            firstPricedDay.add(const Duration(days: 1)): Decimal.fromInt(2),
            pricedSaleDay: Decimal.fromInt(3),
          }),
        ),
      );
      final result = await calculator.getProfitFromTransactions(
        [
          _transaction('buy-1', firstPricedDay, 2),
          _transaction('buy-2', firstPricedDay.add(const Duration(days: 1)), 3),
          _transaction('sell', pricedSaleDay, -4),
        ],
        coinId: _asset,
        fiatCoinId: 'USDT',
      );
      // Four units sell for $12: cost is 2 x $1 plus 2 x $2.
      expect(result.last.profitLoss, 6);
    });

    test(
      'missing sale prices also leave the whole calculation unavailable',
      () async {
        final calculator = RealisedProfitLossCalculator(
          _Sdk(_MarketData({firstPricedDay: Decimal.one})),
        );
        await expectLater(
          calculator.getProfitFromTransactions(
            [
              _transaction('buy', firstPricedDay, 10),
              _transaction('sell', pricedSaleDay, -4),
            ],
            coinId: _asset,
            fiatCoinId: 'USDT',
          ),
          throwsA(isA<ProfitLossPriceUnavailable>()),
        );
      },
    );

    test(
      'accepts immutable transaction history without changing its order',
      () async {
        final calculator = ProfitLossCalculator(
          _Sdk(
            _MarketData({
              firstPricedDay: Decimal.one,
              pricedSaleDay: Decimal.fromInt(2),
            }),
          ),
        );
        final transactions = List<Transaction>.unmodifiable([
          _transaction('sell', pricedSaleDay, -1),
          _transaction('buy', firstPricedDay, 2),
        ]);
        final result = await calculator.getProfitFromTransactions(
          transactions,
          coinId: _asset,
          fiatCoinId: 'USDT',
        );
        expect(result.last.profitLoss, 2);
        expect(transactions.first.id, 'sell');
      },
    );

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
        throwsA(isA<ProfitLossPriceUnavailable>()),
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

    test(
      'a receive is counted before the spend that shares its block',
      () async {
        final calculator = RealisedProfitLossCalculator(
          _Sdk(_MarketData({firstPricedDay: Decimal.one})),
        );
        final blockTime = firstPricedDay.add(const Duration(hours: 3));

        final result = await calculator.getProfitFromTransactions(
          [
            _transaction('spend', blockTime, -2),
            _transaction('receive', blockTime, 2),
          ],
          coinId: _asset,
          fiatCoinId: 'USDT',
        );

        expect(result.map((entry) => entry.internalId), ['receive', 'spend']);
        expect(result.last.profitLoss, 0);
      },
    );

    test('same-block pairs stay ordered in a long history', () async {
      final calculator = RealisedProfitLossCalculator(
        _Sdk(_MarketData({firstPricedDay: Decimal.one})),
      );
      // Long enough to leave the insertion sort that small lists get, with
      // every spend listed before the receive it consumes.
      final transactions = [
        for (var block = 60; block > 0; block--) ...[
          _transaction(
            'spend-$block',
            firstPricedDay.add(Duration(minutes: block)),
            -1,
            blockHeight: block,
          ),
          _transaction(
            'receive-$block',
            firstPricedDay.add(Duration(minutes: block)),
            1,
            blockHeight: block,
          ),
        ],
      ];

      final result = await calculator.getProfitFromTransactions(
        transactions,
        coinId: _asset,
        fiatCoinId: 'USDT',
      );

      expect(result, hasLength(120));
      expect(result.take(4).map((entry) => entry.internalId), [
        'receive-1',
        'spend-1',
        'receive-2',
        'spend-2',
      ]);
      expect(result.last.profitLoss, 0);
    });

    test('equal timestamps resolve the same way in any input order', () async {
      final calculator = RealisedProfitLossCalculator(
        _Sdk(_MarketData({firstPricedDay: Decimal.one})),
      );
      final transactions = [
        _transaction('b', firstPricedDay, 1, blockHeight: 7),
        _transaction('a', firstPricedDay, 1, blockHeight: 7),
        _transaction('c', firstPricedDay, 1, blockHeight: 6),
        _transaction('d', firstPricedDay, -1, blockHeight: 6),
      ];

      Future<List<String>> order(List<Transaction> input) async => [
        for (final entry in await calculator.getProfitFromTransactions(
          input,
          coinId: _asset,
          fiatCoinId: 'USDT',
        ))
          entry.internalId,
      ];

      expect(await order(transactions), ['c', 'a', 'b', 'd']);
      expect(await order(transactions.reversed.toList()), ['c', 'a', 'b', 'd']);
    });
  });
}

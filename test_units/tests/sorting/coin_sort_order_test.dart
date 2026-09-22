import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_sdk/src/balances/balance_manager.dart';
import 'package:komodo_defi_sdk/src/market_data/market_data_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/coins_bloc/asset_coin_extension.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/coin_utils.dart';

/// Pins the order produced by the wallet-list sorts.
///
/// `sortByPriorityAndBalance` runs inside `ActiveCoinsList.build()` on every
/// `CoinsBloc` emission, and its comparator calls `lastKnownUsdBalance` twice
/// per comparison - each call rebuilding a non-memoised cache key and doing a
/// `Decimal` multiply, so roughly 426 of each per rebuild at 40 coins.
///
/// Hoisting those reads out of the comparator (decorate-sort-undecorate) is
/// only safe if the resulting order is identical, so these cases are written
/// against the *original* comparator and must keep passing unchanged
/// afterwards. They cover every branch the comparator can take, including the
/// ones a happy-path fixture would miss: a known balance with an unknown price,
/// a zero balance with a known price, and ties at each level.
void testCoinSortOrder() {
  group('wallet list sort order:', () {
    /// [prices] and [balances] are per-ticker; USD value is their product,
    /// which is what `lastKnownUsdBalance` computes.
    List<Coin> sortPriority(
      List<Coin> coins, {
      Map<String, double> prices = const {},
      Map<String, double> balances = const {},
    }) =>
        sortByPriorityAndBalance(coins, _fakeSdk(prices, balances));

    List<Coin> sortFiat(
      List<Coin> coins, {
      Map<String, double> prices = const {},
      Map<String, double> balances = const {},
    }) =>
        sortFiatBalance(coins, _fakeSdk(prices, balances));

    List<String> tickers(List<Coin> coins) => coins.map((c) => c.abbr).toList();

    test('parents come before child tokens, whatever the balance', () {
      final parent = _coin('ETH');
      final child = _coin('USDT', parent: parent);

      expect(
        tickers(
          sortPriority(
            [child, parent],
            prices: {'USDT': 1},
            balances: {'USDT': 999},
          ),
        ),
        ['ETH', 'USDT'],
      );
    });

    test('non-zero balances sort ahead of zero, by USD descending', () {
      final coins = [_coin('AAA'), _coin('BBB'), _coin('CCC')];
      expect(
        tickers(
          sortPriority(
            coins,
            prices: {'AAA': 5, 'CCC': 50},
            balances: {'AAA': 1, 'CCC': 1},
          ),
        ),
        ['CCC', 'AAA', 'BBB'],
      );
    });

    test('with no balances at all, higher priority wins', () {
      final coins = [
        _coin('AAA', priority: 1),
        _coin('BBB', priority: 9),
        _coin('CCC', priority: 5),
      ];
      expect(tickers(sortPriority(coins)), ['BBB', 'CCC', 'AAA']);
    });

    test('equal priority falls back to ticker, alphabetically', () {
      final coins = [_coin('CCC'), _coin('AAA'), _coin('BBB')];
      expect(tickers(sortPriority(coins)), ['AAA', 'BBB', 'CCC']);
    });

    test('a known balance with an unknown price is not a balance', () {
      // `lastKnownUsdBalance` returns null when the balance is known but the
      // price is not. Those coins must fall through to the priority branch
      // rather than be ordered by a garbage number.
      final coins = [_coin('AAA', priority: 1), _coin('BBB', priority: 9)];
      expect(
        tickers(sortPriority(coins, balances: {'AAA': 10, 'BBB': 10})),
        ['BBB', 'AAA'],
      );
    });

    test('a zero balance short-circuits to zero before the price is read', () {
      final coins = [_coin('AAA', priority: 1), _coin('BBB', priority: 9)];
      expect(
        tickers(
          sortPriority(
            coins,
            prices: {'AAA': 100, 'BBB': 100},
            balances: {'AAA': 0, 'BBB': 0},
          ),
        ),
        ['BBB', 'AAA'],
      );
    });

    test('order is stable across repeated sorts of the same input', () {
      // The hoisted version reads each balance once instead of once per
      // comparison. A comparator that is not internally consistent can produce
      // a different order on each call, which this would catch.
      final coins = [
        _coin('AAA', priority: 3),
        _coin('BBB', priority: 3),
        _coin('CCC', priority: 7),
        _coin('DDD'),
      ];
      final prices = {'DDD': 12.5};
      final balances = {'DDD': 1.0};
      final first = tickers(
        sortPriority(coins, prices: prices, balances: balances),
      );
      for (var i = 0; i < 5; i++) {
        expect(
          tickers(sortPriority(coins, prices: prices, balances: balances)),
          first,
        );
      }
    });

    test('the input list is not mutated', () {
      final coins = [_coin('CCC'), _coin('AAA')];
      final before = tickers(coins);
      sortPriority(coins);
      expect(tickers(coins), before);
    });

    test('empty and single-element inputs are handled', () {
      expect(sortPriority(const <Coin>[]), isEmpty);
      expect(tickers(sortPriority([_coin('AAA')])), ['AAA']);
    });

    group('sortFiatBalance:', () {
      test('sorts by USD descending', () {
        final coins = [_coin('AAA'), _coin('BBB'), _coin('CCC')];
        expect(
          tickers(
            sortFiat(
              coins,
              prices: {'AAA': 5, 'CCC': 50},
              balances: {'AAA': 1, 'CCC': 1},
            ),
          ),
          ['CCC', 'AAA', 'BBB'],
        );
      });

      test('equal USD falls through to the raw balance', () {
        // Both price to zero USD, so the tie-break is the underlying balance -
        // a second pair of SDK reads per comparison in the original.
        final coins = [_coin('AAA'), _coin('BBB')];
        expect(
          tickers(sortFiat(coins, balances: {'AAA': 1, 'BBB': 3})),
          ['BBB', 'AAA'],
        );
      });

      test('parents still come first', () {
        final parent = _coin('ETH');
        final child = _coin('USDT', parent: parent);
        expect(
          tickers(
            sortFiat(
              [child, parent],
              prices: {'USDT': 1},
              balances: {'USDT': 999},
            ),
          ),
          ['ETH', 'USDT'],
        );
      });
    });
  });
}

void main() => testCoinSortOrder();

KomodoDefiSdk _fakeSdk(
  Map<String, double> prices,
  Map<String, double> balances,
) =>
    _FakeSdk(
      balanceManager: _FakeBalanceManager(balances),
      marketDataManager: _FakeMarketDataManager(prices),
    );

Coin _coin(String ticker, {int priority = 0, Coin? parent}) {
  final asset = Asset.fromJson({
    'coin': ticker,
    'type': 'UTXO',
    'name': ticker,
    'fname': ticker,
    'wallet_only': false,
    'mm2': 1,
    'chain_id': 141,
    'decimals': 8,
    'is_testnet': false,
    'required_confirmations': 1,
    'derivation_path': "m/44'/141'/0'",
    'protocol': {'type': 'UTXO'},
  }, knownIds: const {});
  return asset.toCoin().copyWith(
        state: CoinState.active,
        priority: priority,
        parentCoin: parent,
      );
}

class _FakeSdk implements KomodoDefiSdk {
  _FakeSdk({required this.balanceManager, required this.marketDataManager});

  final BalanceManager balanceManager;
  final MarketDataManager marketDataManager;

  @override
  BalanceManager get balances => balanceManager;

  @override
  MarketDataManager get marketData => marketDataManager;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBalanceManager implements BalanceManager {
  _FakeBalanceManager(this.byTicker);

  final Map<String, double> byTicker;

  @override
  BalanceInfo? lastKnown(AssetId assetId) {
    final value = byTicker[assetId.id];
    if (value == null) return null;
    return BalanceInfo(
      total: Decimal.parse(value.toString()),
      spendable: Decimal.parse(value.toString()),
      unspendable: Decimal.zero,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMarketDataManager implements MarketDataManager {
  _FakeMarketDataManager(this.byTicker);

  final Map<String, double> byTicker;

  @override
  Decimal? priceIfKnown(
    AssetId assetId, {
    DateTime? priceDate,
    QuoteCurrency quoteCurrency = Stablecoin.usdt,
  }) {
    final value = byTicker[assetId.id];
    return value == null ? null : Decimal.parse(value.toString());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

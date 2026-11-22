import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_session.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_persistence_layer/komodo_persistence_layer.dart';
import 'package:web_dex/bloc/cex_market_data/common/price_history_coverage.dart';
import 'package:web_dex/bloc/cex_market_data/models/graph_cache.dart';
import 'package:web_dex/bloc/cex_market_data/portfolio_growth/portfolio_growth_repository.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/transaction_history/transaction_history_repo.dart';
import 'package:web_dex/model/coin.dart';

import '../../../tests/utils/test_util.dart';

DateTime _utcDay(DateTime date) {
  final utc = date.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

/// The UTC days of [dates], oldest first.
List<DateTime> _days(Iterable<DateTime> dates) =>
    {for (final date in dates) _utcDay(date)}.toList()..sort();

Map<DateTime, Decimal> _priced(Iterable<DateTime> days) => {
  for (final day in days) day: Decimal.fromInt(2),
};

class _Auth extends Fake implements KomodoDefiLocalAuth {
  final _sessions = AuthSessionTracker()
    ..observe(
      KdfUser(
        walletId: WalletId.withPubkeyHash(
          'wallet-a',
          const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
          'hash-a',
        ),
        isBip39Seed: true,
      ),
    );

  @override
  Future<AuthSessionContext> captureSessionContext() async =>
      _sessions.current!;
}

/// Prices the days [known] picks out of the ones it is asked for, as the SDK
/// does when its history providers fail for the rest.
class _MarketData extends Fake implements MarketDataManager {
  Map<DateTime, Decimal> Function(List<DateTime> days) known = _priced;

  @override
  Future<Map<DateTime, Decimal>> fiatPriceHistory(
    AssetId assetId,
    List<DateTime> dates, {
    QuoteCurrency quoteCurrency = Stablecoin.usdt,
  }) async => known(_days(dates));
}

class _Sdk extends Fake implements KomodoDefiSdk {
  @override
  final _Auth auth = _Auth();

  @override
  final _MarketData marketData = _MarketData();
}

class _Coins extends Fake implements CoinsRepo {
  _Coins(this._coin);

  final Coin _coin;

  @override
  Coin? getCoinFromId(AssetId id) => _coin;
}

class _History extends Fake implements TransactionHistoryRepo {
  _History(this._coin);

  final Coin _coin;

  @override
  Future<List<Transaction>> fetchCompletedTransactions(AssetId assetId) async =>
      [
        Transaction(
          id: 'buy',
          internalId: 'buy',
          assetId: _coin.id,
          balanceChanges: BalanceChanges(
            netChange: Decimal.one,
            receivedByMe: Decimal.one,
            spentByMe: Decimal.zero,
            totalAmount: Decimal.one,
          ),
          timestamp: DateTime.now().subtract(const Duration(days: 30)),
          confirmations: 1,
          blockHeight: 1,
          from: const ['from-address'],
          to: const ['to-address'],
          txHash: 'hash-buy',
        ),
      ];
}

class _Charts extends Fake implements PersistenceProvider<String, GraphCache> {
  final entries = <String, GraphCache>{};

  @override
  Future<GraphCache?> get(String key) async => entries[key];

  @override
  Future<void> insert(GraphCache object) async =>
      entries[object.primaryKey] = object;
}

void main() {
  group('isPartialPriceHistory', () {
    final now = DateTime.utc(2026, 11, 17, 12);
    final range = [
      for (var day = 30; day >= 0; day--) now.subtract(Duration(days: day)),
    ];
    final days = _days(range);

    bool partial(Iterable<DateTime> pricedDays) =>
        isPartialPriceHistory(_priced(pricedDays), range, now: now);

    test('a history with every requested day is whole', () {
      expect(partial(days), isFalse);
    });

    test("today's price alone is what an outage leaves of a longer range", () {
      expect(partial([days.last]), isTrue);
    });

    test('a few scattered days are a remnant', () {
      expect(partial([days[3], days[11], days[19], days.last]), isTrue);
    });

    test('a history that starts after the range does is whole', () {
      // A provider that keeps a week, or an asset priced a week ago.
      expect(partial(days.skip(24)), isFalse);
    });

    test('a history with a few days missing is whole', () {
      expect(partial(days.where((day) => day.day % 5 != 0)), isFalse);
    });

    test('no price at all is not a remnant of one', () {
      expect(partial(const []), isFalse);
    });

    test('one requested day with its price is whole', () {
      expect(
        isPartialPriceHistory(_priced([_utcDay(now)]), [now], now: now),
        isFalse,
      );
    });

    test('days still to come are not expected to have a price', () {
      final withTomorrow = [...range, now.add(const Duration(days: 1))];
      expect(
        isPartialPriceHistory(_priced(days), withTomorrow, now: now),
        isFalse,
      );
    });
  });

  group('PortfolioGrowthRepository with a partly known price history', () {
    final coin = setCoin(coinAbbr: 'BTCZ');
    late _Sdk sdk;
    late _Charts cache;
    late PortfolioGrowthRepository repository;

    setUp(() {
      sdk = _Sdk();
      cache = _Charts();
      repository = PortfolioGrowthRepository(
        transactionHistoryRepo: _History(coin),
        cacheProvider: cache,
        coinsRepository: _Coins(coin),
        sdk: sdk,
      );
    });

    Future<List<Object>> refresh() => repository.getCoinGrowthChart(
      coin.id,
      fiatCoinId: 'USDT',
      walletId: 'wallet-a',
      useCache: false,
    );

    Map<DateTime, Decimal> onlyToday(List<DateTime> days) =>
        _priced([days.last]);

    test('a whole history is charted and cached', () async {
      final chart = await refresh();
      expect(chart.length, greaterThan(20));
      expect(cache.entries.values.single.graph, chart);
    });

    test(
      "a chart from today's price alone is neither shown nor cached",
      () async {
        sdk.marketData.known = onlyToday;
        await expectLater(
          refresh(),
          throwsA(isA<PartialPriceHistoryException>()),
        );
        expect(cache.entries, isEmpty);
      },
    );

    test(
      'an outage keeps the last whole chart, on screen and in the cache',
      () async {
        final whole = await refresh();

        sdk.marketData.known = onlyToday;
        expect(await refresh(), whole);
        expect(cache.entries.values.single.graph, whole);
      },
    );

    test(
      'the portfolio chart leaves the coin out instead of failing',
      () async {
        sdk.marketData.known = onlyToday;
        final chart = await repository.getPortfolioGrowthChart(
          [coin],
          fiatCoinId: 'USDT',
          walletId: 'wallet-a',
          useCache: false,
        );
        expect(chart, isEmpty);
        expect(cache.entries, isEmpty);
      },
    );

    test('an asset nobody prices still caches its empty chart', () async {
      sdk.marketData.known = (_) => const {};
      expect(await refresh(), isEmpty);
      expect(cache.entries.values.single.graph, isEmpty);
    });
  });
}

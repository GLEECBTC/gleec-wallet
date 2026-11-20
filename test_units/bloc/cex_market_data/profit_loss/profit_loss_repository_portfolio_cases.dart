part of 'profit_loss_repository_test.dart';

void _portfolioProfitLossTests() {
  group('getPortfolioProfitLoss', () {
    AssetId coin(String id) => AssetId(
      id: id,
      name: id,
      symbol: AssetSymbol(assetConfigId: id),
      chainId: AssetChainId(chainId: 0),
      derivationPath: null,
      subClass: CoinSubClass.utxo,
    );
    final priced = coin('BTCZ');
    final unpriced = coin('GLEEC');
    final unread = coin('KMD');

    late _Sdk sdk;
    late _MemoryCache cache;
    late _PerCoin source;
    late ProfitLossRepository repository;

    setUp(() {
      sdk = _Sdk();
      cache = _MemoryCache();
      source = _PerCoin(sdk)
        ..unpriced.add(unpriced)
        ..unread.add(unread);
      repository = ProfitLossRepository(
        profitLossCacheProvider: cache,
        transactionHistoryRepo: source,
        profitLossCalculator: source,
        sdk: sdk,
      );
    });

    test('values what it can and lists what it cannot', () async {
      final portfolio = await repository.getPortfolioProfitLoss(
        [priced, unpriced, unread],
        'USDT',
        'wallet-a',
      );
      expect(portfolio.valued.keys, [priced]);
      expect(portfolio.valued[priced]!.single.internalId, 'buy');
      expect(portfolio.unavailable, [unpriced, unread]);
      expect(portfolio.isUnavailable, isFalse);
      // Only the coin that was valued has a cached result.
      expect(cache._entries.values.map((entry) => entry.coinId), ['BTCZ']);
    });

    test('nothing valued is unavailable rather than an empty total', () async {
      final portfolio = await repository.getPortfolioProfitLoss(
        [unpriced, unread],
        'USDT',
        'wallet-a',
      );
      expect(portfolio.valued, isEmpty);
      expect(portfolio.isUnavailable, isTrue);
    });

    test('a coin without transactions is valued, not unavailable', () async {
      source.empty.add(priced);
      final portfolio = await repository.getPortfolioProfitLoss(
        [priced],
        'USDT',
        'wallet-a',
      );
      expect(portfolio.valued[priced], isEmpty);
      expect(portfolio.isUnavailable, isFalse);
    });

    test(
      'an ended session fails the load instead of excluding coins',
      () async {
        sdk.auth.invalidateSession();
        await expectLater(
          repository.getPortfolioProfitLoss([priced], 'USDT', 'wallet-a'),
          throwsA(isA<AuthSessionChangedException>()),
        );
      },
    );

    test(
      'an unreadable identity fails the load for the whole wallet',
      () async {
        sdk.auth.signInWithoutIdentity();
        await expectLater(
          repository.getPortfolioProfitLoss(
            [priced, unpriced],
            'USDT',
            'wallet-a',
          ),
          throwsA(isA<AuthIdentityUnavailableException>()),
        );
      },
    );
  });
}

/// A history and a calculator that fail for chosen coins only.
class _PerCoin extends ProfitLossCalculator implements TransactionHistoryRepo {
  _PerCoin(super.sdk);

  final unpriced = <AssetId>{};
  final unread = <AssetId>{};
  final empty = <AssetId>{};

  @override
  Future<List<Transaction>?> fetch(AssetId assetId) async {
    if (unread.contains(assetId)) return null;
    return [if (!empty.contains(assetId)) _transaction(assetId, 'buy')];
  }

  @override
  Future<List<Transaction>> fetchCompletedTransactions(AssetId assetId) =>
      throw UnimplementedError();

  @override
  Future<List<ProfitLoss>> getProfitFromTransactions(
    List<Transaction> transactions, {
    required AssetId coinId,
    required String fiatCoinId,
  }) async {
    if (unpriced.contains(coinId)) {
      throw ProfitLossPriceUnavailable(coinId.id, DateTime.utc(2025, 11, 7));
    }
    return [
      for (final transaction in transactions)
        ProfitLoss.fromTransaction(transaction, FiatValue.usd(1), 0),
    ];
  }
}

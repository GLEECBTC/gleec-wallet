import 'dart:math';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:uuid/uuid.dart';
import 'package:web_dex/bloc/cex_market_data/mockup/performance_mode.dart';

// Cache for demo price history data
final _priceHistoryCache = <AssetId, Map<DateTime, double>>{};

/// Generates semi-random transaction data for demo purposes. The transactions
/// are generated based on simulated historical price data for the given coin. The
/// transactions are generated in a way that the overall balance of the user
/// will increase or decrease based on the given performance mode.
class DemoDataGenerator {
  final KomodoDefiSdk _sdk;
  final int randomSeed;
  final List<AssetId> assetIds;
  final Map<PerformanceMode, double> transactionsPerMode;
  final Map<PerformanceMode, double> overallReturn;
  final Map<PerformanceMode, List<double>> buyProbabilities;
  final Map<PerformanceMode, List<double>> tradeAmountFactors;
  final double initialBalance;

  const DemoDataGenerator(
    this._sdk, {
    this.initialBalance = 1000.0,
    this.assetIds = const <AssetId>[], // Will be initialized with default list
    this.transactionsPerMode = const {
      PerformanceMode.good: 28,
      PerformanceMode.mediocre: 52,
      PerformanceMode.veryBad: 34,
    },
    this.overallReturn = const {
      PerformanceMode.good: 2.0,
      PerformanceMode.mediocre: 1.0,
      PerformanceMode.veryBad: 0.05,
    },
    this.buyProbabilities = const {
      PerformanceMode.good: [0.9, 0.7, 0.5, 0.2],
      PerformanceMode.mediocre: [0.6, 0.5, 0.5, 0.4],
      PerformanceMode.veryBad: [0.7, 0.5, 0.3, 0.1],
    },
    this.tradeAmountFactors = const {
      PerformanceMode.good: [0.25, 0.2, 0.15, 0.1],
      PerformanceMode.mediocre: [0.01, 0.01, 0.01, 0.01],
      PerformanceMode.veryBad: [0.1, 0.15, 0.2, 0.25],
    },
    this.randomSeed = 42,
  });

  /// Default asset IDs for demo purposes
  static final List<AssetId> defaultAssetIds = [
    AssetId(
      chainId: AssetChainId(chainId: 1),
      derivationPath: '',
      id: 'KMD',
      name: 'Komodo',
      subClass: CoinSubClass.smartChain,
      symbol: AssetSymbol(assetConfigId: 'KMD'),
    ),
    AssetId(
      chainId: AssetChainId(chainId: 2),
      derivationPath: '',
      id: 'LTC',
      name: 'Litecoin',
      subClass: CoinSubClass.smartChain,
      symbol: AssetSymbol(assetConfigId: 'LTC'),
    ),
    AssetId(
      chainId: AssetChainId(chainId: 137),
      derivationPath: '',
      id: 'POL',
      name: 'Polygon',
      subClass: CoinSubClass.polygon,
      symbol: AssetSymbol(assetConfigId: 'POL'),
    ),
    AssetId(
      chainId: AssetChainId(chainId: 43114),
      derivationPath: '',
      id: 'AVAX',
      name: 'Avalanche',
      subClass: CoinSubClass.avx20,
      symbol: AssetSymbol(assetConfigId: 'AVAX'),
    ),
    AssetId(
      chainId: AssetChainId(chainId: 250),
      derivationPath: '',
      id: 'FTM',
      name: 'Fantom',
      subClass: CoinSubClass.ftm20,
      symbol: AssetSymbol(assetConfigId: 'FTM'),
    ),
    AssetId(
      chainId: AssetChainId(chainId: 118),
      derivationPath: '',
      id: 'ATOM',
      name: 'Cosmos',
      subClass: CoinSubClass.tendermint,
      symbol: AssetSymbol(assetConfigId: 'ATOM'),
    ),
  ];

  Future<List<Transaction>> generateTransactions(
    String coinId,
    PerformanceMode mode,
  ) async {
    if (_priceHistoryCache.isEmpty) {
      await fetchPriceHistoryData();
    }

    // Try to match the coinId to one of our asset IDs
    final actualAssetIds = assetIds.isEmpty ? defaultAssetIds : assetIds;
    final assetId = actualAssetIds.cast<AssetId?>().firstWhere(
      (asset) =>
          asset!.id.toLowerCase() == coinId.toLowerCase() ||
          asset.symbol.assetConfigId.toLowerCase() == coinId.toLowerCase(),
      orElse: () => null,
    );

    if (assetId == null || !_priceHistoryCache.containsKey(assetId)) {
      return [];
    }

    final priceHistory = _priceHistoryCache[assetId]!;
    final priceEntries = priceHistory.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final numTransactions = transactionsPerMode[mode]!;
    final random = Random(randomSeed);
    final buyProbabilities = this.buyProbabilities[mode]!;
    final tradeAmounts = tradeAmountFactors[mode]!;

    // Get the initial price for calculations
    final initialPrice = priceEntries.first.value;
    final finalPrice = priceEntries.last.value;
    double totalBalance = initialBalance / initialPrice;
    double targetFinalBalance =
        (initialBalance * overallReturn[mode]!) / finalPrice;

    List<Transaction> transactions = [];

    for (int i = 0; i < numTransactions; i++) {
      final int index = (i * priceEntries.length ~/ numTransactions).clamp(
        0,
        priceEntries.length - 1,
      );
      final priceEntry = priceEntries[index];

      final int quarter = (i * 4 ~/ numTransactions).clamp(0, 3);
      final bool isBuy = random.nextDouble() < buyProbabilities[quarter];
      final bool isSameDay = random.nextDouble() < tradeAmounts[quarter];
      final double tradeAmountFactor = tradeAmounts[quarter];

      final double tradeAmount =
          random.nextDouble() * tradeAmountFactor * totalBalance;

      final transaction = fromTradeAmount(
        coinId,
        tradeAmount,
        isBuy,
        priceEntry.key.millisecondsSinceEpoch,
      );
      transactions.add(transaction);

      if (isSameDay) {
        final transaction = fromTradeAmount(
          coinId,
          -tradeAmount,
          !isBuy,
          priceEntry.key.millisecondsSinceEpoch + 100,
        );
        transactions.add(transaction);
      }

      totalBalance += transaction.balanceChanges.netChange.toDouble();
      if (totalBalance <= 0) {
        totalBalance = targetFinalBalance;
        break;
      }
    }

    List<Transaction> adjustedTransactions = _adjustTransactionsToTargetBalance(
      targetFinalBalance,
      totalBalance,
      transactions,
    );

    return adjustedTransactions;
  }

  List<Transaction> _adjustTransactionsToTargetBalance(
    double targetFinalBalance,
    double totalBalance,
    List<Transaction> transactions,
  ) {
    final Decimal adjustmentFactor = Decimal.parse(
      (targetFinalBalance / totalBalance).toString(),
    );
    final adjustedTransactions = <Transaction>[];
    for (var transaction in transactions) {
      final netChange = transaction.balanceChanges.netChange;
      final received = transaction.balanceChanges.receivedByMe;
      final spent = transaction.balanceChanges.spentByMe;
      final totalAmount = transaction.balanceChanges.totalAmount;

      adjustedTransactions.add(
        transaction.copyWith(
          balanceChanges: BalanceChanges(
            netChange: netChange * adjustmentFactor,
            receivedByMe: received * adjustmentFactor,
            spentByMe: spent * adjustmentFactor,
            totalAmount: totalAmount * adjustmentFactor,
          ),
        ),
      );
    }
    return adjustedTransactions;
  }

  /// Fetches simulated price history data for demo purposes.
  /// This replaces the legacy CEX repository OHLC data fetching.
  Future<void> fetchPriceHistoryData() async {
    final actualAssetIds = assetIds.isEmpty ? defaultAssetIds : assetIds;
    for (final assetId in actualAssetIds) {
      try {
        // Try to fetch real price history from SDK if available
        final now = DateTime.now();
        final startDate = now.subtract(const Duration(days: 365));

        // Generate daily intervals for the past year
        final dates = <DateTime>[];
        for (
          var date = startDate;
          date.isBefore(now);
          date = date.add(const Duration(days: 1))
        ) {
          dates.add(date);
        }

        Map<DateTime, double> priceHistory;

        try {
          // Attempt to get real price data from SDK
          final quoteCurrency = QuoteCurrency.fromString('USDT');
          if (quoteCurrency != null) {
            final sdkPriceHistory = await _sdk.marketData.fiatPriceHistory(
              assetId,
              dates,
              quoteCurrency: quoteCurrency,
            );

            // Convert Decimal to double
            priceHistory = sdkPriceHistory.map(
              (key, value) => MapEntry(key, value.toDouble()),
            );
          } else {
            throw Exception('Unable to create USDT quote currency');
          }
        } catch (e) {
          // Fallback: generate simulated price data
          priceHistory = _generateSimulatedPriceData(
            startDate: startDate,
            endDate: now,
            initialPrice:
                50.0 +
                Random(assetId.hashCode).nextDouble() *
                    100, // Price between $50-$150
          );
        }

        _priceHistoryCache[assetId] = priceHistory;
      } catch (e) {
        // If all else fails, generate basic simulated data
        final now = DateTime.now();
        final startDate = now.subtract(const Duration(days: 365));
        final priceHistory = _generateSimulatedPriceData(
          startDate: startDate,
          endDate: now,
          initialPrice:
              10.0 +
              Random(assetId.hashCode).nextDouble() *
                  90, // Price between $10-$100
        );
        _priceHistoryCache[assetId] = priceHistory;
      }
    }
  }

  /// Generates simulated price data for demo purposes
  Map<DateTime, double> _generateSimulatedPriceData({
    required DateTime startDate,
    required DateTime endDate,
    required double initialPrice,
  }) {
    final priceHistory = <DateTime, double>{};
    final random = Random(randomSeed);
    var currentPrice = initialPrice;

    for (
      var date = startDate;
      date.isBefore(endDate);
      date = date.add(const Duration(days: 1))
    ) {
      // Generate semi-realistic price movements (±5% daily change)
      final changePercent = (random.nextDouble() - 0.5) * 0.1; // ±5%
      currentPrice = currentPrice * (1 + changePercent);

      // Ensure price doesn't go below $1
      currentPrice = currentPrice.clamp(1.0, double.infinity);

      priceHistory[date] = currentPrice;
    }

    return priceHistory;
  }
}

Transaction fromTradeAmount(
  String coinId,
  double tradeAmount,
  bool isBuy,
  int timestampMilliseconds,
) {
  const uuid = Uuid();
  final random = Random(42);

  return Transaction(
    id: uuid.v4(),
    blockHeight: random.nextInt(100000) + 100000,
    assetId: AssetId(
      chainId: AssetChainId(chainId: 0),
      derivationPath: '',
      id: coinId,
      name: coinId,
      subClass: CoinSubClass.smartChain,
      symbol: AssetSymbol(assetConfigId: coinId),
    ),
    confirmations: random.nextInt(3) + 1,
    from: const ["address1"],
    internalId: uuid.v4(),
    balanceChanges: BalanceChanges(
      netChange: Decimal.parse(
        isBuy ? tradeAmount.toString() : (-tradeAmount).toString(),
      ),
      receivedByMe: Decimal.parse(!isBuy ? tradeAmount.toString() : '0'),
      spentByMe: Decimal.parse(isBuy ? tradeAmount.toString() : '0'),
      totalAmount: Decimal.parse(tradeAmount.toString()),
    ),
    timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMilliseconds),
    to: const ["address2"],
    txHash: uuid.v4(),
    memo: "memo",
  );
}

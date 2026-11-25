import 'dart:async';
import 'dart:math';

import 'package:hive_ce/hive.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_persistence_layer/komodo_persistence_layer.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/bloc/cex_market_data/cache_constants.dart';
import 'package:web_dex/bloc/cex_market_data/charts.dart';
import 'package:web_dex/bloc/cex_market_data/common/update_frequency_backoff_strategy.dart';
import 'package:web_dex/bloc/cex_market_data/mockup/performance_mode.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/demo_profit_loss_repository.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/extensions/profit_loss_transaction_extension.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/models/adapters/adapters.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/models/profit_loss.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/models/profit_loss_cache.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/profit_loss_calculator.dart';
import 'package:web_dex/bloc/transaction_history/transaction_history_repo.dart';

class ProfitLossRepository {
  ProfitLossRepository({
    required PersistenceProvider<String, ProfitLossCache>
    profitLossCacheProvider,
    required TransactionHistoryRepo transactionHistoryRepo,
    required ProfitLossCalculator profitLossCalculator,
    required KomodoDefiSdk sdk,
    DateTime Function() clock = DateTime.now,
  }) : _transactionHistoryRepo = transactionHistoryRepo,
       _profitLossCacheProvider = profitLossCacheProvider,
       _profitLossCalculator = profitLossCalculator,
       _sdk = sdk,
       _clock = clock;

  /// Return a new instance of [ProfitLossRepository] with default values.
  ///
  /// If [demoMode] is provided, it will return a [MockProfitLossRepository].
  factory ProfitLossRepository.withDefaults({
    required TransactionHistoryRepo transactionHistoryRepo,
    required KomodoDefiSdk sdk,
    String cacheTableName = profitLossCacheBoxName,
    PerformanceMode? demoMode,
  }) {
    if (demoMode != null) {
      return MockProfitLossRepository.withDefaults(
        performanceMode: demoMode,
        cacheTableName: 'mock_${cacheTableName}_${demoMode.name}',
        sdk: sdk,
      );
    }

    return ProfitLossRepository(
      transactionHistoryRepo: transactionHistoryRepo,
      profitLossCacheProvider: HiveLazyBoxProvider<String, ProfitLossCache>(
        name: cacheTableName,
      ),
      profitLossCalculator: RealisedProfitLossCalculator(sdk),
      sdk: sdk,
    );
  }

  final PersistenceProvider<String, ProfitLossCache> _profitLossCacheProvider;
  final TransactionHistoryRepo _transactionHistoryRepo;
  final ProfitLossCalculator _profitLossCalculator;
  final KomodoDefiSdk _sdk;
  final DateTime Function() _clock;

  /// Keyed like [ProfitLossCache]; a success removes the entry.
  final Map<String, _FailureBackoff> _recentFailures = {};

  final _log = Logger('profit-loss-repository');

  static Future<void> ensureInitialized() async {
    if (!Hive.isAdapterRegistered(fiatValueAdapterTypeId)) {
      Hive.registerAdapter(FiatValueAdapter());
    }
    if (!Hive.isAdapterRegistered(profitLossAdapterTypeId)) {
      Hive.registerAdapter(ProfitLossAdapter());
    }
    if (!Hive.isAdapterRegistered(profitLossCacheAdapterTypeId)) {
      Hive.registerAdapter(ProfitLossCacheAdapter());
    }
  }

  Future<void> clearCache() async {
    final stopwatch = Stopwatch()..start();
    _log.fine('Clearing profit/loss cache');

    _recentFailures.clear();
    await _profitLossCacheProvider.deleteAll();

    stopwatch.stop();
    _log.fine(
      'Profit/loss cache cleared in ${stopwatch.elapsedMilliseconds}ms',
    );
  }

  /// Get the profit/loss data for a coin based on the transactions
  /// and the spot price of the coin in the fiat currency.
  ///
  /// [coinId] is the id of the coin. E.g. 'BTC'. This is generally the coin
  /// ticker from the komodo coins repository.
  /// [fiatCoinId] is id of the stablecoin to convert the [coinId] to get the
  /// fiat-equivalent price of the coin. This can be any supported coin id, but
  /// the idea is to convert the coin to a fiat currency to calculate the
  /// profit/loss in fiat.
  /// [walletId] is the wallet ID associated with the profit/loss data.
  ///
  /// Returns the list of [ProfitLoss] for the coin. A calculation that fails
  /// returns the last successful one, unless the coin has transactions that
  /// result leaves out. It then throws: the coin's profit/loss is unavailable,
  /// which is not the empty list of a coin without transactions.
  ///
  /// Throws [AuthSessionChangedException] when [walletId] is not the session's
  /// wallet, and [AuthIdentityUnavailableException] when the session has no
  /// verified identity to store results under.
  Future<List<ProfitLoss>> getProfitLoss(
    AssetId coinId,
    String fiatCoinId,
    String walletId, {
    bool useCache = true,
  }) async {
    final methodStopwatch = Stopwatch()..start();
    _log.fine(
      'Getting profit/loss for ${coinId.id} in $fiatCoinId for wallet $walletId, '
      'useCache: $useCache',
    );

    // HD mode is part of the session's wallet identity. `currentUser` would
    // re-verify it against KDF, two RPCs for every coin on every refresh.
    final session = await _sdk.auth.captureSessionContext();
    if (session.walletId.name != walletId) {
      throw const AuthSessionChangedException();
    }
    // The SDK omits the identity when its RPC was unreachable at sign-in. The
    // session is still this wallet's; only the cache key cannot be built.
    if (session.walletId.pubkeyHash?.isNotEmpty != true) {
      throw const AuthIdentityUnavailableException();
    }
    final isHdWallet = session.walletId.isHd;
    // Include the verified seed identity, not just the reusable display name.
    // The version also retires cached results with approximated cost bases or
    // the earlier multi-lot FIFO calculation.
    final cacheWalletId = 'v2:${session.walletId.compoundId}';

    final String compoundKey = ProfitLossCache.getPrimaryKey(
      coinId: coinId.id,
      fiatCurrency: fiatCoinId,
      walletId: cacheWalletId,
      isHdWallet: isHdWallet,
    );

    if (useCache) {
      final cacheStopwatch = Stopwatch()..start();
      final ProfitLossCache? profitLossCache = await _profitLossCacheProvider
          .get(compoundKey);
      _sdk.auth.ensureSessionContextCurrent(session);
      final bool cacheExists = profitLossCache != null;
      cacheStopwatch.stop();

      if (cacheExists) {
        _log.fine(
          'ProfitLossCache hit for ${coinId.id} in $fiatCoinId for wallet $walletId '
          'in ${cacheStopwatch.elapsedMilliseconds}ms, '
          'entries: ${profitLossCache.profitLosses.length}',
        );
        methodStopwatch.stop();
        return profitLossCache.profitLosses;
      }
      _log.fine(
        'ProfitLossCache miss for ${coinId.id} in $fiatCoinId for wallet $walletId '
        'in ${cacheStopwatch.elapsedMilliseconds}ms',
      );
    }

    final failure = _recentFailures[compoundKey];
    _sdk.auth.ensureSessionContextCurrent(session);
    if (failure != null && _clock().isBefore(failure.retryAt)) {
      _log.fine(
        'Not recomputing profit/loss for ${coinId.id} before '
        '${failure.retryAt}; it last failed with: ${failure.error}',
      );
      return _lastComputedOrThrow(
        compoundKey,
        session,
        failure.error,
        failure.stackTrace,
      );
    }

    try {
      final profitLosses = await _computeProfitLoss(
        coinId,
        fiatCoinId,
        cacheWalletId,
        session: session,
        isHdWallet: isHdWallet,
        compoundKey: compoundKey,
        methodStopwatch: methodStopwatch,
      );
      _recentFailures.remove(compoundKey);
      return profitLosses;
    } catch (error, stackTrace) {
      // Session revocation is not a provider failure. It must neither cache a
      // result nor delay a freshly authenticated session's first calculation.
      _sdk.auth.ensureSessionContextCurrent(session);
      if (error is AuthSessionChangedException) rethrow;
      (_recentFailures[compoundKey] ??= _FailureBackoff()).record(
        error,
        stackTrace,
        failedAt: _clock(),
      );
      return _lastComputedOrThrow(compoundKey, session, error, stackTrace);
    }
  }

  /// The last successful calculation, for a refresh that failed. A cached
  /// result that survives a failure is still the best one known:
  /// [_computeProfitLoss] removes it once newer transactions prove it stale.
  /// Rethrows [error] when there is none, leaving the coin unavailable.
  Future<List<ProfitLoss>> _lastComputedOrThrow(
    String compoundKey,
    AuthSessionContext session,
    Object error,
    StackTrace stackTrace,
  ) async {
    final lastComputed = await _profitLossCacheProvider.get(compoundKey);
    _sdk.auth.ensureSessionContextCurrent(session);
    if (lastComputed == null) Error.throwWithStackTrace(error, stackTrace);
    return lastComputed.profitLosses;
  }

  /// Completed transactions, or [ProfitLossHistoryUnavailable] when the
  /// history could not be read. The history repository reports a failed read
  /// as "no transactions", which would be cached as a coin without history.
  Future<List<Transaction>> _fetchCompletedTransactions(AssetId coinId) async {
    final transactions = await _transactionHistoryRepo.fetch(coinId);
    if (transactions == null) throw ProfitLossHistoryUnavailable(coinId.id);
    final unconfirmed = DateTime.fromMillisecondsSinceEpoch(0);
    return [
      for (final transaction in transactions)
        if (transaction.timestamp != unconfirmed) transaction,
    ];
  }

  Future<List<ProfitLoss>> _computeProfitLoss(
    AssetId coinId,
    String fiatCoinId,
    String walletId, {
    required AuthSessionContext session,
    required bool isHdWallet,
    required String compoundKey,
    required Stopwatch methodStopwatch,
  }) async {
    final txStopwatch = Stopwatch()..start();
    _log.fine('Fetching transactions for ${coinId.id}');
    final transactions = await _fetchCompletedTransactions(coinId);
    _sdk.auth.ensureSessionContextCurrent(session);
    txStopwatch.stop();
    _log.fine(
      'Fetched ${transactions.length} transactions for ${coinId.id} '
      'in ${txStopwatch.elapsedMilliseconds}ms',
    );

    if (transactions.isEmpty) {
      _log.fine('No transactions found for ${coinId.id}');

      final existingCache = await _profitLossCacheProvider.get(compoundKey);
      _sdk.auth.ensureSessionContextCurrent(session);
      if (existingCache != null && existingCache.profitLosses.isNotEmpty) {
        _log.fine(
          'Keeping existing non-empty cache for ${coinId.id} '
          '(${existingCache.profitLosses.length} entries) '
          'instead of overwriting with empty transactions',
        );
        methodStopwatch.stop();
        return existingCache.profitLosses;
      }

      final cacheInsertStopwatch = Stopwatch()..start();
      await _profitLossCacheProvider.insert(
        ProfitLossCache(
          coinId: coinId.id,
          profitLosses: List.empty(),
          fiatCoinId: fiatCoinId,
          lastUpdated: DateTime.now(),
          walletId: walletId,
          isHdWallet: isHdWallet,
        ),
      );
      _sdk.auth.ensureSessionContextCurrent(session);
      cacheInsertStopwatch.stop();
      _log.fine(
        'Cached empty profit/loss for ${coinId.id} '
        'in ${cacheInsertStopwatch.elapsedMilliseconds}ms',
      );
      methodStopwatch.stop();
      return <ProfitLoss>[];
    }

    final calcStopwatch = Stopwatch()..start();
    _log.fine(
      'Calculating profit/loss for ${coinId.id} with ${transactions.length} transactions',
    );
    final List<ProfitLoss> profitLosses;
    try {
      profitLosses = await _profitLossCalculator.getProfitFromTransactions(
        transactions,
        coinId: coinId,
        fiatCoinId: fiatCoinId,
      );
    } catch (_) {
      _sdk.auth.ensureSessionContextCurrent(session);
      await _dropCacheNotCovering(transactions, compoundKey, session);
      rethrow;
    }
    _sdk.auth.ensureSessionContextCurrent(session);
    calcStopwatch.stop();
    _log.fine(
      'Calculated ${profitLosses.length} profit/loss entries for ${coinId.id} '
      'in ${calcStopwatch.elapsedMilliseconds}ms',
    );

    final cacheInsertStopwatch = Stopwatch()..start();
    await _profitLossCacheProvider.insert(
      ProfitLossCache(
        coinId: coinId.id,
        profitLosses: profitLosses,
        fiatCoinId: fiatCoinId,
        lastUpdated: DateTime.now(),
        walletId: walletId,
        isHdWallet: isHdWallet,
      ),
    );
    _sdk.auth.ensureSessionContextCurrent(session);
    cacheInsertStopwatch.stop();
    _log.fine(
      'Cached ${profitLosses.length} profit/loss entries for ${coinId.id} '
      'in ${cacheInsertStopwatch.elapsedMilliseconds}ms',
    );
    methodStopwatch.stop();
    return profitLosses;
  }

  /// Removes a cached result that leaves out some of [transactions].
  ///
  /// When those cannot be valued, the cached result would keep answering for
  /// an older history: a coin cached while empty would count as zero forever
  /// after receiving funds that have no price.
  Future<void> _dropCacheNotCovering(
    List<Transaction> transactions,
    String compoundKey,
    AuthSessionContext session,
  ) async {
    final cached = await _profitLossCacheProvider.get(compoundKey);
    _sdk.auth.ensureSessionContextCurrent(session);
    if (cached == null) return;
    final cachedIds = {
      for (final profitLoss in cached.profitLosses) profitLoss.internalId,
    };
    // The calculator leaves out transfers that moved nothing.
    final isCurrent = transactions
        .where((transaction) => transaction.totalAmountAsDouble != 0)
        .every((transaction) => cachedIds.contains(transaction.internalId));
    if (isCurrent) return;
    await _profitLossCacheProvider.delete(compoundKey);
    _sdk.auth.ensureSessionContextCurrent(session);
  }
}

/// When a coin whose profit/loss failed may be computed again. Each refresh
/// recomputes every coin without a cached result, so a coin that cannot be
/// priced would otherwise fetch its history and prices again every minute.
class _FailureBackoff {
  final _intervals = UpdateFrequencyBackoffStrategy();
  late Object error;
  late StackTrace stackTrace;
  late DateTime retryAt;

  void record(
    Object error,
    StackTrace stackTrace, {
    required DateTime failedAt,
  }) {
    this.error = error;
    this.stackTrace = stackTrace;
    retryAt = failedAt.add(_intervals.getNextInterval());
  }
}

/// The coin's transaction history could not be read, which says nothing about
/// whether it has transactions.
class ProfitLossHistoryUnavailable implements Exception {
  const ProfitLossHistoryUnavailable(this.coinId);

  final String coinId;

  @override
  String toString() => 'Transaction history unavailable for $coinId';
}

extension ProfitLossExtension on List<ProfitLoss> {
  ChartData toChartData() {
    return map((ProfitLoss profitLoss) {
      return Point<double>(
        profitLoss.timestamp.millisecondsSinceEpoch.toDouble(),
        profitLoss.profitLoss,
      );
    }).toList();
  }
}

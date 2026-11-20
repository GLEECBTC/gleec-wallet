import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_session.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_persistence_layer/komodo_persistence_layer.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/models/fiat_value.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/models/profit_loss.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/models/profit_loss_cache.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/portfolio_profit_loss.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/profit_loss_calculator.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/profit_loss_repository.dart';
import 'package:web_dex/bloc/transaction_history/transaction_history_repo.dart';

part 'profit_loss_repository_portfolio_cases.dart';

final _asset = AssetId(
  id: 'BTCZ',
  name: 'BitcoinZ',
  symbol: AssetSymbol(assetConfigId: 'BTCZ'),
  chainId: AssetChainId(chainId: 0),
  derivationPath: null,
  subClass: CoinSubClass.utxo,
);

class _Auth implements KomodoDefiLocalAuth {
  final _sessions = AuthSessionTracker()
    ..observe(
      KdfUser(
        walletId: WalletId.withPubkeyHash(
          'wallet-a',
          const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
          'wallet-a-pubkey-hash',
        ),
        isBip39Seed: true,
      ),
    );

  @override
  Future<AuthSessionContext> captureSessionContext() async =>
      _sessions.current ?? (throw const AuthSessionChangedException());

  void invalidateSession() => _sessions.invalidate();

  @override
  void ensureSessionContextCurrent(AuthSessionContext context) {
    if (!_sessions.isCurrent(context)) {
      throw const AuthSessionChangedException();
    }
  }

  void replaceSession({
    String name = 'wallet-a',
    String hash = 'wallet-a-pubkey-hash',
  }) {
    _sessions.invalidate();
    _sessions.observe(
      KdfUser(
        walletId: WalletId.withPubkeyHash(
          name,
          const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
          hash,
        ),
        isBip39Seed: true,
      ),
    );
  }

  /// The session the SDK opens when its identity RPC was unreachable.
  void signInWithoutIdentity() {
    _sessions.invalidate();
    _sessions.observe(
      KdfUser(
        walletId: WalletId.fromName(
          'wallet-a',
          const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
        ),
        isBip39Seed: true,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sdk implements KomodoDefiSdk {
  @override
  final _Auth auth = _Auth();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryCache implements PersistenceProvider<String, ProfitLossCache> {
  final _entries = <String, ProfitLossCache>{};

  @override
  Future<ProfitLossCache?> get(String key) async => _entries[key];

  @override
  Future<void> insert(ProfitLossCache object) async =>
      _entries[object.primaryKey] = object;

  @override
  Future<void> delete(String key) async => _entries.remove(key);

  @override
  Future<void> deleteAll() async => _entries.clear();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Transaction _transaction(AssetId assetId, String id, {DateTime? at}) =>
    Transaction(
      id: id,
      internalId: id,
      assetId: assetId,
      balanceChanges: BalanceChanges(
        netChange: Decimal.one,
        receivedByMe: Decimal.one,
        spentByMe: Decimal.zero,
        totalAmount: Decimal.one,
      ),
      timestamp: at ?? DateTime.utc(2025, 11, 7),
      confirmations: 1,
      blockHeight: 1,
      from: const ['from-address'],
      to: const ['to-address'],
      txHash: 'hash-$id',
    );

class _History implements TransactionHistoryRepo {
  int fetches = 0;
  Future<void> Function()? beforeReturn;

  /// The history as the node reports it; null is a read that failed.
  List<String>? transactionIds = ['buy'];

  @override
  Future<List<Transaction>?> fetch(AssetId assetId) async {
    fetches++;
    await beforeReturn?.call();
    return transactionIds?.map((id) => _transaction(assetId, id)).toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Calculator extends ProfitLossCalculator {
  _Calculator(super.sdk);

  bool fails = true;
  Future<void> Function()? beforeReturn;

  @override
  Future<List<ProfitLoss>> getProfitFromTransactions(
    List<Transaction> transactions, {
    required AssetId coinId,
    required String fiatCoinId,
  }) async {
    await beforeReturn?.call();
    if (fails) throw Exception('No USD price history for ${coinId.id}');
    return [
      for (final transaction in transactions)
        ProfitLoss.fromTransaction(transaction, FiatValue.usd(1), 0),
    ];
  }
}

/// A confirmed history followed by a transaction still waiting for a block.
class _MixedHistory implements TransactionHistoryRepo {
  _MixedHistory(this._confirmed);

  final _History _confirmed;

  @override
  Future<List<Transaction>?> fetch(AssetId assetId) async => [
    ...?await _confirmed.fetch(assetId),
    _transaction(
      assetId,
      'pending',
      at: DateTime.fromMillisecondsSinceEpoch(0),
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('ProfitLossRepository failure backoff', () {
    late DateTime now;
    late _History history;
    late _Calculator calculator;
    late ProfitLossRepository repository;
    late _Sdk sdk;
    late _MemoryCache cache;

    setUp(() {
      now = DateTime.utc(2026, 11, 6, 9);
      sdk = _Sdk();
      cache = _MemoryCache();
      history = _History();
      calculator = _Calculator(sdk);
      repository = ProfitLossRepository(
        profitLossCacheProvider: cache,
        transactionHistoryRepo: history,
        profitLossCalculator: calculator,
        sdk: sdk,
        clock: () => now,
      );
    });

    Future<void> expectFailure({bool useCache = true}) => expectLater(
      repository.getProfitLoss(_asset, 'USDT', 'wallet-a', useCache: useCache),
      throwsA(isA<Exception>()),
    );

    test('returns the last error until the coin may be retried', () async {
      await expectFailure();
      expect(history.fetches, 1);

      now = now.add(const Duration(seconds: 59));
      await expectFailure();
      await expectFailure(useCache: false);
      expect(history.fetches, 1);

      now = now.add(const Duration(seconds: 2));
      await expectFailure();
      expect(history.fetches, 2);
    });

    test('waits longer after repeated failures', () async {
      // Retry intervals run 1, 1, 2, 2, 4 minutes.
      await expectFailure();
      now = now.add(const Duration(minutes: 1));
      await expectFailure();
      now = now.add(const Duration(minutes: 1));
      await expectFailure();
      expect(history.fetches, 3);

      now = now.add(const Duration(minutes: 1, seconds: 59));
      await expectFailure();
      expect(history.fetches, 3);

      now = now.add(const Duration(seconds: 1));
      await expectFailure();
      expect(history.fetches, 4);
    });

    test('a success restarts the retry intervals', () async {
      await expectFailure();
      now = now.add(const Duration(minutes: 1));
      await expectFailure();
      now = now.add(const Duration(minutes: 1));
      calculator.fails = false;
      await repository.getProfitLoss(
        _asset,
        'USDT',
        'wallet-a',
        useCache: false,
      );

      // Without the success this third failure would wait 2 minutes. The
      // failed refreshes answer with the result the success left behind.
      calculator.fails = true;
      Future<void> refresh() =>
          repository.getProfitLoss(_asset, 'USDT', 'wallet-a', useCache: false);
      await refresh();
      now = now.add(const Duration(minutes: 1));
      await refresh();
      expect(history.fetches, 5);
    });

    test('clearCache forgets failures', () async {
      await expectFailure();
      await repository.clearCache();

      await expectFailure();
      expect(history.fetches, 2);
    });

    test(
      'a missing wallet session is unavailable rather than empty history',
      () async {
        sdk.auth.invalidateSession();
        await expectLater(
          repository.getProfitLoss(_asset, 'USDT', 'wallet-a'),
          throwsA(isA<AuthSessionChangedException>()),
        );
        expect(history.fetches, 0);
        expect(cache._entries, isEmpty);
      },
    );

    test(
      'rejects requests for a wallet other than the active session',
      () async {
        calculator.fails = false;
        await expectLater(
          repository.getProfitLoss(_asset, 'USDT', 'wallet-b'),
          throwsA(isA<AuthSessionChangedException>()),
        );
        expect(history.fetches, 0);
        expect(cache._entries, isEmpty);
      },
    );

    for (final boundary in ['history', 'calculation']) {
      test(
        'session replacement during $boundary cannot poison the cache or backoff',
        () async {
          calculator.fails = false;
          final reached = Completer<void>();
          final released = Completer<void>();
          Future<void> wait() async {
            reached.complete();
            await released.future;
          }

          if (boundary == 'history') {
            history.beforeReturn = wait;
          } else {
            calculator.beforeReturn = wait;
          }
          final pending = repository.getProfitLoss(_asset, 'USDT', 'wallet-a');
          final rejected = expectLater(
            pending,
            throwsA(isA<AuthSessionChangedException>()),
          );
          await reached.future;
          sdk.auth.replaceSession();
          released.complete();
          await rejected;
          expect(cache._entries, isEmpty);
          history.beforeReturn = null;
          calculator.beforeReturn = null;
          await repository.getProfitLoss(_asset, 'USDT', 'wallet-a');
          expect(history.fetches, 2);
        },
      );
    }

    test(
      'a failed history read is not cached as a coin without history',
      () async {
        calculator.fails = false;
        history.transactionIds = null;
        await expectLater(
          repository.getProfitLoss(_asset, 'USDT', 'wallet-a'),
          throwsA(isA<ProfitLossHistoryUnavailable>()),
        );
        expect(cache._entries, isEmpty);

        history.transactionIds = ['buy'];
        now = now.add(const Duration(minutes: 1));
        final recovered = await repository.getProfitLoss(
          _asset,
          'USDT',
          'wallet-a',
        );
        expect(recovered.single.internalId, 'buy');
      },
    );

    test('an empty history that was read is still cached', () async {
      history.transactionIds = [];
      expect(
        await repository.getProfitLoss(_asset, 'USDT', 'wallet-a'),
        isEmpty,
      );
      expect(cache._entries, hasLength(1));
    });

    test('unconfirmed transactions are left out of the calculation', () async {
      calculator.fails = false;
      final confirmed = _History()..transactionIds = ['buy'];
      final repository = ProfitLossRepository(
        profitLossCacheProvider: cache,
        transactionHistoryRepo: _MixedHistory(confirmed),
        profitLossCalculator: calculator,
        sdk: sdk,
        clock: () => now,
      );
      final result = await repository.getProfitLoss(_asset, 'USDT', 'wallet-a');
      expect(result.map((entry) => entry.internalId), ['buy']);
    });

    test('a refresh that fails returns the last computed result', () async {
      calculator.fails = false;
      final computed = await repository.getProfitLoss(
        _asset,
        'USDT',
        'wallet-a',
      );

      history.transactionIds = null;
      expect(
        await repository.getProfitLoss(
          _asset,
          'USDT',
          'wallet-a',
          useCache: false,
        ),
        computed,
      );
      // Still inside the retry interval: no second read, same answer.
      expect(
        await repository.getProfitLoss(
          _asset,
          'USDT',
          'wallet-a',
          useCache: false,
        ),
        computed,
      );
      expect(history.fetches, 2);
    });

    test(
      'the last result is kept when the same history cannot be recomputed',
      () async {
        calculator.fails = false;
        final computed = await repository.getProfitLoss(
          _asset,
          'USDT',
          'wallet-a',
        );

        calculator.fails = true;
        expect(
          await repository.getProfitLoss(
            _asset,
            'USDT',
            'wallet-a',
            useCache: false,
          ),
          computed,
        );
        expect(cache._entries, hasLength(1));
      },
    );

    test(
      'a result that predates unvalued transactions is not served',
      () async {
        // Cached while the coin had no history: it must not keep answering
        // "nothing happened" once funds arrive that cannot be priced.
        history.transactionIds = [];
        await repository.getProfitLoss(_asset, 'USDT', 'wallet-a');
        expect(cache._entries, hasLength(1));

        history.transactionIds = ['buy'];
        await expectFailure(useCache: false);
        expect(cache._entries, isEmpty);
        await expectFailure();
      },
    );

    test(
      'a session without a wallet identity is unavailable, not ended',
      () async {
        calculator.fails = false;
        sdk.auth.signInWithoutIdentity();
        await expectLater(
          repository.getProfitLoss(_asset, 'USDT', 'wallet-a'),
          throwsA(isA<AuthIdentityUnavailableException>()),
        );
        expect(history.fetches, 0);
        expect(cache._entries, isEmpty);
      },
    );

    test(
      'same-name wallet replacement never reuses another identity cache',
      () async {
        calculator.fails = false;
        await repository.getProfitLoss(_asset, 'USDT', 'wallet-a');
        sdk.auth.replaceSession(hash: 'replacement-pubkey-hash');
        await repository.getProfitLoss(_asset, 'USDT', 'wallet-a');
        expect(history.fetches, 2);
        expect(cache._entries, hasLength(2));
      },
    );
  });

  _portfolioProfitLossTests();
}

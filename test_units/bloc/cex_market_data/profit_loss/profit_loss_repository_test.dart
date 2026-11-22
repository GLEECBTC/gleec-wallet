import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_session.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_persistence_layer/komodo_persistence_layer.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/models/profit_loss.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/models/profit_loss_cache.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/profit_loss_calculator.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/profit_loss_repository.dart';
import 'package:web_dex/bloc/transaction_history/transaction_history_repo.dart';

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
  Future<void> deleteAll() async => _entries.clear();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _History implements TransactionHistoryRepo {
  int fetches = 0;
  Future<void> Function()? beforeReturn;

  @override
  Future<List<Transaction>> fetchCompletedTransactions(AssetId assetId) async {
    fetches++;
    await beforeReturn?.call();
    return [
      Transaction(
        id: 'buy',
        internalId: 'buy',
        assetId: assetId,
        balanceChanges: BalanceChanges(
          netChange: Decimal.one,
          receivedByMe: Decimal.one,
          spentByMe: Decimal.zero,
          totalAmount: Decimal.one,
        ),
        timestamp: DateTime.utc(2025, 11, 7),
        confirmations: 1,
        blockHeight: 1,
        from: const ['from-address'],
        to: const ['to-address'],
        txHash: 'hash-buy',
      ),
    ];
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
    return const <ProfitLoss>[];
  }
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

      // Without the success this third failure would wait 2 minutes.
      calculator.fails = true;
      await expectFailure(useCache: false);
      now = now.add(const Duration(minutes: 1));
      await expectFailure(useCache: false);
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
}

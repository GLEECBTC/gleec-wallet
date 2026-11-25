import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_session.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/cex_market_data/common/update_frequency_backoff_strategy.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/models/fiat_value.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/models/profit_loss.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/profit_loss_calculator.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/profit_loss_repository.dart';

const tick = Duration(milliseconds: 50);

Future<void> waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// One purchase of [bought] units at [price], leaving a running profit of
/// [profit].
ProfitLoss purchase(
  String coin, {
  required double bought,
  required double price,
  double profit = 0,
  DateTime? at,
}) => ProfitLoss(
  profitLoss: profit,
  coin: coin,
  fiatPrice: FiatValue.usd(price),
  internalId: '$coin-buy',
  myBalanceChange: bought,
  receivedAmountFiatPrice: bought * price,
  spentAmountFiatPrice: 0,
  timestamp: at ?? DateTime.utc(2025, 11, 7),
  totalAmount: bought,
  txHash: '$coin-hash',
);

/// Holds every profit/loss lookup until [release].
class SlowProfitLoss implements ProfitLossRepository {
  final _gates = <String, Completer<List<ProfitLoss>>>{};
  int lookups = 0;

  /// Completes the lookups of [walletId] with a purchase worth 1 USD for
  /// `wallet-a` and 2 USD for any other wallet, to tell their totals apart.
  void release({String walletId = 'wallet-a'}) => _gates[walletId]!.complete([
    purchase('BTCZ', bought: walletId == 'wallet-a' ? 1 : 2, price: 1),
  ]);

  void reject() => _gates['wallet-a']!.completeError(
    ProfitLossPriceUnavailable('BTCZ', DateTime.utc(2020)),
  );

  void invalidateSession() =>
      _gates['wallet-a']!.completeError(const AuthSessionChangedException());

  @override
  Future<List<ProfitLoss>> getProfitLoss(
    AssetId coinId,
    String fiatCoinId,
    String walletId, {
    bool useCache = true,
  }) {
    lookups++;
    return _gates.putIfAbsent(walletId, Completer<List<ProfitLoss>>.new).future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Answers each coin from [results]: its entries, or the error its lookup
/// throws. A coin without a result has no transactions.
class ScriptedProfitLoss implements ProfitLossRepository {
  final results = <String, Object>{};
  int lookups = 0;

  void failAll(Iterable<String> coins, Object error) {
    for (final coin in coins) {
      results[coin] = error;
    }
  }

  @override
  Future<List<ProfitLoss>> getProfitLoss(
    AssetId coinId,
    String fiatCoinId,
    String walletId, {
    bool useCache = true,
  }) async {
    lookups++;
    final result = results[coinId.id] ?? const <ProfitLoss>[];
    if (result is List<ProfitLoss>) return result;
    throw result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ActivatedAssets implements ActivatedAssetsCache {
  _ActivatedAssets(this.ids);

  final Set<AssetId> ids;

  @override
  Future<Set<AssetId>> getActivatedAssetIds({
    bool forceRefresh = false,
  }) async => ids;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// An SDK signed in to `wallet-a`, with [active] as its enabled assets.
class PortfolioSdk implements KomodoDefiSdk {
  PortfolioSdk(Set<AssetId> active)
    : activatedAssetsCache = _ActivatedAssets(active);

  @override
  final ActivatedAssetsCache activatedAssetsCache;

  @override
  final SignedInAuth auth = SignedInAuth();

  @override
  Future<bool> waitForEnabledAssetsToPassThreshold(
    Iterable<AssetId> assetIds, {
    double threshold = 0.5,
    Duration timeout = const Duration(seconds: 30),
  }) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SignedInAuth extends Fake implements KomodoDefiLocalAuth {
  SignedInAuth() {
    replaceSession();
  }

  final _sessions = AuthSessionTracker();

  void replaceSession() {
    _sessions.invalidate();
    _sessions.observe(
      KdfUser(
        walletId: WalletId.withPubkeyHash(
          'wallet-a',
          const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
          'hash-a',
        ),
        isBip39Seed: true,
      ),
    );
  }

  @override
  Future<AuthSessionContext> captureSessionContext() async =>
      _sessions.current!;

  @override
  void ensureSessionContextCurrent(AuthSessionContext session) {
    if (!_sessions.isCurrent(session)) {
      throw const AuthSessionChangedException();
    }
  }

  @override
  Future<bool> isSignedIn() async => true;
}

class FastBackoff extends Fake implements UpdateFrequencyBackoffStrategy {
  @override
  Duration getNextInterval() => tick;
  @override
  void reset() {}
}

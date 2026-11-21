import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_session.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/assets_overview/bloc/asset_overview_bloc.dart';
import 'package:web_dex/bloc/assets_overview/investment_repository.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/models/fiat_value.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/models/profit_loss.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/profit_loss_repository.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/profit_loss_calculator.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/profit_loss_bloc.dart';
import 'package:web_dex/bloc/cex_market_data/common/update_frequency_backoff_strategy.dart';
import 'package:web_dex/model/coin.dart';

import '../../tests/utils/test_util.dart';

/// Holds every profit/loss lookup until [release].
class _SlowProfitLoss implements ProfitLossRepository {
  final _gates = <String, Completer<List<ProfitLoss>>>{};
  int lookups = 0;

  void release({String walletId = 'wallet-a'}) =>
      _gates[walletId]!.complete(const <ProfitLoss>[]);

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

class _Investment implements InvestmentRepository {
  void Function()? onCalculate;
  @override
  Future<FiatValue> calculateTotalInvestment(
    String walletId,
    List<Coin> coins,
  ) async {
    onCalculate?.call();
    return FiatValue.usd(walletId == 'wallet-a' ? 1 : 2);
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

class _Sdk implements KomodoDefiSdk {
  _Sdk(Set<AssetId> active) : activatedAssetsCache = _ActivatedAssets(active);

  @override
  final ActivatedAssetsCache activatedAssetsCache;

  @override
  final _SignedInAuth auth = _SignedInAuth();

  @override
  Future<bool> waitForEnabledAssetsToPassThreshold(
    Iterable<AssetId> assetIds, {
    double threshold = 0.5,
    Duration timeout = const Duration(seconds: 30),
  }) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SignedInAuth extends Fake implements KomodoDefiLocalAuth {
  _SignedInAuth() {
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

class _FastBackoff extends Fake implements UpdateFrequencyBackoffStrategy {
  @override
  Duration getNextInterval() => _tick;
  @override
  void reset() {}
}

const _tick = Duration(milliseconds: 50);

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  group('AssetOverviewBloc portfolio refresh', () {
    final coin = setCoin(coinAbbr: 'BTCZ');
    late _SlowProfitLoss profitLoss;
    late AssetOverviewBloc bloc;
    late _Investment investment;
    late _Sdk sdk;

    setUp(() {
      profitLoss = _SlowProfitLoss();
      investment = _Investment();
      sdk = _Sdk({coin.id});
      bloc = AssetOverviewBloc(profitLoss, investment, sdk);
    });

    tearDown(() => bloc.close());

    PortfolioAssetsOverviewSubscriptionRequested subscription({
      String walletId = 'wallet-a',
    }) => PortfolioAssetsOverviewSubscriptionRequested(
      coins: [coin],
      walletId: walletId,
      updateFrequency: _tick,
    );

    test(
      'does not combine profit and investment from different sessions',
      () async {
        investment.onCalculate = sdk.auth.replaceSession;
        bloc.add(
          PortfolioAssetsOverviewLoadRequested(
            coins: [coin],
            walletId: 'wallet-a',
          ),
        );
        await _waitFor(() => profitLoss.lookups > 0);
        profitLoss.release();
        await _waitFor(() => bloc.state is AssetOverviewLoadFailure);
        expect(bloc.state, isA<AssetOverviewLoadFailure>());
      },
    );

    test('skips ticks while a portfolio load is still running', () async {
      bloc.add(subscription());
      await _waitFor(() => profitLoss.lookups > 0);
      await Future<void>.delayed(_tick * 6);
      expect(profitLoss.lookups, 1);

      profitLoss.release();
      await _waitFor(() => profitLoss.lookups > 1);
      expect(profitLoss.lookups, greaterThan(1));
    });

    test('a new subscription loads while an earlier load runs', () async {
      bloc.add(subscription());
      await _waitFor(() => profitLoss.lookups > 0);

      bloc.add(subscription());
      await _waitFor(() => profitLoss.lookups > 1);
      expect(profitLoss.lookups, 2);
      profitLoss.release();
    });

    test('clearing the portfolio rejects the pending load result', () async {
      bloc.add(subscription());
      await _waitFor(() => profitLoss.lookups > 0);
      bloc.add(const AssetOverviewClearRequested());
      await Future<void>.delayed(Duration.zero);
      profitLoss.release();
      await Future<void>.delayed(_tick * 2);
      expect(bloc.state, isA<AssetOverviewInitial>());
      expect(profitLoss.lookups, 1);
    });

    test(
      'missing cost basis is unavailable rather than a zero-dollar portfolio',
      () async {
        bloc.add(subscription());
        await _waitFor(() => profitLoss.lookups > 0);
        profitLoss.reject();
        await _waitFor(() => bloc.state is AssetOverviewLoadFailure);
        expect(bloc.state, isA<AssetOverviewLoadFailure>());
      },
    );

    test(
      'old wallet result cannot overwrite its replacement subscription',
      () async {
        bloc.add(subscription());
        await _waitFor(() => profitLoss.lookups > 0);
        bloc.add(subscription(walletId: 'wallet-b'));
        await _waitFor(() => profitLoss.lookups > 1);
        profitLoss.release(walletId: 'wallet-b');
        await _waitFor(() => bloc.state is PortfolioAssetsOverviewLoadSuccess);
        expect(
          (bloc.state as PortfolioAssetsOverviewLoadSuccess)
              .totalInvestment
              .value,
          2,
        );
        // Stop new timer loads so they cannot hide an obsolete publication.
        bloc.add(PortfolioAssetsOverviewUnsubscriptionRequested());
        await Future<void>.delayed(Duration.zero);
        profitLoss.release();
        await Future<void>.delayed(_tick * 2);
        expect(
          (bloc.state as PortfolioAssetsOverviewLoadSuccess)
              .totalInvestment
              .value,
          2,
        );
      },
    );
  });

  group('ProfitLossBloc lifecycle and unavailable history', () {
    final coin = setCoin(coinAbbr: 'BTCZ');
    late _SlowProfitLoss profitLoss;
    late ProfitLossBloc bloc;

    setUp(() {
      profitLoss = _SlowProfitLoss();
      bloc = ProfitLossBloc(
        profitLoss,
        _Sdk({coin.id}),
        backoffStrategy: _FastBackoff(),
      );
    });
    tearDown(() => bloc.close());

    ProfitLossPortfolioChartLoadRequested load() =>
        ProfitLossPortfolioChartLoadRequested(
          coins: [coin],
          fiatCoinId: 'USDT',
          selectedPeriod: const Duration(hours: 1),
          walletId: 'wallet-a',
        );

    test(
      'cleared one-hour chart stays cleared after its old request returns',
      () async {
        bloc.add(load());
        await _waitFor(() => profitLoss.lookups > 0);
        bloc.add(const ProfitLossPortfolioChartClearRequested());
        await Future<void>.delayed(Duration.zero);
        profitLoss.release();
        await Future<void>.delayed(_tick * 3);
        expect(bloc.state, isA<ProfitLossInitial>());
        expect(profitLoss.lookups, 1);
      },
    );

    test(
      'missing acquisition history becomes a failure rather than an empty chart',
      () async {
        bloc.add(load());
        await _waitFor(() => profitLoss.lookups > 0);
        profitLoss.reject();
        await _waitFor(() => bloc.state is ProfitLossLoadFailure);
        expect(bloc.state, isA<ProfitLossLoadFailure>());
      },
    );

    test(
      'a changed wallet session cannot become zero total investment',
      () async {
        final repository = InvestmentRepository(
          profitLossRepository: profitLoss,
        );
        final investment = repository.calculateTotalInvestment('wallet-a', [
          coin,
        ]);
        final rejected = expectLater(
          investment,
          throwsA(isA<AuthSessionChangedException>()),
        );
        profitLoss.invalidateSession();
        await rejected;
      },
    );

    test('missing cost basis cannot become zero total investment', () async {
      final repository = InvestmentRepository(profitLossRepository: profitLoss);
      final investment = repository.calculateTotalInvestment('wallet-a', [
        coin,
      ]);
      final rejected = expectLater(
        investment,
        throwsA(isA<ProfitLossPriceUnavailable>()),
      );
      profitLoss.reject();
      await rejected;
    });

    test(
      'changing period after unavailable history keeps the request retryable',
      () async {
        bloc.add(load());
        await _waitFor(() => profitLoss.lookups > 0);
        profitLoss.reject();
        await _waitFor(() => bloc.state is ProfitLossLoadFailure);
        final lookups = profitLoss.lookups;
        bloc.add(
          const ProfitLossPortfolioPeriodChanged(
            selectedPeriod: Duration(days: 1),
          ),
        );
        await Future<void>.delayed(_tick * 3);
        expect(bloc.state, isA<ProfitLossLoadFailure>());
        expect(bloc.state.selectedPeriod, const Duration(days: 1));
        expect(profitLoss.lookups, greaterThan(lookups));
      },
    );
  });
}

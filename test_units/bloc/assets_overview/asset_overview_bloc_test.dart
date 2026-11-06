import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/assets_overview/bloc/asset_overview_bloc.dart';
import 'package:web_dex/bloc/assets_overview/investment_repository.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/models/fiat_value.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/models/profit_loss.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/profit_loss_repository.dart';
import 'package:web_dex/model/coin.dart';

import '../../tests/utils/test_util.dart';

/// Holds every profit/loss lookup until [release].
class _SlowProfitLoss implements ProfitLossRepository {
  final _gate = Completer<List<ProfitLoss>>();
  int lookups = 0;

  void release() => _gate.complete(const <ProfitLoss>[]);

  @override
  Future<List<ProfitLoss>> getProfitLoss(
    AssetId coinId,
    String fiatCoinId,
    String walletId, {
    bool useCache = true,
  }) {
    lookups++;
    return _gate.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Investment implements InvestmentRepository {
  @override
  Future<FiatValue> calculateTotalInvestment(
    String walletId,
    List<Coin> coins,
  ) async => FiatValue.usd(0);

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
  Future<bool> waitForEnabledAssetsToPassThreshold(
    Iterable<AssetId> assetIds, {
    double threshold = 0.5,
    Duration timeout = const Duration(seconds: 30),
  }) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

    setUp(() {
      profitLoss = _SlowProfitLoss();
      bloc = AssetOverviewBloc(profitLoss, _Investment(), _Sdk({coin.id}));
    });

    tearDown(() => bloc.close());

    PortfolioAssetsOverviewSubscriptionRequested subscription() =>
        PortfolioAssetsOverviewSubscriptionRequested(
          coins: [coin],
          walletId: 'wallet-a',
          updateFrequency: _tick,
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
  });
}

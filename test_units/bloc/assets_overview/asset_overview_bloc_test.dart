import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/bloc/assets_overview/bloc/asset_overview_bloc.dart';
import 'package:web_dex/bloc/assets_overview/investment_repository.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/profit_loss_bloc.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/profit_loss_calculator.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/profit_loss_repository.dart';
import 'package:web_dex/model/coin.dart';

import '../../tests/utils/test_util.dart';
import 'portfolio_test_fakes.dart';

part 'profit_loss_chart_policy_cases.dart';

void main() {
  group('AssetOverviewBloc portfolio refresh', () {
    final coin = setCoin(coinAbbr: 'BTCZ');
    late SlowProfitLoss profitLoss;
    late AssetOverviewBloc bloc;
    late PortfolioSdk sdk;

    setUp(() {
      profitLoss = SlowProfitLoss();
      sdk = PortfolioSdk({coin.id});
      bloc = AssetOverviewBloc(
        profitLoss,
        InvestmentRepository(profitLossRepository: profitLoss),
        sdk,
      );
    });

    tearDown(() => bloc.close());

    PortfolioAssetsOverviewSubscriptionRequested subscription({
      String walletId = 'wallet-a',
    }) => PortfolioAssetsOverviewSubscriptionRequested(
      coins: [coin],
      walletId: walletId,
      updateFrequency: tick,
    );

    test('a result loaded for a session that ended is not shown', () async {
      bloc.add(
        PortfolioAssetsOverviewLoadRequested(
          coins: [coin],
          walletId: 'wallet-a',
        ),
      );
      await waitFor(() => profitLoss.lookups > 0);
      sdk.auth.replaceSession();
      profitLoss.release();
      await Future<void>.delayed(tick * 2);
      expect(bloc.state, isA<AssetOverviewInitial>());
    });

    test('skips ticks while a portfolio load is still running', () async {
      bloc.add(subscription());
      await waitFor(() => profitLoss.lookups > 0);
      await Future<void>.delayed(tick * 6);
      expect(profitLoss.lookups, 1);

      profitLoss.release();
      await waitFor(() => profitLoss.lookups > 1);
      expect(profitLoss.lookups, greaterThan(1));
    });

    test('a new subscription loads while an earlier load runs', () async {
      bloc.add(subscription());
      await waitFor(() => profitLoss.lookups > 0);

      bloc.add(subscription());
      await waitFor(() => profitLoss.lookups > 1);
      expect(profitLoss.lookups, 2);
      profitLoss.release();
    });

    test('clearing the portfolio rejects the pending load result', () async {
      bloc.add(subscription());
      await waitFor(() => profitLoss.lookups > 0);
      bloc.add(const AssetOverviewClearRequested());
      await Future<void>.delayed(Duration.zero);
      profitLoss.release();
      await Future<void>.delayed(tick * 2);
      expect(bloc.state, isA<AssetOverviewInitial>());
      expect(profitLoss.lookups, 1);
    });

    test(
      'missing cost basis is unavailable rather than a zero-dollar portfolio',
      () async {
        bloc.add(subscription());
        await waitFor(() => profitLoss.lookups > 0);
        profitLoss.reject();
        await waitFor(() => bloc.state is PortfolioAssetsOverviewUnavailable);
        expect(
          bloc.state,
          const PortfolioAssetsOverviewUnavailable(
            reason: AssetOverviewUnavailableReason.noAssetValued,
          ),
        );
      },
    );

    test(
      'old wallet result cannot overwrite its replacement subscription',
      () async {
        bloc.add(subscription());
        await waitFor(() => profitLoss.lookups > 0);
        bloc.add(subscription(walletId: 'wallet-b'));
        await waitFor(() => profitLoss.lookups > 1);
        profitLoss.release(walletId: 'wallet-b');
        await waitFor(() => bloc.state is PortfolioAssetsOverviewLoadSuccess);
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
        await Future<void>.delayed(tick * 2);
        expect(
          (bloc.state as PortfolioAssetsOverviewLoadSuccess)
              .totalInvestment
              .value,
          2,
        );
      },
    );
  });

  group('AssetOverviewBloc totals when an asset cannot be valued', () {
    final btcz = setCoin(coinAbbr: 'BTCZ');
    final kmd = setCoin(coinAbbr: 'KMD');
    final gleec = setCoin(coinAbbr: 'GLEEC');
    final coins = [btcz, kmd, gleec];
    final unpriced = ProfitLossPriceUnavailable('GLEEC', DateTime.utc(2020));
    late ScriptedProfitLoss profitLoss;
    late AssetOverviewBloc bloc;

    setUp(() {
      profitLoss = ScriptedProfitLoss()
        ..results['BTCZ'] = [purchase('BTCZ', bought: 2, price: 10, profit: 5)]
        ..results['KMD'] = [purchase('KMD', bought: 1, price: 3, profit: -1)]
        ..results['GLEEC'] = unpriced;
      bloc = AssetOverviewBloc(
        profitLoss,
        InvestmentRepository(profitLossRepository: profitLoss),
        PortfolioSdk({for (final coin in coins) coin.id}),
      );
    });

    tearDown(() => bloc.close());

    Future<AssetOverviewState> load() async {
      final lookups = profitLoss.lookups;
      bloc.add(
        PortfolioAssetsOverviewLoadRequested(
          coins: coins,
          walletId: 'wallet-a',
        ),
      );
      await waitFor(() => profitLoss.lookups >= lookups + coins.length);
      await Future<void>.delayed(tick);
      return bloc.state;
    }

    test('totals cover the valued assets and name the excluded one', () async {
      final state = await load() as PortfolioAssetsOverviewLoadSuccess;
      expect(state.totalInvestment.value, 23);
      expect(state.profitAmount.value, 4);
      expect(state.selectedAssetIds, ['BTCZ', 'KMD']);
      expect(state.excludedAssetIds, ['GLEEC']);
    });

    test('each asset is looked up once per load', () async {
      await load();
      expect(profitLoss.lookups, coins.length);
    });

    for (final failure in <Object>[
      const ProfitLossHistoryUnavailable('KMD'),
      Exception('Attempting to sell more than currently held'),
      StateError('price provider is down'),
    ]) {
      test(
        '${failure.runtimeType} excludes only the asset it is about',
        () async {
          profitLoss.results['KMD'] = failure;
          final state = await load() as PortfolioAssetsOverviewLoadSuccess;
          expect(state.totalInvestment.value, 20);
          expect(state.excludedAssetIds, ['KMD', 'GLEEC']);
        },
      );
    }

    test('no valued asset is unavailable, not a zero total', () async {
      profitLoss.failAll(['BTCZ', 'KMD'], unpriced);
      expect(
        await load(),
        const PortfolioAssetsOverviewUnavailable(
          reason: AssetOverviewUnavailableReason.noAssetValued,
        ),
      );
    });

    test('a failed refresh keeps the totals already shown', () async {
      final shown = await load();
      expect(shown, isA<PortfolioAssetsOverviewLoadSuccess>());

      profitLoss.failAll(['BTCZ', 'KMD'], Exception('provider outage'));
      expect(await load(), same(shown));
    });

    test(
      'an unreadable wallet identity is its own unavailable state',
      () async {
        profitLoss.failAll([
          'BTCZ',
          'KMD',
          'GLEEC',
        ], const AuthIdentityUnavailableException());
        expect(
          await load(),
          const PortfolioAssetsOverviewUnavailable(
            reason: AssetOverviewUnavailableReason.walletIdentity,
          ),
        );
      },
    );

    test('totals survive the identity becoming unreadable', () async {
      final shown = await load();
      profitLoss.results['KMD'] = const AuthIdentityUnavailableException();
      expect(await load(), same(shown));
    });

    test('an ended session takes its totals off the screen', () async {
      expect(await load(), isA<PortfolioAssetsOverviewLoadSuccess>());
      profitLoss.results['KMD'] = const AuthSessionChangedException();
      expect(await load(), isA<AssetOverviewInitial>());
    });

    test('a wallet without active assets resolves to unavailable', () async {
      final idle = AssetOverviewBloc(
        profitLoss,
        InvestmentRepository(profitLossRepository: profitLoss),
        PortfolioSdk(const {}),
      );
      addTearDown(idle.close);
      idle.add(
        PortfolioAssetsOverviewLoadRequested(
          coins: coins,
          walletId: 'wallet-a',
        ),
      );
      await waitFor(() => idle.state is PortfolioAssetsOverviewUnavailable);
      expect(
        idle.state,
        const PortfolioAssetsOverviewUnavailable(
          reason: AssetOverviewUnavailableReason.noActiveAssets,
        ),
      );
      expect(profitLoss.lookups, 0);
    });
  });

  group('InvestmentRepository', () {
    final coin = setCoin(coinAbbr: 'BTCZ');
    late SlowProfitLoss profitLoss;
    late InvestmentRepository repository;

    setUp(() {
      profitLoss = SlowProfitLoss();
      repository = InvestmentRepository(profitLossRepository: profitLoss);
    });

    test(
      'a changed wallet session cannot become zero total investment',
      () async {
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
      final pending = repository.calculateTotalInvestment('wallet-a', [coin]);
      profitLoss.reject();
      final investment = await pending;
      expect(investment.profitLoss.unavailable, [coin.id]);
      expect(investment.profitLoss.valued, isEmpty);
      expect(investment.profitLoss.isUnavailable, isTrue);
    });
  });

  group('ProfitLossBloc lifecycle and unavailable history', () {
    final coin = setCoin(coinAbbr: 'BTCZ');
    late SlowProfitLoss profitLoss;
    late ProfitLossBloc bloc;

    setUp(() {
      profitLoss = SlowProfitLoss();
      bloc = ProfitLossBloc(
        profitLoss,
        PortfolioSdk({coin.id}),
        backoffStrategy: FastBackoff(),
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
        await waitFor(() => profitLoss.lookups > 0);
        bloc.add(const ProfitLossPortfolioChartClearRequested());
        await Future<void>.delayed(Duration.zero);
        profitLoss.release();
        await Future<void>.delayed(tick * 3);
        expect(bloc.state, isA<ProfitLossInitial>());
        expect(profitLoss.lookups, 1);
      },
    );

    test('missing acquisition history becomes a failure rather than an empty chart', () async {
      bloc.add(load());
      await waitFor(() => profitLoss.lookups > 0);
      profitLoss.reject();
      await waitFor(() => bloc.state is ProfitLossLoadFailure);
      expect(
        bloc.state,
        const ProfitLossLoadFailure(
          reason: ProfitLossUnavailableReason.noAssetValued,
          selectedPeriod: Duration(hours: 1),
        ),
      );
    });

    test(
      'changing period after unavailable history keeps the request retryable',
      () async {
        bloc.add(load());
        await waitFor(() => profitLoss.lookups > 0);
        profitLoss.reject();
        await waitFor(() => bloc.state is ProfitLossLoadFailure);
        final lookups = profitLoss.lookups;
        bloc.add(
          const ProfitLossPortfolioPeriodChanged(
            selectedPeriod: Duration(days: 1),
          ),
        );
        await Future<void>.delayed(tick * 3);
        expect(bloc.state, isA<ProfitLossLoadFailure>());
        expect(bloc.state.selectedPeriod, const Duration(days: 1));
        expect(profitLoss.lookups, greaterThan(lookups));
      },
    );
  });

  _profitLossChartPolicyTests();
}

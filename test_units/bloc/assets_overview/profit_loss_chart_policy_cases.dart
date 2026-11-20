part of 'asset_overview_bloc_test.dart';

void _profitLossChartPolicyTests() {
  group('ProfitLossBloc when an asset cannot be valued', () {
    final btcz = setCoin(coinAbbr: 'BTCZ');
    final gleec = setCoin(coinAbbr: 'GLEEC');
    final unpriced = ProfitLossPriceUnavailable('GLEEC', DateTime.utc(2020));
    late ScriptedProfitLoss profitLoss;
    late ProfitLossBloc bloc;

    setUp(() {
      profitLoss = ScriptedProfitLoss()
        ..results['BTCZ'] = [
          purchase('BTCZ', bought: 1, price: 10, profit: 2),
          purchase(
            'BTCZ',
            bought: 1,
            price: 12,
            profit: 5,
            at: DateTime.utc(2025, 11, 9),
          ),
        ]
        ..results['GLEEC'] = unpriced;
      bloc = ProfitLossBloc(
        profitLoss,
        PortfolioSdk({btcz.id, gleec.id}),
        backoffStrategy: FastBackoff(),
      );
    });
    tearDown(() => bloc.close());

    ProfitLossPortfolioChartLoadRequested request(List<Coin> coins) =>
        ProfitLossPortfolioChartLoadRequested(
          coins: coins,
          fiatCoinId: 'USDT',
          selectedPeriod: const Duration(hours: 1),
          walletId: 'wallet-a',
        );

    /// The state once the cached, the refreshed and a few periodic loads ran.
    Future<ProfitLossState> settled() async {
      await Future<void>.delayed(tick * 4);
      return bloc.state;
    }

    test(
      'the chart covers the valued assets and names the excluded one',
      () async {
        bloc.add(request([btcz, gleec]));
        final state = await settled() as PortfolioProfitLossChartLoadSuccess;
        expect(state.excludedAssetIds, ['GLEEC']);
        expect(state.profitLossChart, hasLength(2));
        expect(state.totalValue, 3);
        expect(state.isUpdating, isFalse);
      },
    );

    test(
      'no valued asset is a failure with its reason, not an empty chart',
      () async {
        profitLoss.results['BTCZ'] = unpriced;
        bloc.add(request([btcz, gleec]));
        expect(
          await settled(),
          const ProfitLossLoadFailure(
            reason: ProfitLossUnavailableReason.noAssetValued,
            selectedPeriod: Duration(hours: 1),
          ),
        );
      },
    );

    test('a failed refresh keeps the chart already shown', () async {
      bloc.add(request([btcz, gleec]));
      final shown = await settled();
      expect(shown, isA<PortfolioProfitLossChartLoadSuccess>());

      final lookups = profitLoss.lookups;
      profitLoss.results['BTCZ'] = Exception('provider outage');
      expect(await settled(), shown);
      expect(profitLoss.lookups, greaterThan(lookups));
    });

    test(
      'an unreadable wallet identity ends loading with its own reason',
      () async {
        profitLoss.failAll([
          'BTCZ',
          'GLEEC',
        ], const AuthIdentityUnavailableException());
        bloc.add(request([btcz, gleec]));
        expect(
          await settled(),
          const ProfitLossLoadFailure(
            reason: ProfitLossUnavailableReason.walletIdentity,
            selectedPeriod: Duration(hours: 1),
          ),
        );
      },
    );

    test('an ended session leaves neither a chart nor a failure', () async {
      profitLoss.failAll([
        'BTCZ',
        'GLEEC',
      ], const AuthSessionChangedException());
      bloc.add(request([btcz, gleec]));
      expect(await settled(), isA<ProfitLossInitial>());
    });

    test(
      'a failed period change stops marking the chart as updating',
      () async {
        bloc.add(request([btcz, gleec]));
        final shown = await settled() as PortfolioProfitLossChartLoadSuccess;

        profitLoss.results['BTCZ'] = Exception('provider outage');
        bloc.add(
          const ProfitLossPortfolioPeriodChanged(
            selectedPeriod: Duration(days: 1),
          ),
        );
        expect(
          await settled(),
          shown.copyWith(selectedPeriod: const Duration(days: 1)),
        );
      },
    );

    test('a failure for another selection replaces the chart', () async {
      bloc.add(request([btcz, gleec]));
      expect(await settled(), isA<PortfolioProfitLossChartLoadSuccess>());

      bloc.add(request([gleec]));
      expect(
        await settled(),
        const ProfitLossLoadFailure(
          reason: ProfitLossUnavailableReason.noAssetValued,
          selectedPeriod: Duration(hours: 1),
        ),
      );
    });

    test(
      'no active asset ends loading instead of drawing an empty chart',
      () async {
        final idle = ProfitLossBloc(
          profitLoss,
          PortfolioSdk(const {}),
          backoffStrategy: FastBackoff(),
        );
        addTearDown(idle.close);
        idle.add(request([btcz, gleec]));
        await waitFor(() => idle.state is ProfitLossLoadFailure);
        expect(
          idle.state,
          const ProfitLossLoadFailure(
            reason: ProfitLossUnavailableReason.noActiveAssets,
            selectedPeriod: Duration(hours: 1),
          ),
        );
        expect(profitLoss.lookups, 0);
      },
    );
  });
}

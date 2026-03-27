import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/blocs/kmd_rewards_bloc.dart';
import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:web_dex/mm2/mm2_api/rpc/bloc_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/kmd_rewards_info/kmd_reward_item.dart';
import 'package:web_dex/views/wallet/coin_details/rewards/kmd_rewards_info.dart';

import 'coin_details_test_harness.dart';

class _FakeCoinsRepo implements CoinsRepo {
  _FakeCoinsRepo();

  @override
  double? getUsdPriceForAmount(num amount, String coinAbbr) => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeKmdRewardsBloc implements KmdRewardsBloc {
  _FakeKmdRewardsBloc({required this.totalFuture, required this.infoFuture});

  final Future<double?> totalFuture;
  final Future<List<KmdRewardItem>> infoFuture;

  @override
  Future<double?> getTotal(BuildContext context) => totalFuture;

  @override
  Future<List<KmdRewardItem>> getInfo() => infoFuture;

  @override
  Future<BlocResponse<String, BaseError>> claim(BuildContext context) async =>
      BlocResponse(result: '0');

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthBloc extends Cubit<AuthBlocState> implements AuthBloc {
  _FakeAuthBloc() : super(AuthBlocState.initial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _buildWidget({
  required KmdRewardsBloc rewardsBloc,
  required CoinsRepo coinsRepo,
}) {
  final coin = buildTestCoin(abbr: 'KMD');
  coin.address = 'R-address';

  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(size: Size(1600, 1200)),
      child: Builder(
        builder: (context) {
          updateScreenType(context);
          return MultiRepositoryProvider(
            providers: [
              RepositoryProvider<CoinsRepo>.value(value: coinsRepo),
              RepositoryProvider<KmdRewardsBloc>.value(value: rewardsBloc),
            ],
            child: BlocProvider<AuthBloc>(
              create: (_) => _FakeAuthBloc(),
              child: Scaffold(
                body: KmdRewardsInfo(
                  coin: coin,
                  onSuccess: (_, __) {},
                  onBackButtonPressed: () {},
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

void testRewardsWidgets() {
  group('KmdRewardsInfo widget', () {
    testWidgets('rewards page shows spinner before data load', (tester) async {
      final totalCompleter = Completer<double?>();
      final infoCompleter = Completer<List<KmdRewardItem>>();
      final rewardsBloc = _FakeKmdRewardsBloc(
        totalFuture: totalCompleter.future,
        infoFuture: infoCompleter.future,
      );

      await tester.pumpWidget(
        _buildWidget(rewardsBloc: rewardsBloc, coinsRepo: _FakeCoinsRepo()),
      );

      expect(find.byType(UiSpinnerList), findsOneWidget);
    });

    testWidgets('rewards page shows no rewards when empty', (tester) async {
      final rewardsBloc = _FakeKmdRewardsBloc(
        totalFuture: Future<double?>.value(0),
        infoFuture: Future<List<KmdRewardItem>>.value(const []),
      );

      await tester.pumpWidget(
        _buildWidget(rewardsBloc: rewardsBloc, coinsRepo: _FakeCoinsRepo()),
      );
      await tester.pumpAndSettle();

      expect(find.text('noRewards'), findsOneWidget);
    });

    testWidgets('rewards page renders reward items when present', (
      tester,
    ) async {
      final rewardsBloc = _FakeKmdRewardsBloc(
        totalFuture: Future<double?>.value(1.2),
        infoFuture: Future<List<KmdRewardItem>>.value([
          KmdRewardItem(
            txHash: 'hash-1',
            height: 1,
            outputIndex: 0,
            amount: '10',
            lockTime: 1,
            reward: 0.1,
            accrueStartAt: 1,
            accrueStopAt: 2,
          ),
        ]),
      );

      await tester.pumpWidget(
        _buildWidget(rewardsBloc: rewardsBloc, coinsRepo: _FakeCoinsRepo()),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reward-claim-button')), findsOneWidget);
    });
  });
}

void main() {
  testRewardsWidgets();
}

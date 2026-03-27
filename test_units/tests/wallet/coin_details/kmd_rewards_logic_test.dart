// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/blocs/kmd_rewards_bloc.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:web_dex/mm2/mm2_api/rpc/bloc_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/kmd_rewards_info/kmd_reward_item.dart';
import 'package:web_dex/mm2/mm2_api/rpc/kmd_rewards_info/kmd_rewards_info_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/send_raw_transaction/send_raw_transaction_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/send_raw_transaction/send_raw_transaction_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/withdraw/withdraw_request.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/model/withdraw_details/fee_details.dart';
import 'package:web_dex/model/withdraw_details/withdraw_details.dart';

import 'coin_details_test_harness.dart';

class _FakeCoinsRepo implements CoinsRepo {
  _FakeCoinsRepo({this.coin, this.withdrawResult});

  final Coin? coin;
  final BlocResponse<WithdrawDetails, BaseError>? withdrawResult;

  @override
  Coin? getCoin(String _) => coin;

  @override
  Future<BlocResponse<WithdrawDetails, BaseError>> withdraw(
    WithdrawRequest _,
  ) async {
    return withdrawResult ??
        BlocResponse(error: TextError(error: 'withdraw not configured'));
  }

  @override
  double? getUsdPriceForAmount(num amount, String coinAbbr) => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMm2Api implements Mm2Api {
  _FakeMm2Api({this.rewards, this.sendResponse});

  final List<KmdRewardItem>? rewards;
  final SendRawTransactionResponse? sendResponse;

  @override
  Future<Map<String, dynamic>?> getRewardsInfo(KmdRewardsInfoRequest _) async {
    if (rewards == null) {
      return null;
    }

    return <String, dynamic>{
      'result': rewards!
          .map(
            (r) => <String, dynamic>{
              'tx_hash': r.txHash,
              'height': r.height,
              'output_index': r.outputIndex,
              'amount': r.amount,
              'locktime': r.lockTime,
              'accrued_rewards': r.reward == null
                  ? <String, dynamic>{'NotAccruedReason': 'OneHourNotPassedYet'}
                  : <String, dynamic>{'Accrued': '${r.reward!}'},
              'accrue_start_at': r.accrueStartAt,
              'accrue_stop_at': r.accrueStopAt,
            },
          )
          .toList(),
    };
  }

  @override
  Future<SendRawTransactionResponse> sendRawTransaction(
    SendRawTransactionRequest _,
  ) async {
    return sendResponse ??
        SendRawTransactionResponse(
          txHash: null,
          error: TextError(error: 'broadcast failed'),
        );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

WithdrawDetails _withdrawDetails({
  String txHex = 'signed-hex',
  String myBalanceChange = '1.5',
}) {
  return WithdrawDetails(
    txHex: txHex,
    txHash: 'tx-hash',
    from: const ['from'],
    to: const ['to'],
    totalAmount: '1.5',
    spentByMe: '0',
    receivedByMe: '1.5',
    myBalanceChange: myBalanceChange,
    blockHeight: 1,
    timestamp: 1,
    feeDetails: FeeDetails.empty(),
    coin: 'KMD',
    internalId: 'internal-1',
  );
}

void testKmdRewardsLogic() {
  group('KmdRewardsBloc', () {
    testWidgets('claim returns error when no KMD coin is active', (
      tester,
    ) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) {
              context = ctx;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final bloc = KmdRewardsBloc(_FakeCoinsRepo(coin: null), _FakeMm2Api());

      final response = await bloc.claim(context);

      expect(response.error, isNotNull);
      expect(response.result, isNull);
    });

    testWidgets('claim returns error when withdraw fails', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) {
              context = ctx;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final coin = buildTestCoin(abbr: 'KMD');
      coin.address = 'R-address';

      final bloc = KmdRewardsBloc(
        _FakeCoinsRepo(
          coin: coin,
          withdrawResult: BlocResponse(
            error: TextError(error: 'withdraw failed'),
          ),
        ),
        _FakeMm2Api(),
      );

      final response = await bloc.claim(context);

      expect(response.error, isNotNull);
      expect(response.result, isNull);
    });

    testWidgets('claim returns error when txHex is missing', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) {
              context = ctx;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final coin = buildTestCoin(abbr: 'KMD');
      coin.address = 'R-address';

      final bloc = KmdRewardsBloc(
        _FakeCoinsRepo(
          coin: coin,
          withdrawResult: BlocResponse(result: _withdrawDetails(txHex: '')),
        ),
        _FakeMm2Api(),
      );

      final response = await bloc.claim(context);

      expect(response.error, isNotNull);
      expect(response.result, isNull);
    });

    testWidgets('claim succeeds when withdraw and broadcast succeed', (
      tester,
    ) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) {
              context = ctx;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final coin = buildTestCoin(abbr: 'KMD');
      coin.address = 'R-address';

      final bloc = KmdRewardsBloc(
        _FakeCoinsRepo(
          coin: coin,
          withdrawResult: BlocResponse(result: _withdrawDetails()),
        ),
        _FakeMm2Api(sendResponse: SendRawTransactionResponse(txHash: 'hash-1')),
      );

      final response = await bloc.claim(context);

      expect(response.error, isNull);
      expect(response.result, '1.5');
    });

    test('getInfo returns empty list when API returns no result', () async {
      final bloc = KmdRewardsBloc(_FakeCoinsRepo(), _FakeMm2Api(rewards: null));

      final info = await bloc.getInfo();

      expect(info, isEmpty);
    });

    testWidgets('getTotal returns parsed total from withdraw response', (
      tester,
    ) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) {
              context = ctx;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final coin = buildTestCoin(abbr: 'KMD');
      coin.address = 'R-address';

      final bloc = KmdRewardsBloc(
        _FakeCoinsRepo(
          coin: coin,
          withdrawResult: BlocResponse(
            result: _withdrawDetails(myBalanceChange: '2.25'),
          ),
        ),
        _FakeMm2Api(),
      );

      final total = await bloc.getTotal(context);

      expect(total, 2.25);
    });
  });
}

void main() {
  testKmdRewardsLogic();
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/blocs/bloc_base.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:web_dex/mm2/mm2_api/rpc/bloc_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/kmd_rewards_info/kmd_reward_item.dart';
import 'package:web_dex/mm2/mm2_api/rpc/kmd_rewards_info/kmd_rewards_info_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/send_raw_transaction/send_raw_transaction_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/withdraw/withdraw_request.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/model/withdraw_details/withdraw_details.dart';
import 'package:web_dex/services/wallet_access/wallet_operation_gate.dart';

class KmdRewardsBloc implements BlocBase {
  KmdRewardsBloc(this._coinsBlocRepository, this._mm2Api);

  final CoinsRepo _coinsBlocRepository;
  final Mm2Api _mm2Api;
  bool _claimInProgress = false;

  Future<BlocResponse<String, BaseError>> claim(BuildContext context) async {
    final WalletOperationPermit permit;
    try {
      permit = WalletOperationGate.instance.capture();
    } on WalletOperationDenied {
      return BlocResponse(
        error: TextError(error: LocaleKeys.somethingWrong.tr()),
      );
    }
    if (_claimInProgress) {
      return BlocResponse(
        error: TextError(error: LocaleKeys.rewardClaiming.tr()),
      );
    }

    _claimInProgress = true;
    final withdraw = await _withdraw();
    final WithdrawDetails? withdrawDetails = withdraw.result;

    if (withdrawDetails == null || withdraw.error != null) {
      final BaseError error =
          withdraw.error ?? TextError(error: LocaleKeys.somethingWrong.tr());
      _claimInProgress = false;
      return BlocResponse(error: error);
    }

    if (withdrawDetails.txHex == null) {
      _claimInProgress = false;
      return BlocResponse(
        error: TextError(error: LocaleKeys.somethingWrong.tr()),
      );
    }

    try {
      permit.ensureCurrent();
    } on WalletOperationDenied {
      _claimInProgress = false;
      return BlocResponse(
        error: TextError(error: LocaleKeys.somethingWrong.tr()),
      );
    }
    final tx = await _mm2Api.sendRawTransaction(
      SendRawTransactionRequest(coin: 'KMD', txHex: withdrawDetails.txHex),
    );
    if (tx.error != null) {
      final BaseError error =
          tx.error ?? TextError(error: LocaleKeys.somethingWrong.tr());
      _claimInProgress = false;
      return BlocResponse(error: error);
    }
    _claimInProgress = false;
    return BlocResponse(result: withdrawDetails.myBalanceChange);
  }

  @override
  void dispose() {}

  Future<List<KmdRewardItem>> getInfo() async {
    final Map<String, dynamic>? response = await _mm2Api.getRewardsInfo(
      KmdRewardsInfoRequest(),
    );
    if (response != null && response['result'] != null) {
      return response['result']
          .map<KmdRewardItem>(
            (dynamic reward) => KmdRewardItem.fromJson(reward),
          )
          .toList();
    }
    return [];
  }

  Future<double?> getTotal(BuildContext context) async {
    final withdraw = await _withdraw();
    final String? myBalanceChange = withdraw.result?.myBalanceChange;
    if (myBalanceChange == null || withdraw.error != null) {
      return null;
    }

    return double.tryParse(myBalanceChange);
  }

  Future<BlocResponse<WithdrawDetails, BaseError>> _withdraw() async {
    final Coin? kmdCoin = _coinsBlocRepository.getCoin('KMD');
    if (kmdCoin == null) {
      return BlocResponse(
        error: TextError(error: LocaleKeys.plsActivateKmd.tr()),
      );
    }
    if (kmdCoin.address == null) {
      return BlocResponse(
        error: TextError(error: LocaleKeys.noKmdAddress.tr()),
      );
    }

    return await _coinsBlocRepository.withdraw(
      WithdrawRequest(coin: 'KMD', max: true, to: kmdCoin.address!),
    );
  }
}

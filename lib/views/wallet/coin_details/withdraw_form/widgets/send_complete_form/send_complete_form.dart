import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/withdraw_form/withdraw_form_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/views/wallet/coin_details/constants.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/widgets/send_confirm_form/send_confirm_item.dart';

class SendCompleteForm extends StatelessWidget {
  const SendCompleteForm({super.key});

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      color: theme.custom.buttonColorDefault,
    );

    return BlocBuilder<WithdrawFormBloc, WithdrawFormState>(
      builder: (context, WithdrawFormState state) {
        final feeValue = state.result?.fee;

        if (state.result == null) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: isMobile ? double.infinity : withdrawWidth,
              padding: const EdgeInsets.all(26),
              decoration: decoration,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SendConfirmItem(
                    title: LocaleKeys.recipientAddress.tr(),
                    value: state.result!.toAddress,
                    centerAlign: true,
                  ),
                  const SizedBox(height: 7),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 10),
                      SelectableText(
                        '-${state.amount} ${Coin.normalizeAbbr(state.asset.id.id)}',
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w700,
                          color: theme.custom.headerFloatBoxColor,
                        ),
                      ),
                      if (state.usdAmountPrice != null) ...[
                        const SizedBox(height: 5),
                        SelectableText(
                          '\$${state.usdAmountPrice}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: theme.custom.headerFloatBoxColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (state.hasTransactionError)
                    _SendCompleteError(error: state.transactionError!),
                ],
              ),
            ),
            if (state.result?.txHash != null)
              _TransactionHash(
                feeValue: feeValue!.totalFee.toString(),
                feeCoin: feeValue.coin,
                txHash: state.result!.txHash,
                usdFeePrice: state.usdFeePrice,
                isFeePriceExpensive: state.isFeePriceExpensive,
              ),
          ],
        );
      },
    );
  }
}

class _SendCompleteError extends StatelessWidget {
  const _SendCompleteError({required this.error});

  final BaseError error;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 10),
      width: double.infinity,
      child: Text(
        error.message,
        textAlign: TextAlign.left,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

class _TransactionHash extends StatelessWidget {
  const _TransactionHash({
    required this.feeValue,
    required this.txHash,
    required this.feeCoin,
    required this.usdFeePrice,
    required this.isFeePriceExpensive,
  });
  final String txHash;
  final String feeValue;
  final String feeCoin;
  final double? usdFeePrice;
  final bool isFeePriceExpensive;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: isMobile ? double.infinity : withdrawWidth,
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          SendConfirmItem(
            title: '${LocaleKeys.fee.tr()}:',
            value:
                '${truncateDecimal(feeValue, decimalRange)} ${Coin.normalizeAbbr(feeCoin)}',
            usdPrice: usdFeePrice,
            isWarningShown: isFeePriceExpensive,
          ),
          const SizedBox(height: 21),
          const _BuildMemo(),
          SendConfirmItem(
            title: '${LocaleKeys.transactionHash.tr()}:',
            value: txHash,
            isCopied: true,
            isCopiedValueTruncated: true,
          ),
        ],
      ),
    );
  }
}

class _BuildMemo extends StatelessWidget {
  const _BuildMemo({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocSelector<WithdrawFormBloc, WithdrawFormState, String?>(
      selector: (state) {
        return state.memo;
      },
      builder: (context, memo) {
        if (memo == null || memo.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: 21),
          child: SendConfirmItem(
            title: '${LocaleKeys.memo.tr()}:',
            value: memo,
          ),
        );
      },
    );
  }
}

import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui/utils.dart';
import 'package:web_dex/bloc/withdraw_form/withdraw_form_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/views/wallet/coin_details/constants.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/widgets/send_confirm_form/send_confirm_form_error.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/widgets/send_confirm_form/send_confirm_item.dart';

class SendConfirmForm extends StatelessWidget {
  const SendConfirmForm({super.key});

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      color: theme.custom.buttonColorDefault,
    );

    return BlocBuilder<WithdrawFormBloc, WithdrawFormState>(
      builder: (context, WithdrawFormState state) {
        final amountString =
            '${truncateDecimal(state.amount, decimalRange)} ${Coin.normalizeAbbr(state.result!.coin)}';

        // Use the new formatting extension for fees
        final feeString = state.preview?.fee.formatTotal(
          precision: decimalRange,
        );

        // Use the isExpensive helper for warnings
        final isFeePriceExpensive = state.preview?.fee.isHighFee ?? false;

        return Container(
          width: isMobile ? double.infinity : withdrawWidth,
          padding: const EdgeInsets.all(26),
          decoration: decoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SendConfirmItem(
                title: '${LocaleKeys.recipientAddress.tr()}:',
                value: state.result!.toAddress,
                centerAlign: false,
              ),
              const SizedBox(height: 26),
              SendConfirmItem(
                title: '${LocaleKeys.amount.tr()}:',
                value: amountString,
                usdPrice: state.usdAmountPrice,
              ),
              const SizedBox(height: 26),
              SendConfirmItem(
                title: '${LocaleKeys.fee.tr()}:',
                value: feeString ?? '',
                usdPrice: state.usdFeePrice,
                isWarningShown: isFeePriceExpensive,
              ),
              if (state.memo != null)
                Padding(
                  padding: const EdgeInsets.only(top: 26),
                  child: SendConfirmItem(
                    title: '${LocaleKeys.memo.tr()}:',
                    value: state.memo!,
                    isWarningShown: false,
                  ),
                ),
              const SendConfirmFormError(),
            ],
          ),
        );
      },
    );
  }
}

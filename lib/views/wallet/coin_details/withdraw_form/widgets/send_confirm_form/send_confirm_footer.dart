import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/withdraw_form/withdraw_form_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/views/wallet/coin_details/constants.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/widgets/send_confirm_form/send_confirm_buttons.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

class SendConfirmFooter extends StatelessWidget {
  const SendConfirmFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WithdrawFormBloc, WithdrawFormState>(
      builder: (context, WithdrawFormState state) {
        return SizedBox(
          width: isMobile ? double.infinity : withdrawWidth,
          child: state.isSending
              ? const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Center(child: UiSpinner()),
                )
              : SendConfirmButtons(
                  hasSendError: state.hasTransactionError,
                  onBackTap: () => context.read<WithdrawFormBloc>().add(
                    const WithdrawFormStepReverted(),
                  ),
                ),
        );
      },
    );
  }
}

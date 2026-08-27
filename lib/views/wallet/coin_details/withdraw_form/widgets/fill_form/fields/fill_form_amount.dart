import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/withdraw_form/withdraw_form_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/ui/custom_numeric_text_form_field.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/widgets/fill_form/buttons/sell_max_button.dart';

class FillFormAmount extends StatefulWidget {
  const FillFormAmount({super.key});

  @override
  State<FillFormAmount> createState() => _FillFormAmountState();
}

class _FillFormAmountState extends State<FillFormAmount> {
  final TextEditingController _amountController = TextEditingController();
  TextSelection _previousTextSelection = const TextSelection.collapsed(
    offset: 0,
  );
  @override
  void initState() {
    _amountController.text = context.read<WithdrawFormBloc>().state.amount;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<WithdrawFormBloc, WithdrawFormState>(
      listenWhen: (prev, cur) => prev.amount != cur.amount,
      listener: (context, state) {
        _amountController
          ..text = state.amount
          ..selection = _previousTextSelection;
      },
      buildWhen: (prev, cur) => prev.amountError != cur.amountError,
      builder: (context, state) {
        return CustomNumericTextFormField(
          key: const Key('enter-form-amount-input'),
          controller: _amountController,
          filteringRegExp: numberRegExp.pattern,
          hintText: LocaleKeys.amountToSend.tr(),
          hintTextStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          suffixIcon: const SellMaxButton(),
          onChanged: (String? amount) {
            setState(() {
              _previousTextSelection = _amountController.selection;
            });
            context.read<WithdrawFormBloc>().add(
              WithdrawFormAmountChanged(amount ?? ''),
            );
          },
          validationMode: InputValidationMode.aggressive,
          validator: (_) => state.amountError?.message,
        );
      },
    );
  }
}

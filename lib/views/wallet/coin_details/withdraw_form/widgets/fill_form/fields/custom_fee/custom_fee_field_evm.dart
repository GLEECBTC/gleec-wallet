import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/withdraw_form/withdraw_form_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/ui/custom_numeric_text_form_field.dart';

class CustomFeeFieldEVM extends StatefulWidget {
  const CustomFeeFieldEVM({super.key});

  @override
  State<CustomFeeFieldEVM> createState() => _CustomFeeFieldEVMState();
}

class _CustomFeeFieldEVMState extends State<CustomFeeFieldEVM> {
  final TextEditingController _gasLimitController = TextEditingController();
  final TextEditingController _gasPriceController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: _buildGasLimitField(),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: _buildGasPriceField(),
        ),
      ],
    );
  }

  Widget _buildGasLimitField() {
    return CustomNumericTextFormField(
      controller: _gasLimitController,
      validationMode: InputValidationMode.aggressive,
      validator: (_) {
        const error = null; //TODO!.SDK
        if (error.isEmpty) return null;
        return error;
      },
      onChanged: (_) {
        _change();
      },
      filteringRegExp: r'^(|[1-9]\d*)$',
      style: _style,
      hintText: LocaleKeys.gasLimit.tr(),
      hintTextStyle: _hintTextStyle,
    );
  }

  Widget _buildGasPriceField() {
    return BlocConsumer<WithdrawFormBloc, WithdrawFormState>(
      listenWhen: (previous, current) =>
          // TODO!.SDK: Add custom fee error property error to state and add here
          previous.customFee != current.customFee,
      listener: (context, state) {
        //
      },
      builder: (context, error) {
        return BlocSelector<
          WithdrawFormBloc,
          WithdrawFormState,
          FeeInfoEthGas?
        >(
          selector: (state) {
            if (state.customFee is! FeeInfoEthGas) return null;
            return (state.customFee as FeeInfoEthGas);
          },
          builder: (context, fee) {
            // final price = fee?.gasPrice.toString() ?? '';

            // _gasPriceController
            //   ..text = price
            //   ..selection = _gasPriceSelection;
            return CustomNumericTextFormField(
              controller: _gasPriceController,
              validationMode: InputValidationMode.aggressive,
              validator: (_) {
                const error = null; //TODO!.SDK
                if (error.isEmpty) return null;
                return error;
              },
              onChanged: (_) {
                _change();
              },
              filteringRegExp: numberRegExp.pattern,
              style: _style,
              hintText: LocaleKeys.gasPriceGwei.tr(),
              hintTextStyle: _hintTextStyle,
            );
          },
        );
      },
    );
  }

  void _change() {
    final asset = context.read<WithdrawFormBloc>().state.asset;

    context.read<WithdrawFormBloc>().add(
      WithdrawFormCustomFeeChanged(
        FeeInfo.ethGas(
          coin: asset.id.id,
          gas: double.tryParse(_gasLimitController.text)?.toInt() ?? 0,
          gasPrice: Decimal.tryParse(_gasPriceController.text) ?? Decimal.zero,
        ),
      ),
    );
  }
}

const _style = TextStyle(fontSize: 12, fontWeight: FontWeight.w400);
const _hintTextStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w500);

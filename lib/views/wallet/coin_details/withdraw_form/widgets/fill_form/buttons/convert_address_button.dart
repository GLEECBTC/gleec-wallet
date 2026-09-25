import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/withdraw_form/withdraw_form_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

class ConvertAddressButton extends StatelessWidget {
  const ConvertAddressButton({super.key});

  @override
  Widget build(BuildContext context) {
    return UiPrimaryButton(
      text: LocaleKeys.convert.tr(),
      width: 80,
      height: 30,
      textStyle: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 12,
        color: theme.custom.defaultGradientButtonTextColor,
      ),
      onPressed: () => context.read<WithdrawFormBloc>().add(
        const WithdrawFormConvertAddressRequested(),
      ),
    );
  }
}

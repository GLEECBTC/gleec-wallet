import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/withdraw_form/withdraw_form_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

class SellMaxButton extends StatefulWidget {
  const SellMaxButton({super.key});

  @override
  State<StatefulWidget> createState() => _SellMaxButtonState();
}

class _SellMaxButtonState extends State<SellMaxButton> {
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WithdrawFormBloc, WithdrawFormState>(
      builder: (context, state) {
        final fontWeight = _hasFocus ? FontWeight.w900 : FontWeight.w500;
        final color = state.isMaxAmount
            ? Theme.of(context).colorScheme.primary
            : null;
        return InkWell(
          onFocusChange: (value) => setState(() {
            _hasFocus = value;
          }),
          onTap: () => context.read<WithdrawFormBloc>().add(
            WithdrawFormMaxAmountEnabled(!state.isMaxAmount),
          ),
          borderRadius: BorderRadius.circular(7),
          child: Container(
            width: 46,
            height: 23,
            margin: const EdgeInsets.only(top: 10, bottom: 10, right: 10),
            padding: const EdgeInsets.only(left: 10, top: 2, right: 10),
            child: Text(
              LocaleKeys.max.tr().toLowerCase(),
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                fontSize: 12,
                fontWeight: fontWeight,
                color: color,
              ),
            ),
          ),
        );
      },
    );
  }
}

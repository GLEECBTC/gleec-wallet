import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/withdraw_form/withdraw_form_bloc.dart';
import 'package:web_dex/common/app_assets.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/custom_fee/custom_fee_field_evm.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/custom_fee/custom_fee_field_utxo.dart';

class FillFormCustomFee extends StatefulWidget {
  const FillFormCustomFee({super.key});

  @override
  State<FillFormCustomFee> createState() => _FillFormCustomFeeState();
}

class _FillFormCustomFeeState extends State<FillFormCustomFee> {
  bool _isOpen = false;

  @override
  void initState() {
    _isOpen = context.read<WithdrawFormBloc>().state.isCustomFee;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      radius: 18,
      onTap: () {
        final bool newOpenState = !_isOpen;
        context.read<WithdrawFormBloc>().add(
          WithdrawFormCustomFeeEnabled(_isOpen),
        );
        setState(() {
          _isOpen = newOpenState;
        });
      },
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          color: Colors.transparent,
        ),
        child: _isOpen ? _Expanded() : _Collapsed(),
      ),
    );
  }
}

class _Collapsed extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          height: 25,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(18)),
            border: Border.all(color: theme.custom.specificButtonBorderColor),
          ),
          child: const Padding(
            padding: EdgeInsets.only(left: 13, right: 13),
            child: _Header(DexSvgImage(path: Assets.chevronDown)),
          ),
        ),
      ],
    );
  }
}

class _Expanded extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(18)),
            border: Border.all(color: theme.custom.specificButtonBorderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: 13, right: 13),
            child: Column(
              children: [
                const _Header(DexSvgImage(path: Assets.chevronDown)),
                const SizedBox(height: 4),
                const _Line(),
                const SizedBox(height: 12),
                const _Warning(),
                const SizedBox(height: 9),
                _FeeAmount(),
                const SizedBox(height: 15),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.chevron);

  final Widget chevron;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            LocaleKeys.customFeeOptional.tr(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).inputDecorationTheme.labelStyle?.color,
            ),
          ),
        ),
        Padding(padding: const EdgeInsets.only(top: 9), child: chevron),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 1,
      color: const Color.fromARGB(0, 255, 0, 0),
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning();

  @override
  Widget build(BuildContext context) {
    return Text(
      LocaleKeys.customFeesWarning.tr(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: Theme.of(context).inputDecorationTheme.labelStyle?.color,
      ),
    );
  }
}

class _FeeAmount extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WithdrawFormBloc, WithdrawFormState>(
      builder: (ctx, state) {
        // TODO! Handle both fixed and perkb
        final isUtxo = state.customFee is FeeInfoUtxoFixed;

        return isUtxo ? const CustomFeeFieldUtxo() : const CustomFeeFieldEVM();
      },
    );
  }
}

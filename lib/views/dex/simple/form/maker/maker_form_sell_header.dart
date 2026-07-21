import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/blocs/maker_form_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/available_balance_state.dart';
import 'package:web_dex/views/dex/simple/form/common/dex_form_group_header.dart';
import 'package:web_dex/views/dex/simple/form/common/dex_small_button.dart';
import 'package:web_dex/views/dex/simple/form/taker/available_balance.dart';

class MakerFormSellHeader extends StatelessWidget {
  const MakerFormSellHeader({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return DexFormGroupHeader(
      title: LocaleKeys.sell.tr(),
      actions: const [
        _AvailableBalance(),
        SizedBox(width: 8),
        _HalfMaxButtons(),
      ],
    );
  }
}

class _AvailableBalance extends StatelessWidget {
  const _AvailableBalance({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final makerFormBloc = RepositoryProvider.of<MakerFormBloc>(context);
    return StreamBuilder<Rational?>(
      initialData: makerFormBloc.maxSellAmount,
      stream: makerFormBloc.outMaxSellAmount,
      builder: (context, snapshot) {
        return StreamBuilder<AvailableBalanceState?>(
          initialData: makerFormBloc.availableBalanceState,
          stream: makerFormBloc.outAvailableBalanceState,
          builder: (context, state) {
            return AvailableBalance(
              snapshot.data,
              state.data ?? AvailableBalanceState.initial,
            );
          },
        );
      },
    );
  }
}

class _HalfMaxButtons extends StatelessWidget {
  const _HalfMaxButtons({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final makerFormBloc = RepositoryProvider.of<MakerFormBloc>(context);
    return StreamBuilder<Rational?>(
      initialData: makerFormBloc.maxSellAmount,
      stream: makerFormBloc.outMaxSellAmount,
      builder: (context, snapshot) {
        return Row(
          children: [_MaxButton(), const SizedBox(width: 3), _HalfButton()],
        );
      },
    );
  }
}

class _MaxButton extends DexSmallButton {
  _MaxButton()
    : super(
        LocaleKeys.max.tr(),
        (context) =>
            RepositoryProvider.of<MakerFormBloc>(context).setMaxSellAmount(),
      );
}

class _HalfButton extends DexSmallButton {
  _HalfButton()
    : super(
        LocaleKeys.half.tr(),
        (context) =>
            RepositoryProvider.of<MakerFormBloc>(context).setHalfSellAmount(),
      );
}

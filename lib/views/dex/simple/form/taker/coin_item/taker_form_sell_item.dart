import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/taker_form/taker_bloc.dart';
import 'package:web_dex/bloc/taker_form/taker_event.dart';
import 'package:web_dex/bloc/taker_form/taker_state.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/views/dex/common/front_plate.dart';
import 'package:web_dex/views/dex/simple/form/common/dex_form_group_header.dart';
import 'package:web_dex/views/dex/simple/form/common/dex_small_button.dart';
import 'package:web_dex/views/dex/simple/form/taker/available_balance.dart';
import 'package:web_dex/views/dex/simple/form/taker/coin_item/taker_form_sell_switcher.dart';
import 'package:web_dex/views/dex/simple/form/taker/coin_item/trade_controller.dart';

class TakerFormSellItem extends StatelessWidget {
  const TakerFormSellItem({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocSelector<TakerBloc, TakerState, Coin?>(
      selector: (state) => state.sellCoin,
      builder: (context, sellCoin) {
        return FrontPlate(
          child: Column(
            children: [
              _SellHeader(),
              TakerFormSellSwitcher(
                controller: TradeCoinController(
                  coin: sellCoin,
                  onTap: () =>
                      context.read<TakerBloc>().add(TakerCoinSelectorClick()),
                  isEnabled: sellCoin != null,
                  isOpened: false,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SellHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DexFormGroupHeader(
      title: LocaleKeys.sell.tr(),
      actions: [
        _AvailableGroup(),
        const SizedBox(width: 8),
        _ExactButton(),
        const SizedBox(width: 3),
        _MaxButton(),
        const SizedBox(width: 3),
        _HalfButton(),
      ],
    );
  }
}

class _AvailableGroup extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TakerBloc, TakerState>(
      builder: (context, state) {
        return AvailableBalance(
          state.maxSellAmount,
          state.availableBalanceState,
        );
      },
    );
  }
}

class _HalfButton extends DexSmallButton {
  _HalfButton()
    : super(LocaleKeys.half.tr(), (context) {
        context.read<TakerBloc>().add(TakerAmountButtonClick(0.5));
      });
}

class _MaxButton extends DexSmallButton {
  _MaxButton()
    : super(LocaleKeys.max.tr(), (context) {
        context.read<TakerBloc>().add(TakerAmountButtonClick(1));
      });
}

class _ExactButton extends DexSmallButton {
  _ExactButton()
    : super(LocaleKeys.exact.tr(), (context) {
        final state = context.read<TakerBloc>().state;
        final order = state.selectedOrder;
        if (order == null) return;
        context.read<TakerBloc>().add(TakerSetSellAmount(order.maxVolume));
      });
}

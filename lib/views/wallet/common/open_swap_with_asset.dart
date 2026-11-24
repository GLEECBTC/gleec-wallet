import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/taker_form/taker_bloc.dart';
import 'package:web_dex/bloc/taker_form/taker_event.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/shared/swap/swap_services.dart';

/// Opens Swap paying with [coin]. Advanced's taker form is seeded too, so
/// switching to it keeps the choice.
void openSwapWithAsset(BuildContext context, Coin coin) {
  context.read<SwapServices>().requestIntent((
    pay: coin.abbr,
    receive: null,
    amount: null,
    fiat: false,
  ));
  context.read<TakerBloc>().add(TakerSetSellCoin(coin));
  routingState.selectedMenu = MainMenuValue.dex;
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/blocs/maker_form_bloc.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/views/dex/simple/form/maker/maker_form_sell_switcher.dart';
import 'package:web_dex/views/dex/simple/form/tables/coins_table/coins_table.dart';
import 'package:web_dex/views/dex/simple/form/taker/coin_item/trade_controller.dart';

class MakerFormSellCoinTable extends StatelessWidget {
  const MakerFormSellCoinTable({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final makerFormBloc = RepositoryProvider.of<MakerFormBloc>(context);
    return StreamBuilder<bool>(
      initialData: makerFormBloc.showSellCoinSelect,
      stream: makerFormBloc.outShowSellCoinSelect,
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.all(16),
          child: StreamBuilder<Coin?>(
            initialData: makerFormBloc.sellCoin,
            stream: makerFormBloc.outSellCoin,
            builder: (context, coinSnapshot) {
              final Coin? coin = coinSnapshot.data;

              return CoinsTable(
                key: const Key('maker-sell-coins-table'),
                head: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 16, 0, 12),
                  child: MakerFormSellSwitcher(
                    controller: TradeCoinController(
                      coin: coin,
                      onTap: () => makerFormBloc.showSellCoinSelect = false,
                      isOpened: true,
                      isEnabled: coin != null,
                    ),
                  ),
                ),
                maxHeight: 330,
                onSelect: (Coin coin) {
                  makerFormBloc.sellCoin = coin;
                  makerFormBloc.showSellCoinSelect = false;
                },
              );
            },
          ),
        );
      },
    );
  }
}

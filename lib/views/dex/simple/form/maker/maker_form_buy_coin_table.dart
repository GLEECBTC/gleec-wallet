import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/blocs/maker_form_bloc.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/views/dex/simple/form/maker/maker_form_buy_switcher.dart';
import 'package:web_dex/views/dex/simple/form/tables/coins_table/coins_table.dart';
import 'package:web_dex/views/dex/simple/form/taker/coin_item/trade_controller.dart';

class MakerFormBuyCoinTable extends StatelessWidget {
  const MakerFormBuyCoinTable({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final makerFormBloc = RepositoryProvider.of<MakerFormBloc>(context);
    return StreamBuilder<bool>(
      initialData: makerFormBloc.showBuyCoinSelect,
      stream: makerFormBloc.outShowBuyCoinSelect,
      builder: (context, isOpenSnapshot) {
        if (isOpenSnapshot.data != true) return const SizedBox.shrink();

        return StreamBuilder<Coin?>(
          initialData: makerFormBloc.buyCoin,
          stream: makerFormBloc.outBuyCoin,
          builder: (context, coinSnapshot) {
            final Coin? coin = coinSnapshot.data;

            return Padding(
              padding: const EdgeInsets.all(16),
              child: CoinsTable(
                key: const Key('maker-buy-coins-table'),
                head: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 16, 0, 12),
                  child: MakerFormBuySwitcher(
                    controller: TradeCoinController(
                      coin: coin,
                      isEnabled: coin != null,
                      isOpened: true,
                      onTap: () => makerFormBloc.showBuyCoinSelect = false,
                    ),
                  ),
                ),
                maxHeight: 250,
                onSelect: (Coin coin) {
                  makerFormBloc.buyCoin = coin;
                  makerFormBloc.showBuyCoinSelect = false;
                },
              ),
            );
          },
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/taker_form/taker_bloc.dart';
import 'package:web_dex/bloc/taker_form/taker_event.dart';
import 'package:web_dex/bloc/taker_form/taker_state.dart';
import 'package:web_dex/mm2/mm2_api/rpc/best_orders/best_orders.dart';
import 'package:web_dex/views/dex/common/front_plate.dart';
import 'package:web_dex/views/dex/simple/form/tables/orders_table/orders_table_content.dart';
import 'package:web_dex/views/dex/simple/form/tables/table_search_field.dart';
import 'package:web_dex/views/dex/simple/form/taker/coin_item/taker_form_buy_switcher.dart';
import 'package:web_dex/views/dex/simple/form/taker/coin_item/trade_controller.dart';

class OrdersTable extends StatefulWidget {
  const OrdersTable({Key? key}) : super(key: key);

  @override
  State<OrdersTable> createState() => _OrdersTableState();
}

class _OrdersTableState extends State<OrdersTable> {
  String? _searchTerm;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<TakerBloc, TakerState, BestOrder?>(
      selector: (state) => state.selectedOrder,
      builder: (context, selectedOrder) {
        final coinsRepository = RepositoryProvider.of<CoinsRepo>(context);
        final coin = coinsRepository.getCoin(selectedOrder?.coin ?? '');
        final controller = TradeOrderController(
          order: selectedOrder,
          coin: coin,
          onTap: () => context.read<TakerBloc>().add(TakerOrderSelectorClick()),
          isEnabled: false,
          isOpened: true,
        );

        return FocusTraversalGroup(
          child: FrontPlate(
            shadowEnabled: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TakerFormBuySwitcher(
                  controller,
                  padding: const EdgeInsets.only(top: 16, bottom: 12),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TableSearchField(
                    height: 48,
                    onChanged: (String value) {
                      if (_searchTerm == value) return;
                      setState(() => _searchTerm = value);
                    },
                  ),
                ),
                const SizedBox(height: 5),
                OrdersTableContent(
                  onSelect: (BestOrder order) =>
                      context.read<TakerBloc>().add(TakerSelectOrder(order)),
                  searchString: _searchTerm,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/blocs/trading_entities_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/my_orders/my_order.dart';
import 'package:web_dex/model/trading_entities_filter.dart';
import 'package:web_dex/shared/utils/sorting.dart';
import 'package:web_dex/views/dex/dex_helpers.dart';
import 'package:web_dex/views/dex/common/dex_confirmation_dialog.dart';
import 'package:web_dex/views/dex/common/dex_responsive.dart';
import 'package:web_dex/views/dex/entities_list/common/dex_empty_list.dart';
import 'package:web_dex/views/dex/entities_list/common/dex_error_message.dart';
import 'package:web_dex/views/dex/entities_list/orders/order_cancel_button.dart';
import 'package:web_dex/views/dex/entities_list/orders/order_item.dart';
import 'package:web_dex/views/dex/entities_list/orders/order_list_header.dart';

class OrdersList extends StatefulWidget {
  const OrdersList({Key? key, required this.entitiesFilterData})
    : super(key: key);
  final TradingEntitiesFilter? entitiesFilterData;

  @override
  State<OrdersList> createState() => _OrdersListState();
}

class _OrdersListState extends State<OrdersList> {
  final _mainScrollController = ScrollController();

  SortData<OrderListSortType> _sortData = const SortData<OrderListSortType>(
    sortDirection: SortDirection.increase,
    sortType: OrderListSortType.send,
  );

  @override
  Widget build(BuildContext context) {
    final tradingEntitiesBloc = RepositoryProvider.of<TradingEntitiesBloc>(
      context,
    );
    return StreamBuilder<List<MyOrder>>(
      initialData: tradingEntitiesBloc.myOrders,
      stream: tradingEntitiesBloc.outMyOrders,
      builder: (context, ordersSnapshot) {
        final List<MyOrder> orders = ordersSnapshot.data ?? [];

        if (ordersSnapshot.hasError) {
          return const DexErrorMessage();
        }

        final TradingEntitiesFilter? entitiesFilterData =
            widget.entitiesFilterData;

        final filtered = entitiesFilterData != null
            ? applyFiltersForOrders(orders, entitiesFilterData)
            : orders;

        if (!ordersSnapshot.hasData || filtered.isEmpty) {
          return const DexEmptyList();
        }
        final List<MyOrder> sortedOrders = _sortOrders(filtered);

        return LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = DexResponsiveSpec.fromWidth(
              constraints.maxWidth,
            ).usesMobileLists;
            return Column(
              mainAxisSize: MainAxisSize.max,
              children: [
                if (!isCompact)
                  Column(
                    children: [
                      const Align(
                        alignment: Alignment.bottomRight,
                        child: SizedBox(height: 8),
                      ),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: UiPrimaryButton(
                          text: LocaleKeys.cancelAll.tr(),
                          height: 48,
                          width: 140,
                          onPressed: _confirmCancelAll,
                        ),
                      ),
                      OrderListHeader(
                        sortData: _sortData,
                        onSortChange: _onSortChange,
                      ),
                    ],
                  ),
                Flexible(
                  child: Padding(
                    padding: EdgeInsets.only(top: isCompact ? 0 : 10.0),
                    child: DexScrollbar(
                      isMobile: isCompact,
                      scrollController: _mainScrollController,
                      child: ListView.builder(
                        shrinkWrap: true,
                        controller: _mainScrollController,
                        itemBuilder: (BuildContext context, int index) {
                          final MyOrder order = sortedOrders[index];
                          final bool isCancelable = order.cancelable;

                          return OrderItem(
                            order,
                            actions: !isCancelable
                                ? []
                                : [OrderCancelButton(order: order)],
                          );
                        },
                        itemCount: sortedOrders.length,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _onSortChange(SortData<OrderListSortType> sortData) {
    setState(() {
      _sortData = sortData;
    });
  }

  Future<void> _confirmCancelAll() async {
    final confirmed = await showDexActionConfirmation(
      context: context,
      actionLabel: LocaleKeys.cancelAll.tr(),
      confirmButtonKey: const Key('dex-cancel-all-confirm'),
    );
    if (!confirmed || !mounted) return;
    await RepositoryProvider.of<TradingEntitiesBloc>(context).cancelAllOrders();
  }

  List<MyOrder> _sortOrders(List<MyOrder> orders) {
    switch (_sortData.sortType) {
      case OrderListSortType.send:
        return _sortByAmount(orders, true);
      case OrderListSortType.receive:
        return _sortByAmount(orders, false);
      case OrderListSortType.price:
        return _sortByPrice(orders);
      case OrderListSortType.date:
        return _sortByDate(orders);
      case OrderListSortType.orderType:
        return _sortByType(orders);
      case OrderListSortType.none:
        return orders;
    }
  }

  List<MyOrder> _sortByAmount(List<MyOrder> orders, bool isSend) {
    if (isSend) {
      orders.sort(
        (first, second) => sortByDouble(
          first.baseAmount.toDouble(),
          second.baseAmount.toDouble(),
          _sortData.sortDirection,
        ),
      );
    } else {
      orders.sort(
        (first, second) => sortByDouble(
          first.relAmount.toDouble(),
          second.relAmount.toDouble(),
          _sortData.sortDirection,
        ),
      );
    }
    return orders;
  }

  List<MyOrder> _sortByPrice(List<MyOrder> orders) {
    final tradingEntitiesBloc = RepositoryProvider.of<TradingEntitiesBloc>(
      context,
    );
    orders.sort(
      (first, second) => sortByDouble(
        tradingEntitiesBloc.getPriceFromAmount(
          first.baseAmount,
          first.relAmount,
        ),
        tradingEntitiesBloc.getPriceFromAmount(
          second.baseAmount,
          second.relAmount,
        ),
        _sortData.sortDirection,
      ),
    );
    return orders;
  }

  List<MyOrder> _sortByDate(List<MyOrder> orders) {
    orders.sort(
      (first, second) => sortByDouble(
        first.createdAt.toDouble(),
        second.createdAt.toDouble(),
        _sortData.sortDirection,
      ),
    );
    return orders;
  }

  List<MyOrder> _sortByType(List<MyOrder> orders) {
    orders.sort(
      (first, second) => sortByOrderType(
        first.orderType,
        second.orderType,
        _sortData.sortDirection,
      ),
    );
    return orders;
  }
}

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
  const OrdersList({super.key, required this.entitiesFilterData});
  final TradingEntitiesFilter? entitiesFilterData;

  @override
  State<OrdersList> createState() => _OrdersListState();
}

class _OrdersListState extends State<OrdersList> {
  final _mainScrollController = ScrollController();
  bool _isCancellingAll = false;
  String? _cancelAllResult;

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
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildOrdersStaleStatus(tradingEntitiesBloc),
              const DexEmptyList(),
            ],
          );
        }
        // TradingEntitiesBloc deliberately publishes an immutable snapshot.
        // Sorting must never mutate that shared snapshot (or a filter result
        // that may alias it), otherwise the unfiltered Orders view throws an
        // UnsupportedError while building.
        final List<MyOrder> sortedOrders = _sortOrders(
          List<MyOrder>.of(filtered),
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = DexResponsiveSpec.fromWidth(
              constraints.maxWidth,
            ).usesMobileLists;
            return Column(
              mainAxisSize: MainAxisSize.max,
              children: [
                _buildOrdersStaleStatus(tradingEntitiesBloc),
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
                          prefix: _isCancellingAll
                              ? const UiSpinner(width: 14, height: 14)
                              : null,
                          onPressed: _isCancellingAll
                              ? null
                              : () => _confirmCancelAll(tradingEntitiesBloc),
                        ),
                      ),
                      if (_cancelAllResult case final result?)
                        Semantics(
                          liveRegion: true,
                          child: Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Text(result),
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

  Widget _buildOrdersStaleStatus(TradingEntitiesBloc tradingEntitiesBloc) {
    return StreamBuilder<bool>(
      initialData: tradingEntitiesBloc.ordersAreStale,
      stream: tradingEntitiesBloc.outOrdersAreStale,
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();
        final colors = Theme.of(context).colorScheme;
        return Semantics(
          container: true,
          liveRegion: true,
          child: Container(
            key: const Key('advanced-orders-stale-notice'),
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.sync_problem_rounded,
                  color: colors.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'advancedOrdersStale'.tr(),
                    style: TextStyle(color: colors.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _onSortChange(SortData<OrderListSortType> sortData) {
    setState(() {
      _sortData = sortData;
    });
  }

  Future<void> _confirmCancelAll(
    TradingEntitiesBloc tradingEntitiesBloc,
  ) async {
    if (_isCancellingAll) return;
    final targetIds = tradingEntitiesBloc.cancellableOrderIds;
    if (targetIds.isEmpty) return;
    final confirmed = await showDexActionConfirmation(
      context: context,
      actionLabel: LocaleKeys.cancelAll.tr(),
      targetDescription: 'advancedAllOpenOrdersTarget'.tr(
        namedArgs: {'count': '${targetIds.length}'},
      ),
      confirmButtonKey: const Key('dex-cancel-all-confirm'),
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _isCancellingAll = true;
      _cancelAllResult = null;
    });
    try {
      final result = await tradingEntitiesBloc.cancelExactOrders(targetIds);
      if (mounted) {
        setState(() => _cancelAllResult = _cancelAllResultMessage(result));
      }
    } on Object {
      if (mounted) {
        setState(() {
          _cancelAllResult = 'advancedCancellationRequestFailed'.tr();
        });
      }
    } finally {
      if (mounted) setState(() => _isCancellingAll = false);
    }
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

String _cancelAllResultMessage(CancelAllOrdersResult result) {
  if (result.walletChanged) {
    return 'advancedCancellationWalletChanged'.tr();
  }
  if (result.uncertain) {
    return 'advancedCancellationUncertain'.tr();
  }
  if (result.isComplete) {
    return 'advancedCancellationComplete'.tr(
      namedArgs: {
        'cancelled': '${result.cancelledCount}',
        'attempted': '${result.attemptedCount}',
      },
    );
  }
  if (result.isPartial) {
    return 'advancedCancellationPartial'.tr(
      namedArgs: {
        'cancelled': '${result.cancelledCount}',
        'failed': '${result.failedCount}',
      },
    );
  }
  if (result.attemptedCount == 0) return 'advancedNoOpenOrders'.tr();
  return 'advancedCancellationTotalFailed'.tr(
    namedArgs: {
      'failed': '${result.failedCount}',
      'attempted': '${result.attemptedCount}',
    },
  );
}

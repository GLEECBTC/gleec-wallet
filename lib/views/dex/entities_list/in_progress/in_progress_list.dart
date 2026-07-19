import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/blocs/trading_entities_bloc.dart';
import 'package:web_dex/model/swap.dart';
import 'package:web_dex/model/trading_entities_filter.dart';
import 'package:web_dex/shared/utils/sorting.dart';
import 'package:web_dex/views/dex/dex_helpers.dart';
import 'package:web_dex/views/dex/common/dex_responsive.dart';
import 'package:web_dex/views/dex/entities_list/common/dex_empty_list.dart';
import 'package:web_dex/views/dex/entities_list/common/dex_error_message.dart';
import 'package:web_dex/views/dex/entities_list/in_progress/in_progress_item.dart';
import 'package:web_dex/views/dex/entities_list/in_progress/in_progress_list_header.dart';

class InProgressList extends StatefulWidget {
  const InProgressList({
    Key? key,
    required this.onItemClick,
    this.entitiesFilterData,
    this.filter,
  }) : super(key: key);

  final bool Function(Swap)? filter;
  final Function(Swap) onItemClick;

  final TradingEntitiesFilter? entitiesFilterData;
  @override
  State<InProgressList> createState() => _InProgressListState();
}

class _InProgressListState extends State<InProgressList> {
  final _mainScrollController = ScrollController();
  SortData<InProgressListSortType> _sortData =
      const SortData<InProgressListSortType>(
        sortDirection: SortDirection.none,
        sortType: InProgressListSortType.none,
      );

  @override
  Widget build(BuildContext context) {
    final tradingEntitiesBloc = RepositoryProvider.of<TradingEntitiesBloc>(
      context,
    );
    return StreamBuilder<List<Swap>>(
      initialData: tradingEntitiesBloc.swaps,
      stream: tradingEntitiesBloc.outSwaps,
      builder: (context, swapsSnapshot) {
        final List<Swap> swaps = (swapsSnapshot.data ?? [])
            .where((swap) => !swap.isCompleted)
            .toList();

        if (swapsSnapshot.hasError) {
          return const DexErrorMessage();
        }

        if (widget.filter != null) {
          swaps.retainWhere(widget.filter!);
        }

        final TradingEntitiesFilter? entitiesFilterData =
            widget.entitiesFilterData;

        final filtered = entitiesFilterData != null
            ? applyFiltersForSwap(swaps, entitiesFilterData)
            : swaps;

        if (!swapsSnapshot.hasData || filtered.isEmpty) {
          return const DexEmptyList();
        }

        final List<Swap> sortedSwaps = _sortSwaps(filtered);

        return LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = DexResponsiveSpec.fromWidth(
              constraints.maxWidth,
            ).usesMobileLists;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isCompact)
                  InProgressListHeader(
                    sortData: _sortData,
                    onSortChange: _onSortChange,
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
                          final Swap swap = sortedSwaps[index];

                          return InProgressItem(
                            swap,
                            onClick: () {
                              widget.onItemClick(swap);
                            },
                          );
                        },
                        itemCount: sortedSwaps.length,
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

  void _onSortChange(SortData<InProgressListSortType> sortData) {
    setState(() {
      _sortData = sortData;
    });
  }

  List<Swap> _sortSwaps(List<Swap> swaps) {
    switch (_sortData.sortType) {
      case InProgressListSortType.send:
        return _sortByAmount(swaps, true);
      case InProgressListSortType.receive:
        return _sortByAmount(swaps, false);
      case InProgressListSortType.price:
        return _sortByPrice(swaps);
      case InProgressListSortType.date:
        return _sortByDate(swaps);
      case InProgressListSortType.orderType:
        return _sortByType(swaps);
      case InProgressListSortType.status:
        return _sortByStatus(swaps);
      case InProgressListSortType.none:
        return swaps;
    }
  }

  List<Swap> _sortByStatus(List<Swap> swaps) {
    swaps.sort(
      (first, second) => sortByDouble(
        first.statusStep.toDouble(),
        second.statusStep.toDouble(),
        _sortData.sortDirection,
      ),
    );
    return swaps;
  }

  List<Swap> _sortByAmount(List<Swap> swaps, bool isSend) {
    if (isSend) {
      swaps.sort(
        (first, second) => sortByDouble(
          first.sellAmount.toDouble(),
          second.sellAmount.toDouble(),
          _sortData.sortDirection,
        ),
      );
    } else {
      swaps.sort(
        (first, second) => sortByDouble(
          first.buyAmount.toDouble(),
          second.buyAmount.toDouble(),
          _sortData.sortDirection,
        ),
      );
    }
    return swaps;
  }

  List<Swap> _sortByPrice(List<Swap> swaps) {
    final tradingEntitiesBloc = RepositoryProvider.of<TradingEntitiesBloc>(
      context,
    );
    swaps.sort(
      (first, second) => sortByDouble(
        tradingEntitiesBloc.getPriceFromAmount(
          first.sellAmount,
          first.buyAmount,
        ),
        tradingEntitiesBloc.getPriceFromAmount(
          second.sellAmount,
          second.buyAmount,
        ),
        _sortData.sortDirection,
      ),
    );
    return swaps;
  }

  List<Swap> _sortByDate(List<Swap> swaps) {
    swaps.sort(
      (first, second) => sortByDouble(
        first.myInfo?.startedAt.toDouble() ?? 0,
        second.myInfo?.startedAt.toDouble() ?? 0,
        _sortData.sortDirection,
      ),
    );
    return swaps;
  }

  List<Swap> _sortByType(List<Swap> swaps) {
    swaps.sort(
      (first, second) =>
          sortByBool(first.isTaker, second.isTaker, _sortData.sortDirection),
    );
    return swaps;
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/blocs/trading_entities_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/model/swap.dart';
import 'package:web_dex/model/trading_entities_filter.dart';
import 'package:web_dex/views/dex/dex_helpers.dart';
import 'package:web_dex/views/dex/entities_list/common/dex_empty_list.dart';
import 'package:web_dex/views/dex/entities_list/common/dex_error_message.dart';
import 'package:web_dex/views/dex/entities_list/history/history_item.dart';
import 'package:web_dex/views/dex/entities_list/history/history_list_header.dart';

import 'swap_history_sort_mixin.dart';

class HistoryList extends StatefulWidget {
  const HistoryList({
    Key? key,
    this.filter,
    required this.onItemClick,
    this.entitiesFilterData,
    this.onFilterChange,
  }) : super(key: key);

  final bool Function(Swap)? filter;
  final Function(Swap) onItemClick;
  final TradingEntitiesFilter? entitiesFilterData;
  final VoidCallback? onFilterChange;

  @override
  State<HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends State<HistoryList>
    with SwapHistorySortingMixin {
  final _mainScrollController = ScrollController();

  SortData<HistoryListSortType> _sortData = const SortData<HistoryListSortType>(
    sortDirection: SortDirection.none,
    sortType: HistoryListSortType.none,
  );

  StreamSubscription<List<Swap>>? _swapsSubscription;
  List<Swap> _processedSwaps = [];

  List<Swap> _unprocessedSwaps = [];

  String? error;
  bool _hasReceivedData = false;
  @override
  void initState() {
    super.initState();

    _swapsSubscription = listenForSwaps();
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return const DexErrorMessage();
    }

    if (!_hasReceivedData) {
      return const Center(child: UiSpinner(width: 26, height: 26));
    }

    if (_processedSwaps.isEmpty) {
      return const DexEmptyList();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isMobile)
          HistoryListHeader(sortData: _sortData, onSortChange: _onSortChange),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: isMobile ? 0 : 10.0),
            child: DexScrollbar(
              isMobile: isMobile,
              scrollController: _mainScrollController,
              child: ListView.builder(
                key: const Key('swap-history-list-list-view'),
                shrinkWrap: false,
                controller: _mainScrollController,
                itemBuilder: (BuildContext context, int index) {
                  final Swap swap = _processedSwaps[index];

                  return HistoryItem(
                    key: Key('swap-item-${swap.uuid}'),
                    swap,
                    onClick: () => widget.onItemClick(swap),
                  );
                },
                itemCount: _processedSwaps.length,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _onSortChange(SortData<HistoryListSortType> sortData) {
    setState(() {
      _sortData = sortData;
    });
    _processSwapFilters(_unprocessedSwaps);
  }

  StreamSubscription<List<Swap>> listenForSwaps() {
    final tradingEntitiesBloc = RepositoryProvider.of<TradingEntitiesBloc>(
      context,
    );
    return tradingEntitiesBloc.outSwaps
        .where((swaps) {
          final didSwapsChange =
              !_hasReceivedData || !areSwapsSame(swaps, _unprocessedSwaps);

          _unprocessedSwaps = swaps;

          return didSwapsChange;
        })
        .listen(
          _processSwapFilters,
          onError: (e) {
            setState(() => error = e.toString());
          },
          cancelOnError: false,
        );
  }

  void _processSwapFilters(List<Swap> swaps) {
    Iterable<Swap> completedSwaps = swaps.where((swap) => swap.isCompleted);

    if (widget.filter != null) {
      completedSwaps = completedSwaps.where(widget.filter!);
    }

    final entitiesFilterData = widget.entitiesFilterData;

    final filteredSwaps = entitiesFilterData != null
        ? applyFiltersForSwap(completedSwaps.toList(), entitiesFilterData)
        : completedSwaps.toList();

    setState(() {
      error = null;
      _hasReceivedData = true;
      _processedSwaps = sortSwaps(context, filteredSwaps, sortData: _sortData);
    });
  }

  @override
  void didUpdateWidget(covariant HistoryList oldWidget) {
    super.didUpdateWidget(oldWidget);

    final didFiltersChange =
        oldWidget.filter != widget.filter ||
        oldWidget.entitiesFilterData != widget.entitiesFilterData;

    if (didFiltersChange) {
      _processSwapFilters(_unprocessedSwaps);
    }
  }

  @override
  void dispose() {
    _swapsSubscription?.cancel();
    super.dispose();
  }
}

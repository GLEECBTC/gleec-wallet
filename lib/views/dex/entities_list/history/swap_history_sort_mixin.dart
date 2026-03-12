import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/blocs/trading_entities_bloc.dart';
import 'package:web_dex/model/swap.dart';
import 'package:web_dex/shared/utils/sorting.dart';
import 'package:web_dex/views/dex/entities_list/history/history_list_header.dart';

mixin SwapHistorySortingMixin {
  bool areSwapsSame(List<Swap> newSwaps, List<Swap> oldSwaps) {
    if (newSwaps.length != oldSwaps.length) {
      return false;
    }

    return newSwaps.every((newSwap) => oldSwaps.contains(newSwap));
  }

  List<Swap> sortSwaps(
    BuildContext context,
    List<Swap> swaps, {
    required SortData<HistoryListSortType> sortData,
  }) {
    final direction = sortData.sortDirection;

    switch (sortData.sortType) {
      case HistoryListSortType.send:
        return _sortByAmount(swaps, true, direction);
      case HistoryListSortType.receive:
        return _sortByAmount(swaps, false, direction);
      case HistoryListSortType.price:
        return _sortByPrice(context, swaps, sortDirection: direction);
      case HistoryListSortType.date:
        return _sortByDate(swaps, sortDirection: direction);
      case HistoryListSortType.orderType:
        return _sortByType(swaps, sortDirection: direction);
      case HistoryListSortType.status:
        return _sortByStatus(swaps, sortData.sortDirection);
      case HistoryListSortType.none:
        return swaps;
    }
  }

  List<Swap> _sortByStatus(List<Swap> swaps, SortDirection sortDirection) {
    if (sortDirection == SortDirection.none) {
      return swaps;
    }

    int statusRank(Swap swap) => swap.isFailed ? 1 : 0;

    swaps.sort((first, second) {
      final firstRank = statusRank(first);
      final secondRank = statusRank(second);

      if (sortDirection == SortDirection.increase) {
        return firstRank.compareTo(secondRank);
      }

      return secondRank.compareTo(firstRank);
    });
    return swaps;
  }

  List<Swap> _sortByAmount(
    List<Swap> swaps,
    bool isSend,
    SortDirection sortDirection,
  ) {
    if (isSend) {
      swaps.sort(
        (first, second) => sortByDouble(
          first.sellAmount.toDouble(),
          second.sellAmount.toDouble(),
          sortDirection,
        ),
      );
    } else {
      swaps.sort(
        (first, second) => sortByDouble(
          first.buyAmount.toDouble(),
          second.buyAmount.toDouble(),
          sortDirection,
        ),
      );
    }
    return swaps;
  }

  List<Swap> _sortByPrice(
    BuildContext context,
    List<Swap> swaps, {
    required SortDirection sortDirection,
  }) {
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
        sortDirection,
      ),
    );
    return swaps;
  }

  List<Swap> _sortByDate(
    List<Swap> swaps, {
    required SortDirection sortDirection,
  }) {
    swaps.sort(
      (first, second) => sortByDouble(
        first.myInfo?.startedAt.toDouble() ?? 0,
        second.myInfo?.startedAt.toDouble() ?? 0,
        sortDirection,
      ),
    );
    return swaps;
  }

  List<Swap> _sortByType(
    List<Swap> swaps, {
    required SortDirection sortDirection,
  }) {
    swaps.sort(
      (first, second) =>
          sortByBool(first.isTaker, second.isTaker, sortDirection),
    );
    return swaps;
  }
}

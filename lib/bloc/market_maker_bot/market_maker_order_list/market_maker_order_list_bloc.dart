import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_order_list/market_maker_bot_order_list_repository.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_order_list/trade_pair.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_bot/market_maker_bot_wallet_session.dart';
import 'package:web_dex/model/my_orders/my_order.dart';
import 'package:web_dex/mm2/mm2_api/rpc/market_maker_bot/trade_coin_pair_config.dart';
import 'package:web_dex/model/trading_entities_filter.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/market_maker_bot/market_maker_bot_order_list_header.dart';

part 'market_maker_order_list_event.dart';
part 'market_maker_order_list_state.dart';

class MarketMakerOrderListBloc
    extends Bloc<MarketMakerOrderListEvent, MarketMakerOrderListState> {
  MarketMakerOrderListBloc(
    MarketMakerBotOrderListRepository orderListRepository, {
    required MarketMakerBotWalletSession? Function() captureWalletSession,
    required MarketMakerBotOrderOwnership? Function(
      MarketMakerBotWalletSession walletSession,
    )
    captureOrderOwnership,
    required Future<bool> Function(MarketMakerBotWalletSession walletSession)
    isFreshWalletSession,
  }) : _orderListRepository = orderListRepository,
       _captureWalletSession = captureWalletSession,
       _captureOrderOwnership = captureOrderOwnership,
       _isFreshWalletSession = isFreshWalletSession,
       super(MarketMakerOrderListState.initial()) {
    on<MarketMakerOrderListRequested>(
      _onOrderListRequested,
      transformer: restartable(),
    );
    on<MarketMakerOrderListSortChanged>(_onOrderListSortChanged);
    on<MarketMakerOrderListFilterChanged>(_onOrderListFilterChanged);
  }

  final MarketMakerBotOrderListRepository _orderListRepository;
  final MarketMakerBotWalletSession? Function() _captureWalletSession;
  final MarketMakerBotOrderOwnership? Function(MarketMakerBotWalletSession)
  _captureOrderOwnership;
  final Future<bool> Function(MarketMakerBotWalletSession)
  _isFreshWalletSession;

  Future<void> _onOrderListRequested(
    MarketMakerOrderListRequested event,
    Emitter<MarketMakerOrderListState> emit,
  ) async {
    if (event.updateInterval < const Duration(seconds: 1) ||
        event.updateInterval > const Duration(minutes: 5)) {
      emit(
        state.copyWith(
          allMakerBotOrders: const [],
          makerBotOrders: const [],
          status: MarketMakerOrderListStatus.failure,
          walletSession: _captureWalletSession,
          orderCorrelation: () => null,
          configurationSnapshot: const [],
        ),
      );
      return;
    }
    final currentSession = _captureWalletSession();
    emit(
      state.copyWith(
        allMakerBotOrders: currentSession == state.walletSession
            ? null
            : const [],
        makerBotOrders: currentSession == state.walletSession ? null : const [],
        status: currentSession == null
            ? MarketMakerOrderListStatus.initial
            : MarketMakerOrderListStatus.loading,
        walletSession: () => currentSession,
        orderCorrelation: currentSession == state.walletSession
            ? null
            : () => null,
        configurationSnapshot: currentSession == state.walletSession
            ? null
            : const [],
      ),
    );

    try {
      final initialSnapshot = await _loadScopedOrders();
      if (initialSnapshot != null && !emit.isDone) {
        emit(_stateForSnapshot(initialSnapshot));
      }
    } catch (_, s) {
      log(
        'Failed to load market maker orders',
        trace: s,
        isError: true,
        path: 'MarketMakerOrderListBloc',
      );
      if (!emit.isDone) emit(_failureState());
    }

    return emit.forEach(
      Stream.periodic(
        event.updateInterval,
      ).asyncMap((_) => _loadScopedOrders()),
      onData: (snapshot) =>
          snapshot == null ? state : _stateForSnapshot(snapshot),
      onError: (_, __) => _failureState(),
    );
  }

  MarketMakerOrderListState _failureState() => state.copyWith(
    allMakerBotOrders: const [],
    makerBotOrders: const [],
    status: MarketMakerOrderListStatus.failure,
    walletSession: _captureWalletSession,
    orderCorrelation: () => null,
    configurationSnapshot: const [],
  );

  void _onOrderListSortChanged(
    MarketMakerOrderListSortChanged event,
    Emitter<MarketMakerOrderListState> emit,
  ) {
    final sortData = event.sortData;
    final allOrders = _sortedOrders(state.allMakerBotOrders, sortData);
    final visibleOrders = _visibleOrders(allOrders, state.filterData);

    emit(
      state.copyWith(
        allMakerBotOrders: allOrders,
        makerBotOrders: visibleOrders,
        sortData: sortData,
      ),
    );
  }

  void _onOrderListFilterChanged(
    MarketMakerOrderListFilterChanged event,
    Emitter<MarketMakerOrderListState> emit,
  ) {
    final filterData = event.filterData;
    final visibleOrders = _visibleOrders(state.allMakerBotOrders, filterData);

    emit(
      state.copyWith(
        makerBotOrders: visibleOrders,
        filterData: () => filterData,
      ),
    );
  }

  Future<_MarketMakerOrderSnapshot?> _loadScopedOrders() async {
    final walletSession = _captureWalletSession();
    if (walletSession == null) {
      return const _MarketMakerOrderSnapshot(
        walletSession: null,
        orderCorrelation: null,
        configurations: [],
        orders: [],
      );
    }

    final ownership = _captureOrderOwnership(walletSession);
    if (!await _isFreshWalletSession(walletSession)) return null;
    final repositorySnapshot = await _orderListRepository.getTradePairSnapshot(
      ownership: ownership,
    );
    if (_captureWalletSession() != walletSession ||
        !await _isFreshWalletSession(walletSession) ||
        !identical(_captureOrderOwnership(walletSession), ownership)) {
      return null;
    }
    return _MarketMakerOrderSnapshot(
      walletSession: walletSession,
      orderCorrelation: ownership,
      configurations: repositorySnapshot.configurations,
      orders: repositorySnapshot.tradePairs,
    );
  }

  MarketMakerOrderListState _stateForSnapshot(
    _MarketMakerOrderSnapshot snapshot,
  ) {
    final walletSession = snapshot.walletSession;
    if (walletSession == null) {
      return state.copyWith(
        allMakerBotOrders: const [],
        makerBotOrders: const [],
        status: MarketMakerOrderListStatus.initial,
        walletSession: () => null,
        orderCorrelation: () => null,
        configurationSnapshot: const [],
      );
    }

    final allOrders = _sortedOrders(snapshot.orders, state.sortData);
    return state.copyWith(
      allMakerBotOrders: allOrders,
      makerBotOrders: _visibleOrders(allOrders, state.filterData),
      status: MarketMakerOrderListStatus.success,
      walletSession: () => walletSession,
      orderCorrelation: () => snapshot.orderCorrelation,
      configurationSnapshot: snapshot.configurations,
    );
  }

  List<TradePair> _visibleOrders(
    List<TradePair> allOrders,
    TradingEntitiesFilter? filterData,
  ) {
    if (filterData == null) return allOrders;
    return List<TradePair>.unmodifiable(_applyFilters(filterData, allOrders));
  }

  List<TradePair> _sortedOrders(
    Iterable<TradePair> orders,
    SortData<MarketMakerBotOrderListType> sortData,
  ) {
    final sortedOrders = List<TradePair>.of(orders);
    // Retrieve the sorting function based on the sort type.
    var sortingFunction = sortFunctions[sortData.sortType];
    if (sortingFunction != null) {
      sortedOrders.sort((a, b) {
        // Apply the sorting function.
        var result = sortingFunction(a, b);
        // Reverse the result if sortDirection is descending.
        return sortData.sortDirection == SortDirection.decrease
            ? -result
            : result;
      });
    }
    return List<TradePair>.unmodifiable(sortedOrders);
  }
}

final class _MarketMakerOrderSnapshot {
  const _MarketMakerOrderSnapshot({
    required this.walletSession,
    required this.orderCorrelation,
    required this.configurations,
    required this.orders,
  });

  final MarketMakerBotWalletSession? walletSession;
  final MarketMakerBotOrderOwnership? orderCorrelation;
  final List<TradeCoinPairConfig> configurations;
  final List<TradePair> orders;
}

// Define a map that associates each sort type with a sorting function.
final sortFunctions =
    <MarketMakerBotOrderListType, int Function(TradePair, TradePair)>{
      MarketMakerBotOrderListType.date: (a, b) =>
          a.order?.createdAt.compareTo(b.order?.createdAt ?? 0) ?? 0,
      MarketMakerBotOrderListType.margin: (a, b) =>
          double.tryParse(
            a.config.spread,
          )?.compareTo(double.tryParse(b.config.spread) ?? 0) ??
          0,
      MarketMakerBotOrderListType.receive: (a, b) =>
          a.config.relCoinId.compareTo(b.config.relCoinId),
      MarketMakerBotOrderListType.send: (a, b) =>
          a.config.baseCoinId.compareTo(b.config.baseCoinId),
      MarketMakerBotOrderListType.updateInterval: (a, b) =>
          a.config.priceElapsedValidity?.compareTo(
            b.config.priceElapsedValidity ?? 0,
          ) ??
          0,
      MarketMakerBotOrderListType.price: (a, b) =>
          (a.order?.price ?? 0).compareTo(b.order?.price ?? 0),
    };

List<TradePair> _applyFilters(
  TradingEntitiesFilter filters,
  List<TradePair> orders,
) {
  return orders.where((order) {
    final String? sellCoin = filters.sellCoin;
    final String? buyCoin = filters.buyCoin;
    final int? startDate = filters.startDate?.millisecondsSinceEpoch;
    final int? endDate = filters.endDate?.millisecondsSinceEpoch;
    final List<TradeSide>? shownSides = filters.shownSides;

    if (sellCoin != null && order.config.baseCoinId != sellCoin) return false;
    if (buyCoin != null && order.config.relCoinId != buyCoin) return false;

    if (order.order != null) {
      if (startDate != null && order.order!.createdAt < startDate / 1000) {
        return false;
      }
      if (endDate != null &&
          order.order!.createdAt > (endDate + millisecondsIn24H) / 1000) {
        return false;
      }
      if ((shownSides != null && shownSides.isNotEmpty) &&
          !shownSides.contains(order.order!.orderType)) {
        return false;
      }
    }

    return true;
  }).toList();
}

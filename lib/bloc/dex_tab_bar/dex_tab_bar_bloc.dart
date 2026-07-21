import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_order_list/market_maker_bot_order_list_repository.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_order_list/trade_pair.dart';
import 'package:web_dex/blocs/trading_entities_bloc.dart';
import 'package:web_dex/model/dex_list_type.dart';
import 'package:web_dex/model/my_orders/my_order.dart';
import 'package:web_dex/model/swap.dart';
import 'package:web_dex/model/trading_entities_filter.dart';
import 'package:web_dex/views/market_maker_bot/tab_type_enum.dart';
import 'package:web_dex/shared/utils/kdf_wallet_authority.dart';

part 'dex_tab_bar_event.dart';
part 'dex_tab_bar_state.dart';

class DexTabBarBloc extends Bloc<DexTabBarEvent, DexTabBarState> {
  DexTabBarBloc(
    this._kdfSdk,
    this._tradingEntitiesBloc,
    this._tradingBotRepository,
  ) : super(const DexTabBarState.initial()) {
    on<TabChanged>(_onTabChanged);
    on<FilterChanged>(_onFilterChanged);
    on<ListenToOrdersRequested>(_onStartListening);
    on<StopListeningToOrdersRequested>(_onStopListening);
    on<MyOrdersUpdated>(_onMyOrdersUpdated);
    on<SwapsUpdated>(_onSwapsUpdated);
    on<TradeBotOrdersUpdated>(_onTradeBotOrdersUpdated);
  }

  final TradingEntitiesBloc _tradingEntitiesBloc;
  final MarketMakerBotOrderListRepository _tradingBotRepository;
  final KomodoDefiSdk _kdfSdk;

  StreamSubscription<KdfUser?>? _authorizationSubscription;
  StreamSubscription<List<MyOrder>>? _myOrdersSubscription;
  StreamSubscription<List<Swap>>? _swapsSubscription;
  StreamSubscription<List<TradePair>>? _tradeBotOrdersSubscription;

  @override
  Future<void> close() async {
    await _cancelSubscriptions();
    return super.close();
  }

  int get tabIndex => state.tabIndex;

  Future<void> _onStartListening(
    ListenToOrdersRequested event,
    Emitter<DexTabBarState> emit,
  ) async {
    await _cancelSubscriptions();
    _authorizationSubscription = _kdfSdk.auth.watchCurrentUser().listen(
      (event) {
        if (isClosed) return;
        if (event != null) {
          add(const TabChanged(0));
        }
      },
      onError: (_) {},
      onDone: () {},
    );

    _myOrdersSubscription = _tradingEntitiesBloc.outMyOrders.listen((orders) {
      if (!isClosed) add(MyOrdersUpdated(orders));
    });

    _swapsSubscription = _tradingEntitiesBloc.outSwaps.listen((swaps) {
      if (!isClosed) add(SwapsUpdated(swaps));
    });

    _tradeBotOrdersSubscription = Stream.periodic(const Duration(seconds: 3))
        .asyncMap((_) => _loadTradeBotOrders())
        .listen(
          (orders) {
            if (!isClosed) add(TradeBotOrdersUpdated(orders));
          },
          onError: (_) {
            if (!isClosed) add(const TradeBotOrdersUpdated([]));
          },
        );
  }

  Future<List<TradePair>> _loadTradeBotOrders() async {
    final walletId = await freshKdfCurrentWalletId(_kdfSdk);
    if (walletId == null) return const [];
    final orders = await _tradingBotRepository.getTradePairs();
    return await freshKdfCurrentWalletId(_kdfSdk) == walletId
        ? orders
        : const [];
  }

  Future<void> _onStopListening(
    StopListeningToOrdersRequested event,
    Emitter<DexTabBarState> emit,
  ) async {
    await _cancelSubscriptions();
  }

  Future<void> _cancelSubscriptions() async {
    await _authorizationSubscription?.cancel();
    _authorizationSubscription = null;

    await _myOrdersSubscription?.cancel();
    _myOrdersSubscription = null;

    await _swapsSubscription?.cancel();
    _swapsSubscription = null;

    await _tradeBotOrdersSubscription?.cancel();
    _tradeBotOrdersSubscription = null;
  }

  FutureOr<void> _onTabChanged(TabChanged event, Emitter<DexTabBarState> emit) {
    // Validate tabIndex to prevent out-of-bounds access
    final int validatedIndex = event.tabIndex
        .clamp(0, DexListType.values.length - 1)
        .toInt();
    emit(state.copyWith(tabIndex: validatedIndex));
  }

  void _onFilterChanged(FilterChanged event, Emitter<DexTabBarState> emit) {
    final filters = Map<ITabTypeEnum, TradingEntitiesFilter?>.of(state.filters);
    final filter = event.filter;
    if (filter == null) {
      filters.remove(event.tabType);
    } else {
      filters[event.tabType] = filter;
    }
    emit(state.copyWith(filters: Map.unmodifiable(filters)));
  }

  void _onMyOrdersUpdated(MyOrdersUpdated event, Emitter<DexTabBarState> emit) {
    final ordersCount = event.myOrders.length;
    emit(state.copyWith(ordersCount: ordersCount));
  }

  void _onSwapsUpdated(SwapsUpdated event, Emitter<DexTabBarState> emit) {
    final inProgressCount = event.swaps
        .where((swap) => !swap.isCompleted)
        .length;
    final completedCount = event.swaps.where((swap) => swap.isCompleted).length;
    emit(
      state.copyWith(
        inProgressCount: inProgressCount,
        completedCount: completedCount,
      ),
    );
  }

  void _onTradeBotOrdersUpdated(
    TradeBotOrdersUpdated event,
    Emitter<DexTabBarState> emit,
  ) {
    emit(state.copyWith(tradeBotOrdersCount: event.tradeBotOrders.length));
  }
}

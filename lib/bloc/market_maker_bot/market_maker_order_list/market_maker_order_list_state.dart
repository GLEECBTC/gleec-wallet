part of 'market_maker_order_list_bloc.dart';

enum MarketMakerOrderListStatus { initial, loading, success, failure }

class MarketMakerOrderListState extends Equatable {
  /// Complete, unfiltered configuration snapshot for the captured wallet
  /// session. Destructive actions must always freeze targets from this list.
  final List<TradePair> allMakerBotOrders;

  /// Visible list after applying the selected filter and sort.
  final List<TradePair> makerBotOrders;

  /// Status of the market maker order list.
  final MarketMakerOrderListStatus status;

  /// Sorting data for the market maker order list.
  final SortData<MarketMakerBotOrderListType> sortData;

  /// Filter data for the market maker order list.
  final TradingEntitiesFilter? filterData;

  /// Exact wallet session under which both order lists were loaded.
  final MarketMakerBotWalletSession? walletSession;

  /// Correlation object captured with this successful list snapshot.
  ///
  /// Identity, not value equality, is intentional: a bot restart in the same
  /// wallet creates a new correlation and immediately invalidates old rows.
  final MarketMakerBotOrderOwnership? orderCorrelation;

  /// Exact persisted configurations used to build this order snapshot.
  /// Start requests freeze this value and revalidate it at the RPC boundary.
  final List<TradeCoinPairConfig> configurationSnapshot;

  const MarketMakerOrderListState({
    this.allMakerBotOrders = const [],
    this.makerBotOrders = const [],
    required this.status,
    required this.sortData,
    this.filterData,
    this.walletSession,
    this.orderCorrelation,
    this.configurationSnapshot = const [],
  });

  MarketMakerOrderListState.initial()
    : this(
        status: MarketMakerOrderListStatus.initial,
        sortData: initialSortState(),
      );

  MarketMakerOrderListState copyWith({
    List<TradePair>? allMakerBotOrders,
    List<TradePair>? makerBotOrders,
    MarketMakerOrderListStatus? status,
    SortData<MarketMakerBotOrderListType>? sortData,
    TradingEntitiesFilter? Function()? filterData,
    MarketMakerBotWalletSession? Function()? walletSession,
    MarketMakerBotOrderOwnership? Function()? orderCorrelation,
    List<TradeCoinPairConfig>? configurationSnapshot,
  }) {
    return MarketMakerOrderListState(
      allMakerBotOrders: allMakerBotOrders ?? this.allMakerBotOrders,
      makerBotOrders: makerBotOrders ?? this.makerBotOrders,
      status: status ?? this.status,
      sortData: sortData ?? this.sortData,
      filterData: filterData == null ? this.filterData : filterData(),
      walletSession: walletSession == null
          ? this.walletSession
          : walletSession(),
      orderCorrelation: orderCorrelation == null
          ? this.orderCorrelation
          : orderCorrelation(),
      configurationSnapshot:
          configurationSnapshot ?? this.configurationSnapshot,
    );
  }

  static SortData<MarketMakerBotOrderListType> initialSortState() {
    return const SortData<MarketMakerBotOrderListType>(
      sortDirection: SortDirection.increase,
      sortType: MarketMakerBotOrderListType.send,
    );
  }

  @override
  List<Object?> get props => [
    allMakerBotOrders,
    makerBotOrders,
    status,
    sortData,
    filterData,
    walletSession,
    orderCorrelation,
    configurationSnapshot,
  ];
}

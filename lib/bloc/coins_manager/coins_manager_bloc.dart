import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart' show Bloc, Emitter;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart' show CoinSubClass;
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/analytics/events/portfolio_events.dart';
import 'package:web_dex/analytics/events/misc_events.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/coins_manager/coins_manager_sort.dart';
import 'package:web_dex/bloc/settings/settings_repository.dart';
import 'package:web_dex/blocs/trading_entities_bloc.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/coin_utils.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/shared/utils/extensions/kdf_user_extensions.dart';
import 'package:web_dex/router/state/wallet_state.dart';
import 'package:web_dex/views/wallet/coins_manager/coins_manager_helpers.dart';

part 'coins_manager_event.dart';
part 'coins_manager_state.dart';

class CoinsManagerBloc extends Bloc<CoinsManagerEvent, CoinsManagerState> {
  CoinsManagerBloc({
    required CoinsRepo coinsRepo,
    required KomodoDefiSdk sdk,
    required AnalyticsBloc analyticsBloc,
    required SettingsRepository settingsRepository,
    required TradingEntitiesBloc tradingEntitiesBloc,
  }) : _coinsRepo = coinsRepo,
       _sdk = sdk,
       _analyticsBloc = analyticsBloc,
       _settingsRepository = settingsRepository,
       _tradingEntitiesBloc = tradingEntitiesBloc,
       super(CoinsManagerState.initial(coins: [])) {
    on<CoinsManagerCoinsUpdate>(_onCoinsUpdate);
    on<CoinsManagerCoinsListReset>(_onCoinsListReset);
    on<CoinsManagerCoinTypeSelect>(_onCoinTypeSelect);
    on<CoinsManagerCoinsSwitch>(_onCoinsSwitch);
    on<CoinsManagerCoinSelect>(_onCoinSelect);
    on<CoinsManagerSelectAllTap>(_onSelectAll);
    on<CoinsManagerSelectedTypesReset>(_onSelectedTypesReset);
    on<CoinsManagerSearchUpdate>(_onSearchUpdate);
    on<CoinsManagerSortChanged>(_onSortChanged);
    on<CoinsManagerCoinRemoveRequested>(_onCoinRemoveRequested);
    on<CoinsManagerCoinRemoveConfirmed>(_onCoinRemoveConfirmed);
    on<CoinsManagerCoinRemovalCancelled>(_onCoinRemovalCancelled);
    on<CoinsManagerErrorCleared>(_onErrorCleared);
  }

  final CoinsRepo _coinsRepo;
  final KomodoDefiSdk _sdk;
  final AnalyticsBloc _analyticsBloc;
  final SettingsRepository _settingsRepository;
  final TradingEntitiesBloc _tradingEntitiesBloc;
  final _log = Logger('CoinsManagerBloc');

  // Cache for expensive operations
  Map<String, Coin>? _cachedKnownCoinsMap;
  List<Coin>? _cachedWalletCoins;
  bool? _cachedTestCoinsEnabled;

  Future<void> _onCoinsUpdate(
    CoinsManagerCoinsUpdate event,
    Emitter<CoinsManagerState> emit,
  ) async {
    final List<FilterFunction> filters = [];

    final originalCoins = await _filterUnsupportedHardwareCoins(
      await _getOriginalCoinList(
        _coinsRepo,
        event.action,
        cachedKnownCoinsMap: _cachedKnownCoinsMap,
        cachedWalletCoins: _cachedWalletCoins,
      ),
      event.action,
    );
    final mergedCoinsList = _mergeCoinLists(
      originalCoins,
      state.coins,
    ).toList();

    // Add wallet coins to selected coins if in add mode so that they
    // are displayed in the list with the checkbox selected. This is
    // necessary, since the UI does not consider the state of the coins
    // in the list, but only the selected coins.
    final selectedCoins = await _mergeWalletCoinsIfNeeded(
      state.selectedCoins,
      event.action,
    );
    final visibleSelectedCoins = await _filterUnsupportedHardwareCoins(
      selectedCoins,
      event.action,
    );

    final uniqueCombinedList = <Coin>{
      ...mergedCoinsList,
      ...visibleSelectedCoins,
    };

    final testFilteredCoins = await _filterTestCoinsIfNeeded(
      uniqueCombinedList.toList(),
    );

    if (state.searchPhrase.isNotEmpty) {
      filters.add(_filterByPhrase);
    }
    if (state.selectedCoinTypes.isNotEmpty) {
      filters.add(_filterByType);
    }

    List<Coin> filteredCoins = testFilteredCoins;
    for (final filter in filters) {
      filteredCoins = filter(filteredCoins);
    }

    final sortedCoins = _sortCoins(filteredCoins, event.action, state.sortData);

    emit(
      state.copyWith(
        coins: sortedCoins.unique((coin) => coin.id),
        action: event.action,
        selectedCoins: visibleSelectedCoins,
      ),
    );
  }

  Future<void> _onCoinsListReset(
    CoinsManagerCoinsListReset event,
    Emitter<CoinsManagerState> emit,
  ) async {
    _cachedWalletCoins = null;
    _cachedTestCoinsEnabled = null;

    emit(
      state.copyWith(
        action: event.action,
        coins: _cachedKnownCoinsMap?.values.toList() ?? [],
        selectedCoins: const [],
        searchPhrase: '',
        selectedCoinTypes: const [],
        isSwitching: false,
      ),
    );

    // Cache expensive operations when opening the list, as these values
    // should not change while the list is open.
    // Known coins map can be cached for longer, but would need to add an
    // auth listener to clear it on logout/login, so leaving as-is for now.
    // Wallet and test coins can be changed by the user outside of this
    // bloc within the same auth session, so they must always be cleared.
    _cachedKnownCoinsMap = _coinsRepo.getKnownCoinsMap(
      excludeExcludedAssets: true,
    );
    _cachedWalletCoins = await _coinsRepo.getWalletCoins();
    _cachedTestCoinsEnabled =
        (await _settingsRepository.loadSettings()).testCoinsEnabled;

    final List<Coin> coins = await _filterUnsupportedHardwareCoins(
      await _getOriginalCoinList(
        _coinsRepo,
        event.action,
        cachedKnownCoinsMap: _cachedKnownCoinsMap,
        cachedWalletCoins: _cachedWalletCoins,
      ),
      event.action,
    );

    // Add wallet coins to selected coins if in add mode so that they
    // are displayed in the list with the checkbox selected. This is
    // necessary, since the UI does not consider the state of the coins
    // in the list, but only the selected coins.
    final selectedCoins = await _mergeWalletCoinsIfNeeded(
      event.action == CoinsManagerAction.add
          ? coins.where((c) => c.isActive).toList()
          : <Coin>[],
      event.action,
    );
    final visibleSelectedCoins = await _filterUnsupportedHardwareCoins(
      selectedCoins,
      event.action,
    );

    final filteredCoins = await _filterTestCoinsIfNeeded(
      {...coins, ...visibleSelectedCoins}.toList(),
    );
    final sortedCoins = _sortCoins(filteredCoins, event.action, state.sortData);

    emit(
      state.copyWith(
        coins: sortedCoins.unique((coin) => coin.id),
        action: event.action,
        selectedCoins: visibleSelectedCoins,
      ),
    );
  }

  void _onCoinTypeSelect(
    CoinsManagerCoinTypeSelect event,
    Emitter<CoinsManagerState> emit,
  ) {
    final List<CoinSubClass> newTypes =
        state.selectedCoinTypes.contains(event.type)
        ? state.selectedCoinTypes.where((type) => type != event.type).toList()
        : [...state.selectedCoinTypes, event.type];

    emit(state.copyWith(selectedCoinTypes: newTypes));

    add(CoinsManagerCoinsUpdate(state.action));
  }

  Future<void> _onCoinsSwitch(
    CoinsManagerCoinsSwitch event,
    Emitter<CoinsManagerState> emit,
  ) async {
    final List<Coin> selectedCoins = [...state.selectedCoins];
    emit(state.copyWith(isSwitching: true));

    final Future<void> switchingFuture = state.action == CoinsManagerAction.add
        ? _coinsRepo.activateCoinsSync(selectedCoins)
        : _coinsRepo.deactivateCoinsSync(selectedCoins);

    emit(state.copyWith(selectedCoins: [], isSwitching: false));
    await switchingFuture;
  }

  Future<void> _onCoinSelect(
    CoinsManagerCoinSelect event,
    Emitter<CoinsManagerState> emit,
  ) async {
    final coin = event.coin;
    final Set<Coin> selectedCoins = Set.from(state.selectedCoins);
    final bool wasSelected = selectedCoins.contains(coin);

    // Check if this is a deselection (removal) that needs trading checks
    final bool isDeselection = wasSelected;
    final bool needsTradingChecks =
        isDeselection && state.action == CoinsManagerAction.add;

    if (needsTradingChecks) {
      // Trigger the same removal flow as the remove action
      add(CoinsManagerCoinRemoveRequested(coin: coin));
      return;
    }

    if (wasSelected) {
      selectedCoins.remove(coin);
    } else {
      selectedCoins.add(coin);
    }

    // Emit state immediately for responsive UI
    // before performing the actual activation/deactivation in background
    emit(state.copyWith(selectedCoins: selectedCoins.toList()));

    final bool shouldActivate =
        (state.action == CoinsManagerAction.add && !wasSelected) ||
        (state.action == CoinsManagerAction.remove && wasSelected);

    if (shouldActivate) {
      try {
        await _tryActivateCoin(coin);
      } on ZhtlcActivationCancelled {
        // Revert optimistic selection and show a friendly message
        selectedCoins.remove(coin);
        emit(
          state.copyWith(
            selectedCoins: selectedCoins.toList(),
            errorMessage: 'Activation canceled.',
          ),
        );
        return;
      }
    } else {
      await _tryDeactivateCoin(coin);
    }
  }

  Future<void> _tryDeactivateCoin(Coin coin) async {
    try {
      await _coinsRepo.deactivateCoinsSync([coin]);
    } catch (e, s) {
      _log.warning('Failed to deactivate coin ${coin.abbr}', e, s);
    }
    _analyticsBloc.logEvent(
      AssetDisabledEventData(
        asset: coin.abbr,
        network: coin.protocolType,
        hdType: (await _sdk.auth.currentUser)?.type ?? '',
      ),
    );
  }

  Future<void> _tryActivateCoin(Coin coin) async {
    try {
      await _coinsRepo.activateCoinsSync([coin]);
    } on ZhtlcActivationCancelled {
      // Rethrow so the caller can revert the optimistic toggle and show UI
      rethrow;
    } catch (e, s) {
      _log.warning('Failed to activate coin ${coin.abbr}', e, s);
      return;
    }
    _analyticsBloc.logEvent(
      AssetEnabledEventData(
        asset: coin.abbr,
        network: coin.protocolType,
        hdType: (await _sdk.auth.currentUser)?.type ?? '',
      ),
    );
  }

  FutureOr<void> _onSelectAll(
    CoinsManagerSelectAllTap event,
    Emitter<CoinsManagerState> emit,
  ) {
    final selectedCoins = state.isSelectedAllCoinsEnabled
        ? <Coin>[]
        : state.coins;
    emit(state.copyWith(selectedCoins: selectedCoins));
  }

  FutureOr<void> _onSelectedTypesReset(
    CoinsManagerSelectedTypesReset event,
    Emitter<CoinsManagerState> emit,
  ) {
    emit(state.copyWith(selectedCoinTypes: []));
    add(CoinsManagerCoinsUpdate(state.action));
  }

  FutureOr<void> _onSearchUpdate(
    CoinsManagerSearchUpdate event,
    Emitter<CoinsManagerState> emit,
  ) {
    emit(state.copyWith(searchPhrase: event.text));
    final query = event.text.trim();
    final matchedCoin = _coinsRepo.getCoin(query.toUpperCase());
    _analyticsBloc.logEvent(
      SearchbarInputEventData(
        queryLength: query.length,
        assetSymbol: matchedCoin?.abbr,
      ),
    );
    add(CoinsManagerCoinsUpdate(state.action));
  }

  FutureOr<void> _onSortChanged(
    CoinsManagerSortChanged event,
    Emitter<CoinsManagerState> emit,
  ) {
    final List<Coin> sorted = _sortCoins(
      [...state.coins],
      state.action,
      event.sortData,
    );
    emit(state.copyWith(coins: sorted, sortData: event.sortData));
  }

  Future<List<Coin>> _filterTestCoinsIfNeeded(List<Coin> coins) async {
    _cachedTestCoinsEnabled ??=
        (await _settingsRepository.loadSettings()).testCoinsEnabled;
    return _cachedTestCoinsEnabled! ? coins : removeTestCoins(coins);
  }

  List<Coin> _filterByPhrase(List<Coin> coins) {
    final String filter = state.searchPhrase.toLowerCase();
    return filter.isEmpty
          ? coins.toList()
          : coins
                .where((Coin coin) => compareCoinByPhrase(coin, filter))
                .toList()
      ..sort((a, b) => a.abbr.toLowerCase().compareTo(b.abbr.toLowerCase()));
  }

  List<Coin> _filterByType(List<Coin> coins) {
    return coins
        .where((coin) => state.selectedCoinTypes.contains(coin.id.subClass))
        .toList();
  }

  Future<List<Coin>> _filterUnsupportedHardwareCoins(
    List<Coin> coins,
    CoinsManagerAction action,
  ) async {
    if (action != CoinsManagerAction.add) {
      return coins;
    }

    final currentWalletType = (await _sdk.auth.currentUser)?.wallet.config.type;
    if (currentWalletType != WalletType.trezor) {
      return coins;
    }

    return coins.where((coin) => coin.id.subClass != CoinSubClass.sia).toList();
  }

  /// Merges wallet coins into selected coins list when in add mode
  Future<List<Coin>> _mergeWalletCoinsIfNeeded(
    List<Coin> selectedCoins,
    CoinsManagerAction action,
  ) async {
    if (action != CoinsManagerAction.add) {
      return selectedCoins;
    }

    _cachedWalletCoins ??= await _coinsRepo.getWalletCoins();
    final walletCoins = _cachedWalletCoins!;
    final result = List<Coin>.from(selectedCoins);
    final selectedCoinIds = result.map((c) => c.id.id).toSet();

    for (final walletCoin in walletCoins) {
      // Do not pre-select ZHTLC coins without saved configuration.
      // This ensures toggles remain OFF if auto-activation was bypassed.
      if (walletCoin.id.subClass == CoinSubClass.zhtlc) {
        try {
          final saved = await _sdk.activationConfigService.getSavedZhtlc(
            walletCoin.id,
          );
          if (saved == null) {
            continue;
          }
        } catch (_) {
          // On any error, be conservative and keep toggle OFF
          continue;
        }
      }

      if (!selectedCoinIds.contains(walletCoin.id.id)) {
        result.add(walletCoin);
      }
    }

    return result;
  }

  Set<Coin> _mergeCoinLists(List<Coin> originalList, List<Coin> newList) {
    final Map<String, Coin> coinMap = {};

    for (final Coin coin in originalList) {
      coinMap[coin.id.id] = coin;
    }

    for (final Coin coin in newList) {
      coinMap[coin.id.id] = coin;
    }

    return coinMap.values.toSet();
  }

  List<Coin> _sortCoins(
    List<Coin> coins,
    CoinsManagerAction action,
    CoinsManagerSortData sortData,
  ) {
    List<Coin> sorted = List.from(coins);
    switch (sortData.sortType) {
      case CoinsManagerSortType.name:
        sorted = sortByName(sorted, sortData.sortDirection);
      case CoinsManagerSortType.protocol:
        sorted = sortByProtocol(sorted, sortData.sortDirection);
      case CoinsManagerSortType.balance:
        sorted = sortByUsdBalance(sorted, sortData.sortDirection, _sdk);
      case CoinsManagerSortType.none:
        sorted = sortByPriorityAndBalance(sorted, _sdk);
    }

    return sorted;
  }

  Future<void> _onCoinRemoveRequested(
    CoinsManagerCoinRemoveRequested event,
    Emitter<CoinsManagerState> emit,
  ) async {
    final coin = event.coin;

    // Find child coins (tokens)
    final walletCoins = await _coinsRepo.getWalletCoins();
    final childCoins = walletCoins
        .where((c) => c.parentCoin?.abbr == coin.abbr)
        .toList();

    // Check for active swaps
    final hasSwap =
        _tradingEntitiesBloc.hasActiveSwap(coin.abbr) ||
        childCoins.any((c) => _tradingEntitiesBloc.hasActiveSwap(c.abbr));

    if (hasSwap) {
      emit(
        state.copyWith(
          removalState: CoinRemovalState(
            coin: coin,
            childCoins: childCoins,
            blockReason: CoinRemovalBlockReason.activeSwap,
            openOrdersCount: 0,
          ),
        ),
      );
      return;
    }

    // Check for open orders
    final int openOrders =
        _tradingEntitiesBloc.openOrdersCount(coin.abbr) +
        childCoins.fold<int>(
          0,
          (sum, c) => sum + _tradingEntitiesBloc.openOrdersCount(c.abbr),
        );

    if (openOrders > 0) {
      emit(
        state.copyWith(
          removalState: CoinRemovalState(
            coin: coin,
            childCoins: childCoins,
            blockReason: CoinRemovalBlockReason.openOrders,
            openOrdersCount: openOrders,
          ),
        ),
      );
      return;
    }

    // No blocking conditions, proceed with confirmation flow
    emit(
      state.copyWith(
        removalState: CoinRemovalState(
          coin: coin,
          childCoins: childCoins,
          blockReason: CoinRemovalBlockReason.none,
          openOrdersCount: 0,
        ),
      ),
    );
  }

  Future<void> _onCoinRemoveConfirmed(
    CoinsManagerCoinRemoveConfirmed event,
    Emitter<CoinsManagerState> emit,
  ) async {
    final removalState = state.removalState;
    if (removalState == null) return;

    final coin = removalState.coin;
    final childCoins = removalState.childCoins;

    // Cancel orders if there were any
    if (removalState.hasOpenOrders) {
      try {
        await _tradingEntitiesBloc.cancelOrdersForCoin(coin.abbr);
        for (final child in childCoins) {
          await _tradingEntitiesBloc.cancelOrdersForCoin(child.abbr);
        }
      } catch (e, s) {
        _log.warning('Failed to cancel orders for coin ${coin.abbr}', e, s);

        emit(
          state.copyWith(
            removalState: null,
            errorMessage:
                'Failed to cancel open orders for ${coin.abbr}. Please try again.',
          ),
        );
        return;
      }
    }

    final selectedCoins = List<Coin>.from(state.selectedCoins)
      ..remove(coin)
      ..removeWhere((coin) => childCoins.any((child) => child.id == coin.id));

    //  Emit state immediately for responsive UI
    // before performing the actual activation/deactivation in background
    emit(
      state.copyWith(removalState: null, selectedCoins: selectedCoins.toList()),
    );

    await _tryDeactivateCoin(coin);
  }

  void _onCoinRemovalCancelled(
    CoinsManagerCoinRemovalCancelled event,
    Emitter<CoinsManagerState> emit,
  ) {
    emit(state.copyWith(removalState: null));
  }

  void _onErrorCleared(
    CoinsManagerErrorCleared event,
    Emitter<CoinsManagerState> emit,
  ) {
    emit(state.copyWith(errorMessage: null));
  }
}

Future<List<Coin>> _getOriginalCoinList(
  CoinsRepo coinsRepo,
  CoinsManagerAction action, {
  Map<String, Coin>? cachedKnownCoinsMap,
  List<Coin>? cachedWalletCoins,
}) async {
  switch (action) {
    case CoinsManagerAction.add:
      final knownCoinsMap =
          cachedKnownCoinsMap ??
          coinsRepo.getKnownCoinsMap(excludeExcludedAssets: true);
      return knownCoinsMap.values.toList();
    case CoinsManagerAction.remove:
      return cachedWalletCoins ?? await coinsRepo.getWalletCoins();
    case CoinsManagerAction.none:
      return [];
  }
}

typedef FilterFunction = List<Coin> Function(List<Coin>);

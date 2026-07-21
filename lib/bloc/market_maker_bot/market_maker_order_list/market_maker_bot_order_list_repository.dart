import 'package:decimal/decimal.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_order_list/trade_pair.dart';
import 'package:web_dex/bloc/settings/settings_repository.dart';
import 'package:web_dex/mm2/mm2_api/rpc/market_maker_bot/trade_coin_pair_config.dart';
import 'package:web_dex/mm2/mm2_api/rpc/market_maker_bot/trade_volume.dart';
import 'package:web_dex/views/market_maker_bot/trade_volume_type.dart';
import 'package:web_dex/model/my_orders/my_order.dart';
import 'package:web_dex/services/orders_service/my_orders_service.dart';

final class MarketMakerBotCancellationResult {
  const MarketMakerBotCancellationResult({
    required this.requestedCount,
    required this.completedCount,
    required this.failedCount,
    required this.uncertainCount,
    this.walletChanged = false,
  });

  final int requestedCount;
  final int completedCount;
  final int failedCount;
  final int uncertainCount;
  final bool walletChanged;

  bool get isComplete =>
      requestedCount > 0 &&
      !walletChanged &&
      completedCount == requestedCount &&
      failedCount == 0 &&
      uncertainCount == 0;
}

final class MarketMakerBotTradePairSnapshot {
  const MarketMakerBotTradePairSnapshot({
    required this.configurations,
    required this.tradePairs,
  });

  final List<TradeCoinPairConfig> configurations;
  final List<TradePair> tradePairs;
}

/// A configured pair cannot be associated with a bot order authoritatively.
///
/// KDF's order projection does not expose a bot owner field. A clean pre-start
/// baseline can only produce a conservative temporal UUID correlation, not
/// authoritative provenance. Pair-only matches are never accepted, ambiguous
/// correlations fail closed, and this evidence must never authorize direct
/// UUID mutation.
final class MarketMakerBotOrderOwnershipUnavailable implements Exception {
  const MarketMakerBotOrderOwnershipUnavailable();
}

enum MarketMakerBotOrderReconciliationState {
  active,
  absent,
  ownershipUnavailable,
}

final class MarketMakerBotCleanOrderBaseline {
  const MarketMakerBotCleanOrderBaseline._(this.configsByName);

  final Map<String, TradeCoinPairConfig> configsByName;
}

/// Conservative UUID correlation observed during one app-started lifecycle.
///
/// Despite the legacy type name, this is not authoritative owner metadata. It
/// is only suitable for read-only row projection and post-stop absence checks.
final class MarketMakerBotOrderOwnership {
  const MarketMakerBotOrderOwnership._({
    required this.configsByName,
    required Map<String, String?> orderUuidsByConfigName,
  }) : _orderUuidsByConfigName = orderUuidsByConfigName;

  final Map<String, TradeCoinPairConfig> configsByName;
  final Map<String, String?> _orderUuidsByConfigName;

  String? orderUuidFor(TradeCoinPairConfig config) {
    if (configsByName[config.name] != config) return null;
    return _orderUuidsByConfigName[config.name];
  }

  bool matchesProjectedPair(TradePair pair) {
    if (configsByName[pair.config.name] != pair.config) return false;
    final expectedUuid = _orderUuidsByConfigName[pair.config.name];
    final order = pair.order;
    // A null projection is valid for a disabled pair or a correlated order
    // that temporarily disappeared. The live snapshot is checked again before
    // every bot lifecycle mutation, but never authorizes direct UUID mutation.
    return order == null ||
        (expectedUuid != null &&
            order.uuid == expectedUuid &&
            _isMakerOrderFor(order, pair.config));
  }

  bool matches(Iterable<TradeCoinPairConfig> configs) {
    try {
      final candidate = _configsByName(configs);
      return candidate.length == configsByName.length &&
          configsByName.entries.every(
            (entry) => candidate[entry.key] == entry.value,
          );
    } on MarketMakerBotOrderOwnershipUnavailable {
      return false;
    }
  }
}

class MarketMakerBotOrderListRepository {
  const MarketMakerBotOrderListRepository(
    this._ordersService,
    this._settingsRepository,
    this._coinsRepository,
  );

  final CoinsRepo _coinsRepository;
  final MyOrdersService _ordersService;
  final SettingsRepository _settingsRepository;

  Future<MarketMakerBotTradePairSnapshot> getTradePairSnapshot({
    MarketMakerBotOrderOwnership? ownership,
  }) async {
    final settings = await _settingsRepository.loadSettingsStrict();
    final configs = settings.marketMakerBotSettings.tradeCoinPairConfigs;
    final scopedOwnership = ownership?.matches(configs) == true
        ? ownership
        : null;
    final orders = await _ordersService.getOrders();
    if (orders == null) {
      throw const MarketMakerBotOrderOwnershipUnavailable();
    }

    final tradePairs = configs.map((TradeCoinPairConfig config) {
      final correlatedUuid = scopedOwnership?.orderUuidFor(config);
      final order = correlatedUuid == null
          ? null
          : orders
                .where(
                  (candidate) =>
                      candidate.uuid == correlatedUuid &&
                      _isMakerOrderFor(candidate, config),
                )
                .firstOrNull;

      final Rational baseCoinAmount = _getBaseCoinAmount(config, order);
      return TradePair(
        config,
        order,
        baseCoinAmount: baseCoinAmount,
        relCoinAmount: _getRelCoinAmount(baseCoinAmount, config, order),
      );
    }).toList();

    final recheckedSettings = await _settingsRepository.loadSettingsStrict();
    final recheckedConfigs =
        recheckedSettings.marketMakerBotSettings.tradeCoinPairConfigs;
    if (!_sameConfigs(configs, recheckedConfigs)) {
      throw const MarketMakerBotOrderOwnershipUnavailable();
    }

    return MarketMakerBotTradePairSnapshot(
      configurations: List<TradeCoinPairConfig>.unmodifiable(configs),
      tradePairs: List<TradePair>.unmodifiable(tradePairs),
    );
  }

  Future<List<TradePair>> getTradePairs({
    MarketMakerBotOrderOwnership? ownership,
  }) async => (await getTradePairSnapshot(ownership: ownership)).tradePairs;

  Future<MarketMakerBotCleanOrderBaseline> captureCleanOrderBaseline(
    Iterable<TradeCoinPairConfig> tradePairs,
  ) async {
    final configsByName = _configsByName(tradePairs);
    final orders = await _ordersService.getOrders();
    if (orders == null ||
        _matchingMakerOrders(orders, configsByName).isNotEmpty) {
      throw const MarketMakerBotOrderOwnershipUnavailable();
    }
    return MarketMakerBotCleanOrderBaseline._(
      Map<String, TradeCoinPairConfig>.unmodifiable(configsByName),
    );
  }

  Future<void> requireCleanOrderBaseline(
    MarketMakerBotCleanOrderBaseline baseline,
  ) async {
    final orders = await _ordersService.getOrders();
    if (orders == null ||
        _matchingMakerOrders(orders, baseline.configsByName).isNotEmpty) {
      throw const MarketMakerBotOrderOwnershipUnavailable();
    }
  }

  Future<MarketMakerBotOrderOwnership> captureStartedOrderOwnership(
    MarketMakerBotCleanOrderBaseline baseline, {
    required Duration timeout,
    Future<void> Function()? beforeRead,
  }) async {
    final clock = Stopwatch()..start();
    while (true) {
      await beforeRead?.call();
      final remaining = timeout - clock.elapsed;
      if (remaining <= Duration.zero) {
        throw const MarketMakerBotOrderOwnershipUnavailable();
      }
      final orders = await _ordersService.getOrders().timeout(remaining);
      await beforeRead?.call();
      if (orders == null) {
        throw const MarketMakerBotOrderOwnershipUnavailable();
      }
      final ownership = _ownershipFromOrders(
        baseline.configsByName,
        orders,
        requireEnabledOrders: true,
      );
      if (ownership != null) return ownership;

      final delay = remaining < const Duration(milliseconds: 500)
          ? remaining
          : const Duration(milliseconds: 500);
      await Future<void>.delayed(delay);
    }
  }

  /// Correlates orders observed after a clean baseline for rollback only.
  /// Missing rows are retained as absence and multiple candidates fail closed.
  Future<MarketMakerBotOrderOwnership> captureSessionOrderOwnership(
    MarketMakerBotCleanOrderBaseline baseline, {
    Future<void> Function()? beforeRead,
    Duration? timeout,
  }) async {
    final clock = timeout == null ? null : (Stopwatch()..start());
    while (true) {
      await beforeRead?.call();
      final remaining = timeout == null ? null : timeout - clock!.elapsed;
      if (remaining != null && remaining <= Duration.zero) {
        throw const MarketMakerBotOrderOwnershipUnavailable();
      }
      final orders = remaining == null
          ? await _ordersService.getOrders()
          : await _ordersService.getOrders().timeout(remaining);
      await beforeRead?.call();
      if (orders != null) {
        return _ownershipFromOrders(
              baseline.configsByName,
              orders,
              requireEnabledOrders: false,
            ) ??
            (throw const MarketMakerBotOrderOwnershipUnavailable());
      }
      if (remaining == null) {
        throw const MarketMakerBotOrderOwnershipUnavailable();
      }
      final delay = remaining < const Duration(milliseconds: 500)
          ? remaining
          : const Duration(milliseconds: 500);
      await Future<void>.delayed(delay);
    }
  }

  Future<void> requireCurrentOrderOwnership(
    MarketMakerBotOrderOwnership ownership,
    Iterable<TradeCoinPairConfig> tradePairs,
  ) async {
    if (!ownership.matches(tradePairs)) {
      throw const MarketMakerBotOrderOwnershipUnavailable();
    }
    final orders = await _ordersService.getOrders();
    if (orders == null || !_ownershipMatchesOrders(ownership, orders)) {
      throw const MarketMakerBotOrderOwnershipUnavailable();
    }
  }

  Future<MarketMakerBotOrderReconciliationState> reconcileOrderOwnership(
    MarketMakerBotOrderOwnership ownership,
  ) async {
    final orders = await _ordersService.getOrders();
    if (orders == null) {
      return MarketMakerBotOrderReconciliationState.ownershipUnavailable;
    }

    var hasActiveOwnedOrder = false;
    for (final entry in ownership.configsByName.entries) {
      final config = entry.value;
      final expectedUuid = ownership._orderUuidsByConfigName[entry.key];
      final matching = orders
          .where((order) => _isMakerOrderFor(order, config))
          .toList(growable: false);
      if (matching.any((order) => order.uuid != expectedUuid)) {
        return MarketMakerBotOrderReconciliationState.ownershipUnavailable;
      }
      if (expectedUuid != null &&
          matching.any((order) => order.uuid == expectedUuid)) {
        hasActiveOwnedOrder = true;
      }
    }
    return hasActiveOwnedOrder
        ? MarketMakerBotOrderReconciliationState.active
        : MarketMakerBotOrderReconciliationState.absent;
  }

  /// Reconciles only UUIDs already correlated with this bot lifecycle.
  ///
  /// Unknown same-pair orders are deliberately ignored here. This method is
  /// only used after KDF has authoritatively reported the bot stopped and never
  /// authorizes cancelling or otherwise mutating any order UUID.
  Future<MarketMakerBotOrderReconciliationState> reconcileOwnedOrderAbsence(
    MarketMakerBotOrderOwnership ownership,
  ) async {
    final orders = await _ordersService.getOrders();
    if (orders == null) {
      return MarketMakerBotOrderReconciliationState.ownershipUnavailable;
    }

    for (final entry in ownership.configsByName.entries) {
      final expectedUuid = ownership._orderUuidsByConfigName[entry.key];
      if (expectedUuid == null) continue;
      final matchingUuid = orders
          .where((order) => order.uuid == expectedUuid)
          .firstOrNull;
      if (matchingUuid == null) continue;
      if (!_isMakerOrderFor(matchingUuid, entry.value)) {
        return MarketMakerBotOrderReconciliationState.ownershipUnavailable;
      }
      return MarketMakerBotOrderReconciliationState.active;
    }
    return MarketMakerBotOrderReconciliationState.absent;
  }

  Rational _getRelCoinAmount(
    Rational baseCoinAmount,
    TradeCoinPairConfig config,
    MyOrder? order,
  ) {
    return order?.relAmountAvailable ??
        _getRelAmountFromBaseAmount(baseCoinAmount, config, order);
  }

  Rational _getBaseCoinAmount(TradeCoinPairConfig config, MyOrder? order) {
    if (order?.baseAmountAvailable != null) {
      return order!.baseAmountAvailable!;
    }

    final TradeVolume? maxVolume = config.maxVolume;
    if (maxVolume == null) return Rational.zero;

    return _getBaseAmountFromVolume(config.baseCoinId, maxVolume);
  }

  Rational _getBaseAmountFromVolume(String baseCoinId, TradeVolume maxVolume) {
    final baseCoin = _coinsRepository.getCoin(baseCoinId);
    final Decimal balance = baseCoin == null
        ? Decimal.zero
        : _coinsRepository.lastKnownBalance(baseCoin.id)?.spendable ??
              Decimal.zero;

    if (balance == Decimal.zero) return Rational.zero;

    final Rational balanceRational = balance.toRational();

    if (maxVolume.type == TradeVolumeType.percentage) {
      // maxVolume.value is a fraction (e.g., 0.1 for 10%)
      final Rational percentage = Rational.parse(maxVolume.value.toString());
      final Rational desired = balanceRational * percentage;
      return desired > balanceRational ? balanceRational : desired;
    }

    // USD-based volume: convert USD to base coin amount using USD price (as Rational), then clamp to balance
    final Decimal? usdPrice = baseCoin?.usdPrice?.price;
    if (usdPrice == null || usdPrice == Decimal.zero) return Rational.zero;

    final Rational usdPriceRational = usdPrice.toRational();
    final Rational usdVolumeRational = Rational.parse(
      maxVolume.value.toString(),
    );
    final Rational amountInBase = usdVolumeRational / usdPriceRational;
    return amountInBase > balanceRational ? balanceRational : amountInBase;
  }

  Rational _getRelAmountFromBaseAmount(
    Rational baseCoinAmount,
    TradeCoinPairConfig config,
    MyOrder? order,
  ) {
    final Decimal? baseUsdPrice = _coinsRepository
        .getCoin(config.baseCoinId)
        ?.usdPrice
        ?.price;
    final Decimal? relUsdPrice = _coinsRepository
        .getCoin(config.relCoinId)
        ?.usdPrice
        ?.price;
    final price = relUsdPrice != null && baseUsdPrice != null
        ? baseUsdPrice / relUsdPrice
        : null;

    Rational relAmount = Rational.zero;
    if (price != null) {
      final Rational marginFraction =
          Decimal.parse(config.margin.toString()) / Decimal.fromInt(100);
      final Rational priceWithMargin = price * (Rational.one + marginFraction);
      return baseCoinAmount * priceWithMargin;
    }

    return relAmount;
  }
}

Map<String, TradeCoinPairConfig> _configsByName(
  Iterable<TradeCoinPairConfig> configs,
) {
  final byName = <String, TradeCoinPairConfig>{};
  final pairKeys = <String>{};
  for (final config in configs) {
    final name = config.name;
    final pairKey = _pairKey(config.baseCoinId, config.relCoinId);
    if (name.isEmpty ||
        name.trim() != name ||
        config.baseCoinId.isEmpty ||
        config.relCoinId.isEmpty ||
        byName.containsKey(name) ||
        !pairKeys.add(pairKey)) {
      throw const MarketMakerBotOrderOwnershipUnavailable();
    }
    byName[name] = config;
  }
  if (byName.isEmpty) {
    throw const MarketMakerBotOrderOwnershipUnavailable();
  }
  return byName;
}

bool _sameConfigs(
  Iterable<TradeCoinPairConfig> first,
  Iterable<TradeCoinPairConfig> second,
) {
  final firstList = first.toList(growable: false);
  final secondList = second.toList(growable: false);
  if (firstList.length != secondList.length) return false;
  final secondByName = <String, TradeCoinPairConfig>{
    for (final config in secondList) config.name: config,
  };
  return secondByName.length == secondList.length &&
      firstList.every((config) => secondByName[config.name] == config);
}

String _pairKey(String base, String rel) => '$base\u0000$rel';

bool _isMakerOrderFor(MyOrder order, TradeCoinPairConfig config) =>
    order.orderType == TradeSide.maker &&
    order.base == config.baseCoinId &&
    order.rel == config.relCoinId;

List<MyOrder> _matchingMakerOrders(
  Iterable<MyOrder> orders,
  Map<String, TradeCoinPairConfig> configsByName,
) => orders
    .where(
      (order) =>
          configsByName.values.any((config) => _isMakerOrderFor(order, config)),
    )
    .toList(growable: false);

MarketMakerBotOrderOwnership? _ownershipFromOrders(
  Map<String, TradeCoinPairConfig> configsByName,
  List<MyOrder> orders, {
  required bool requireEnabledOrders,
}) {
  final orderUuids = <String, String?>{};
  final assignedUuids = <String>{};
  var isComplete = true;
  for (final entry in configsByName.entries) {
    final config = entry.value;
    final matching = orders
        .where((order) => _isMakerOrderFor(order, config))
        .toList(growable: false);
    if (matching.length > 1 || (!config.enable && matching.isNotEmpty)) {
      throw const MarketMakerBotOrderOwnershipUnavailable();
    }
    final uuid = matching.firstOrNull?.uuid;
    if (config.enable && requireEnabledOrders && uuid == null) {
      isComplete = false;
    }
    if (uuid != null && !assignedUuids.add(uuid)) {
      throw const MarketMakerBotOrderOwnershipUnavailable();
    }
    orderUuids[entry.key] = uuid;
  }
  if (!isComplete) return null;
  return MarketMakerBotOrderOwnership._(
    configsByName: Map<String, TradeCoinPairConfig>.unmodifiable(configsByName),
    orderUuidsByConfigName: Map<String, String?>.unmodifiable(orderUuids),
  );
}

bool _ownershipMatchesOrders(
  MarketMakerBotOrderOwnership ownership,
  List<MyOrder> orders,
) {
  for (final entry in ownership.configsByName.entries) {
    final matching = orders
        .where((order) => _isMakerOrderFor(order, entry.value))
        .toList(growable: false);
    final expectedUuid = ownership._orderUuidsByConfigName[entry.key];
    if (expectedUuid == null) {
      if (matching.isNotEmpty) return false;
      continue;
    }
    // KDF can temporarily remove a correlated order when price data expires
    // and recreate it on a later loop. Absence is safe to observe; an
    // unknown replacement UUID is not and requires a new clean session.
    if (matching.length > 1 ||
        (matching.length == 1 && matching.single.uuid != expectedUuid)) {
      return false;
    }
  }
  return true;
}

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/blocs/bloc_base.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/mm2/mm2_api/rpc/cancel_order/cancel_order_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/max_taker_vol/max_taker_vol_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/max_taker_vol/max_taker_vol_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/my_recent_swaps/my_recent_swaps_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/my_recent_swaps/my_recent_swaps_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/recover_funds_of_swap/recover_funds_of_swap_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/recover_funds_of_swap/recover_funds_of_swap_response.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/model/my_orders/my_order.dart';
import 'package:web_dex/model/swap.dart';
import 'package:web_dex/model/trading_entity_id.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/services/orders_service/my_orders_service.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/shared/utils/kdf_wallet_authority.dart';

final class _TradingWalletChanged implements Exception {
  const _TradingWalletChanged();
}

class CancelAllOrdersResult {
  const CancelAllOrdersResult({
    required this.attemptedCount,
    required this.cancelledCount,
    required this.failedCount,
    required this.walletChanged,
    this.uncertain = false,
  });

  final int attemptedCount;
  final int cancelledCount;
  final int failedCount;
  final bool walletChanged;
  final bool uncertain;

  bool get isComplete =>
      attemptedCount > 0 &&
      !walletChanged &&
      !uncertain &&
      failedCount == 0 &&
      attemptedCount == cancelledCount;
  bool get isPartial => cancelledCount > 0 && !isComplete;
}

enum RecoverySubmissionStatus { idle, submitting, accepted, uncertain }

class TradingEntitiesBloc implements BlocBase {
  TradingEntitiesBloc(
    KomodoDefiSdk kdfSdk,
    Mm2Api mm2Api,
    MyOrdersService myOrdersService,
  ) : _mm2Api = mm2Api,
      _myOrdersService = myOrdersService,
      _kdfSdk = kdfSdk {
    _authModeListener = _kdfSdk.auth.watchCurrentUser().listen(
      (user) {
        if (_closed) return;
        _authObservationUnavailable = false;
        _authObservationEpoch++;
        _synchronizeWallet(user?.walletId.compoundId, forceSessionChange: true);
      },
      onError: (_) {
        if (_closed) return;
        _authObservationUnavailable = true;
        _authObservationEpoch++;
        _synchronizeWallet(null, forceSessionChange: true);
      },
      onDone: () {
        if (_closed) return;
        _authObservationUnavailable = true;
        _authObservationEpoch++;
        _synchronizeWallet(null, forceSessionChange: true);
      },
    );
    unawaited(_initializeWalletScope());
  }

  final KomodoDefiSdk _kdfSdk;
  final MyOrdersService _myOrdersService;
  final Mm2Api _mm2Api;
  StreamSubscription<KdfUser?>? _authModeListener;
  List<MyOrder> _myOrders = [];
  List<Swap> _swaps = [];
  Timer? timer;
  bool _closed = false;
  final Stopwatch _fetchClock = Stopwatch()..start();
  Duration? _lastFetchElapsed;
  bool _hasLoadedInitialSwaps = false;
  String? _walletId;
  int _walletGeneration = 0;
  int _authObservationEpoch = 0;
  bool _authObservationUnavailable = false;
  int _fetchGeneration = 0;
  bool _backgroundFetchInProgress = false;
  static const int _maximumCachedOrderWallets = 16;
  final Map<String, List<MyOrder>> _verifiedOrdersByWallet = {};
  Future<CancelAllOrdersResult>? _cancelAllInFlight;
  String? _cancelAllTargetKey;
  final Map<String, Future<String?>> _cancelOrderInFlight = {};
  final Map<String, Future<RecoverFundsOfSwapResponse?>> _recoveryInFlight = {};
  final Map<String, Map<String, RecoverySubmissionStatus>>
  _recoveryStatusesByWallet = {};
  final StreamController<Map<String, RecoverySubmissionStatus>>
  _recoveryStatusController =
      StreamController<Map<String, RecoverySubmissionStatus>>.broadcast();

  Stream<Map<String, RecoverySubmissionStatus>> get outRecoveryStatuses =>
      _recoveryStatusController.stream;
  RecoverySubmissionStatus recoveryStatusFor(String uuid) {
    final normalizedUuid = normalizeTradingEntityUuid(uuid);
    if (normalizedUuid == null) return RecoverySubmissionStatus.idle;
    return _currentRecoveryStatuses[normalizedUuid] ??
        RecoverySubmissionStatus.idle;
  }

  Map<String, RecoverySubmissionStatus> get _currentRecoveryStatuses {
    final walletId = _walletId;
    if (walletId == null) return const {};
    return _recoveryStatusesByWallet.putIfAbsent(walletId, () => {});
  }

  static const Duration _pollingInterval = Duration(seconds: 10);
  static const Duration _backgroundFetchInterval = Duration(seconds: 45);
  static const int _initialSwapsLimit = 1000;
  static const int _refreshSwapsLimit = 250;

  final StreamController<List<MyOrder>> _myOrdersController =
      StreamController<List<MyOrder>>.broadcast();
  Sink<List<MyOrder>> get _inMyOrders => _myOrdersController.sink;
  Stream<List<MyOrder>> get outMyOrders => _myOrdersController.stream;
  final StreamController<bool> _ordersStaleController =
      StreamController<bool>.broadcast();
  bool _ordersAreStale = false;
  bool get ordersAreStale => _ordersAreStale;
  Stream<bool> get outOrdersAreStale => _ordersStaleController.stream;
  List<MyOrder> get myOrders => _myOrders;
  set myOrders(List<MyOrder> orderList) {
    final sorted = List<MyOrder>.of(orderList)
      ..sort((first, second) => second.createdAt - first.createdAt);
    _myOrders = List<MyOrder>.unmodifiable(sorted);
    if (!_closed) _inMyOrders.add(_myOrders);
  }

  final StreamController<List<Swap>> _swapsController =
      StreamController<List<Swap>>.broadcast();
  Sink<List<Swap>> get _inSwaps => _swapsController.sink;
  Stream<List<Swap>> get outSwaps => _swapsController.stream;
  List<Swap> get swaps => _swaps;
  set swaps(List<Swap> swapList) {
    final sorted = List<Swap>.of(swapList)
      ..sort(
        (first, second) =>
            (second.myInfo?.startedAt ?? 0) - (first.myInfo?.startedAt ?? 0),
      );
    _swaps = List<Swap>.unmodifiable(sorted);
    if (!_closed) _inSwaps.add(_swaps);
  }

  CancelAllOrdersResult? _lastCancelAllResult;
  final StreamController<CancelAllOrdersResult?> _cancelAllResultController =
      StreamController<CancelAllOrdersResult?>.broadcast();
  Stream<CancelAllOrdersResult?> get outCancelAllResult =>
      _cancelAllResultController.stream;
  CancelAllOrdersResult? get lastCancelAllResult => _lastCancelAllResult;

  Future<void> _initializeWalletScope() async {
    final observationEpoch = _authObservationEpoch;
    try {
      final user = await _kdfSdk.auth.currentUser;
      if (!_closed && observationEpoch == _authObservationEpoch) {
        _synchronizeWallet(user?.walletId.compoundId);
      }
    } catch (_) {
      if (!_closed && observationEpoch == _authObservationEpoch) {
        _synchronizeWallet(null);
      }
    }
  }

  void _synchronizeWallet(String? walletId, {bool forceSessionChange = false}) {
    if (_authObservationUnavailable) walletId = null;
    if (_closed || (!forceSessionChange && walletId == _walletId)) return;
    final previousWalletId = _walletId;
    if (previousWalletId != null) {
      final previousStatuses = _recoveryStatusesByWallet[previousWalletId];
      if (previousStatuses != null) {
        for (final entry in previousStatuses.entries.toList()) {
          if (entry.value == RecoverySubmissionStatus.submitting) {
            previousStatuses[entry.key] = RecoverySubmissionStatus.uncertain;
          }
        }
      }
    }
    _walletId = walletId;
    _walletGeneration++;
    _fetchGeneration++;
    _hasLoadedInitialSwaps = false;
    _lastFetchElapsed = null;
    _cancelAllInFlight = null;
    _cancelAllTargetKey = null;
    _cancelOrderInFlight.clear();
    _recoveryInFlight.clear();
    _lastCancelAllResult = null;
    final cachedOrders = walletId == null
        ? null
        : _verifiedOrdersByWallet[walletId];
    _setOrdersAreStale(cachedOrders != null);
    myOrders = cachedOrders ?? const [];
    swaps = const [];
    _cancelAllResultController.add(null);
    _recoveryStatusController.add(Map.unmodifiable(_currentRecoveryStatuses));
  }

  bool _isCurrentWallet(String walletId, int generation) {
    return !_closed && _walletId == walletId && _walletGeneration == generation;
  }

  Future<void> _requireFreshWallet(String walletId, int generation) async {
    if (_authObservationUnavailable ||
        !_isCurrentWallet(walletId, generation)) {
      throw const _TradingWalletChanged();
    }
    String? freshWalletId;
    try {
      freshWalletId = await freshKdfCurrentWalletId(_kdfSdk);
    } on Object {
      _authObservationUnavailable = true;
      _authObservationEpoch++;
      _synchronizeWallet(null, forceSessionChange: true);
      throw const _TradingWalletChanged();
    }
    if (freshWalletId != walletId || !_isCurrentWallet(walletId, generation)) {
      _synchronizeWallet(freshWalletId, forceSessionChange: true);
      throw const _TradingWalletChanged();
    }
  }

  Future<void> fetch() async {
    if (_closed || _authObservationUnavailable) return;
    final observationEpoch = _authObservationEpoch;
    KdfUser? user;
    try {
      user = await freshKdfCurrentUser(_kdfSdk);
    } catch (_) {
      if (!_closed && observationEpoch == _authObservationEpoch) {
        _authObservationUnavailable = true;
        _authObservationEpoch++;
        _synchronizeWallet(null, forceSessionChange: true);
      }
      return;
    }
    if (_closed || observationEpoch != _authObservationEpoch) return;
    final currentWalletId = user?.walletId.compoundId;
    _synchronizeWallet(currentWalletId);
    if (currentWalletId == null) {
      return;
    }

    final walletGeneration = _walletGeneration;
    final fetchGeneration = ++_fetchGeneration;
    final loadInitialSwaps = !_hasLoadedInitialSwaps;
    List<MyOrder>? fetchedOrders;
    try {
      fetchedOrders = await _myOrdersService.getOrders();
    } catch (_) {
      fetchedOrders = null;
    }
    if (!_isCurrentWallet(currentWalletId, walletGeneration) ||
        fetchGeneration != _fetchGeneration) {
      return;
    }
    if (fetchedOrders == null) {
      // Publish the failed refresh promptly even if the independent swaps or
      // auth recheck also fail. The previous order snapshot remains usable.
      _setOrdersAreStale(true);
    }
    final recentSwaps =
        await getRecentSwaps(
          MyRecentSwapsRequest(
            limit: loadInitialSwaps ? _initialSwapsLimit : _refreshSwapsLimit,
          ),
        ) ??
        const [];
    KdfUser? recheckedUser;
    try {
      recheckedUser = await freshKdfCurrentUser(_kdfSdk);
    } catch (_) {
      if (!_closed && observationEpoch == _authObservationEpoch) {
        _authObservationUnavailable = true;
        _authObservationEpoch++;
        _synchronizeWallet(null, forceSessionChange: true);
      }
      return;
    }
    if (recheckedUser?.walletId.compoundId != currentWalletId ||
        !_isCurrentWallet(currentWalletId, walletGeneration) ||
        fetchGeneration != _fetchGeneration) {
      return;
    }

    if (fetchedOrders != null) {
      myOrders = fetchedOrders;
      _rememberVerifiedOrders(currentWalletId, _myOrders);
      _setOrdersAreStale(false);
    }
    _hasLoadedInitialSwaps = true;
    final mergedSwaps = _mergeSwaps(_swaps, recentSwaps);
    swaps = mergedSwaps;
    _reconcileRecoveryStatuses(mergedSwaps);
    _lastFetchElapsed = _fetchClock.elapsed;
  }

  @override
  void dispose() {
    _closed = true;
    _authObservationUnavailable = true;
    _authModeListener?.cancel();
    timer?.cancel();
    _myOrdersController.close();
    _ordersStaleController.close();
    _swapsController.close();
    _cancelAllResultController.close();
    _recoveryStatusController.close();
    _verifiedOrdersByWallet.clear();
  }

  void _setOrdersAreStale(bool value) {
    if (_closed || _ordersAreStale == value) return;
    _ordersAreStale = value;
    _ordersStaleController.add(value);
  }

  void _rememberVerifiedOrders(String walletId, List<MyOrder> orders) {
    _verifiedOrdersByWallet.remove(walletId);
    _verifiedOrdersByWallet[walletId] = List<MyOrder>.unmodifiable(orders);
    while (_verifiedOrdersByWallet.length > _maximumCachedOrderWallets) {
      _verifiedOrdersByWallet.remove(_verifiedOrdersByWallet.keys.first);
    }
  }

  void runUpdate() {
    timer?.cancel();
    timer = Timer.periodic(_pollingInterval, (_) async {
      if (_closed) return;
      if (_backgroundFetchInProgress) return;
      if (!_shouldRunBackgroundFetch()) return;
      // TODO!: do not run for hidden login or HW

      _backgroundFetchInProgress = true;
      try {
        await fetch();
      } catch (e) {
        if (e is StateError && e.message.contains('disposed')) {
          _closed = true;
        } else {
          await log(
            'Unable to refresh trading activity',
            path: 'TradingEntitiesBloc.fetch',
            isError: true,
          );
        }
      } finally {
        _backgroundFetchInProgress = false;
      }
    });
  }

  bool _shouldRunBackgroundFetch() {
    if (_isTradingMenuActive) return true;
    final lastFetchElapsed = _lastFetchElapsed;
    if (lastFetchElapsed == null) return true;
    return _fetchClock.elapsed - lastFetchElapsed >= _backgroundFetchInterval;
  }

  bool get _isTradingMenuActive {
    final currentMenu = routingState.selectedMenu;
    return currentMenu == MainMenuValue.dex ||
        currentMenu == MainMenuValue.bridge;
  }

  List<Swap> _mergeSwaps(List<Swap> existing, List<Swap> incoming) {
    if (existing.isEmpty) return List.of(incoming);
    if (incoming.isEmpty) return List.of(existing);

    final merged = <String, Swap>{for (final swap in existing) swap.uuid: swap};
    for (final swap in incoming) {
      merged[swap.uuid] = swap;
    }
    return merged.values.toList();
  }

  Future<String?> cancelOrder(String uuid) async {
    final normalizedUuid = normalizeTradingEntityUuid(uuid);
    if (normalizedUuid == null || !canCancelOrder(normalizedUuid)) {
      return LocaleKeys.somethingWrong.tr();
    }
    final existing = _cancelOrderInFlight[normalizedUuid];
    if (existing != null) return existing;

    final operation = _cancelOrderForCurrentWallet(normalizedUuid);
    _cancelOrderInFlight[normalizedUuid] = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(_cancelOrderInFlight[normalizedUuid], operation)) {
          _cancelOrderInFlight.remove(normalizedUuid);
        }
      }),
    );
    return operation;
  }

  Future<String?> _cancelOrderForCurrentWallet(String uuid) async {
    final walletId = _walletId;
    final generation = _walletGeneration;
    if (walletId == null) return LocaleKeys.somethingWrong.tr();
    try {
      await _requireFreshWallet(walletId, generation);
      if (!canCancelOrder(uuid)) return LocaleKeys.somethingWrong.tr();
      final Map<String, dynamic> response = await _mm2Api.cancelOrder(
        CancelOrderRequest(uuid: uuid),
        beforeMutation: () async {
          await _requireFreshWallet(walletId, generation);
          if (!canCancelOrder(uuid)) throw const _TradingWalletChanged();
        },
      );
      await _requireFreshWallet(walletId, generation);
      return Mm2Api.isPositiveCancelOrderResponse(response)
          ? null
          : LocaleKeys.somethingWrong.tr();
    } catch (_) {
      return LocaleKeys.somethingWrong.tr();
    }
  }

  bool isCoinBusy(String coin) {
    return (_swaps
                .where((swap) => !swap.isCompleted)
                .where((swap) => swap.sellCoin == coin || swap.buyCoin == coin)
                .toList()
                .length +
            _myOrders
                .where((order) => order.base == coin || order.rel == coin)
                .toList()
                .length) >
        0;
  }

  bool hasActiveSwap(String coin) {
    return _swaps
        .where((swap) => !swap.isCompleted)
        .any((swap) => swap.sellCoin == coin || swap.buyCoin == coin);
  }

  bool hasOpenOrders(String coin) {
    return _myOrders.any((order) => order.base == coin || order.rel == coin);
  }

  int openOrdersCount(String coin) {
    return _myOrders
        .where((order) => order.base == coin || order.rel == coin)
        .length;
  }

  Future<void> cancelOrdersForCoin(String coin) async {
    final futures = _myOrders
        .where((o) => o.base == coin || o.rel == coin)
        .map((o) => cancelOrder(o.uuid));
    await Future.wait(futures);
  }

  double getPriceFromAmount(Rational sellAmount, Rational buyAmount) {
    final sellDoubleAmount = sellAmount.toDouble();
    final buyDoubleAmount = buyAmount.toDouble();

    if (!sellDoubleAmount.isFinite ||
        !buyDoubleAmount.isFinite ||
        sellDoubleAmount <= 0 ||
        buyDoubleAmount <= 0) {
      return 0;
    }
    final price = buyDoubleAmount / sellDoubleAmount;
    return price.isFinite && price > 0 ? price : 0;
  }

  String getTypeString(bool isTaker) =>
      isTaker ? LocaleKeys.takerOrder.tr() : LocaleKeys.makerOrder.tr();

  bool canCancelOrder(String uuid) {
    final normalizedUuid = normalizeTradingEntityUuid(uuid);
    if (normalizedUuid == null || _walletId == null) return false;
    return _myOrders.any(
      (order) =>
          order.cancelable &&
          normalizeTradingEntityUuid(order.uuid) == normalizedUuid,
    );
  }

  List<String> get cancellableOrderIds => List<String>.unmodifiable(
    _myOrders
        .where((order) => order.cancelable)
        .map((order) => normalizeTradingEntityUuid(order.uuid))
        .whereType<String>(),
  );

  bool canRecoverSwap(String uuid) {
    final normalizedUuid = normalizeTradingEntityUuid(uuid);
    if (normalizedUuid == null || _walletId == null) return false;
    return _swaps.any(
      (swap) =>
          normalizeTradingEntityUuid(swap.uuid) == normalizedUuid &&
          swap.recoverable,
    );
  }

  Swap? getSwap(String uuid) {
    final normalizedUuid = normalizeTradingEntityUuid(uuid);
    if (normalizedUuid == null) return null;
    return swaps.firstWhereOrNull(
      (swap) => normalizeTradingEntityUuid(swap.uuid) == normalizedUuid,
    );
  }

  double getProgressFillSwap(MyOrder order) {
    final List<Swap> swaps = (order.startedSwaps ?? [])
        .map((id) => getSwap(id))
        .whereType<Swap>()
        .toList();
    final double swapFill = swaps.fold(
      0,
      (previousValue, swap) => previousValue + (swap.myInfo?.myAmount ?? 0),
    );
    final baseAmount = order.baseAmount.toDouble();
    if (!baseAmount.isFinite || baseAmount <= 0 || !swapFill.isFinite) {
      return 0;
    }
    return (swapFill / baseAmount).clamp(0, 1).toDouble();
  }

  Future<CancelAllOrdersResult> cancelAllOrders() =>
      cancelExactOrders(cancellableOrderIds);

  Future<CancelAllOrdersResult> cancelExactOrders(Iterable<String> orderIds) {
    final orderSnapshot =
        orderIds
            .map(normalizeTradingEntityUuid)
            .whereType<String>()
            .toSet()
            .take(1000)
            .toList(growable: false)
          ..sort();
    final targetKey =
        '${_walletId ?? ''}:$_walletGeneration:'
        '${orderSnapshot.join(',')}';
    final existing = _cancelAllInFlight;
    if (existing != null) {
      if (_cancelAllTargetKey == targetKey) return existing;
      return Future.value(
        CancelAllOrdersResult(
          attemptedCount: orderSnapshot.length,
          cancelledCount: 0,
          failedCount: orderSnapshot.length,
          walletChanged: false,
        ),
      );
    }

    final operation = _cancelOrdersForCurrentWallet(orderSnapshot);
    _cancelAllInFlight = operation;
    _cancelAllTargetKey = targetKey;
    unawaited(
      operation.whenComplete(() {
        if (identical(_cancelAllInFlight, operation)) {
          _cancelAllInFlight = null;
          _cancelAllTargetKey = null;
        }
      }),
    );
    return operation;
  }

  Future<CancelAllOrdersResult> _cancelOrdersForCurrentWallet(
    List<String> orderSnapshot,
  ) async {
    final walletId = _walletId;
    final generation = _walletGeneration;
    if (walletId == null) {
      return _publishCancelAllResult(
        CancelAllOrdersResult(
          attemptedCount: orderSnapshot.length,
          cancelledCount: 0,
          failedCount: orderSnapshot.length,
          walletChanged: true,
        ),
      );
    }

    const maximumConcurrentCancellations = 8;
    final results = <String?>[];
    for (
      var offset = 0;
      offset < orderSnapshot.length;
      offset += maximumConcurrentCancellations
    ) {
      if (!_isCurrentWallet(walletId, generation)) break;
      final end = (offset + maximumConcurrentCancellations).clamp(
        0,
        orderSnapshot.length,
      );
      results.addAll(
        await Future.wait(orderSnapshot.sublist(offset, end).map(cancelOrder)),
      );
    }
    final walletChanged = !_isCurrentWallet(walletId, generation);
    final cancelledCount = walletChanged
        ? 0
        : results.where((error) => error == null).length;
    final result = CancelAllOrdersResult(
      attemptedCount: orderSnapshot.length,
      cancelledCount: cancelledCount,
      failedCount: walletChanged ? 0 : orderSnapshot.length - cancelledCount,
      walletChanged: walletChanged,
      uncertain: walletChanged,
    );
    return walletChanged ? result : _publishCancelAllResult(result);
  }

  CancelAllOrdersResult _publishCancelAllResult(CancelAllOrdersResult result) {
    if (!_closed) {
      _lastCancelAllResult = result;
      _cancelAllResultController.add(result);
    }
    return result;
  }

  Future<List<Swap>?> getRecentSwaps(MyRecentSwapsRequest request) async {
    final MyRecentSwapsResponse? response = await _mm2Api.getMyRecentSwaps(
      request,
    );
    if (response == null) {
      return null;
    }

    return response.result.swaps;
  }

  Future<RecoverFundsOfSwapResponse?> recoverFundsOfSwap(String uuid) async {
    final normalizedUuid = normalizeTradingEntityUuid(uuid);
    if (normalizedUuid == null || !canRecoverSwap(normalizedUuid)) return null;
    final status =
        _currentRecoveryStatuses[normalizedUuid] ??
        RecoverySubmissionStatus.idle;
    if (status != RecoverySubmissionStatus.idle) {
      return null;
    }
    final existing = _recoveryInFlight[normalizedUuid];
    if (existing != null) return existing;

    final operation = _recoverFundsForCurrentWallet(normalizedUuid);
    _recoveryInFlight[normalizedUuid] = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(_recoveryInFlight[normalizedUuid], operation)) {
          _recoveryInFlight.remove(normalizedUuid);
        }
      }),
    );
    return operation;
  }

  Future<RecoverFundsOfSwapResponse?> _recoverFundsForCurrentWallet(
    String uuid,
  ) async {
    final walletId = _walletId;
    final generation = _walletGeneration;
    if (walletId == null) return null;
    _setRecoveryStatus(uuid, RecoverySubmissionStatus.submitting);
    try {
      await _requireFreshWallet(walletId, generation);
      if (!canRecoverSwap(uuid)) {
        _resolveRecoveryPreflightAbort(uuid);
        return null;
      }
      final response = await _mm2Api.recoverFundsOfSwap(
        RecoverFundsOfSwapRequest(uuid: uuid),
        beforeMutation: () async {
          await _requireFreshWallet(walletId, generation);
          if (!canRecoverSwap(uuid)) throw const _TradingWalletChanged();
        },
      );
      await _requireFreshWallet(walletId, generation);
      if (response == null) {
        _setRecoveryStatus(uuid, RecoverySubmissionStatus.uncertain);
        return null;
      }
      _setRecoveryStatus(uuid, RecoverySubmissionStatus.accepted);
      return response;
    } catch (_) {
      if (_isCurrentWallet(walletId, generation)) {
        _setRecoveryStatus(uuid, RecoverySubmissionStatus.uncertain);
      }
      return null;
    }
  }

  void _setRecoveryStatus(String uuid, RecoverySubmissionStatus status) {
    if (_closed || _walletId == null) return;
    _currentRecoveryStatuses[uuid] = status;
    _recoveryStatusController.add(Map.unmodifiable(_currentRecoveryStatuses));
  }

  void _resolveRecoveryPreflightAbort(String uuid) {
    final authoritativeSwap = _swaps.firstWhereOrNull(
      (swap) => normalizeTradingEntityUuid(swap.uuid) == uuid,
    );
    _setRecoveryStatus(
      uuid,
      authoritativeSwap != null && !authoritativeSwap.recoverable
          ? RecoverySubmissionStatus.accepted
          : RecoverySubmissionStatus.uncertain,
    );
  }

  void _reconcileRecoveryStatuses(List<Swap> authoritativeSwaps) {
    final recoveryStatuses = _currentRecoveryStatuses;
    if (recoveryStatuses.isEmpty) return;
    var changed = false;
    for (final entry in recoveryStatuses.entries.toList()) {
      if (entry.value != RecoverySubmissionStatus.uncertain) continue;
      final swap = authoritativeSwaps.firstWhereOrNull(
        (candidate) => normalizeTradingEntityUuid(candidate.uuid) == entry.key,
      );
      if (swap != null && !swap.recoverable) {
        recoveryStatuses[entry.key] = RecoverySubmissionStatus.accepted;
        changed = true;
      }
    }
    if (changed && !_closed) {
      _recoveryStatusController.add(Map.unmodifiable(recoveryStatuses));
    }
  }

  Future<Rational?> getMaxTakerVolume(String coinAbbr) async {
    final MaxTakerVolResponse? response = await _mm2Api.getMaxTakerVolume(
      MaxTakerVolRequest(coin: coinAbbr),
    );
    if (response == null) {
      return null;
    }

    return fract2rat(response.result.toJson());
  }
}

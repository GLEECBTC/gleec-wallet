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
import 'package:web_dex/shared/utils/kdf_wallet_authority.dart';
import 'package:web_dex/shared/utils/utils.dart';

/// The live wallet stopped being the one a trading mutation was bound to.
final class _TradingWalletChanged implements Exception {
  const _TradingWalletChanged();
}

/// Lifecycle of a single `recover_funds_of_swap` submission.
///
/// [uncertain] is deliberately distinct from failure: the request may have
/// reached KDF and moved funds even though this client never saw the reply.
/// Re-submitting from that state could double-spend the recovery, so the
/// button stays locked until a later swap snapshot resolves it.
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
      (user) => _onAuthObservation(user?.walletId.compoundId),
      onError: (_) => _onAuthObservation(null, unavailable: true),
      onDone: () => _onAuthObservation(null, unavailable: true),
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
  DateTime? _lastFetchAt;
  bool _hasLoadedInitialSwaps = false;

  /// Compound ID of the wallet every cached order, swap and in-flight mutation
  /// below belongs to. `null` means signed out, which disables every guard.
  String? _walletId;

  /// Bumped on every wallet transition, including re-auth into the same
  /// wallet. Async work captures it and refuses to publish or mutate if it has
  /// moved on, so a late response can never land against the wrong session.
  int _walletGeneration = 0;

  /// Bumped on every auth observation so a stale [_initializeWalletScope] or
  /// [fetch] recheck cannot overwrite a newer observation.
  int _authObservationEpoch = 0;

  /// Set when the auth stream errors or closes. Trading is disabled entirely
  /// while true: we cannot prove which wallet, if any, is live.
  bool _authObservationUnavailable = false;
  int _fetchGeneration = 0;

  final Map<String, Future<String?>> _cancelOrderInFlight = {};
  final Map<String, Future<RecoverFundsOfSwapResponse?>> _recoveryInFlight = {};
  final Map<String, Map<String, RecoverySubmissionStatus>>
  _recoveryStatusesByWallet = {};
  final StreamController<Map<String, RecoverySubmissionStatus>>
  _recoveryStatusController =
      StreamController<Map<String, RecoverySubmissionStatus>>.broadcast();

  /// Per-swap recovery lifecycle for the live wallet, keyed by canonical UUID.
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
  List<MyOrder> get myOrders => _myOrders;
  set myOrders(List<MyOrder> orderList) {
    orderList.sort((first, second) => second.createdAt - first.createdAt);
    _myOrders = orderList;
    _inMyOrders.add(_myOrders);
  }

  final StreamController<List<Swap>> _swapsController =
      StreamController<List<Swap>>.broadcast();
  Sink<List<Swap>> get _inSwaps => _swapsController.sink;
  Stream<List<Swap>> get outSwaps => _swapsController.stream;
  List<Swap> get swaps => _swaps;
  set swaps(List<Swap> swapList) {
    swapList.sort(
      (first, second) =>
          (second.myInfo?.startedAt ?? 0) - (first.myInfo?.startedAt ?? 0),
    );
    _swaps = swapList;
    _inSwaps.add(_swaps);
  }

  void _onAuthObservation(String? walletId, {bool unavailable = false}) {
    if (_closed) return;
    _authObservationUnavailable = unavailable;
    _authObservationEpoch++;
    _synchronizeWallet(walletId, forceSessionChange: true);
  }

  Future<void> _initializeWalletScope() async {
    final observationEpoch = _authObservationEpoch;
    String? walletId;
    try {
      walletId = (await _kdfSdk.auth.currentUser)?.walletId.compoundId;
    } catch (_) {
      walletId = null;
    }
    if (_closed || observationEpoch != _authObservationEpoch) return;
    _synchronizeWallet(walletId);
  }

  /// Rebinds every piece of wallet-scoped state to [walletId].
  ///
  /// [forceSessionChange] treats a same-ID observation as a new session, which
  /// is what a sign-out/sign-in into the same wallet actually is.
  void _synchronizeWallet(String? walletId, {bool forceSessionChange = false}) {
    if (_authObservationUnavailable) walletId = null;
    if (_closed || (!forceSessionChange && walletId == _walletId)) return;

    // A submission we can no longer observe is not a failure — it may have
    // been applied by KDF. Preserve that ambiguity against the old wallet.
    final previousStatuses = _recoveryStatusesByWallet[_walletId];
    if (previousStatuses != null) {
      for (final entry in previousStatuses.entries.toList()) {
        if (entry.value == RecoverySubmissionStatus.submitting) {
          previousStatuses[entry.key] = RecoverySubmissionStatus.uncertain;
        }
      }
    }

    _walletId = walletId;
    _walletGeneration++;
    _fetchGeneration++;
    _hasLoadedInitialSwaps = false;
    _lastFetchAt = null;
    _cancelOrderInFlight.clear();
    _recoveryInFlight.clear();
    myOrders = [];
    swaps = [];
    _recoveryStatusController.add(Map.unmodifiable(_currentRecoveryStatuses));
  }

  bool _isCurrentWallet(String walletId, int generation) {
    return !_closed && _walletId == walletId && _walletGeneration == generation;
  }

  /// Asserts that [walletId]/[generation] is still KDF's live wallet, reading
  /// past the SDK's auth cache. Throws [_TradingWalletChanged] otherwise.
  Future<void> _requireFreshWallet(String walletId, int generation) async {
    if (_authObservationUnavailable ||
        !_isCurrentWallet(walletId, generation)) {
      throw const _TradingWalletChanged();
    }
    String? freshWalletId;
    try {
      freshWalletId = await freshKdfCurrentWalletId(_kdfSdk);
    } on Object {
      _onAuthObservation(null, unavailable: true);
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
        _onAuthObservation(null, unavailable: true);
      }
      return;
    }
    if (_closed || observationEpoch != _authObservationEpoch) return;
    final currentWalletId = user?.walletId.compoundId;
    _synchronizeWallet(currentWalletId);
    if (currentWalletId == null) return;

    final walletGeneration = _walletGeneration;
    final fetchGeneration = ++_fetchGeneration;
    final loadInitialSwaps = !_hasLoadedInitialSwaps;
    final fetchedOrders = await _myOrdersService.getOrders() ?? <MyOrder>[];
    final recentSwaps =
        await getRecentSwaps(
          MyRecentSwapsRequest(
            limit: loadInitialSwaps ? _initialSwapsLimit : _refreshSwapsLimit,
          ),
        ) ??
        <Swap>[];

    // Both RPCs above are wallet-scoped by the daemon's current session, so a
    // wallet change mid-fetch means this data describes a wallet we are no
    // longer showing. Drop it rather than publishing it against the new one.
    if (!_isCurrentWallet(currentWalletId, walletGeneration) ||
        fetchGeneration != _fetchGeneration) {
      return;
    }

    myOrders = fetchedOrders;
    _hasLoadedInitialSwaps = true;
    final mergedSwaps = _mergeSwaps(_swaps, recentSwaps);
    swaps = mergedSwaps;
    _reconcileRecoveryStatuses(mergedSwaps);
    _lastFetchAt = DateTime.now();
  }

  @override
  void dispose() {
    _closed = true;
    _authObservationUnavailable = true;
    _authModeListener?.cancel();
    timer?.cancel();
    _myOrdersController.close();
    _swapsController.close();
    _recoveryStatusController.close();
  }

  void runUpdate() {
    bool updateInProgress = false;

    timer = Timer.periodic(_pollingInterval, (_) async {
      if (_closed) return;
      if (updateInProgress) return;
      if (!_shouldRunBackgroundFetch()) return;
      // TODO!: do not run for hidden login or HW

      updateInProgress = true;
      try {
        await fetch();
      } catch (e) {
        if (e is StateError && e.message.contains('disposed')) {
          _closed = true;
        } else {
          await log('fetch error: $e', path: 'TradingEntitiesBloc.fetch');
        }
      } finally {
        updateInProgress = false;
      }
    });
  }

  bool _shouldRunBackgroundFetch() {
    if (_isTradingMenuActive) return true;
    if (_lastFetchAt == null) return true;
    return DateTime.now().difference(_lastFetchAt!) >= _backgroundFetchInterval;
  }

  bool get _isTradingMenuActive {
    final currentMenu = routingState.selectedMenu;
    return currentMenu == MainMenuValue.dex ||
        currentMenu == MainMenuValue.bridge;
  }

  List<Swap> _mergeSwaps(List<Swap> existing, List<Swap> incoming) {
    if (existing.isEmpty) return incoming;
    if (incoming.isEmpty) return existing;

    final merged = <String, Swap>{for (final swap in existing) swap.uuid: swap};
    for (final swap in incoming) {
      merged[swap.uuid] = swap;
    }
    return merged.values.toList();
  }

  /// Cancels [uuid] at most once.
  ///
  /// Concurrent callers share the single in-flight request, and the wallet is
  /// re-verified immediately before the RPC leaves the client.
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
      // Mm2Api reports transport failures as a non-String `error` payload, so
      // normalise anything present to the generic message.
      return response['error'] == null ? null : LocaleKeys.somethingWrong.tr();
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

    if (sellDoubleAmount == 0 || buyDoubleAmount == 0) return 0;
    return buyDoubleAmount / sellDoubleAmount;
  }

  String getTypeString(bool isTaker) =>
      isTaker ? LocaleKeys.takerOrder.tr() : LocaleKeys.makerOrder.tr();

  /// Whether [uuid] names an order the live wallet may still cancel.
  ///
  /// This is the single source of truth for both the button's enabled state
  /// and the bloc's own pre-RPC check, so the UI can never offer an action the
  /// bloc would refuse.
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

  /// Whether [uuid] names a swap of the live wallet that KDF still reports as
  /// recoverable. Once KDF stops reporting it, recovery has been applied.
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
    return swapFill / order.baseAmount.toDouble();
  }

  Future<void> cancelAllOrders() async {
    await Future.wait(cancellableOrderIds.map(cancelOrder));
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

  /// Submits `recover_funds_of_swap` for [uuid] at most once.
  ///
  /// Returns `null` without contacting KDF when the swap is not recoverable by
  /// the live wallet, or when a previous submission has not resolved to
  /// [RecoverySubmissionStatus.idle].
  Future<RecoverFundsOfSwapResponse?> recoverFundsOfSwap(String uuid) async {
    final normalizedUuid = normalizeTradingEntityUuid(uuid);
    if (normalizedUuid == null || !canRecoverSwap(normalizedUuid)) return null;
    if (recoveryStatusFor(normalizedUuid) != RecoverySubmissionStatus.idle) {
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
      if (response == null) {
        // The request may still have been applied by KDF; only a later swap
        // snapshot can tell us. Never re-open the button on this path.
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

  /// Resolves a submission aborted between `submitting` and the RPC.
  ///
  /// If the authoritative snapshot already says the swap is no longer
  /// recoverable, an earlier recovery succeeded; otherwise we cannot tell
  /// whether this attempt reached KDF.
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

  /// Promotes `uncertain` submissions to `accepted` once KDF stops reporting
  /// the swap as recoverable — the only evidence that the recovery landed.
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

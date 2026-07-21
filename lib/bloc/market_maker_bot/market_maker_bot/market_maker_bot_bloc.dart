import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_bot/market_maker_bot_repository.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_bot/market_maker_bot_status.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_bot/market_maker_bot_wallet_session.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_order_list/market_maker_bot_order_list_repository.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_order_list/trade_pair.dart';
import 'package:web_dex/bloc/settings/settings_repository.dart';
import 'package:web_dex/shared/utils/kdf_wallet_authority.dart';
import 'package:web_dex/mm2/mm2_api/rpc/market_maker_bot/market_maker_bot_parameters.dart';
import 'package:web_dex/mm2/mm2_api/rpc/market_maker_bot/trade_coin_pair_config.dart';
import 'package:web_dex/bloc/analytics/analytics_repo.dart';
import 'package:web_dex/analytics/events/market_bot_events.dart';
import 'package:get_it/get_it.dart';

part 'market_maker_bot_event.dart';
part 'market_maker_bot_state.dart';

enum MarketMakerBotStopOutcome { stopped, failed, uncertain, walletChanged }

enum _AcceptedStartRecoveryOutcome { stopped, uncertain, walletChanged }

final class MarketMakerBotStopResult extends Equatable {
  const MarketMakerBotStopResult(this.outcome);

  final MarketMakerBotStopOutcome outcome;

  bool get isStopped => outcome == MarketMakerBotStopOutcome.stopped;
  bool get walletChanged => outcome == MarketMakerBotStopOutcome.walletChanged;
  bool get uncertain => outcome == MarketMakerBotStopOutcome.uncertain;

  @override
  List<Object> get props => [outcome];
}

final class _MarketMakerBotWalletChanged implements Exception {
  const _MarketMakerBotWalletChanged();
}

/// BLoC responsible for starting, stopping and updating the market maker bot.
/// The bot is started with the parameters defined in the settings.
/// All active orders are cancelled when the bot is stopped or updated.
class MarketMakerBotBloc
    extends Bloc<MarketMakerBotEvent, MarketMakerBotState> {
  MarketMakerBotBloc(
    MarketMakerBotRepository marketMaketBotRepository,
    MarketMakerBotOrderListRepository orderRepository,
    KomodoDefiSdk kdfSdk,
  ) : _botRepository = marketMaketBotRepository,
      _orderRepository = orderRepository,
      _kdfSdk = kdfSdk,
      super(const MarketMakerBotState.initial()) {
    on<MarketMakerBotEvent>(_onEvent, transformer: sequential());
    _startAuthObservation();
    unawaited(_initializeWalletScope());
  }

  void _startAuthObservation() {
    if (isClosed || _closing) return;
    unawaited(_authSubscription?.cancel());
    _authSubscription = _kdfSdk.auth.watchCurrentUser().listen(
      (user) {
        _authResubscribeTimer?.cancel();
        _authObservationUnavailable = false;
        _authObservationEpoch++;
        _synchronizeWallet(user?.walletId.compoundId, forceSessionChange: true);
      },
      onError: (_) {
        _failClosedAuthObservation();
      },
      onDone: _failClosedAuthObservation,
    );
  }

  final MarketMakerBotRepository _botRepository;
  final MarketMakerBotOrderListRepository _orderRepository;
  final KomodoDefiSdk _kdfSdk;
  StreamSubscription<KdfUser?>? _authSubscription;
  Timer? _authResubscribeTimer;
  String? _walletId;
  int _walletGeneration = 0;
  int _authObservationEpoch = 0;
  bool _authObservationUnavailable = false;
  Future<MarketMakerBotCancellationResult>? _cancellationInFlight;
  Completer<MarketMakerBotCancellationResult>? _cancellationCompleter;
  String? _cancellationTargetKey;
  int _cancellationTargetCount = 0;
  bool _cancellationAwaitingReconciliation = false;
  MarketMakerBotOrderOwnership? _orderOwnership;
  MarketMakerBotOrderOwnership? _signedOutOrderOwnership;
  _PendingAcceptedStart? _pendingAcceptedStart;
  _PendingAcceptedStart? _signedOutPendingAcceptedStart;
  Future<MarketMakerBotStopResult>? _stopInFlight;
  Completer<MarketMakerBotStopResult>? _stopCompleter;
  MarketMakerBotWalletSession? _stopSession;
  bool _startOrUpdatePending = false;
  bool _configurationMutationInFlight = false;
  Completer<void>? _configurationMutationCompletion;
  bool _closing = false;
  MarketMakerBotWalletSession? _signedOutStopOrigin;
  MarketMakerBotWalletSession? _pendingSignedOutStopOrigin;
  MarketMakerBotWalletSession? _pendingAuthRecoverySession;
  Object? _pendingAuthRecoveryToken;
  MarketMakerBotWalletSession? _observerLossStopOrigin;
  MarketMakerBotOrderOwnership? _observerLossOrderOwnership;
  _PendingAcceptedStart? _observerLossPendingAcceptedStart;
  MarketMakerBotWalletSession? _pendingObserverLossStopOrigin;

  bool get _signedOutStopPending => _pendingSignedOutStopOrigin != null;

  bool get _authRecoveryStopPending =>
      _pendingAuthRecoverySession != null && _pendingAuthRecoveryToken != null;

  bool get _observerLossStopPending => _pendingObserverLossStopOrigin != null;

  Future<void> _onEvent(
    MarketMakerBotEvent event,
    Emitter<MarketMakerBotState> emit,
  ) async {
    switch (event) {
      case MarketMakerBotStartRequested():
        await _onStartRequested(event, emit);
      case MarketMakerBotStopRequested():
        await _onStopRequested(event, emit);
      case MarketMakerBotOrderUpdateRequested():
        await _onOrderUpdateRequested(event, emit);
      case MarketMakerBotOrderCancelRequested():
        await _onOrderCancelRequested(event, emit);
      case MarketMakerBotSessionChanged():
        emit(const MarketMakerBotState.initial());
    }
  }

  MarketMakerBotWalletSession? captureWalletSession() {
    final walletId = _walletId;
    if (walletId == null) return null;
    return MarketMakerBotWalletSession(
      walletId: walletId,
      generation: _walletGeneration,
    );
  }

  MarketMakerBotOrderOwnership? captureOrderOwnership(
    MarketMakerBotWalletSession walletSession,
  ) {
    return _isCurrentWalletSession(walletSession) ? _orderOwnership : null;
  }

  Future<bool> isFreshWalletSession(
    MarketMakerBotWalletSession walletSession,
  ) async {
    try {
      await _requireFreshWalletSession(walletSession);
      return true;
    } on Object {
      return false;
    }
  }

  bool isConfigurationMutationSafe(MarketMakerBotWalletSession walletSession) {
    return _isConfigurationMutationSafe(walletSession, allowHeldLease: false);
  }

  Future<bool> runStoppedConfigurationMutation({
    required MarketMakerBotWalletSession walletSession,
    required Future<void> Function(Future<void> Function() beforeWrite)
    mutation,
  }) async {
    if (!isConfigurationMutationSafe(walletSession)) return false;
    final completion = Completer<void>();
    _configurationMutationCompletion = completion;
    _configurationMutationInFlight = true;
    try {
      await _requireFreshWalletSession(walletSession);
      if (!_isConfigurationMutationSafe(walletSession, allowHeldLease: true)) {
        return false;
      }
      await mutation(() async {
        if (!_isConfigurationMutationSafe(
          walletSession,
          allowHeldLease: true,
        )) {
          throw const _MarketMakerBotWalletChanged();
        }
        await _requireFreshWalletSession(walletSession);
      });
      await _requireFreshWalletSession(walletSession);
      return _isConfigurationMutationSafe(walletSession, allowHeldLease: true);
    } finally {
      if (identical(_configurationMutationCompletion, completion)) {
        _configurationMutationInFlight = false;
        _configurationMutationCompletion = null;
        completion.complete();
      }
    }
  }

  bool _isConfigurationMutationSafe(
    MarketMakerBotWalletSession walletSession, {
    required bool allowHeldLease,
  }) {
    return !isClosed &&
        _isCurrentWalletSession(walletSession) &&
        state.lifecycleProvenStopped &&
        !state.isUpdating &&
        !_startOrUpdatePending &&
        (allowHeldLease || !_configurationMutationInFlight) &&
        _stopInFlight == null &&
        !_signedOutStopPending &&
        !_authRecoveryStopPending &&
        !_observerLossStopPending &&
        _cancellationInFlight == null &&
        !_cancellationAwaitingReconciliation;
  }

  bool requestStart({
    MarketMakerBotWalletSession? walletSession,
    required Iterable<TradeCoinPairConfig> expectedTradePairs,
  }) {
    final session = walletSession ?? captureWalletSession();
    final frozenTradePairs = List<TradeCoinPairConfig>.unmodifiable(
      expectedTradePairs,
    );
    if (!_isCurrentWalletSession(session) ||
        isClosed ||
        state.isRunning ||
        state.isUpdating ||
        _startOrUpdatePending ||
        _configurationMutationInFlight ||
        _signedOutStopPending ||
        _authRecoveryStopPending ||
        _observerLossStopPending ||
        _stopInFlight != null ||
        _cancellationInFlight != null ||
        frozenTradePairs.isEmpty) {
      return false;
    }
    _startOrUpdatePending = true;
    add(
      MarketMakerBotStartRequested(
        walletSession: session,
        expectedTradePairs: frozenTradePairs,
      ),
    );
    return true;
  }

  Future<MarketMakerBotStopResult> stopAndWait({
    required MarketMakerBotWalletSession walletSession,
    Iterable<TradeCoinPairConfig>? expectedTradePairs,
  }) {
    if (!_isCurrentWalletSession(walletSession)) {
      return Future.value(
        const MarketMakerBotStopResult(MarketMakerBotStopOutcome.walletChanged),
      );
    }
    final existing = _stopInFlight;
    if (existing != null) {
      return _stopSession == walletSession
          ? existing
          : Future.value(
              const MarketMakerBotStopResult(
                MarketMakerBotStopOutcome.walletChanged,
              ),
            );
    }
    if (isClosed ||
        state.isUpdating ||
        _startOrUpdatePending ||
        _configurationMutationInFlight ||
        _signedOutStopPending ||
        _authRecoveryStopPending ||
        _observerLossStopPending ||
        _cancellationInFlight != null) {
      return Future.value(
        const MarketMakerBotStopResult(MarketMakerBotStopOutcome.failed),
      );
    }

    final completion = Completer<MarketMakerBotStopResult>();
    final rawOperation = completion.future;
    final operation = _configureStopOperation(
      session: walletSession,
      completion: completion,
      expectedTradePairs: expectedTradePairs == null
          ? null
          : List<TradeCoinPairConfig>.unmodifiable(expectedTradePairs),
    );
    _stopCompleter = completion;
    _stopInFlight = operation;
    _stopSession = walletSession;
    unawaited(
      rawOperation.whenComplete(() {
        if (identical(_stopCompleter, completion)) {
          _stopCompleter = null;
          _stopInFlight = null;
          _stopSession = null;
        }
      }),
    );
    return operation;
  }

  Future<MarketMakerBotStopResult> _configureStopOperation({
    required MarketMakerBotWalletSession session,
    required Completer<MarketMakerBotStopResult> completion,
    required List<TradeCoinPairConfig>? expectedTradePairs,
  }) async {
    try {
      await _requireWalletSession(session);
      final config = await _botRepository.loadStoredConfig();
      await _requireWalletSession(session);
      final currentTradePairs = _configuredPairs(config, allowEmpty: true);
      if (expectedTradePairs != null &&
          !_sameTradePairConfigs(expectedTradePairs, currentTradePairs)) {
        throw const MarketMakerBotOrderOwnershipUnavailable();
      }
      final frozenTradePairs = expectedTradePairs ?? currentTradePairs;
      final operation = completion.future.timeout(
        _lifecycleDeadline(config.botRefreshRate),
        onTimeout: () =>
            const MarketMakerBotStopResult(MarketMakerBotStopOutcome.uncertain),
      );
      add(
        MarketMakerBotStopRequested(
          walletSession: session,
          expectedTradePairs: frozenTradePairs,
          completion: completion,
        ),
      );
      return await operation;
    } on _MarketMakerBotWalletChanged {
      const result = MarketMakerBotStopResult(
        MarketMakerBotStopOutcome.walletChanged,
      );
      if (!completion.isCompleted) completion.complete(result);
      return result;
    } on Object {
      const result = MarketMakerBotStopResult(MarketMakerBotStopOutcome.failed);
      if (!completion.isCompleted) completion.complete(result);
      return result;
    }
  }

  bool requestOrderUpdate(
    TradeCoinPairConfig tradePair, {
    MarketMakerBotWalletSession? walletSession,
    TradeCoinPairConfig? originalConfig,
  }) {
    final session = walletSession ?? captureWalletSession();
    if (!_isCurrentWalletSession(session) ||
        isClosed ||
        state.isUpdating ||
        _startOrUpdatePending ||
        _configurationMutationInFlight ||
        _signedOutStopPending ||
        _authRecoveryStopPending ||
        _observerLossStopPending ||
        _stopInFlight != null ||
        _cancellationInFlight != null) {
      return false;
    }
    _startOrUpdatePending = true;
    add(
      MarketMakerBotOrderUpdateRequested(
        tradePair,
        walletSession: session,
        originalConfig: originalConfig,
      ),
    );
    return true;
  }

  Future<MarketMakerBotCancellationResult> cancelOrdersAndWait(
    Iterable<TradePair> tradePairs, {
    required MarketMakerBotWalletSession? walletSession,
  }) {
    final uniquePairs = <String, TradePair>{
      for (final pair in tradePairs) pair.config.name: pair,
    };
    final names = uniquePairs.keys.toList()..sort();
    final snapshot = List<TradePair>.unmodifiable(
      names.map((name) => uniquePairs[name]!),
    );
    final session = walletSession;
    if (!_isCurrentWalletSession(session)) {
      return Future.value(_walletChangedCancellationResult(snapshot.length));
    }
    final targetKey =
        '${session!.walletId}:${session.generation}:'
        '${snapshot.map((pair) => pair.config.name).join('|')}';
    if (_cancellationAwaitingReconciliation) {
      return Future.value(_uncertainCancellationResult(snapshot.length));
    }
    final existing = _cancellationInFlight;
    if (existing != null) {
      if (_cancellationTargetKey == targetKey) return existing;
      return Future.value(
        MarketMakerBotCancellationResult(
          requestedCount: snapshot.length,
          completedCount: 0,
          failedCount: snapshot.length,
          uncertainCount: 0,
        ),
      );
    }
    final ownership = _orderOwnership;
    if (isClosed ||
        state.isUpdating ||
        _startOrUpdatePending ||
        _configurationMutationInFlight ||
        _signedOutStopPending ||
        _authRecoveryStopPending ||
        _observerLossStopPending ||
        _stopInFlight != null ||
        snapshot.isEmpty ||
        ownership == null ||
        snapshot.any((pair) => !ownership.matchesProjectedPair(pair))) {
      return Future.value(
        MarketMakerBotCancellationResult(
          requestedCount: snapshot.length,
          completedCount: 0,
          failedCount: snapshot.length,
          uncertainCount: 0,
        ),
      );
    }
    final completion = Completer<MarketMakerBotCancellationResult>();
    final rawOperation = completion.future;
    final operation = _configureCancellationOperation(
      snapshot: snapshot,
      session: session,
      completion: completion,
    );
    _cancellationCompleter = completion;
    _cancellationInFlight = operation;
    _cancellationTargetKey = targetKey;
    _cancellationTargetCount = snapshot.length;
    unawaited(
      rawOperation.whenComplete(() {
        if (identical(_cancellationCompleter, completion)) {
          _cancellationCompleter = null;
          _cancellationInFlight = null;
          _cancellationTargetKey = null;
          _cancellationTargetCount = 0;
          _cancellationAwaitingReconciliation = false;
        }
      }),
    );
    return operation;
  }

  Future<MarketMakerBotCancellationResult> _configureCancellationOperation({
    required List<TradePair> snapshot,
    required MarketMakerBotWalletSession session,
    required Completer<MarketMakerBotCancellationResult> completion,
  }) async {
    try {
      await _requireWalletSession(session);
      final config = await _botRepository.loadStoredConfig();
      await _requireWalletSession(session);
      final operation = completion.future.timeout(
        _cancellationLifecycleDeadline(config.botRefreshRate),
        onTimeout: () {
          if (identical(_cancellationCompleter, completion)) {
            // The event may still be mutating. Block another destructive
            // request until its raw completion reconciles.
            _cancellationInFlight = null;
            _cancellationAwaitingReconciliation = true;
          }
          return _uncertainCancellationResult(snapshot.length);
        },
      );
      add(
        MarketMakerBotOrderCancelRequested(
          snapshot,
          walletSession: session,
          completion: completion,
        ),
      );
      return await operation;
    } on _MarketMakerBotWalletChanged {
      final result = _walletChangedCancellationResult(snapshot.length);
      if (!completion.isCompleted) completion.complete(result);
      return result;
    } on Object {
      final result = MarketMakerBotCancellationResult(
        requestedCount: snapshot.length,
        completedCount: 0,
        failedCount: snapshot.length,
        uncertainCount: 0,
      );
      if (!completion.isCompleted) completion.complete(result);
      return result;
    }
  }

  MarketMakerBotCancellationResult _uncertainCancellationResult(int count) {
    return MarketMakerBotCancellationResult(
      requestedCount: count,
      completedCount: 0,
      failedCount: 0,
      uncertainCount: count,
    );
  }

  MarketMakerBotCancellationResult _walletChangedCancellationResult(int count) {
    return MarketMakerBotCancellationResult(
      requestedCount: count,
      completedCount: 0,
      failedCount: 0,
      uncertainCount: count,
      walletChanged: true,
    );
  }

  @override
  Future<void> close() async {
    _closing = true;
    final completion = _cancellationCompleter;
    if (completion != null && !completion.isCompleted) {
      completion.complete(
        _uncertainCancellationResult(_cancellationTargetCount),
      );
    }
    final stopCompletion = _stopCompleter;
    if (stopCompletion != null && !stopCompletion.isCompleted) {
      stopCompletion.complete(
        const MarketMakerBotStopResult(MarketMakerBotStopOutcome.uncertain),
      );
    }
    await _authSubscription?.cancel();
    _authResubscribeTimer?.cancel();
    return super.close();
  }

  Future<void> _initializeWalletScope() async {
    final observationEpoch = _authObservationEpoch;
    try {
      final user = await _kdfSdk.auth.currentUser;
      if (!isClosed && !_closing && observationEpoch == _authObservationEpoch) {
        _synchronizeWallet(user?.walletId.compoundId);
      }
    } on Object {
      if (!isClosed && !_closing && observationEpoch == _authObservationEpoch) {
        _synchronizeWallet(null);
      }
    }
  }

  void _failClosedAuthObservation() {
    if (isClosed || _closing) return;
    if (_authObservationUnavailable) {
      _scheduleAuthResubscribe();
      return;
    }
    final previousSession = captureWalletSession();
    final previousOwnership = _orderOwnership;
    final previousPendingStart = _pendingAcceptedStart;
    _authObservationEpoch++;
    _authObservationUnavailable = true;
    if (previousSession != null &&
        (previousOwnership != null || previousPendingStart != null)) {
      _observerLossStopOrigin = previousSession;
      _observerLossOrderOwnership = previousOwnership;
      _observerLossPendingAcceptedStart = previousPendingStart;
    } else {
      _observerLossStopOrigin = null;
      _observerLossOrderOwnership = null;
      _observerLossPendingAcceptedStart = null;
    }
    _walletId = null;
    _walletGeneration++;
    _orderOwnership = null;
    _pendingAcceptedStart = null;
    final completion = _cancellationCompleter;
    if (completion != null && !completion.isCompleted) {
      completion.complete(
        _walletChangedCancellationResult(_cancellationTargetCount),
      );
    }
    final stopCompletion = _stopCompleter;
    if (stopCompletion != null && !stopCompletion.isCompleted) {
      stopCompletion.complete(
        const MarketMakerBotStopResult(MarketMakerBotStopOutcome.walletChanged),
      );
    }
    add(const MarketMakerBotSessionChanged());
    final origin = _observerLossStopOrigin;
    if (origin != null) _enqueueObserverLossStop(origin);
    _scheduleAuthResubscribe();
  }

  void _scheduleAuthResubscribe() {
    if (isClosed || _closing || _authResubscribeTimer?.isActive == true) {
      return;
    }
    _authResubscribeTimer = Timer(const Duration(seconds: 1), () {
      if (!isClosed && !_closing && _authObservationUnavailable) {
        _startAuthObservation();
      }
    });
  }

  void _synchronizeWallet(String? walletId, {bool forceSessionChange = false}) {
    if (isClosed ||
        _closing ||
        (!forceSessionChange && walletId == _walletId)) {
      return;
    }
    final previousWalletId = _walletId;
    final previousSession = previousWalletId == null
        ? null
        : MarketMakerBotWalletSession(
            walletId: previousWalletId,
            generation: _walletGeneration,
          );
    final previousOwnership = _orderOwnership;
    final previousPendingStart = _pendingAcceptedStart;
    final hasAppLifecycleEvidence =
        previousOwnership != null || previousPendingStart != null;
    final signedOut = walletId == null && previousSession != null;
    final sameWalletRotation =
        walletId != null && walletId == previousWalletId && forceSessionChange;
    final sameWalletReauthentication =
        walletId != null &&
        previousWalletId == null &&
        _signedOutStopOrigin?.walletId == walletId;
    final sameWalletObserverRecovery =
        walletId != null &&
        previousWalletId == null &&
        _observerLossStopOrigin?.walletId == walletId;
    final sameWalletContinuity =
        sameWalletRotation ||
        sameWalletReauthentication ||
        sameWalletObserverRecovery;

    if (signedOut && hasAppLifecycleEvidence) {
      _signedOutOrderOwnership = previousOwnership;
      _signedOutPendingAcceptedStart = previousPendingStart;
      _signedOutStopOrigin = previousSession;
    } else if (signedOut || (walletId != null && !sameWalletReauthentication)) {
      _signedOutOrderOwnership = null;
      _signedOutPendingAcceptedStart = null;
      _signedOutStopOrigin = null;
    }
    _walletId = walletId;
    _walletGeneration++;
    final currentSession = captureWalletSession();
    if (sameWalletContinuity && currentSession != null) {
      // A same-wallet auth refresh invalidates every captured authority token,
      // but it must not erase recovery evidence for an RPC already in flight.
      _orderOwnership = sameWalletRotation
          ? previousOwnership
          : sameWalletObserverRecovery
          ? _observerLossOrderOwnership
          : _signedOutOrderOwnership;
      _pendingAcceptedStart =
          (sameWalletRotation
                  ? previousPendingStart
                  : sameWalletObserverRecovery
                  ? _observerLossPendingAcceptedStart
                  : _signedOutPendingAcceptedStart)
              ?.forWallet(currentSession);
    } else {
      _orderOwnership = null;
      _pendingAcceptedStart = null;
      _pendingAuthRecoverySession = null;
      _pendingAuthRecoveryToken = null;
    }
    final completion = _cancellationCompleter;
    if (completion != null && !completion.isCompleted) {
      completion.complete(
        _walletChangedCancellationResult(_cancellationTargetCount),
      );
    }
    final stopCompletion = _stopCompleter;
    if (stopCompletion != null && !stopCompletion.isCompleted) {
      stopCompletion.complete(
        const MarketMakerBotStopResult(MarketMakerBotStopOutcome.walletChanged),
      );
    }
    add(const MarketMakerBotSessionChanged());

    if (signedOut && hasAppLifecycleEvidence) {
      _enqueueSignedOutStop(previousSession);
    } else if (sameWalletContinuity && currentSession != null) {
      final pending = _pendingAcceptedStart;
      if (pending != null) _enqueueAuthRecoveryStop(currentSession, pending);
    }
    if (!sameWalletObserverRecovery) {
      _observerLossOrderOwnership = null;
      _observerLossPendingAcceptedStart = null;
    }
    _observerLossStopOrigin = null;
    _pendingObserverLossStopOrigin = null;
  }

  void _enqueueSignedOutStop(MarketMakerBotWalletSession origin) {
    if (isClosed ||
        _signedOutStopOrigin != origin ||
        _pendingSignedOutStopOrigin == origin ||
        (_signedOutOrderOwnership == null &&
            _signedOutPendingAcceptedStart == null)) {
      return;
    }
    _pendingSignedOutStopOrigin = origin;
    add(
      MarketMakerBotStopRequested(
        walletSession: null,
        allowSignedOut: true,
        signedOutOrigin: origin,
        pendingStartToken: _signedOutPendingAcceptedStart?.attemptToken,
      ),
    );
  }

  void _enqueueAuthRecoveryStop(
    MarketMakerBotWalletSession walletSession,
    _PendingAcceptedStart pending,
  ) {
    _pendingAuthRecoverySession = walletSession;
    _pendingAuthRecoveryToken = pending.attemptToken;
    add(
      MarketMakerBotStopRequested(
        walletSession: walletSession,
        pendingStartToken: pending.attemptToken,
        expectedTradePairs: List<TradeCoinPairConfig>.unmodifiable(
          pending.config.tradeCoinPairs?.values ??
              const <TradeCoinPairConfig>[],
        ),
      ),
    );
  }

  void _enqueueObserverLossStop(MarketMakerBotWalletSession origin) {
    if (isClosed ||
        !_authObservationUnavailable ||
        _observerLossStopOrigin != origin ||
        _pendingObserverLossStopOrigin == origin ||
        (_observerLossOrderOwnership == null &&
            _observerLossPendingAcceptedStart == null)) {
      return;
    }
    _pendingObserverLossStopOrigin = origin;
    add(
      MarketMakerBotStopRequested(
        walletSession: null,
        allowObserverRecovery: true,
        observerLossOrigin: origin,
        pendingStartToken: _observerLossPendingAcceptedStart?.attemptToken,
        expectedTradePairs: List<TradeCoinPairConfig>.unmodifiable(
          _observerLossPendingAcceptedStart?.config.tradeCoinPairs?.values ??
              _observerLossOrderOwnership?.configsByName.values ??
              const <TradeCoinPairConfig>[],
        ),
      ),
    );
  }

  bool _isCurrentWalletSession(MarketMakerBotWalletSession? session) {
    return session != null &&
        session.walletId == _walletId &&
        session.generation == _walletGeneration;
  }

  Future<void> _requireWalletSession(
    MarketMakerBotWalletSession? session, {
    bool allowSignedOut = false,
    MarketMakerBotWalletSession? signedOutOrigin,
  }) async {
    if (allowSignedOut && session == null) {
      if (_walletId != null ||
          signedOutOrigin == null ||
          _signedOutStopOrigin != signedOutOrigin) {
        throw const _MarketMakerBotWalletChanged();
      }
      final observationEpoch = _authObservationEpoch;
      final user = await _kdfSdk.auth.currentUser;
      if (observationEpoch != _authObservationEpoch ||
          user != null ||
          _walletId != null ||
          _signedOutStopOrigin != signedOutOrigin) {
        throw const _MarketMakerBotWalletChanged();
      }
      return;
    }
    if (!_isCurrentWalletSession(session)) {
      throw const _MarketMakerBotWalletChanged();
    }
    final observationEpoch = _authObservationEpoch;
    final user = await _kdfSdk.auth.currentUser;
    if (observationEpoch != _authObservationEpoch ||
        !_isCurrentWalletSession(session) ||
        user?.walletId.compoundId != session!.walletId) {
      throw const _MarketMakerBotWalletChanged();
    }
  }

  Future<void> _requireFreshWalletSession(
    MarketMakerBotWalletSession? session, {
    bool allowSignedOut = false,
    MarketMakerBotWalletSession? signedOutOrigin,
  }) async {
    await _requireWalletSession(
      session,
      allowSignedOut: allowSignedOut,
      signedOutOrigin: signedOutOrigin,
    );
    final user = await freshKdfCurrentUser(_kdfSdk);
    if (allowSignedOut && session == null) {
      if (user != null ||
          _walletId != null ||
          signedOutOrigin == null ||
          _signedOutStopOrigin != signedOutOrigin) {
        throw const _MarketMakerBotWalletChanged();
      }
      return;
    }
    if (user?.walletId.compoundId != session?.walletId ||
        !_isCurrentWalletSession(session)) {
      throw const _MarketMakerBotWalletChanged();
    }
  }

  Future<void> _requireObserverLossSession(
    MarketMakerBotWalletSession? origin,
  ) async {
    if (!_authObservationUnavailable ||
        _walletId != null ||
        origin == null ||
        _observerLossStopOrigin != origin) {
      throw const _MarketMakerBotWalletChanged();
    }
    final user = await freshKdfCurrentUser(_kdfSdk);
    if (!_authObservationUnavailable ||
        _walletId != null ||
        _observerLossStopOrigin != origin ||
        user?.walletId.compoundId != origin.walletId) {
      throw const _MarketMakerBotWalletChanged();
    }
  }

  Future<void> _onStartRequested(
    MarketMakerBotStartRequested event,
    Emitter<MarketMakerBotState> emit,
  ) async {
    try {
      await _handleStartRequested(event, emit);
    } finally {
      _startOrUpdatePending = false;
    }
  }

  Future<void> _handleStartRequested(
    MarketMakerBotStartRequested event,
    Emitter<MarketMakerBotState> emit,
  ) async {
    if (_stopInFlight != null) return;
    final previousState = state;
    late MarketMakerBotParameters config;
    late MarketMakerBotCleanOrderBaseline baseline;
    _PendingAcceptedStart? attemptedStart;
    var startAttempted = false;
    Future<void> guard() => _requireWalletSession(event.walletSession);

    Future<void> recoverAttemptedStart() async {
      final recovery = await _recoverAcceptedStart(
        baseline: baseline,
        config: config,
        botId: event.botId,
        walletSession: event.walletSession,
      );
      switch (recovery) {
        case _AcceptedStartRecoveryOutcome.stopped:
          emit(
            const MarketMakerBotState(
              status: MarketMakerBotStatus.stopped,
              lifecycleProvenStopped: true,
              errorMessage:
                  'The bot start was rolled back because order correlation '
                  'could not be verified safely.',
            ),
          );
        case _AcceptedStartRecoveryOutcome.uncertain:
          emit(
            const MarketMakerBotState(
              status: MarketMakerBotStatus.running,
              errorMessage:
                  'The bot start may have been accepted, but its safe '
                  'rollback could not be confirmed. Use Stop to retry safe '
                  'lifecycle reconciliation.',
            ),
          );
        case _AcceptedStartRecoveryOutcome.walletChanged:
          return;
      }
    }

    try {
      await guard();
      if (state.isRunning || state.isUpdating) return;
      config = await _botRepository.loadStoredConfig();
      await guard();
      final configuredPairs = _configuredPairs(config);
      if (!_sameTradePairConfigs(event.expectedTradePairs, configuredPairs)) {
        throw const MarketMakerBotOrderOwnershipUnavailable();
      }
      baseline = await _orderRepository.captureCleanOrderBaseline(
        configuredPairs,
      );
      await guard();
      Future<void> startGuard() async {
        await guard();
        await _requireStoredConfiguration(config);
        await _orderRepository.requireCleanOrderBaseline(baseline);
        await _requireFreshWalletSession(event.walletSession);
        final pending = _PendingAcceptedStart(
          baseline: baseline,
          config: config,
          botId: event.botId,
          walletSession: event.walletSession!,
        );
        attemptedStart = pending;
        _pendingAcceptedStart = pending;
        startAttempted = true;
      }

      emit(const MarketMakerBotState.starting());
      await _botRepository.start(
        botId: event.botId,
        parameters: config,
        allowAlreadyStarted: false,
        beforeMutation: startGuard,
      );
      await guard();
      _orderOwnership = await _orderRepository.captureStartedOrderOwnership(
        baseline,
        timeout: _ownershipDiscoveryDeadline(config.botRefreshRate),
        beforeRead: guard,
      );
      await guard();
      _pendingAcceptedStart = null;
      emit(const MarketMakerBotState.running());
    } on MarketMakerBotAlreadyStarted {
      _discardRejectedStart(attemptedStart);
      _orderOwnership = null;
      emit(
        const MarketMakerBotState(
          status: MarketMakerBotStatus.running,
          errorMessage:
              'A market maker bot was already running. It was not stopped or '
              'associated with this app session.',
        ),
      );
    } on MarketMakerBotStartRejected {
      _discardRejectedStart(attemptedStart);
      _orderOwnership = null;
      emit(
        MarketMakerBotState(
          status: previousState.status,
          lifecycleProvenStopped: previousState.lifecycleProvenStopped,
          errorMessage: 'KDF rejected the market maker bot configuration.',
        ),
      );
    } on MarketMakerBotStartUncertain {
      _discardRejectedStart(attemptedStart);
      _orderOwnership = null;
      emit(
        const MarketMakerBotState(
          status: MarketMakerBotStatus.running,
          errorMessage:
              'The bot start outcome is uncertain. Automatic cleanup is '
              'disabled; use Stop to reconcile bot ID 0 explicitly.',
        ),
      );
    } on _MarketMakerBotWalletChanged {
      return;
    } on MarketMakerBotOrderOwnershipUnavailable {
      if (startAttempted) {
        await recoverAttemptedStart();
        return;
      }
      _orderOwnership = null;
      emit(
        MarketMakerBotState(
          status: previousState.status,
          lifecycleProvenStopped: previousState.lifecycleProvenStopped,
          errorMessage:
              'Unable to verify that configured pairs are free of manual '
              'maker orders',
        ),
      );
    } on Object {
      // Log bot error
      GetIt.I<AnalyticsRepo>().queueEvent(
        MarketbotErrorEventData(
          failureDetail: 'start_failed',
          strategyType: 'simple',
        ),
      );
      if (startAttempted) {
        await recoverAttemptedStart();
        return;
      }
      _orderOwnership = null;
      emit(
        MarketMakerBotState(
          status: previousState.status,
          lifecycleProvenStopped: previousState.lifecycleProvenStopped,
          errorMessage: 'Unable to start the market maker bot',
        ),
      );
    }
  }

  Future<void> _onStopRequested(
    MarketMakerBotStopRequested event,
    Emitter<MarketMakerBotState> emit,
  ) async {
    final previousState = state;
    var result = const MarketMakerBotStopResult(
      MarketMakerBotStopOutcome.failed,
    );
    var stopAttempted = false;
    Future<void> guard() async {
      if (event.allowObserverRecovery) {
        await _requireObserverLossSession(event.observerLossOrigin);
      } else {
        await _requireWalletSession(
          event.walletSession,
          allowSignedOut: event.allowSignedOut,
          signedOutOrigin: event.signedOutOrigin,
        );
      }
      final pendingStartToken = event.pendingStartToken;
      if (pendingStartToken != null) {
        final pendingMatches = event.allowObserverRecovery
            ? identical(
                pendingStartToken,
                _observerLossPendingAcceptedStart?.attemptToken,
              )
            : event.allowSignedOut
            ? identical(
                pendingStartToken,
                _signedOutPendingAcceptedStart?.attemptToken,
              )
            : event.walletSession == _pendingAuthRecoverySession &&
                  identical(pendingStartToken, _pendingAuthRecoveryToken) &&
                  identical(
                    pendingStartToken,
                    _pendingAcceptedStart?.attemptToken,
                  );
        if (!pendingMatches) throw const _MarketMakerBotWalletChanged();
      }
    }

    try {
      if (event.allowSignedOut ||
          event.allowObserverRecovery ||
          event.pendingStartToken != null) {
        final configurationBarrier = _configurationMutationCompletion?.future;
        if (configurationBarrier != null) await configurationBarrier;
      }
      await guard();
      final config = await _botRepository.loadStoredConfig();
      await guard();
      final configuredPairs = _configuredPairs(config, allowEmpty: true);
      final expectedTradePairs = event.expectedTradePairs;
      if (expectedTradePairs != null &&
          !_sameTradePairConfigs(expectedTradePairs, configuredPairs)) {
        throw const MarketMakerBotOrderOwnershipUnavailable();
      }
      final ownership = await _captureStopOwnership(
        botId: event.botId,
        configuredPairs: configuredPairs,
        walletSession: event.walletSession,
        allowSignedOut: event.allowSignedOut,
        allowObserverRecovery: event.allowObserverRecovery,
        beforeRead: guard,
      );
      await guard();
      Future<void> stopGuard() async {
        await guard();
        await _requireStoredTradePairs(
          configuredPairs,
          allowEmpty: configuredPairs.isEmpty,
        );
        if (event.allowObserverRecovery) {
          await _requireObserverLossSession(event.observerLossOrigin);
        } else {
          await _requireFreshWalletSession(
            event.walletSession,
            allowSignedOut: event.allowSignedOut,
            signedOutOrigin: event.signedOutOrigin,
          );
        }
        stopAttempted = true;
      }

      emit(const MarketMakerBotState.stopping());
      final initialStopOutcome = await _botRepository.stop(
        botId: event.botId,
        beforeMutation: stopGuard,
      );
      await guard();
      if (initialStopOutcome != MarketMakerBotStopRpcOutcome.alreadyStopped ||
          ownership != null) {
        await _waitForBotToStopAndOrdersToBeCancelled(
          botId: event.botId,
          walletSession: event.walletSession,
          allowSignedOut: event.allowSignedOut,
          allowObserverRecovery: event.allowObserverRecovery,
          signedOutOrigin: event.signedOutOrigin,
          observerLossOrigin: event.observerLossOrigin,
          ownership: ownership,
          botRefreshRate: config.botRefreshRate,
          beforeStatusProbe: stopGuard,
        );
      }
      await guard();
      _orderOwnership = null;
      _signedOutOrderOwnership = null;
      _pendingAcceptedStart = null;
      _signedOutPendingAcceptedStart = null;
      _signedOutStopOrigin = null;
      _observerLossOrderOwnership = null;
      _observerLossPendingAcceptedStart = null;
      _observerLossStopOrigin = null;
      emit(const MarketMakerBotState.stopped());
      result = const MarketMakerBotStopResult(
        MarketMakerBotStopOutcome.stopped,
      );
    } on _MarketMakerBotWalletChanged {
      result = const MarketMakerBotStopResult(
        MarketMakerBotStopOutcome.walletChanged,
      );
    } on MarketMakerBotOrderOwnershipUnavailable {
      emit(
        MarketMakerBotState(
          status: previousState.status,
          lifecycleProvenStopped: previousState.lifecycleProvenStopped,
          errorMessage: stopAttempted
              ? 'The bot stop was requested, but stopped status could not be '
                    'confirmed.'
              : 'The confirmed bot scope changed before it could be stopped.',
        ),
      );
      result = MarketMakerBotStopResult(
        stopAttempted
            ? MarketMakerBotStopOutcome.uncertain
            : MarketMakerBotStopOutcome.failed,
      );
    } on Object {
      // Log bot error
      GetIt.I<AnalyticsRepo>().queueEvent(
        MarketbotErrorEventData(
          failureDetail: 'stop_failed',
          strategyType: 'simple',
        ),
      );
      emit(
        MarketMakerBotState(
          status: previousState.status,
          lifecycleProvenStopped: previousState.lifecycleProvenStopped,
          errorMessage: 'Unable to confirm that the bot stopped',
        ),
      );
      result = MarketMakerBotStopResult(
        stopAttempted
            ? MarketMakerBotStopOutcome.uncertain
            : MarketMakerBotStopOutcome.failed,
      );
    } finally {
      event.complete(result);
      if (event.allowSignedOut &&
          event.signedOutOrigin == _pendingSignedOutStopOrigin) {
        _pendingSignedOutStopOrigin = null;
      }
      if (event.walletSession == _pendingAuthRecoverySession &&
          identical(event.pendingStartToken, _pendingAuthRecoveryToken)) {
        _pendingAuthRecoverySession = null;
        _pendingAuthRecoveryToken = null;
      }
      if (event.allowObserverRecovery &&
          event.observerLossOrigin == _pendingObserverLossStopOrigin) {
        _pendingObserverLossStopOrigin = null;
      }
    }
  }

  Future<void> _onOrderUpdateRequested(
    MarketMakerBotOrderUpdateRequested event,
    Emitter<MarketMakerBotState> emit,
  ) async {
    try {
      await _handleOrderUpdateRequested(event, emit);
    } finally {
      _startOrUpdatePending = false;
    }
  }

  Future<void> _handleOrderUpdateRequested(
    MarketMakerBotOrderUpdateRequested event,
    Emitter<MarketMakerBotState> emit,
  ) async {
    if (_stopInFlight != null) return;
    final previousState = state;
    late MarketMakerBotParameters nextConfig;
    late MarketMakerBotCleanOrderBaseline restartBaseline;
    _PendingAcceptedStart? attemptedRestart;
    var stoppedAndOrdersAbsent = false;
    var stopAccepted = false;
    var restartAttempted = false;
    Future<void> guard() => _requireWalletSession(event.walletSession);

    Future<void> recoverAttemptedRestart() async {
      final recovery = await _recoverAcceptedStart(
        baseline: restartBaseline,
        config: nextConfig,
        botId: event.botId,
        walletSession: event.walletSession,
      );
      switch (recovery) {
        case _AcceptedStartRecoveryOutcome.stopped:
          emit(
            const MarketMakerBotState(
              status: MarketMakerBotStatus.stopped,
              lifecycleProvenStopped: true,
              errorMessage:
                  'The updated bot was stopped because order correlation '
                  'could not be verified safely.',
            ),
          );
        case _AcceptedStartRecoveryOutcome.uncertain:
          emit(
            const MarketMakerBotState(
              status: MarketMakerBotStatus.running,
              errorMessage:
                  'The updated bot may have restarted, but its safe rollback '
                  'could not be confirmed. Use Stop to retry safe lifecycle '
                  'reconciliation.',
            ),
          );
        case _AcceptedStartRecoveryOutcome.walletChanged:
          return;
      }
    }

    try {
      await guard();
      final currentConfig = await _botRepository.loadStoredConfig();
      await guard();
      final configuredPairs = _configuredPairs(currentConfig, allowEmpty: true);
      final originalConfig = event.originalConfig;
      if (originalConfig != null &&
          !configuredPairs.any(
            (candidate) =>
                candidate.name == originalConfig.name &&
                candidate == originalConfig,
          )) {
        throw const MarketMakerBotOrderOwnershipUnavailable();
      }
      if (originalConfig == null &&
          configuredPairs.any(
            (candidate) => candidate.name == event.tradePair.name,
          )) {
        throw const MarketMakerBotOrderOwnershipUnavailable();
      }
      final canConfigureWithoutLifecycleMutation =
          !state.isRunning &&
          (state.lifecycleProvenStopped || configuredPairs.isEmpty);
      if (canConfigureWithoutLifecycleMutation) {
        await _botRepository.addTradePairToStoredSettings(
          event.tradePair,
          beforeMutation: () async {
            await guard();
            await _requireStoredTradePairs(configuredPairs, allowEmpty: true);
            await _requireFreshWalletSession(event.walletSession);
          },
        );
        await _requireFreshWalletSession(event.walletSession);
        emit(
          state.lifecycleProvenStopped
              ? const MarketMakerBotState.stopped()
              : previousState,
        );
        return;
      }
      final ownership = _requireTrackedOwnership(configuredPairs);
      await _orderRepository.requireCurrentOrderOwnership(
        ownership,
        configuredPairs,
      );
      await guard();
      Future<void> stopGuard() async {
        await guard();
        await _requireStoredTradePairs(configuredPairs);
        await _orderRepository.requireCurrentOrderOwnership(
          ownership,
          configuredPairs,
        );
        await _requireFreshWalletSession(event.walletSession);
      }

      Future<void> statusGuard() async {
        await guard();
        await _requireStoredTradePairs(configuredPairs);
        await _requireFreshWalletSession(event.walletSession);
      }

      emit(const MarketMakerBotState.stopping());
      await _botRepository.stop(botId: event.botId, beforeMutation: stopGuard);
      stopAccepted = true;
      await guard();
      await _waitForBotToStopAndOrdersToBeCancelled(
        botId: event.botId,
        walletSession: event.walletSession,
        ownership: ownership,
        botRefreshRate: currentConfig.botRefreshRate,
        beforeStatusProbe: statusGuard,
      );
      await guard();
      stoppedAndOrdersAbsent = true;
      _orderOwnership = null;
      _pendingAcceptedStart = null;
      await _botRepository.addTradePairToStoredSettings(
        event.tradePair,
        beforeMutation: () async {
          await guard();
          await _requireStoredTradePairs(configuredPairs);
          await _requireFreshWalletSession(event.walletSession);
        },
      );
      await guard();
      nextConfig = await _botRepository.loadStoredConfig();
      await guard();
      final nextPairs = _configuredPairs(nextConfig);
      restartBaseline = await _orderRepository.captureCleanOrderBaseline(
        nextPairs,
      );
      await guard();
      Future<void> startGuard() async {
        await guard();
        await _requireStoredConfiguration(nextConfig);
        await _orderRepository.requireCleanOrderBaseline(restartBaseline);
        await _requireFreshWalletSession(event.walletSession);
        final pending = _PendingAcceptedStart(
          baseline: restartBaseline,
          config: nextConfig,
          botId: event.botId,
          walletSession: event.walletSession!,
        );
        attemptedRestart = pending;
        _pendingAcceptedStart = pending;
        restartAttempted = true;
      }

      emit(const MarketMakerBotState.starting());
      await _botRepository.start(
        botId: event.botId,
        parameters: nextConfig,
        allowAlreadyStarted: false,
        beforeMutation: startGuard,
      );
      await guard();
      _orderOwnership = await _orderRepository.captureStartedOrderOwnership(
        restartBaseline,
        timeout: _ownershipDiscoveryDeadline(nextConfig.botRefreshRate),
        beforeRead: guard,
      );
      await guard();
      _pendingAcceptedStart = null;
      emit(const MarketMakerBotState.running());
    } on MarketMakerBotAlreadyStarted {
      _discardRejectedStart(attemptedRestart);
      _orderOwnership = null;
      emit(
        const MarketMakerBotState(
          status: MarketMakerBotStatus.running,
          errorMessage:
              'Another market maker bot was already running after the update. '
              'It was not stopped or associated with this app session.',
        ),
      );
    } on MarketMakerBotStartRejected {
      _discardRejectedStart(attemptedRestart);
      _orderOwnership = null;
      emit(
        MarketMakerBotState(
          status: stoppedAndOrdersAbsent
              ? MarketMakerBotStatus.stopped
              : previousState.status,
          lifecycleProvenStopped:
              stoppedAndOrdersAbsent || previousState.lifecycleProvenStopped,
          errorMessage: 'KDF rejected the updated bot configuration.',
        ),
      );
    } on MarketMakerBotStartUncertain {
      _discardRejectedStart(attemptedRestart);
      _orderOwnership = null;
      emit(
        const MarketMakerBotState(
          status: MarketMakerBotStatus.running,
          errorMessage:
              'The updated bot restart outcome is uncertain. Automatic '
              'cleanup is disabled; use Stop to reconcile bot ID 0.',
        ),
      );
    } on _MarketMakerBotWalletChanged {
      return;
    } on MarketMakerBotOrderOwnershipUnavailable {
      if (restartAttempted) {
        await recoverAttemptedRestart();
        return;
      }
      emit(
        MarketMakerBotState(
          status: stoppedAndOrdersAbsent
              ? MarketMakerBotStatus.stopped
              : previousState.status,
          lifecycleProvenStopped:
              stoppedAndOrdersAbsent || previousState.lifecycleProvenStopped,
          errorMessage: stopAccepted
              ? 'The bot stop was accepted, but correlated order absence '
                    'could not be confirmed.'
              : 'Unable to verify bot order correlation',
        ),
      );
    } on Object {
      if (restartAttempted) {
        await recoverAttemptedRestart();
        return;
      }
      emit(
        MarketMakerBotState(
          status: stoppedAndOrdersAbsent
              ? MarketMakerBotStatus.stopped
              : previousState.status,
          lifecycleProvenStopped:
              stoppedAndOrdersAbsent || previousState.lifecycleProvenStopped,
          errorMessage: 'Unable to update the market maker order',
        ),
      );
      // Log bot error
      GetIt.I<AnalyticsRepo>().queueEvent(
        MarketbotErrorEventData(
          failureDetail: 'update_failed',
          strategyType: 'simple',
        ),
      );
    }
  }

  Future<void> _onOrderCancelRequested(
    MarketMakerBotOrderCancelRequested event,
    Emitter<MarketMakerBotState> emit,
  ) async {
    final requestedTargets = List<TradePair>.unmodifiable(event.tradePairs);
    final requestedPairs = List<TradeCoinPairConfig>.unmodifiable(
      requestedTargets.map((target) => target.config),
    );
    final previousState = state;
    late MarketMakerBotParameters remainingConfig;
    late MarketMakerBotCleanOrderBaseline restartBaseline;
    _PendingAcceptedStart? attemptedRestart;

    var result = MarketMakerBotCancellationResult(
      requestedCount: requestedPairs.length,
      completedCount: 0,
      failedCount: requestedPairs.length,
      uncertainCount: 0,
    );
    var stoppedAndOrdersAbsent = false;
    var stopAccepted = false;
    var settingsRemoved = false;
    var restartAttempted = false;
    Future<void> guard() => _requireWalletSession(event.walletSession);

    Future<void> recoverAttemptedRestart() async {
      final recovery = await _recoverAcceptedStart(
        baseline: restartBaseline,
        config: remainingConfig,
        botId: event.botId,
        walletSession: event.walletSession,
      );
      switch (recovery) {
        case _AcceptedStartRecoveryOutcome.stopped:
          emit(
            const MarketMakerBotState(
              status: MarketMakerBotStatus.stopped,
              lifecycleProvenStopped: true,
              errorMessage:
                  'The remaining bot was stopped because order correlation '
                  'could not be verified safely.',
            ),
          );
        case _AcceptedStartRecoveryOutcome.uncertain:
          emit(
            const MarketMakerBotState(
              status: MarketMakerBotStatus.running,
              errorMessage:
                  'The remaining bot may have restarted, but its safe '
                  'rollback could not be confirmed. Use Stop to retry safe '
                  'lifecycle reconciliation.',
            ),
          );
        case _AcceptedStartRecoveryOutcome.walletChanged:
          return;
      }
    }

    try {
      await guard();
      final currentConfig = await _botRepository.loadStoredConfig();
      await guard();
      final configuredPairs = _configuredPairs(currentConfig);
      final ownership = _requireTrackedOwnership(configuredPairs);
      if (requestedTargets.any(
        (target) => !ownership.matchesProjectedPair(target),
      )) {
        throw const MarketMakerBotOrderOwnershipUnavailable();
      }
      await _orderRepository.requireCurrentOrderOwnership(
        ownership,
        configuredPairs,
      );
      await guard();
      Future<void> stopGuard() async {
        await guard();
        await _requireStoredTradePairs(configuredPairs);
        await _orderRepository.requireCurrentOrderOwnership(
          ownership,
          configuredPairs,
        );
        await _requireFreshWalletSession(event.walletSession);
      }

      Future<void> statusGuard() async {
        await guard();
        await _requireStoredTradePairs(configuredPairs);
        await _requireFreshWalletSession(event.walletSession);
      }

      emit(const MarketMakerBotState.stopping());
      await _botRepository.stop(botId: event.botId, beforeMutation: stopGuard);
      stopAccepted = true;
      await guard();
      await _waitForBotToStopAndOrdersToBeCancelled(
        botId: event.botId,
        walletSession: event.walletSession,
        ownership: ownership,
        botRefreshRate: currentConfig.botRefreshRate,
        beforeStatusProbe: statusGuard,
      );
      await guard();
      stoppedAndOrdersAbsent = true;
      _orderOwnership = null;
      _pendingAcceptedStart = null;
      await _botRepository.removeTradePairsFromStoredSettings(
        requestedPairs,
        beforeMutation: () async {
          await guard();
          await _requireStoredTradePairs(configuredPairs);
          await _requireFreshWalletSession(event.walletSession);
        },
      );
      await guard();
      settingsRemoved = true;

      remainingConfig = await _botRepository.loadStoredConfig();
      await guard();
      if (remainingConfig.tradeCoinPairs?.isNotEmpty ?? false) {
        final remainingPairs = _configuredPairs(remainingConfig);
        restartBaseline = await _orderRepository.captureCleanOrderBaseline(
          remainingPairs,
        );
        await guard();
        Future<void> startGuard() async {
          await guard();
          await _requireStoredConfiguration(remainingConfig);
          await _orderRepository.requireCleanOrderBaseline(restartBaseline);
          await _requireFreshWalletSession(event.walletSession);
          final pending = _PendingAcceptedStart(
            baseline: restartBaseline,
            config: remainingConfig,
            botId: event.botId,
            walletSession: event.walletSession!,
          );
          attemptedRestart = pending;
          _pendingAcceptedStart = pending;
          restartAttempted = true;
        }

        emit(const MarketMakerBotState.starting());
        await _botRepository.start(
          botId: event.botId,
          parameters: remainingConfig,
          allowAlreadyStarted: false,
          beforeMutation: startGuard,
        );
        await guard();
        _orderOwnership = await _orderRepository.captureStartedOrderOwnership(
          restartBaseline,
          timeout: _ownershipDiscoveryDeadline(remainingConfig.botRefreshRate),
          beforeRead: guard,
        );
        await guard();
        _pendingAcceptedStart = null;
        emit(const MarketMakerBotState.running());
      } else {
        _pendingAcceptedStart = null;
        emit(const MarketMakerBotState.stopped());
      }
      result = MarketMakerBotCancellationResult(
        requestedCount: requestedPairs.length,
        completedCount: requestedPairs.length,
        failedCount: 0,
        uncertainCount: 0,
      );
    } on MarketMakerBotAlreadyStarted {
      _discardRejectedStart(attemptedRestart);
      _orderOwnership = null;
      result = _uncertainCancellationResult(requestedPairs.length);
      emit(
        const MarketMakerBotState(
          status: MarketMakerBotStatus.running,
          errorMessage:
              'Another market maker bot was already running after the '
              'configuration change. It was not stopped or associated with '
              'this app session.',
        ),
      );
    } on MarketMakerBotStartRejected {
      _discardRejectedStart(attemptedRestart);
      _orderOwnership = null;
      result = MarketMakerBotCancellationResult(
        requestedCount: requestedPairs.length,
        completedCount: settingsRemoved ? requestedPairs.length : 0,
        failedCount: settingsRemoved ? 0 : requestedPairs.length,
        uncertainCount: 0,
      );
      emit(
        MarketMakerBotState(
          status: stoppedAndOrdersAbsent
              ? MarketMakerBotStatus.stopped
              : previousState.status,
          lifecycleProvenStopped:
              stoppedAndOrdersAbsent || previousState.lifecycleProvenStopped,
          errorMessage:
              'The selected configuration was removed, but KDF rejected '
              'restarting the remaining bot.',
        ),
      );
    } on MarketMakerBotStartUncertain {
      _discardRejectedStart(attemptedRestart);
      _orderOwnership = null;
      result = _uncertainCancellationResult(requestedPairs.length);
      emit(
        const MarketMakerBotState(
          status: MarketMakerBotStatus.running,
          errorMessage:
              'The remaining bot restart outcome is uncertain. Automatic '
              'cleanup is disabled; use Stop to reconcile bot ID 0.',
        ),
      );
    } on _MarketMakerBotWalletChanged {
      result = _walletChangedCancellationResult(requestedPairs.length);
    } on MarketMakerBotOrderOwnershipUnavailable {
      if (restartAttempted) {
        result = _uncertainCancellationResult(requestedPairs.length);
        await recoverAttemptedRestart();
        return;
      }
      result = stopAccepted
          ? _uncertainCancellationResult(requestedPairs.length)
          : MarketMakerBotCancellationResult(
              requestedCount: requestedPairs.length,
              completedCount: 0,
              failedCount: requestedPairs.length,
              uncertainCount: 0,
            );
      emit(
        MarketMakerBotState(
          status: stoppedAndOrdersAbsent
              ? MarketMakerBotStatus.stopped
              : previousState.status,
          lifecycleProvenStopped:
              stoppedAndOrdersAbsent || previousState.lifecycleProvenStopped,
          errorMessage: stopAccepted
              ? 'The bot stop was accepted, but correlated order absence '
                    'could not be confirmed.'
              : 'Unable to verify bot order correlation',
        ),
      );
    } on Object {
      if (restartAttempted) {
        result = _uncertainCancellationResult(requestedPairs.length);
        await recoverAttemptedRestart();
        return;
      }
      result = MarketMakerBotCancellationResult(
        requestedCount: requestedPairs.length,
        completedCount: 0,
        failedCount: 0,
        uncertainCount: requestedPairs.length,
      );
      emit(
        MarketMakerBotState(
          status: stoppedAndOrdersAbsent
              ? MarketMakerBotStatus.stopped
              : previousState.status,
          lifecycleProvenStopped:
              stoppedAndOrdersAbsent || previousState.lifecycleProvenStopped,
          errorMessage: settingsRemoved
              ? 'Cancellation changed the bot settings, but it could not '
                    'safely restart. Refresh orders.'
              : null,
        ),
      );
      // Log bot error
      GetIt.I<AnalyticsRepo>().queueEvent(
        MarketbotErrorEventData(
          failureDetail: 'cancel_failed',
          strategyType: 'simple',
        ),
      );
    } finally {
      event.complete(result);
    }
  }

  void _discardRejectedStart(_PendingAcceptedStart? rejected) {
    if (rejected == null) return;
    final token = rejected.attemptToken;
    if (identical(_pendingAcceptedStart?.attemptToken, token)) {
      _pendingAcceptedStart = null;
    }
    if (identical(_signedOutPendingAcceptedStart?.attemptToken, token)) {
      _signedOutPendingAcceptedStart = null;
    }
    if (identical(_pendingAuthRecoveryToken, token)) {
      _pendingAuthRecoverySession = null;
      _pendingAuthRecoveryToken = null;
    }
  }

  Future<_AcceptedStartRecoveryOutcome> _recoverAcceptedStart({
    required MarketMakerBotCleanOrderBaseline baseline,
    required MarketMakerBotParameters config,
    required int botId,
    required MarketMakerBotWalletSession? walletSession,
  }) async {
    Future<void> guard() => _requireWalletSession(walletSession);
    try {
      final configuredPairs = _configuredPairs(config);
      if (walletSession != null) {
        _pendingAcceptedStart ??= _PendingAcceptedStart(
          baseline: baseline,
          config: config,
          botId: botId,
          walletSession: walletSession,
        );
      }
      final ownership = await _orderRepository.captureSessionOrderOwnership(
        baseline,
        beforeRead: guard,
        timeout: _pendingOwnershipRetryDeadline,
      );
      _orderOwnership = ownership;
      Future<void> stopGuard() async {
        await guard();
        await _requireStoredTradePairs(configuredPairs);
        await _orderRepository.requireCurrentOrderOwnership(
          ownership,
          configuredPairs,
        );
        await _requireFreshWalletSession(walletSession);
      }

      Future<void> statusGuard() async {
        await guard();
        await _requireStoredTradePairs(configuredPairs);
        await _requireFreshWalletSession(walletSession);
      }

      await _botRepository.stop(botId: botId, beforeMutation: stopGuard);
      await guard();
      await _waitForBotToStopAndOrdersToBeCancelled(
        botId: botId,
        walletSession: walletSession,
        ownership: ownership,
        botRefreshRate: config.botRefreshRate,
        beforeStatusProbe: statusGuard,
      );
      await guard();
      _orderOwnership = null;
      _pendingAcceptedStart = null;
      return _AcceptedStartRecoveryOutcome.stopped;
    } on _MarketMakerBotWalletChanged {
      return _AcceptedStartRecoveryOutcome.walletChanged;
    } on Object {
      // Keep the clean baseline and any unambiguous UUID correlation so an
      // explicit Stop can retry. Pair-only projection remains unavailable and
      // no UUID mutation is authorized by this evidence.
      return _AcceptedStartRecoveryOutcome.uncertain;
    }
  }

  Future<MarketMakerBotOrderOwnership?> _captureStopOwnership({
    required int botId,
    required List<TradeCoinPairConfig> configuredPairs,
    required MarketMakerBotWalletSession? walletSession,
    required bool allowSignedOut,
    required bool allowObserverRecovery,
    required Future<void> Function() beforeRead,
  }) async {
    final tracked = allowObserverRecovery
        ? _observerLossOrderOwnership
        : allowSignedOut && _walletId == null
        ? _signedOutOrderOwnership
        : _orderOwnership;
    if (tracked?.matches(configuredPairs) == true) return tracked;

    final pending = allowObserverRecovery
        ? _observerLossPendingAcceptedStart
        : allowSignedOut && _walletId == null
        ? _signedOutPendingAcceptedStart
        : _pendingAcceptedStart;
    if (pending == null ||
        pending.botId != botId ||
        !pending.matches(configuredPairs) ||
        (!allowSignedOut &&
            !allowObserverRecovery &&
            pending.walletSession != walletSession)) {
      return null;
    }

    try {
      final ownership = await _orderRepository.captureSessionOrderOwnership(
        pending.baseline,
        beforeRead: beforeRead,
        timeout: _pendingOwnershipRetryDeadline,
      );
      if (allowObserverRecovery) {
        _observerLossOrderOwnership = ownership;
      } else if (allowSignedOut && _walletId == null) {
        _signedOutOrderOwnership = ownership;
      } else {
        _orderOwnership = ownership;
      }
      return ownership;
    } on MarketMakerBotOrderOwnershipUnavailable {
      // Stopping the bot by ID remains safe. Unknown same-pair orders are not
      // projected, and correlation evidence never permits direct cancellation.
      return null;
    } on TimeoutException {
      return null;
    }
  }

  /// Confirms KDF reports `AlreadyStopped` after at least one bot loop, then
  /// confirms every conservatively correlated UUID is absent.
  Future<void> _waitForBotToStopAndOrdersToBeCancelled({
    required int botId,
    required MarketMakerBotWalletSession? walletSession,
    required MarketMakerBotOrderOwnership? ownership,
    required int? botRefreshRate,
    required Future<void> Function() beforeStatusProbe,
    bool allowSignedOut = false,
    bool allowObserverRecovery = false,
    MarketMakerBotWalletSession? signedOutOrigin,
    MarketMakerBotWalletSession? observerLossOrigin,
  }) async {
    final settlementFloor = _botRefreshDuration(botRefreshRate);
    final timeout = _reconciliationDeadline(botRefreshRate);
    final clock = Stopwatch()..start();
    var botProvenStopped = false;
    var consecutiveAbsentSnapshots = 0;
    try {
      while (true) {
        if (allowObserverRecovery) {
          await _requireObserverLossSession(observerLossOrigin);
        } else {
          await _requireWalletSession(
            walletSession,
            allowSignedOut: allowSignedOut,
            signedOutOrigin: signedOutOrigin,
          );
        }
        final remaining = timeout - clock.elapsed;
        if (remaining <= Duration.zero) throw TimeoutException('');
        if (clock.elapsed < settlementFloor) {
          final untilSettlement = settlementFloor - clock.elapsed;
          final delay = untilSettlement < const Duration(milliseconds: 500)
              ? untilSettlement
              : const Duration(milliseconds: 500);
          await Future<void>.delayed(delay);
          continue;
        }

        if (!botProvenStopped) {
          try {
            final stopOutcome = await _botRepository
                .stop(
                  botId: botId,
                  retries: 1,
                  beforeMutation: beforeStatusProbe,
                )
                .timeout(remaining);
            botProvenStopped =
                stopOutcome == MarketMakerBotStopRpcOutcome.alreadyStopped;
          } on _MarketMakerBotWalletChanged {
            rethrow;
          } on MarketMakerBotOrderOwnershipUnavailable {
            rethrow;
          } on Object {
            botProvenStopped = false;
          }
          if (!botProvenStopped) {
            final delay = remaining < const Duration(milliseconds: 500)
                ? remaining
                : const Duration(milliseconds: 500);
            await Future<void>.delayed(delay);
            continue;
          }
          if (ownership == null) return;
        }

        final reconciliation = await _orderRepository
            .reconcileOwnedOrderAbsence(ownership!)
            .timeout(remaining);
        if (allowObserverRecovery) {
          await _requireObserverLossSession(observerLossOrigin);
        } else {
          await _requireWalletSession(
            walletSession,
            allowSignedOut: allowSignedOut,
            signedOutOrigin: signedOutOrigin,
          );
        }
        switch (reconciliation) {
          case MarketMakerBotOrderReconciliationState.absent:
            consecutiveAbsentSnapshots++;
            if (consecutiveAbsentSnapshots >= 3) return;
          case MarketMakerBotOrderReconciliationState.active:
            consecutiveAbsentSnapshots = 0;
          case MarketMakerBotOrderReconciliationState.ownershipUnavailable:
            throw const MarketMakerBotOrderOwnershipUnavailable();
        }
        final delay = remaining < const Duration(milliseconds: 500)
            ? remaining
            : const Duration(milliseconds: 500);
        await Future<void>.delayed(delay);
      }
    } on TimeoutException {
      GetIt.I<AnalyticsRepo>().queueEvent(
        MarketbotErrorEventData(
          failureDetail: 'timeout_cancelling',
          strategyType: 'simple',
        ),
      );
      throw TimeoutException('Failed to confirm order cancellation');
    }
  }

  List<TradeCoinPairConfig> _configuredPairs(
    MarketMakerBotParameters config, {
    bool allowEmpty = false,
  }) {
    final pairs = config.tradeCoinPairs?.values;
    if ((pairs == null || pairs.isEmpty) && !allowEmpty) {
      throw const MarketMakerBotOrderOwnershipUnavailable();
    }
    return List<TradeCoinPairConfig>.unmodifiable(
      pairs ?? const <TradeCoinPairConfig>[],
    );
  }

  Future<void> _requireStoredTradePairs(
    Iterable<TradeCoinPairConfig> expected, {
    bool allowEmpty = false,
  }) async {
    final current = _configuredPairs(
      await _botRepository.loadStoredConfig(),
      allowEmpty: allowEmpty,
    );
    if (!_sameTradePairConfigs(expected, current)) {
      throw const MarketMakerBotOrderOwnershipUnavailable();
    }
  }

  Future<void> _requireStoredConfiguration(
    MarketMakerBotParameters expected,
  ) async {
    final current = await _botRepository.loadStoredConfig();
    final expectedPairs = expected.tradeCoinPairs?.values;
    final currentPairs = current.tradeCoinPairs?.values;
    if (expected.priceUrl != current.priceUrl ||
        expected.botRefreshRate != current.botRefreshRate ||
        expectedPairs == null ||
        currentPairs == null ||
        !_sameTradePairConfigs(expectedPairs, currentPairs)) {
      throw const MarketMakerBotOrderOwnershipUnavailable();
    }
  }

  MarketMakerBotOrderOwnership _requireTrackedOwnership(
    Iterable<TradeCoinPairConfig> configuredPairs, {
    bool allowSignedOut = false,
  }) {
    final ownership =
        _orderOwnership ??
        (allowSignedOut && _walletId == null ? _signedOutOrderOwnership : null);
    if (ownership == null || !ownership.matches(configuredPairs)) {
      throw const MarketMakerBotOrderOwnershipUnavailable();
    }
    return ownership;
  }
}

final class _PendingAcceptedStart {
  _PendingAcceptedStart({
    required this.baseline,
    required this.config,
    required this.botId,
    required this.walletSession,
    Object? attemptToken,
  }) : attemptToken = attemptToken ?? Object();

  final MarketMakerBotCleanOrderBaseline baseline;
  final MarketMakerBotParameters config;
  final int botId;
  final MarketMakerBotWalletSession walletSession;
  final Object attemptToken;

  _PendingAcceptedStart forWallet(
    MarketMakerBotWalletSession nextWalletSession,
  ) {
    return _PendingAcceptedStart(
      baseline: baseline,
      config: config,
      botId: botId,
      walletSession: nextWalletSession,
      attemptToken: attemptToken,
    );
  }

  bool matches(Iterable<TradeCoinPairConfig> configuredPairs) {
    final pendingPairs = config.tradeCoinPairs?.values;
    return pendingPairs != null &&
        _sameTradePairConfigs(pendingPairs, configuredPairs);
  }
}

bool _sameTradePairConfigs(
  Iterable<TradeCoinPairConfig> first,
  Iterable<TradeCoinPairConfig> second,
) {
  final firstList = first.toList(growable: false);
  final secondList = second.toList(growable: false);
  final firstByName = <String, TradeCoinPairConfig>{
    for (final config in firstList) config.name: config,
  };
  final secondByName = <String, TradeCoinPairConfig>{
    for (final config in secondList) config.name: config,
  };
  return firstByName.length == firstList.length &&
      secondByName.length == secondList.length &&
      firstByName.length == secondByName.length &&
      firstByName.entries.every(
        (entry) => secondByName[entry.key] == entry.value,
      );
}

Duration _botRefreshDuration(int? seconds) {
  if (seconds == null || seconds < 30 || seconds > 3600) {
    throw const MarketMakerBotOrderOwnershipUnavailable();
  }
  return Duration(seconds: seconds);
}

Duration _reconciliationDeadline(int? botRefreshRate) =>
    _botRefreshDuration(botRefreshRate) + const Duration(seconds: 30);

Duration _lifecycleDeadline(int? botRefreshRate) =>
    _botRefreshDuration(botRefreshRate) + const Duration(seconds: 60);

Duration _cancellationLifecycleDeadline(int? botRefreshRate) =>
    _botRefreshDuration(botRefreshRate) * 2 + const Duration(seconds: 90);

Duration _ownershipDiscoveryDeadline(int? botRefreshRate) =>
    _reconciliationDeadline(botRefreshRate);

const Duration _pendingOwnershipRetryDeadline = Duration(seconds: 5);

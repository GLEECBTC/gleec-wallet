import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_bot/market_maker_bot_wallet_session.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_bot/market_maker_bot_repository.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_bot/market_maker_bot_status.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_order_list/market_maker_bot_order_list_repository.dart';
import 'package:web_dex/bloc/settings/settings_repository.dart';
import 'package:web_dex/mm2/mm2_api/rpc/market_maker_bot/trade_coin_pair_config.dart';
import 'package:web_dex/mm2/mm2_api/rpc/rpc_error.dart';
import 'package:web_dex/mm2/mm2_api/rpc/rpc_error_type.dart';
import 'package:web_dex/bloc/analytics/analytics_repo.dart';
import 'package:web_dex/analytics/events/market_bot_events.dart';
import 'package:get_it/get_it.dart';

part 'market_maker_bot_event.dart';
part 'market_maker_bot_state.dart';

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
    _authListener = _kdfSdk.auth.watchCurrentUser().listen(
      (user) => _onWalletObservation(user?.walletId.compoundId),
      onError: (_) => _onWalletObservation(null),
      onDone: () => _onWalletObservation(null),
    );
    on<MarketMakerBotStartRequested>(
      _onStartRequested,
      transformer: restartable(),
    );
    on<MarketMakerBotStopRequested>(
      _onStopRequested,
      transformer: restartable(),
    );
    on<MarketMakerBotOrderUpdateRequested>(
      _onOrderUpdateRequested,
      transformer: sequential(),
    );
    on<MarketMakerBotOrderCancelRequested>(
      _onOrderCancelRequested,
      transformer: sequential(),
    );
  }

  final MarketMakerBotRepository _botRepository;
  final MarketMakerBotOrderListRepository _orderRepository;
  final KomodoDefiSdk _kdfSdk;
  StreamSubscription<KdfUser?>? _authListener;
  String? _walletId;

  /// Bumped on every wallet observation, so a sign-out and sign-in into the
  /// same wallet produces a session that compares unequal to the previous one.
  int _walletGeneration = 0;

  void _onWalletObservation(String? walletId) {
    _walletId = walletId;
    _walletGeneration++;
  }

  /// The wallet session a bot mutation should be bound to, or `null` when
  /// signed out.
  MarketMakerBotWalletSession? captureWalletSession() {
    final walletId = _walletId;
    if (walletId == null) return null;
    return MarketMakerBotWalletSession(
      walletId: walletId,
      generation: _walletGeneration,
    );
  }

  bool _isCurrentWalletSession(MarketMakerBotWalletSession session) {
    return _walletId == session.walletId &&
        _walletGeneration == session.generation;
  }

  Future<void> _cancelOrdersForSession(
    List<TradeCoinPairConfig> tradePairs,
  ) async {
    final session = captureWalletSession();
    await _orderRepository.cancelOrders(
      tradePairs,
      walletSession: session,
      isSessionCurrent: session == null
          ? null
          : () => _isCurrentWalletSession(session),
    );
  }

  @override
  Future<void> close() {
    _authListener?.cancel();
    return super.close();
  }

  Future<void> _onStartRequested(
    MarketMakerBotStartRequested event,
    Emitter<MarketMakerBotState> emit,
  ) async {
    if (state.isRunning || state.isUpdating) {
      return;
    }

    emit(const MarketMakerBotState.starting());
    try {
      await _botRepository.start(botId: event.botId);
      emit(const MarketMakerBotState.running());
    } catch (e) {
      final isAlreadyStarted =
          e is RpcException && e.error.errorType == RpcErrorType.alreadyStarted;
      if (isAlreadyStarted) {
        emit(const MarketMakerBotState.running());
        return;
      }
      // Log bot error
      GetIt.I<AnalyticsRepo>().queueEvent(
        MarketbotErrorEventData(
          failureDetail: 'start_failed',
          strategyType: 'simple',
        ),
      );
      emit(const MarketMakerBotState.stopped().copyWith(error: e.toString()));
    }
  }

  Future<void> _onStopRequested(
    MarketMakerBotStopRequested event,
    Emitter<MarketMakerBotState> emit,
  ) async {
    try {
      emit(const MarketMakerBotState.stopping());
      await _botRepository.stop(botId: event.botId);
      await _waitForOrdersToBeCancelled(
        timeout: const Duration(minutes: 1),
        fatalTimeout: false,
      );
      emit(const MarketMakerBotState.stopped());
    } catch (e) {
      // Log bot error
      GetIt.I<AnalyticsRepo>().queueEvent(
        MarketbotErrorEventData(
          failureDetail: 'stop_failed',
          strategyType: 'simple',
        ),
      );
      emit(
        const MarketMakerBotState.stopped().copyWith(
          error: 'Failed to stop the bot',
        ),
      );
    }
  }

  Future<void> _onOrderUpdateRequested(
    MarketMakerBotOrderUpdateRequested event,
    Emitter<MarketMakerBotState> emit,
  ) async {
    emit(const MarketMakerBotState.stopping());

    try {
      // Add the trade pair to stored settings immediately to provide feedback
      // and updates to the user.
      await _botRepository.addTradePairToStoredSettings(event.tradePair);

      // Cancel the order immediately to provide feedback to the user that
      // the bot is being updated, since the restart process may take some time.
      await _cancelOrdersForSession([event.tradePair]);
      final Stream<MarketMakerBotStatus> botStatusStream = _botRepository
          .updateOrder(event.tradePair, botId: event.botId);
      await for (final botStatus in botStatusStream) {
        emit(state.copyWith(status: botStatus));
      }
    } catch (e) {
      final isAlreadyStarted =
          e is RpcException && e.error.errorType == RpcErrorType.alreadyStarted;
      if (isAlreadyStarted) {
        emit(const MarketMakerBotState.running());
        return;
      }

      final stoppingState = const MarketMakerBotState.stopping().copyWith(
        error: e.toString(),
      );
      emit(stoppingState);
      // Log bot error
      GetIt.I<AnalyticsRepo>().queueEvent(
        MarketbotErrorEventData(
          failureDetail: 'update_failed',
          strategyType: 'simple',
        ),
      );
      await _botRepository.stop(botId: event.botId);
      emit(stoppingState.copyWith(status: MarketMakerBotStatus.stopped));
    }
  }

  Future<void> _onOrderCancelRequested(
    MarketMakerBotOrderCancelRequested event,
    Emitter<MarketMakerBotState> emit,
  ) async {
    emit(const MarketMakerBotState.stopping());

    try {
      await _cancelOrdersForSession(event.tradePairs.toList());

      final botStatusStream = _botRepository.cancelOrders(
        event.tradePairs,
        botId: event.botId,
      );
      await for (final botStatus in botStatusStream) {
        emit(state.copyWith(status: botStatus));
      }

      // Remove the trade pairs from the stored settings after the orders have
      // been cancelled to prevent the lag between the orders being cancelled
      // and the trade pairs being removed from the settings.
      await _botRepository.removeTradePairsFromStoredSettings(
        event.tradePairs.toList(),
      );
    } catch (e) {
      final isAlreadyStarted =
          e is RpcException && e.error.errorType == RpcErrorType.alreadyStarted;
      if (isAlreadyStarted) {
        emit(const MarketMakerBotState.running());
        return;
      }

      final stoppingState = const MarketMakerBotState.stopping().copyWith(
        error: e.toString(),
      );
      emit(stoppingState);
      // Log bot error
      GetIt.I<AnalyticsRepo>().queueEvent(
        MarketbotErrorEventData(
          failureDetail: 'cancel_failed',
          strategyType: 'simple',
        ),
      );
      await _botRepository.stop(botId: event.botId);
      emit(stoppingState.copyWith(status: MarketMakerBotStatus.stopped));
    }
  }

  /// Waits for all orders to be cancelled.
  ///
  /// Throws a [TimeoutException] if the orders are not cancelled in time if
  /// [fatalTimeout] is `true`. Otherwise, the function returns without throwing
  Future<void> _waitForOrdersToBeCancelled({
    Duration timeout = const Duration(seconds: 30),
    bool fatalTimeout = true,
  }) async {
    final start = DateTime.now();
    final orders = await _orderRepository.getTradePairs();
    while (orders.any((order) => order.order != null)) {
      if (DateTime.now().difference(start) > timeout) {
        if (fatalTimeout) {
          // Log bot error
          GetIt.I<AnalyticsRepo>().queueEvent(
            MarketbotErrorEventData(
              failureDetail: 'timeout_cancelling',
              strategyType: 'simple',
            ),
          );
          throw TimeoutException('Failed to cancel orders in time');
        }
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}

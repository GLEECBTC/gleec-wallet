import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/analytics/events/advanced_trading_events.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/dex_repository.dart';
import 'package:web_dex/model/swap.dart';
import 'package:web_dex/model/trading_entity_id.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';
import 'package:web_dex/services/orders_service/my_orders_service.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/dex/entity_details/maker_order/maker_order_details_page.dart';
import 'package:web_dex/views/dex/entity_details/swap/swap_details_page.dart';
import 'package:web_dex/views/dex/entity_details/taker_order/taker_order_details_page.dart';
import 'package:web_dex/views/dex/common/dex_responsive.dart';

/// Distinguishes what entity the uuid represents
enum TradingEntityKind { order, swap }

class TradingDetails extends StatefulWidget {
  const TradingDetails({
    super.key,
    required this.uuid,
    this.kind = TradingEntityKind.swap,
  });

  final String uuid;
  final TradingEntityKind kind;

  @override
  State<TradingDetails> createState() => _TradingDetailsState();
}

class _TradingDetailsState extends State<TradingDetails> {
  final ScrollController _scrollController = ScrollController();
  Timer? _statusTimer;
  StreamSubscription<SwapStatusEvent>? _swapStatusSubscription;
  StreamSubscription<OrderStatusEvent>? _orderStatusSubscription;

  Swap? _swapStatus;
  OrderStatus? _orderStatus;
  final Set<int> _statusUpdatesInProgress = <int>{};
  final Stopwatch _monotonicClock = Stopwatch()..start();
  int? _lastStatusUpdateTick;
  bool _statusUnavailable = false;
  int _statusGeneration = 0;
  bool _loggedSuccess = false;
  bool _loggedFailure = false;

  String? get _normalizedUuid => normalizeTradingEntityUuid(widget.uuid);

  @override
  void initState() {
    super.initState();

    _startMonitoring();
  }

  @override
  void didUpdateWidget(TradingDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uuid == widget.uuid && oldWidget.kind == widget.kind) return;
    _statusGeneration++;
    _statusTimer?.cancel();
    _swapStatusSubscription?.cancel();
    _orderStatusSubscription?.cancel();
    _swapStatusSubscription = null;
    _orderStatusSubscription = null;
    _swapStatus = null;
    _orderStatus = null;
    _statusUnavailable = false;
    _lastStatusUpdateTick = null;
    _loggedSuccess = false;
    _loggedFailure = false;
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    _startMonitoring();
  }

  void _startMonitoring() {
    if (_normalizedUuid == null) {
      _statusUnavailable = true;
      return;
    }
    final generation = _statusGeneration;

    final myOrdersService = RepositoryProvider.of<MyOrdersService>(context);
    final dexRepository = RepositoryProvider.of<DexRepository>(context);
    final sdk = RepositoryProvider.of<KomodoDefiSdk>(context);

    _statusTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _scheduleStatusUpdate(
        dexRepository,
        myOrdersService,
        generation: generation,
      );
    });

    _scheduleStatusUpdate(
      dexRepository,
      myOrdersService,
      force: true,
      generation: generation,
    );
    _initStreaming(
      sdk,
      dexRepository,
      myOrdersService,
      generation: generation,
    ).ignore();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _swapStatusSubscription?.cancel();
    _orderStatusSubscription?.cancel();
    _scrollController.dispose();

    super.dispose();
  }

  Future<void> _initStreaming(
    KomodoDefiSdk sdk,
    DexRepository dexRepository,
    MyOrdersService myOrdersService, {
    required int generation,
  }) async {
    try {
      if (widget.kind == TradingEntityKind.swap) {
        final subscription = await sdk.subscribeToSwapStatus();
        if (!mounted || generation != _statusGeneration) {
          await subscription.cancel();
          return;
        }

        _swapStatusSubscription = subscription;
        _swapStatusSubscription?.onError((Object _, StackTrace trace) {
          _streamFailed(generation, trace);
        });
        _swapStatusSubscription?.onData((event) {
          if (generation != _statusGeneration ||
              normalizeTradingEntityUuid(event.uuid) != _normalizedUuid) {
            return;
          }
          _scheduleStatusUpdate(
            dexRepository,
            myOrdersService,
            generation: generation,
          );
        });
      } else {
        final subscription = await sdk.subscribeToOrderStatus();
        if (!mounted || generation != _statusGeneration) {
          await subscription.cancel();
          return;
        }

        _orderStatusSubscription = subscription;
        _orderStatusSubscription?.onError((Object _, StackTrace trace) {
          _streamFailed(generation, trace);
        });
        _orderStatusSubscription?.onData((event) {
          if (generation != _statusGeneration ||
              normalizeTradingEntityUuid(event.uuid) != _normalizedUuid) {
            return;
          }
          _scheduleStatusUpdate(
            dexRepository,
            myOrdersService,
            generation: generation,
          );
        });
      }
    } catch (_, s) {
      log(
        'Advanced trading detail updates are temporarily unavailable.',
        path: 'TradingDetails._initStreaming',
        trace: s,
        isError: true,
      );
    }
  }

  void _streamFailed(int generation, StackTrace trace) {
    log(
      'Advanced trading detail update stream failed.',
      path: 'TradingDetails._initStreaming',
      trace: trace,
      isError: true,
    );
    if (!mounted || generation != _statusGeneration) return;
    setState(() => _statusUnavailable = true);
  }

  void _scheduleStatusUpdate(
    DexRepository dexRepository,
    MyOrdersService myOrdersService, {
    bool force = false,
    int? generation,
  }) {
    final requestGeneration = generation ?? _statusGeneration;
    if (requestGeneration != _statusGeneration) return;
    if (_statusUpdatesInProgress.contains(requestGeneration)) return;

    final nowTick = _monotonicClock.elapsedMilliseconds;
    final lastUpdateTick = _lastStatusUpdateTick;
    if (!force && lastUpdateTick != null && nowTick - lastUpdateTick < 500) {
      return;
    }

    _statusUpdatesInProgress.add(requestGeneration);
    () async {
      try {
        await _updateStatus(
          dexRepository,
          myOrdersService,
          generation: requestGeneration,
        );
        if (requestGeneration != _statusGeneration) return;
        _lastStatusUpdateTick = _monotonicClock.elapsedMilliseconds;
      } finally {
        _statusUpdatesInProgress.remove(requestGeneration);
      }
    }().ignore();
  }

  @override
  Widget build(BuildContext context) {
    final dynamic entityStatus =
        _swapStatus ??
        _orderStatus?.takerOrderStatus ??
        _orderStatus?.makerOrderStatus;

    if (entityStatus == null) {
      return Center(
        child: _statusUnavailable
            ? Semantics(
                liveRegion: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 40),
                    const SizedBox(height: 12),
                    Text('advancedTradingDetailsUnavailable'.tr()),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text('advancedTryAgain'.tr()),
                    ),
                  ],
                ),
              )
            : const UiSpinner(),
      );
    }
    return ScreenshotSensitive(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final spec = DexResponsiveSpec.fromWidth(constraints.maxWidth);
          return DexScrollbar(
            scrollController: _scrollController,
            isMobile: spec.usesMobileLists,
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Padding(
                    padding: EdgeInsets.all(spec.gutter),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_statusUnavailable) ...[
                          Semantics(
                            liveRegion: true,
                            child: MaterialBanner(
                              content: Text(
                                'advancedTradingDetailsLastKnown'.tr(),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: _retry,
                                  child: Text('advancedTryAgain'.tr()),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        _getDetailsPage(entityStatus),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _getDetailsPage(dynamic entityStatus) {
    if (entityStatus is Swap) {
      return SwapDetailsPage(entityStatus);
    } else if (entityStatus is TakerOrderStatus) {
      return TakerOrderDetailsPage(entityStatus);
    } else if (entityStatus is MakerOrderStatus) {
      return MakerOrderDetailsPage(entityStatus);
    }

    return const SizedBox.shrink();
  }

  Future<void> _updateStatus(
    DexRepository dexRepository,
    MyOrdersService myOrdersService, {
    required int generation,
  }) async {
    Swap? swapStatus;
    OrderStatus? orderStatus;
    final uuid = _normalizedUuid;
    if (uuid == null) {
      if (mounted && generation == _statusGeneration) {
        setState(() => _statusUnavailable = true);
      }
      return;
    }
    try {
      if (widget.kind == TradingEntityKind.swap) {
        swapStatus = await dexRepository.getSwapStatus(uuid);
      } else if (widget.kind == TradingEntityKind.order) {
        orderStatus = await myOrdersService.getStatus(uuid);
      }
    } catch (_, s) {
      log(
        'Advanced trading details refresh failed.',
        path: 'TradingDetails._updateStatus',
        trace: s,
        isError: true,
      );
      if (!mounted || generation != _statusGeneration) return;
      setState(() => _statusUnavailable = true);
      return;
    }

    if (!mounted || generation != _statusGeneration) return;
    final validSwap = swapStatus == null || _isValidSwapStatus(swapStatus);
    final validOrder = orderStatus == null || _isValidOrderStatus(orderStatus);
    if ((swapStatus == null && orderStatus == null) ||
        !validSwap ||
        !validOrder) {
      setState(() => _statusUnavailable = true);
      return;
    }
    setState(() {
      if (swapStatus != null) _swapStatus = swapStatus;
      if (orderStatus != null) _orderStatus = orderStatus;
      _statusUnavailable = false;
    });

    if (swapStatus != null) {
      final int? rawDurationMs =
          swapStatus.events.isNotEmpty && swapStatus.myInfo != null
          ? swapStatus.events.last.timestamp -
                swapStatus.myInfo!.startedAt * 1000
          : null;
      final durationMs = rawDurationMs == null || rawDurationMs < 0
          ? null
          : rawDurationMs;
      if (swapStatus.isSuccessful && !_loggedSuccess) {
        _loggedSuccess = true;
        _logLifecycle(AdvancedTradeOutcome.completed, durationMs: durationMs);
      } else if (swapStatus.isFailed && !_loggedFailure) {
        _loggedFailure = true;
        _logLifecycle(AdvancedTradeOutcome.failed, durationMs: durationMs);
      }
    }
  }

  bool _isValidSwapStatus(Swap status) {
    final makerAmount = status.makerAmount.toDouble();
    final takerAmount = status.takerAmount.toDouble();
    return normalizeTradingEntityUuid(status.uuid) == _normalizedUuid &&
        status.makerCoin.trim().isNotEmpty &&
        status.takerCoin.trim().isNotEmpty &&
        makerAmount.isFinite &&
        makerAmount > 0 &&
        takerAmount.isFinite &&
        takerAmount > 0 &&
        status.events.every(
          (event) => event.timestamp >= 0 && event.event.type.trim().isNotEmpty,
        );
  }

  bool _isValidOrderStatus(OrderStatus status) {
    final order =
        status.takerOrderStatus?.order ?? status.makerOrderStatus?.order;
    if (order == null ||
        normalizeTradingEntityUuid(order.uuid) != _normalizedUuid) {
      return false;
    }
    final baseAmount = order.baseAmount.toDouble();
    final relAmount = order.relAmount.toDouble();
    return order.base.trim().isNotEmpty &&
        order.rel.trim().isNotEmpty &&
        baseAmount.isFinite &&
        baseAmount > 0 &&
        relAmount.isFinite &&
        relAmount > 0;
  }

  void _retry() {
    final dexRepository = RepositoryProvider.of<DexRepository>(context);
    final myOrdersService = RepositoryProvider.of<MyOrdersService>(context);
    _scheduleStatusUpdate(
      dexRepository,
      myOrdersService,
      force: true,
      generation: _statusGeneration,
    );
  }

  void _logLifecycle(AdvancedTradeOutcome outcome, {required int? durationMs}) {
    context.read<AnalyticsBloc>().add(
      AnalyticsAdvancedTradeLifecycleEvent(
        kind: widget.kind == TradingEntityKind.order
            ? AdvancedTradeKind.makerOrder
            : AdvancedTradeKind.takerSwap,
        outcome: outcome,
        durationBucket: advancedTradeDurationBucket(
          durationMs == null ? null : Duration(milliseconds: durationMs),
        ),
      ),
    );
  }
}

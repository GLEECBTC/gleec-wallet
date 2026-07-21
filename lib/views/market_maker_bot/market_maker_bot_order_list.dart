import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_bot/market_maker_bot_bloc.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_bot/market_maker_bot_wallet_session.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_order_list/market_maker_order_list_bloc.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_order_list/market_maker_bot_order_list_repository.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_order_list/trade_pair.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/trading_entities_filter.dart';
import 'package:web_dex/shared/ui/ui_light_button.dart';
import 'package:web_dex/views/dex/common/dex_confirmation_dialog.dart';
import 'package:web_dex/views/market_maker_bot/animated_bot_status_indicator.dart';
import 'package:web_dex/views/market_maker_bot/market_maker_bot_order_list_header.dart';
import 'package:web_dex/views/market_maker_bot/trade_pair_list_item.dart';

class MarketMakerBotOrdersList extends StatefulWidget {
  const MarketMakerBotOrdersList({
    required this.entitiesFilterData,
    super.key,
    this.onEdit,
    this.onCancel,
    this.onCancelAll,
  });

  final TradingEntitiesFilter? entitiesFilterData;
  final void Function(TradePair, MarketMakerBotWalletSession)? onEdit;
  final Future<MarketMakerBotCancellationResult> Function(
    TradePair,
    MarketMakerBotWalletSession,
  )?
  onCancel;
  final Future<MarketMakerBotCancellationResult> Function(
    List<TradePair>,
    MarketMakerBotWalletSession,
  )?
  onCancelAll;

  @override
  State<MarketMakerBotOrdersList> createState() =>
      _MarketMakerBotOrdersListState();
}

class _MarketMakerBotOrdersListState extends State<MarketMakerBotOrdersList> {
  final _mainScrollController = ScrollController();
  bool _isCancelling = false;
  bool _isStopping = false;

  @override
  void initState() {
    context.read<MarketMakerOrderListBloc>().add(
      const MarketMakerOrderListRequested(Duration(seconds: 3)),
    );
    super.initState();
  }

  @override
  void dispose() {
    _mainScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(MarketMakerBotOrdersList oldWidget) {
    if (oldWidget.entitiesFilterData != widget.entitiesFilterData) {
      context.read<MarketMakerOrderListBloc>().add(
        MarketMakerOrderListFilterChanged(widget.entitiesFilterData),
      );
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MarketMakerOrderListBloc, MarketMakerOrderListState>(
      builder: (context, state) {
        if (state.status == MarketMakerOrderListStatus.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.status == MarketMakerOrderListStatus.failure) {
          return _buildUnavailableStatus(context);
        }

        return BlocBuilder<MarketMakerBotBloc, MarketMakerBotState>(
          builder: (context, botState) {
            final botBloc = context.read<MarketMakerBotBloc>();
            final walletSession = state.walletSession;
            final hasCurrentWalletSnapshot =
                state.status == MarketMakerOrderListStatus.success &&
                walletSession != null &&
                botBloc.captureWalletSession() == walletSession &&
                identical(
                  botBloc.captureOrderOwnership(walletSession),
                  state.orderCorrelation,
                );
            final allConfiguredOrders = state.allMakerBotOrders;
            final shouldStopBot =
                botState.isRunning || !botState.lifecycleProvenStopped;
            if (state.status == MarketMakerOrderListStatus.success &&
                !hasCurrentWalletSnapshot) {
              return _buildUnavailableStatus(context);
            }

            return Column(
              children: [
                if (!isMobile)
                  Column(
                    children: [
                      const Align(
                        alignment: Alignment.bottomRight,
                        child: SizedBox(height: 8),
                      ),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            AnimatedBotStatusIndicator(status: botState.status),
                            const SizedBox(width: 24),
                            UiPrimaryButton(
                              text: shouldStopBot
                                  ? LocaleKeys.mmBotStop.tr()
                                  : LocaleKeys.mmBotStart.tr(),
                              width: 120,
                              height: 32,
                              textStyle: const TextStyle(fontSize: 12),
                              onPressed:
                                  _isCancelling ||
                                      _isStopping ||
                                      botState.isUpdating ||
                                      !hasCurrentWalletSnapshot ||
                                      (!shouldStopBot &&
                                          allConfiguredOrders.isEmpty)
                                  ? null
                                  : shouldStopBot
                                  ? () => _onStopBotPressed(
                                      List<TradePair>.unmodifiable(
                                        allConfiguredOrders,
                                      ),
                                      walletSession,
                                    )
                                  : () => _onStartBotPressed(walletSession),
                            ),
                            const SizedBox(width: 12),
                            UiPrimaryButton(
                              text: LocaleKeys.cancelAll.tr(),
                              width: 120,
                              height: 32,
                              textStyle: const TextStyle(fontSize: 12),
                              onPressed:
                                  _isCancelling ||
                                      _isStopping ||
                                      botState.isUpdating ||
                                      !botState.isRunning ||
                                      !hasCurrentWalletSnapshot ||
                                      allConfiguredOrders.isEmpty
                                  ? null
                                  : () => _confirmCancelAll(
                                      List<TradePair>.unmodifiable(
                                        allConfiguredOrders,
                                      ),
                                      walletSession,
                                    ),
                            ),
                          ],
                        ),
                      ),
                      MarketMakerBotOrderListHeader(
                        sortData: state.sortData,
                        onSortChange: _onSortChange,
                      ),
                    ],
                  ),
                Flexible(
                  child: Padding(
                    padding: EdgeInsets.only(top: isMobile ? 0 : 10.0),
                    child: DexScrollbar(
                      isMobile: isMobile,
                      scrollController: _mainScrollController,
                      child: ListView.builder(
                        shrinkWrap: true,
                        controller: _mainScrollController,
                        itemCount: state.makerBotOrders.length,
                        itemBuilder: (BuildContext context, int index) {
                          final TradePair pair = state.makerBotOrders[index];
                          return TradePairListItem(
                            pair,
                            isBotRunning:
                                botState.isRunning || botState.isUpdating,
                            // Bot rows intentionally do not open the generic
                            // order details page because that page exposes a
                            // direct UUID cancellation outside this lifecycle.
                            onTap: null,
                            actions: [
                              UiLightButton(
                                text: LocaleKeys.edit.tr(),
                                width: 60,
                                height: 22,
                                backgroundColor: Colors.transparent,
                                border: Border.all(
                                  color: const Color.fromRGBO(234, 234, 234, 1),
                                ),
                                textStyle: const TextStyle(fontSize: 12),
                                onPressed:
                                    _isCancelling ||
                                        _isStopping ||
                                        botState.isUpdating ||
                                        !hasCurrentWalletSnapshot
                                    ? null
                                    : () => widget.onEdit?.call(
                                        pair,
                                        walletSession,
                                      ),
                              ),
                              UiLightButton(
                                text: LocaleKeys.cancel.tr(),
                                width: 60,
                                height: 22,
                                backgroundColor: Colors.transparent,
                                border: Border.all(
                                  color: const Color.fromRGBO(234, 234, 234, 1),
                                ),
                                textStyle: const TextStyle(fontSize: 12),
                                onPressed:
                                    _isCancelling ||
                                        _isStopping ||
                                        botState.isUpdating ||
                                        !hasCurrentWalletSnapshot
                                    ? null
                                    : () => _confirmCancel(pair, walletSession),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildUnavailableStatus(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'marketMakerOrderStatusUnavailable'.tr(),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          UiPrimaryButton(
            text: 'marketMakerOrderStatusRetry'.tr(),
            width: 120,
            height: 32,
            onPressed: () {
              context.read<MarketMakerOrderListBloc>().add(
                const MarketMakerOrderListRequested(Duration(seconds: 3)),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _confirmCancel(
    TradePair pair,
    MarketMakerBotWalletSession walletSession,
  ) async {
    final callback = widget.onCancel;
    if (callback == null || _isCancelling) return;
    if (!_hasSuccessfulSnapshot(walletSession)) {
      _showUnavailableSnapshot(walletSession);
      return;
    }
    final confirmed = await showDexActionConfirmation(
      context: context,
      actionLabel: LocaleKeys.cancelOrder.tr(),
      targetDescription:
          '${pair.config.baseCoinId}/${pair.config.relCoinId} configured strategy\n\n'
          '${'marketMakerRestartImpact'.tr()}',
      confirmButtonKey: const Key('market-maker-cancel-order-confirm'),
    );
    if (!confirmed || !mounted || _isCancelling) return;
    if (!_hasSuccessfulSnapshot(walletSession)) {
      _showUnavailableSnapshot(walletSession);
      return;
    }
    setState(() => _isCancelling = true);
    MarketMakerBotCancellationResult? result;
    try {
      result = await callback(pair, walletSession);
    } on Object {
      result = null;
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
    if (mounted) _showCancellationResult(result);
  }

  Future<void> _confirmCancelAll(
    List<TradePair> orders,
    MarketMakerBotWalletSession walletSession,
  ) async {
    final callback = widget.onCancelAll;
    if (callback == null || orders.isEmpty || _isCancelling) return;
    if (!_hasSuccessfulSnapshot(walletSession)) {
      _showUnavailableSnapshot(walletSession);
      return;
    }
    final confirmed = await showDexActionConfirmation(
      context: context,
      actionLabel: LocaleKeys.cancelAll.tr(),
      targetDescription:
          '${'marketMakerAllConfiguredPairsTarget'.tr(namedArgs: {'count': '${orders.length}', 'pairs': _configuredPairsLabel(orders)})}\n\n'
          '${'marketMakerCancelAllImpact'.tr()}',
      confirmButtonKey: const Key('market-maker-cancel-all-confirm'),
    );
    if (!confirmed || !mounted || _isCancelling) return;
    if (!_hasSuccessfulSnapshot(walletSession)) {
      _showUnavailableSnapshot(walletSession);
      return;
    }
    setState(() => _isCancelling = true);
    MarketMakerBotCancellationResult? result;
    try {
      result = await callback(orders, walletSession);
    } on Object {
      result = null;
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
    if (mounted) _showCancellationResult(result);
  }

  void _showCancellationResult(MarketMakerBotCancellationResult? result) {
    final message = switch (result) {
      null => 'advancedCancellationRequestFailed'.tr(),
      final value when value.walletChanged =>
        'advancedCancellationWalletChanged'.tr(),
      final value when value.uncertainCount > 0 =>
        'marketMakerCancellationMixed'.tr(
          namedArgs: {
            'cancelled': '${value.completedCount}',
            'failed': '${value.failedCount}',
            'uncertain': '${value.uncertainCount}',
          },
        ),
      final value when value.isComplete => 'advancedCancellationComplete'.tr(
        namedArgs: {
          'cancelled': '${value.completedCount}',
          'attempted': '${value.requestedCount}',
        },
      ),
      final value when value.completedCount > 0 =>
        'advancedCancellationPartial'.tr(
          namedArgs: {
            'cancelled': '${value.completedCount}',
            'failed': '${value.failedCount}',
          },
        ),
      final value => 'advancedCancellationTotalFailed'.tr(
        namedArgs: {
          'failed': '${value.failedCount}',
          'attempted': '${value.requestedCount}',
        },
      ),
    };
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _onStopBotPressed(
    List<TradePair> orders,
    MarketMakerBotWalletSession walletSession,
  ) async {
    if (_isStopping) return;
    final botBloc = context.read<MarketMakerBotBloc>();
    if (!_hasSuccessfulSnapshot(walletSession)) {
      _showUnavailableSnapshot(walletSession);
      return;
    }
    final confirmed = await showDexActionConfirmation(
      context: context,
      actionLabel: LocaleKeys.mmBotStop.tr(),
      targetDescription:
          '${'marketMakerStopTarget'.tr(namedArgs: {'count': '${orders.length}', 'pairs': orders.isEmpty ? '—' : _configuredPairsLabel(orders)})}\n\n'
          '${'marketMakerBootstrapStopImpact'.tr()}',
      confirmButtonKey: const Key('market-maker-stop-confirm'),
    );
    if (!confirmed || !mounted) return;
    if (!_hasSuccessfulSnapshot(walletSession)) {
      _showUnavailableSnapshot(walletSession);
      return;
    }
    setState(() => _isStopping = true);
    MarketMakerBotStopResult result;
    try {
      result = await botBloc.stopAndWait(
        walletSession: walletSession,
        expectedTradePairs: orders.map((pair) => pair.config),
      );
    } on Object {
      result = const MarketMakerBotStopResult(MarketMakerBotStopOutcome.failed);
    } finally {
      if (mounted) setState(() => _isStopping = false);
    }
    if (mounted) _showStopResult(result);
  }

  void _onStartBotPressed(MarketMakerBotWalletSession walletSession) {
    final botBloc = context.read<MarketMakerBotBloc>();
    if (!_hasSuccessfulSnapshot(walletSession)) {
      _showUnavailableSnapshot(walletSession);
      return;
    }
    final configurationSnapshot = context
        .read<MarketMakerOrderListBloc>()
        .state
        .configurationSnapshot;
    if (!botBloc.requestStart(
      walletSession: walletSession,
      expectedTradePairs: configurationSnapshot,
    )) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('marketMakerLifecycleBusy'.tr())));
    }
  }

  bool _isCurrentWalletSession(MarketMakerBotWalletSession walletSession) {
    return context.read<MarketMakerBotBloc>().captureWalletSession() ==
        walletSession;
  }

  bool _hasSuccessfulSnapshot(MarketMakerBotWalletSession walletSession) {
    final orderState = context.read<MarketMakerOrderListBloc>().state;
    return orderState.status == MarketMakerOrderListStatus.success &&
        orderState.walletSession == walletSession &&
        identical(
          context.read<MarketMakerBotBloc>().captureOrderOwnership(
            walletSession,
          ),
          orderState.orderCorrelation,
        ) &&
        _isCurrentWalletSession(walletSession);
  }

  void _showUnavailableSnapshot(MarketMakerBotWalletSession walletSession) {
    if (!_isCurrentWalletSession(walletSession)) {
      _showWalletChanged();
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('marketMakerOrderStatusUnavailable'.tr())),
    );
  }

  void _showWalletChanged() {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text('marketMakerWalletChanged'.tr())));
  }

  void _showStopResult(MarketMakerBotStopResult result) {
    final message = switch (result.outcome) {
      MarketMakerBotStopOutcome.stopped => 'marketMakerStopComplete'.tr(),
      MarketMakerBotStopOutcome.walletChanged =>
        'marketMakerWalletChanged'.tr(),
      MarketMakerBotStopOutcome.uncertain => 'marketMakerStopUncertain'.tr(),
      MarketMakerBotStopOutcome.failed => 'marketMakerStopFailed'.tr(),
    };
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: result.isStopped
            ? null
            : Theme.of(context).colorScheme.error,
      ),
    );
  }

  String _configuredPairsLabel(Iterable<TradePair> orders) {
    final labels =
        orders
            .map((pair) => '${pair.config.baseCoinId}/${pair.config.relCoinId}')
            .toSet()
            .toList()
          ..sort();
    return labels.join(', ');
  }

  void _onSortChange(SortData<MarketMakerBotOrderListType> sortData) {
    context.read<MarketMakerOrderListBloc>().add(
      MarketMakerOrderListSortChanged(sortData),
    );
  }
}

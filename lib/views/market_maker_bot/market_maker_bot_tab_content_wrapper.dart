import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/dex_tab_bar/dex_tab_bar_bloc.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_bot/market_maker_bot_bloc.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_bot/market_maker_bot_wallet_session.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_order_list/market_maker_order_list_bloc.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_order_list/market_maker_bot_order_list_repository.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_order_list/trade_pair.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_trade_form/market_maker_trade_form_bloc.dart';
import 'package:web_dex/blocs/trading_entities_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/swap.dart';
import 'package:web_dex/model/trading_entities_filter.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/views/dex/common/dex_confirmation_dialog.dart';
import 'package:web_dex/views/dex/dex_list_filter/desktop/dex_list_filter_desktop.dart';
import 'package:web_dex/views/dex/dex_list_filter/mobile/dex_list_filter_mobile.dart';
import 'package:web_dex/views/dex/dex_list_filter/mobile/dex_list_header_mobile.dart';
import 'package:web_dex/views/dex/entities_list/history/history_list.dart';
import 'package:web_dex/views/dex/entities_list/in_progress/in_progress_list.dart';
import 'package:web_dex/views/market_maker_bot/animated_bot_status_indicator.dart';
import 'package:web_dex/views/market_maker_bot/market_maker_bot_form.dart';
import 'package:web_dex/views/market_maker_bot/market_maker_bot_order_list.dart';
import 'package:web_dex/views/market_maker_bot/market_maker_bot_tab_type.dart';

class MarketMakerBotTabContentWrapper extends StatefulWidget {
  const MarketMakerBotTabContentWrapper(
    this.listType, {
    this.filter,
    super.key,
  });

  final MarketMakerBotTabType listType;
  final TradingEntitiesFilter? filter;

  @override
  State<MarketMakerBotTabContentWrapper> createState() =>
      _MarketMakerBotTabContentWrapperState();
}

class _MarketMakerBotTabContentWrapperState
    extends State<MarketMakerBotTabContentWrapper> {
  bool _isFilterShown = false;
  MarketMakerBotTabType? previouseType;

  @override
  Widget build(BuildContext context) {
    previouseType ??= widget.listType;
    if (previouseType != widget.listType) {
      _isFilterShown = false;
      previouseType = widget.listType;
    }
    final child = _SelectedTabContent(
      key: Key('dex-list-${widget.listType}'),
      filter: widget.filter,
      type: widget.listType,
    );

    // the reason why the widgets need to prop drill all filter data,
    // is because the widget wraps a table with filters and a dex/market
    // maker widget. Widget type = enum value at current tab index
    return isMobile
        ? _MobileWidget(
            key: const Key('dex-list-wrapper-mobile'),
            type: widget.listType,
            filterData: widget.filter,
            onApplyFilter: _setFilter,
            isFilterShown: _isFilterShown,
            onFilterTap: () => setState(() {
              _isFilterShown = !_isFilterShown;
            }),
            child: child,
          )
        : _DesktopWidget(
            key: const Key('dex-list-wrapper-desktop'),
            type: widget.listType,
            filterData: widget.filter,
            onApplyFilter: _setFilter,
            child: child,
          );
  }

  void _setFilter(TradingEntitiesFilter? filter) {
    context.read<DexTabBarBloc>().add(
      FilterChanged(tabType: widget.listType, filter: filter),
    );
  }
}

class _SelectedTabContent extends StatelessWidget {
  const _SelectedTabContent({this.filter, required this.type, super.key});

  // TODO: get the current filter and type from BLoC state
  final TradingEntitiesFilter? filter;
  final MarketMakerBotTabType type;

  @override
  Widget build(BuildContext context) {
    final marketMakerBotBloc = context.read<MarketMakerBotBloc>();

    switch (type) {
      case MarketMakerBotTabType.orders:
        return MarketMakerBotOrdersList(
          entitiesFilterData: filter,
          onEdit: (order, walletSession) =>
              _editTradingBotOrder(context, order, walletSession),
          onCancel: (order, walletSession) => _deleteTradingBotOrders(
            context,
            [order],
            marketMakerBotBloc,
            walletSession,
          ),
          onCancelAll: (orders, walletSession) => _deleteTradingBotOrders(
            context,
            orders,
            marketMakerBotBloc,
            walletSession,
          ),
        );
      case MarketMakerBotTabType.inProgress:
        return InProgressList(
          entitiesFilterData: filter,
          onItemClick: _onSwapItemClick,
        );
      case MarketMakerBotTabType.history:
        return HistoryList(
          entitiesFilterData: filter,
          onItemClick: _onSwapItemClick,
        );
      case MarketMakerBotTabType.marketMaker:
        return const MarketMakerBotForm();
    }
  }

  /// Cancels the existing order, updates the trading pairs in the settings
  /// and updates the market maker bot.
  ///
  /// [tradePair] the order to delete
  /// [marketMakerBotBloc] the market maker bot bloc
  Future<MarketMakerBotCancellationResult> _deleteTradingBotOrders(
    BuildContext context,
    Iterable<TradePair> tradePair,
    MarketMakerBotBloc marketMakerBotBloc,
    MarketMakerBotWalletSession walletSession,
  ) {
    final orderListState = context.read<MarketMakerOrderListBloc>().state;
    if (!_isCurrentOrderSnapshot(
      orderListState,
      marketMakerBotBloc,
      walletSession,
    )) {
      return Future.value(
        MarketMakerBotCancellationResult(
          requestedCount: tradePair.length,
          completedCount: 0,
          failedCount: tradePair.length,
          uncertainCount: 0,
        ),
      );
    }
    return marketMakerBotBloc.cancelOrdersAndWait(
      tradePair,
      walletSession: walletSession,
    );
  }

  void _editTradingBotOrder(
    BuildContext context,
    TradePair order,
    MarketMakerBotWalletSession walletSession,
  ) {
    final marketMakerBotBloc = context.read<MarketMakerBotBloc>();
    final orderListState = context.read<MarketMakerOrderListBloc>().state;
    if (!_isCurrentOrderSnapshot(
      orderListState,
      marketMakerBotBloc,
      walletSession,
    )) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('marketMakerOrderStatusUnavailable'.tr())),
      );
      return;
    }
    context.read<MarketMakerTradeFormBloc>().add(
      MarketMakerTradeFormEditOrderRequested(
        order,
        walletSession: walletSession,
      ),
    );
    context.read<DexTabBarBloc>().add(const TabChanged(0));
  }

  bool _isCurrentOrderSnapshot(
    MarketMakerOrderListState orderListState,
    MarketMakerBotBloc botBloc,
    MarketMakerBotWalletSession walletSession,
  ) {
    return orderListState.status == MarketMakerOrderListStatus.success &&
        orderListState.walletSession == walletSession &&
        botBloc.captureWalletSession() == walletSession &&
        identical(
          botBloc.captureOrderOwnership(walletSession),
          orderListState.orderCorrelation,
        );
  }

  void _onSwapItemClick(Swap swap) {
    routingState.marketMakerState.setDetailsAction(swap.uuid);
  }
}

class _MobileWidget extends StatelessWidget {
  final MarketMakerBotTabType type;
  final Widget child;
  final TradingEntitiesFilter? filterData;
  final bool isFilterShown;
  final VoidCallback onFilterTap;
  final void Function(TradingEntitiesFilter?) onApplyFilter;

  const _MobileWidget({
    required this.type,
    required this.child,
    required this.onApplyFilter,
    this.filterData,
    required this.isFilterShown,
    required this.onFilterTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (type == MarketMakerBotTabType.marketMaker) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [Flexible(child: child)],
      );
    } else {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          DexListHeaderMobile(
            entitiesFilterData: filterData,
            listType: type.toDexListType(),
            isFilterShown: isFilterShown,
            onFilterDataChange: onApplyFilter,
            onFilterPressed: onFilterTap,
            centerWidget: type == MarketMakerBotTabType.orders
                ? const _SimplifiedTradingBotControls()
                : null,
            cancelAllActionBuilder: type == MarketMakerBotTabType.orders
                ? () => _createCancelAllAction(context)
                : null,
          ),
          const SizedBox(height: 6),
          Flexible(
            child: isFilterShown
                ? DexListFilterMobile(
                    filterData: filterData,
                    onApplyFilter: onApplyFilter,
                    listType: type.toDexListType(),
                  )
                : child,
          ),
        ],
      );
    }
  }

  DexCancelAllAction _createCancelAllAction(BuildContext context) {
    final orderListBloc = context.read<MarketMakerOrderListBloc>();
    final marketMakerBotBloc = context.read<MarketMakerBotBloc>();
    final orderListState = orderListBloc.state;
    final walletSession = orderListState.walletSession;
    final hasCurrentWalletSnapshot =
        orderListState.status == MarketMakerOrderListStatus.success &&
        walletSession != null &&
        marketMakerBotBloc.captureWalletSession() == walletSession &&
        identical(
          marketMakerBotBloc.captureOrderOwnership(walletSession),
          orderListState.orderCorrelation,
        );
    final orders = hasCurrentWalletSnapshot
        ? List<TradePair>.unmodifiable(orderListState.allMakerBotOrders)
        : const <TradePair>[];
    return DexCancelAllAction(
      targetCount: orders.length,
      targetDescription:
          '${'marketMakerAllConfiguredPairsTarget'.tr(namedArgs: {'count': '${orders.length}', 'pairs': _configuredPairsLabel(orders)})}\n\n'
          '${'marketMakerCancelAllImpact'.tr()}',
      execute: () =>
          _cancelAllOrders(context, orders, marketMakerBotBloc, walletSession),
    );
  }

  Future<CancelAllOrdersResult> _cancelAllOrders(
    BuildContext context,
    List<TradePair> orders,
    MarketMakerBotBloc marketMakerBotBloc,
    MarketMakerBotWalletSession? walletSession,
  ) async {
    final attemptedCount = orders.length;
    final orderListState = context.read<MarketMakerOrderListBloc>().state;
    final hasCurrentSnapshot =
        walletSession != null &&
        orderListState.status == MarketMakerOrderListStatus.success &&
        orderListState.walletSession == walletSession &&
        marketMakerBotBloc.captureWalletSession() == walletSession &&
        identical(
          marketMakerBotBloc.captureOrderOwnership(walletSession),
          orderListState.orderCorrelation,
        );
    if (!hasCurrentSnapshot) {
      return CancelAllOrdersResult(
        attemptedCount: attemptedCount,
        cancelledCount: 0,
        failedCount: attemptedCount,
        walletChanged:
            marketMakerBotBloc.captureWalletSession() != walletSession,
      );
    }
    if (attemptedCount == 0) {
      return const CancelAllOrdersResult(
        attemptedCount: 0,
        cancelledCount: 0,
        failedCount: 0,
        walletChanged: false,
      );
    }
    try {
      final result = await marketMakerBotBloc.cancelOrdersAndWait(
        orders,
        walletSession: walletSession,
      );
      return CancelAllOrdersResult(
        attemptedCount: result.requestedCount,
        cancelledCount: result.completedCount,
        failedCount: result.failedCount,
        walletChanged: result.walletChanged,
        uncertain: result.uncertainCount > 0,
      );
    } on Object {
      return CancelAllOrdersResult(
        attemptedCount: attemptedCount,
        cancelledCount: 0,
        failedCount: attemptedCount,
        walletChanged: false,
      );
    }
  }
}

class _SimplifiedTradingBotControls extends StatelessWidget {
  const _SimplifiedTradingBotControls();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MarketMakerBotBloc, MarketMakerBotState>(
      builder: (context, botState) {
        return BlocBuilder<MarketMakerOrderListBloc, MarketMakerOrderListState>(
          builder: (context, orderListState) {
            final botBloc = context.read<MarketMakerBotBloc>();
            final walletSession = orderListState.walletSession;
            final hasCurrentWalletSnapshot =
                orderListState.status == MarketMakerOrderListStatus.success &&
                walletSession != null &&
                botBloc.captureWalletSession() == walletSession &&
                identical(
                  botBloc.captureOrderOwnership(walletSession),
                  orderListState.orderCorrelation,
                );
            final configuredOrderCount =
                orderListState.allMakerBotOrders.length;
            final shouldStopBot =
                botState.isRunning || !botState.lifecycleProvenStopped;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: AnimatedBotStatusIndicator(
                    status: botState.status,
                    widthThreshold: 100,
                  ),
                ),
                const Spacer(),
                UiPrimaryButton(
                  text: shouldStopBot
                      ? LocaleKeys.mmBotStop.tr()
                      : LocaleKeys.mmBotStart.tr(),
                  width: 100,
                  height: 30,
                  textStyle: const TextStyle(fontSize: 12),
                  onPressed:
                      botState.isUpdating ||
                          !hasCurrentWalletSnapshot ||
                          (!shouldStopBot && configuredOrderCount == 0)
                      ? null
                      : shouldStopBot
                      ? () => _confirmStopBot(
                          context,
                          List<TradePair>.unmodifiable(
                            orderListState.allMakerBotOrders,
                          ),
                          walletSession,
                        )
                      : () => _startBot(context, walletSession),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmStopBot(
    BuildContext context,
    List<TradePair> orders,
    MarketMakerBotWalletSession walletSession,
  ) async {
    final botBloc = context.read<MarketMakerBotBloc>();
    if (!_hasCurrentSnapshot(context, botBloc, walletSession)) {
      _showUnavailableSnapshot(context, botBloc, walletSession);
      return;
    }
    final confirmed = await showDexActionConfirmation(
      context: context,
      actionLabel: LocaleKeys.mmBotStop.tr(),
      targetDescription:
          '${'marketMakerStopTarget'.tr(namedArgs: {'count': '${orders.length}', 'pairs': orders.isEmpty ? '—' : _configuredPairsLabel(orders)})}\n\n'
          '${'marketMakerBootstrapStopImpact'.tr()}',
      confirmButtonKey: const Key('market-maker-mobile-stop-confirm'),
    );
    if (!confirmed || !context.mounted) return;
    if (!_hasCurrentSnapshot(context, botBloc, walletSession)) {
      _showUnavailableSnapshot(context, botBloc, walletSession);
      return;
    }
    MarketMakerBotStopResult result;
    try {
      result = await botBloc.stopAndWait(
        walletSession: walletSession,
        expectedTradePairs: orders.map((pair) => pair.config),
      );
    } on Object {
      result = const MarketMakerBotStopResult(MarketMakerBotStopOutcome.failed);
    }
    if (context.mounted) _showStopResult(context, result);
  }

  void _startBot(
    BuildContext context,
    MarketMakerBotWalletSession walletSession,
  ) {
    final botBloc = context.read<MarketMakerBotBloc>();
    if (!_hasCurrentSnapshot(context, botBloc, walletSession)) {
      _showUnavailableSnapshot(context, botBloc, walletSession);
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

  void _showWalletChanged(BuildContext context) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text('marketMakerWalletChanged'.tr())));
  }

  bool _hasCurrentSnapshot(
    BuildContext context,
    MarketMakerBotBloc botBloc,
    MarketMakerBotWalletSession walletSession,
  ) {
    final orderListState = context.read<MarketMakerOrderListBloc>().state;
    return orderListState.status == MarketMakerOrderListStatus.success &&
        orderListState.walletSession == walletSession &&
        botBloc.captureWalletSession() == walletSession &&
        identical(
          botBloc.captureOrderOwnership(walletSession),
          orderListState.orderCorrelation,
        );
  }

  void _showUnavailableSnapshot(
    BuildContext context,
    MarketMakerBotBloc botBloc,
    MarketMakerBotWalletSession walletSession,
  ) {
    if (botBloc.captureWalletSession() != walletSession) {
      _showWalletChanged(context);
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('marketMakerOrderStatusUnavailable'.tr())),
    );
  }

  void _showStopResult(BuildContext context, MarketMakerBotStopResult result) {
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

class _DesktopWidget extends StatelessWidget {
  final MarketMakerBotTabType type;
  final Widget child;
  final TradingEntitiesFilter? filterData;
  final void Function(TradingEntitiesFilter?) onApplyFilter;
  const _DesktopWidget({
    required this.type,
    required this.child,
    required this.filterData,
    required this.onApplyFilter,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (type == MarketMakerBotTabType.marketMaker) {
      return Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [Flexible(child: child)],
      );
    } else {
      return Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          DexListFilterDesktop(
            filterData: filterData,
            onApplyFilter: onApplyFilter,
            listType: type.toDexListType(),
          ),
          Flexible(child: child),
        ],
      );
    }
  }
}

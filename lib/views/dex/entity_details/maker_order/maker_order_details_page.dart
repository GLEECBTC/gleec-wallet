import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/blocs/trading_entities_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/mm2_api/rpc/order_status/cancellation_reason.dart';
import 'package:web_dex/model/my_orders/my_order.dart';
import 'package:web_dex/router/state/dex_state.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/services/orders_service/my_orders_service.dart';
import 'package:web_dex/shared/ui/ui_light_button.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/views/dex/entity_details/trading_details_coin_pair.dart';
import 'package:web_dex/views/dex/entity_details/trading_details_header.dart';
import 'package:web_dex/views/dex/common/dex_confirmation_dialog.dart';

class MakerOrderDetailsPage extends StatefulWidget {
  const MakerOrderDetailsPage(this.makerOrderStatus, {super.key});

  final MakerOrderStatus makerOrderStatus;

  @override
  State<MakerOrderDetailsPage> createState() => _MakerOrderDetailsPageState();
}

class _MakerOrderDetailsPageState extends State<MakerOrderDetailsPage> {
  bool _inProgress = false;
  String? _cancelingError;

  @override
  Widget build(BuildContext context) {
    final MyOrder order = widget.makerOrderStatus.order;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TradingDetailsHeader(title: LocaleKeys.makerOrderDetails.tr()),
        const SizedBox(height: 40),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TradingDetailsCoinPair(
                  baseCoin: order.base,
                  baseAmount: order.baseAmountAvailable ?? order.baseAmount,
                  relCoin: order.rel,
                  relAmount: order.relAmountAvailable ?? order.relAmount,
                  isOrder: true,
                  swapId: order.uuid,
                ),
                const SizedBox(height: 30),
                _buildDetails(),
                const SizedBox(height: 30),
                _buildCancelButton(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetails() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Table(
        columnWidths: const {0: FlexColumnWidth(1.4), 1: FlexColumnWidth(4)},
        children: [_buildPrice(), _buildCreatedAt(), _buildStatus()],
      ),
    );
  }

  Widget _buildCancelButton() {
    final tradingEntitiesBloc = RepositoryProvider.of<TradingEntitiesBloc>(
      context,
    );
    if (!widget.makerOrderStatus.order.cancelable ||
        !tradingEntitiesBloc.canCancelOrder(
          widget.makerOrderStatus.order.uuid,
        )) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        if (_cancelingError != null)
          Container(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(
              _cancelingError!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        IgnorePointer(
          ignoring: _inProgress,
          child: UiLightButton(
            text: LocaleKeys.cancelOrder.tr(),
            onPressed: _cancelOrder,
            prefix: _inProgress
                ? Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: UiSpinner(
                      width: 10,
                      height: 10,
                      strokeWidth: 1,
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }

  TableRow _buildStatus() {
    final MakerOrderCancellationReason reason =
        widget.makerOrderStatus.cancellationReason;

    String status = LocaleKeys.active.tr();
    switch (reason) {
      case MakerOrderCancellationReason.cancelled:
        status = LocaleKeys.cancelled.tr();
        break;
      case MakerOrderCancellationReason.fulfilled:
        status = LocaleKeys.fulfilled.tr();
        break;
      case MakerOrderCancellationReason.insufficientBalance:
        status = LocaleKeys.cancelledInsufficientBalance.tr();
        break;
      case MakerOrderCancellationReason.none:
        break;
    }

    return TableRow(
      children: [
        SizedBox(
          height: 30,
          child: Text(
            '${LocaleKeys.status.tr()}:',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        Text(status),
      ],
    );
  }

  TableRow _buildCreatedAt() {
    final String createdAt = DateFormat('dd MMM yyyy, HH:mm').format(
      DateTime.fromMillisecondsSinceEpoch(
        widget.makerOrderStatus.order.createdAt * 1000,
      ),
    );

    return TableRow(
      children: [
        SizedBox(
          height: 30,
          child: Text(
            '${LocaleKeys.createdAt.tr()}:',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        Text(createdAt),
      ],
    );
  }

  TableRow _buildPrice() {
    final MyOrder order = widget.makerOrderStatus.order;
    final baseAmount = order.baseAmount.toDouble();
    final relAmount = order.relAmount.toDouble();
    final priceValue =
        baseAmount > 0 &&
            relAmount > 0 &&
            baseAmount.isFinite &&
            relAmount.isFinite
        ? relAmount / baseAmount
        : double.nan;
    final String price = priceValue.isFinite ? formatAmt(priceValue) : '—';

    return TableRow(
      children: [
        SizedBox(
          height: 30,
          child: Text(
            '${LocaleKeys.price.tr()}:',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        Row(
          children: [
            Text(price, style: const TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(width: 5),
            Text(order.rel),
          ],
        ),
      ],
    );
  }

  Future<void> _cancelOrder() async {
    final confirmed = await showDexActionConfirmation(
      context: context,
      actionLabel: LocaleKeys.cancelOrder.tr(),
      targetDescription:
          '${widget.makerOrderStatus.order.base}/'
          '${widget.makerOrderStatus.order.rel} order\n'
          '${widget.makerOrderStatus.order.uuid}',
      confirmButtonKey: const Key('dex-details-cancel-order-confirm'),
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _cancelingError = null;
      _inProgress = true;
    });

    final tradingEntitiesBloc = RepositoryProvider.of<TradingEntitiesBloc>(
      context,
    );
    if (!tradingEntitiesBloc.canCancelOrder(
      widget.makerOrderStatus.order.uuid,
    )) {
      if (mounted) {
        setState(() {
          _inProgress = false;
          _cancelingError = 'advancedCancellationFailed'.tr();
        });
      }
      return;
    }
    String? error;
    try {
      error = await tradingEntitiesBloc.cancelOrder(
        widget.makerOrderStatus.order.uuid,
      );
    } on Object {
      error = 'advancedCancellationFailed';
    }

    await Future<dynamic>.delayed(const Duration(milliseconds: 1000));

    if (!mounted) return;
    setState(() => _inProgress = false);

    if (error != null) {
      setState(
        () => _cancelingError = error == 'advancedCancellationFailed'
            ? 'advancedCancellationFailed'.tr()
            : error,
      );
    } else {
      routingState.dexState.action = DexAction.none;
      routingState.dexState.uuid = '';
    }
  }
}

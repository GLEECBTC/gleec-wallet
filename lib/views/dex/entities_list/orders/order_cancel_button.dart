import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/blocs/trading_entities_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/my_orders/my_order.dart';
import 'package:web_dex/shared/ui/ui_light_button.dart';
import 'package:web_dex/views/dex/common/dex_confirmation_dialog.dart';

class OrderCancelButton extends StatefulWidget {
  const OrderCancelButton({super.key, required this.order});

  final MyOrder order;

  @override
  State<OrderCancelButton> createState() => _OrderCancelButtonState();
}

class _OrderCancelButtonState extends State<OrderCancelButton> {
  bool _isCancelling = false;
  String? _resultMessage;
  bool _resultIsError = false;

  @override
  Widget build(BuildContext context) {
    final colors = GleecColorTokens.of(context);
    final canCancel = RepositoryProvider.of<TradingEntitiesBloc>(
      context,
    ).canCancelOrder(widget.order.uuid);
    return Semantics(
      liveRegion: _resultMessage != null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          UiLightButton(
            text: LocaleKeys.cancel.tr(),
            width: 112,
            height: 48,
            prefix: _isCancelling
                ? const UiSpinner(width: 12, height: 12)
                : null,
            backgroundColor: colors.dangerContainer,
            border: Border.all(color: colors.danger),
            textStyle: TextStyle(color: colors.danger),
            onPressed: _isCancelling || !canCancel
                ? null
                : () => onCancel(widget.order),
          ),
          if (_resultMessage case final message?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _resultIsError ? colors.danger : colors.success,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> onCancel(MyOrder order) async {
    final tradingEntitiesBloc = RepositoryProvider.of<TradingEntitiesBloc>(
      context,
    );
    if (!tradingEntitiesBloc.canCancelOrder(order.uuid)) return;
    final confirmed = await showDexActionConfirmation(
      context: context,
      actionLabel: LocaleKeys.cancelOrder.tr(),
      targetDescription: '${order.base}/${order.rel} order\n${order.uuid}',
      confirmButtonKey: const Key('dex-order-cancel-confirm'),
    );
    if (!confirmed || !mounted) return;
    if (!tradingEntitiesBloc.canCancelOrder(order.uuid)) {
      setState(() {
        _resultIsError = true;
        _resultMessage = 'advancedCancellationFailed'.tr();
      });
      return;
    }
    setState(() {
      _isCancelling = true;
      _resultMessage = null;
    });
    String? error;
    try {
      error = await tradingEntitiesBloc.cancelOrder(order.uuid);
    } on Object {
      error = 'advancedCancellationFailed';
    }
    if (!mounted) return;
    setState(() {
      _isCancelling = false;
      _resultIsError = error != null;
      _resultMessage = error == null
          ? 'advancedCancellationSubmitted'.tr()
          : 'advancedCancellationFailed'.tr();
    });
  }
}

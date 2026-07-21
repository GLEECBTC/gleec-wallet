import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/blocs/trading_entities_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/my_orders/my_order.dart';
import 'package:web_dex/shared/ui/ui_light_button.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/dex/common/dex_confirmation_dialog.dart';

class OrderCancelButton extends StatefulWidget {
  const OrderCancelButton({Key? key, required this.order}) : super(key: key);

  final MyOrder order;

  @override
  State<OrderCancelButton> createState() => _OrderCancelButtonState();
}

class _OrderCancelButtonState extends State<OrderCancelButton> {
  bool _isCancelling = false;

  @override
  Widget build(BuildContext context) {
    final colors = GleecColorTokens.of(context);
    return UiLightButton(
      text: LocaleKeys.cancel.tr(),
      width: 112,
      height: 48,
      prefix: _isCancelling ? const UiSpinner(width: 12, height: 12) : null,
      backgroundColor: colors.dangerContainer,
      border: Border.all(color: colors.danger),
      textStyle: TextStyle(color: colors.danger),
      onPressed: _isCancelling ? null : () => onCancel(widget.order),
    );
  }

  Future<void> onCancel(MyOrder order) async {
    final confirmed = await showDexActionConfirmation(
      context: context,
      actionLabel: LocaleKeys.cancelOrder.tr(),
      confirmButtonKey: const Key('dex-order-cancel-confirm'),
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _isCancelling = true;
    });
    final tradingEntitiesBloc = RepositoryProvider.of<TradingEntitiesBloc>(
      context,
    );
    final String? error = await tradingEntitiesBloc.cancelOrder(order.uuid);
    if (!mounted) return;
    setState(() {
      _isCancelling = false;
    });
    if (error != null) {
      // TODO(Francois): move to bloc / data layer?
      log(
        'Error order cancellation: ${error.toString()}',
        path: 'order_item => _onCancel',
        isError: true,
      );
    }
  }
}

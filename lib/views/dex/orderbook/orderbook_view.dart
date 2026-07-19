import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/blocs/orderbook_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/orderbook/order.dart';
import 'package:web_dex/model/orderbook/orderbook.dart';
import 'package:web_dex/model/orderbook_model.dart';
import 'package:web_dex/views/dex/orderbook/orderbook_error_message.dart';
import 'package:web_dex/views/dex/orderbook/orderbook_table.dart';
import 'package:web_dex/views/dex/orderbook/orderbook_table_title.dart';

class OrderbookView extends StatefulWidget {
  const OrderbookView({
    required this.base,
    required this.rel,
    this.myOrder,
    this.selectedOrderUuid,
    this.onBidClick,
    this.onAskClick,
  });

  final Coin? base;
  final Coin? rel;
  final Order? myOrder;
  final String? selectedOrderUuid;
  final Function(Order)? onBidClick;
  final Function(Order)? onAskClick;

  @override
  State<OrderbookView> createState() => _OrderbookViewState();
}

class _OrderbookViewState extends State<OrderbookView> {
  late OrderbookModel _model;

  @override
  void initState() {
    _model = OrderbookModel(
      base: widget.base,
      rel: widget.rel,
      orderBookRepository: RepositoryProvider.of<OrderbookBloc>(context),
    );

    super.initState();
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant OrderbookView oldWidget) {
    if (widget.base != oldWidget.base) _model.base = widget.base;
    if (widget.rel != oldWidget.rel) _model.rel = widget.rel;

    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<OrderbookResult?>(
      initialData: _model.response,
      stream: _model.outResponse,
      builder: (context, snapshot) {
        if (!_model.isComplete) return const SizedBox.shrink();

        final OrderbookResult? result = snapshot.data;

        if (result == null) {
          return const Center(child: UiSpinner());
        }

        if (result.hasError) {
          return OrderbookErrorMessage(
            result.error ?? LocaleKeys.orderBookFailedLoadError.tr(),
            onReloadClick: _model.reload,
          );
        }

        final response = result.response;
        if (response == null) {
          return const Center(child: UiSpinner());
        }

        final Orderbook orderbook = Orderbook.fromSdkResponse(response);
        if (orderbook.asks.isEmpty && orderbook.bids.isEmpty) {
          return Center(child: Text(LocaleKeys.orderBookEmpty.tr()));
        }

        final colors = GleecColorTokens.of(context);
        final geometry = GleecGeometry.of(context);
        return Container(
          constraints: BoxConstraints(
            maxWidth: Theme.of(context).calmCoreCompatibility.dexFormWidth,
          ),
          padding: EdgeInsets.all(geometry.space16),
          decoration: BoxDecoration(
            color: colors.surfaceRaised,
            border: Border.all(color: colors.border),
            borderRadius: geometry.borderRadius20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(left: geometry.space8),
                child: OrderbookTableTitle(
                  LocaleKeys.orderBook.tr(),
                  titleTextSize: 14,
                ),
              ),
              Padding(
                padding: EdgeInsets.only(top: geometry.space8),
                child: OrderbookTable(
                  orderbook,
                  myOrder: widget.myOrder,
                  selectedOrderUuid: widget.selectedOrderUuid,
                  onAskClick: widget.onAskClick,
                  onBidClick: widget.onBidClick,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

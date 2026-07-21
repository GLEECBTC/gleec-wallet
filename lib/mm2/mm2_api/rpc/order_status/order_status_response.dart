import 'package:web_dex/model/my_orders/maker_order.dart';
import 'package:web_dex/model/my_orders/my_order.dart';
import 'package:web_dex/model/my_orders/order_model_validation.dart';
import 'package:web_dex/model/my_orders/taker_order.dart';

class OrderStatusResponse {
  OrderStatusResponse({
    required this.type,
    required this.order,
    required this.cancellationReason,
  });

  factory OrderStatusResponse.fromJson(Map<dynamic, dynamic> json) {
    final type = switch (json['type']) {
      'Taker' => TradeSide.taker,
      'Maker' => TradeSide.maker,
      _ => throw const FormatException('Invalid order side'),
    };
    final orderJson = orderStringMap(json['order'], 'order');
    final cancellationReason = json['cancellation_reason'];
    return OrderStatusResponse(
      type: type,
      order: type == TradeSide.taker
          ? TakerOrder.fromJson(orderJson)
          : MakerOrder.fromJson(orderJson),
      cancellationReason: cancellationReason == null
          ? null
          : orderBoundedText(
              cancellationReason,
              'cancellation_reason',
              allowEmpty: false,
            ),
    );
  }

  final TradeSide type;
  final dynamic order; // TakerOrder or MakerOrder
  final String? cancellationReason;
}

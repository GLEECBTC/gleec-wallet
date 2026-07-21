import 'package:web_dex/model/my_orders/maker_order.dart';
import 'package:web_dex/model/my_orders/order_model_validation.dart';
import 'package:web_dex/model/my_orders/taker_order.dart';

class MyOrdersResponse {
  MyOrdersResponse({required this.result});

  factory MyOrdersResponse.fromJson(Map<String, dynamic> json) =>
      MyOrdersResponse(
        result: MyOrdersResponseResult.fromJson(
          orderStringMap(json['result'], 'my_orders result'),
        ),
      );

  final MyOrdersResponseResult result;

  Map<String, dynamic> toJson() => <String, dynamic>{'result': result.toJson()};
}

class MyOrdersResponseResult {
  MyOrdersResponseResult({
    required this.makerOrders,
    required this.takerOrders,
  });

  factory MyOrdersResponseResult.fromJson(Map<String, dynamic> json) {
    final rawMakerOrders = _orderCollection(
      json['maker_orders'],
      'maker_orders',
    );
    final rawTakerOrders = _orderCollection(
      json['taker_orders'],
      'taker_orders',
    );
    if (rawMakerOrders.length + rawTakerOrders.length > maximumOrderRecords) {
      throw const FormatException('Too many open orders');
    }

    final makerOrders = <String, MakerOrder>{};
    final orderIds = <String>{};
    for (final entry in rawMakerOrders.entries) {
      final uuid = orderUuid(entry.key, 'maker order identifier');
      final order = MakerOrder.fromJson(
        orderStringMap(entry.value, 'maker order'),
      );
      if (order.uuid != uuid || !orderIds.add(uuid)) {
        throw const FormatException('Mismatched or duplicate maker order');
      }
      makerOrders[uuid] = order;
    }

    final takerOrders = <String, TakerOrder>{};
    for (final entry in rawTakerOrders.entries) {
      final uuid = orderUuid(entry.key, 'taker order identifier');
      final order = TakerOrder.fromJson(
        orderStringMap(entry.value, 'taker order'),
      );
      if (order.request.uuid != uuid || !orderIds.add(uuid)) {
        throw const FormatException('Mismatched or duplicate taker order');
      }
      takerOrders[uuid] = order;
    }
    return MyOrdersResponseResult(
      makerOrders: Map<String, MakerOrder>.unmodifiable(makerOrders),
      takerOrders: Map<String, TakerOrder>.unmodifiable(takerOrders),
    );
  }

  final Map<String, MakerOrder> makerOrders;
  final Map<String, TakerOrder> takerOrders;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'maker_orders': Map<dynamic, dynamic>.from(makerOrders)
        .map<dynamic, dynamic>(
          (dynamic k, dynamic v) => MapEntry<String, dynamic>(k, v.toJson()),
        ),
    'taker_orders': Map<dynamic, dynamic>.from(takerOrders)
        .map<dynamic, dynamic>(
          (dynamic k, dynamic v) => MapEntry<String, dynamic>(k, v.toJson()),
        ),
  };
}

Map<String, dynamic> _orderCollection(Object? value, String field) {
  if (value is! Map || value.length > maximumOrderRecords) {
    throw FormatException('Invalid $field');
  }
  return orderStringMap(value, field);
}

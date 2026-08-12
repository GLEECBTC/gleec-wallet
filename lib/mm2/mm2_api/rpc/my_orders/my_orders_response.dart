import 'package:web_dex/model/my_orders/maker_order.dart';
import 'package:web_dex/model/my_orders/order_model_validation.dart';
import 'package:web_dex/model/my_orders/taker_order.dart';
import 'package:web_dex/model/trading_entity_id.dart';

class MyOrdersResponse {
  MyOrdersResponse({
    required this.result,
  });

  factory MyOrdersResponse.fromJson(Map<String, dynamic> json) =>
      MyOrdersResponse(
        result: MyOrdersResponseResult.fromJson(
          Map<String, dynamic>.from(json['result'] as Map? ?? {}),
        ),
      );

  MyOrdersResponseResult result;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'result': result.toJson(),
      };
}

class MyOrdersResponseResult {
  MyOrdersResponseResult({
    required this.makerOrders,
    required this.takerOrders,
  });

  factory MyOrdersResponseResult.fromJson(Map<String, dynamic> json) =>
      MyOrdersResponseResult(
        makerOrders: _parseOrders(
          json['maker_orders'],
          'maker_orders',
          MakerOrder.fromJson,
        ),
        takerOrders: _parseOrders(
          json['taker_orders'],
          'taker_orders',
          TakerOrder.fromJson,
        ),
      );

  /// Parses each order independently and drops the ones that fail validation.
  ///
  /// One malformed record must not empty the whole list: an empty list makes
  /// every order look non-cancellable, which would leave a user unable to
  /// cancel real orders because of an unrelated bad entry.
  static Map<String, T> _parseOrders<T>(
    Object? value,
    String field,
    T Function(Map<String, dynamic>) parse,
  ) {
    if (value == null) return <String, T>{};
    final entries = orderStringMap(value, field);
    final parsed = <String, T>{};
    for (final entry in entries.entries) {
      if (parsed.length >= maximumOrderRecords) break;
      final uuid = normalizeTradingEntityUuid(entry.key);
      if (uuid == null) continue;
      try {
        parsed[uuid] = parse(orderStringMap(entry.value, '$field entry'));
      } on FormatException {
        continue;
      }
    }
    return parsed;
  }

  Map<String, MakerOrder> makerOrders;
  Map<String, TakerOrder> takerOrders;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'maker_orders':
            Map<dynamic, dynamic>.from(makerOrders).map<dynamic, dynamic>(
          (dynamic k, dynamic v) => MapEntry<String, dynamic>(k, v.toJson()),
        ),
        'taker_orders':
            Map<dynamic, dynamic>.from(takerOrders).map<dynamic, dynamic>(
          (dynamic k, dynamic v) => MapEntry<String, dynamic>(k, v.toJson()),
        ),
      };
}

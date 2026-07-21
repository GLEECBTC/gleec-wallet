import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/mm2/mm2_api/rpc/cancel_order/cancel_order_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/my_orders/my_orders_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/order_status/cancellation_reason.dart';
import 'package:web_dex/mm2/mm2_api/rpc/order_status/order_status_response.dart';
import 'package:web_dex/model/my_orders/maker_order.dart';
import 'package:web_dex/model/my_orders/my_order.dart';
import 'package:web_dex/model/my_orders/taker_order.dart';
import 'package:web_dex/model/trading_entity_id.dart';
import 'package:web_dex/services/mappers/my_orders_mappers.dart';

class MyOrdersService {
  MyOrdersService(this._mm2Api);

  final Mm2Api _mm2Api;

  Future<List<MyOrder>?> getOrders() async {
    try {
      final MyOrdersResponse? response = await _mm2Api.getMyOrders();

      if (response == null) {
        return null;
      }

      return mapMyOrdersResponseToOrders(response);
    } catch (_) {
      // A failed or malformed response is not an authoritative empty order
      // snapshot. Callers retain their last known controls and mark them stale.
      return null;
    }
  }

  Future<OrderStatus?> getStatus(String uuid) async {
    final normalizedUuid = normalizeTradingEntityUuid(uuid);
    if (normalizedUuid == null) return null;

    try {
      final OrderStatusResponse? response = await _mm2Api.getOrderStatus(
        normalizedUuid,
      );
      if (response == null) {
        return null;
      }
      final dynamic order = response.order;
      if (order is TakerOrder) {
        if (normalizeTradingEntityUuid(order.request.uuid) != normalizedUuid) {
          return null;
        }
        return OrderStatus(
          takerOrderStatus: TakerOrderStatus(
            order: mapMyOrderResponseTakerOrderToOrder(order, normalizedUuid),
            cancellationReason: _getTakerOrderCancellationReason(
              response.cancellationReason ?? '',
            ),
          ),
        );
      } else if (order is MakerOrder) {
        if (normalizeTradingEntityUuid(order.uuid) != normalizedUuid) {
          return null;
        }
        return OrderStatus(
          makerOrderStatus: MakerOrderStatus(
            order: mapMyOrderResponseMakerOrderToOrder(order, normalizedUuid),
            cancellationReason: _getMakerOrderCancellationReason(
              response.cancellationReason ?? '',
            ),
          ),
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> cancelOrder(
    String uuid, {
    Future<void> Function()? beforeMutation,
  }) async {
    final normalizedUuid = normalizeTradingEntityUuid(uuid);
    if (normalizedUuid == null) return 'Unable to cancel order';

    try {
      final Map<String, dynamic> response = await _mm2Api.cancelOrder(
        CancelOrderRequest(uuid: normalizedUuid),
        beforeMutation: beforeMutation,
      );
      return Mm2Api.isPositiveCancelOrderResponse(response)
          ? null
          : 'Unable to cancel order';
    } catch (_) {
      return 'Unable to cancel order';
    }
  }

  TakerOrderCancellationReason _getTakerOrderCancellationReason(String reason) {
    switch (reason) {
      case 'Cancelled':
        return TakerOrderCancellationReason.cancelled;
      case 'Fulfilled':
        return TakerOrderCancellationReason.fulfilled;
      case 'TimedOut':
        return TakerOrderCancellationReason.timedOut;
      case 'ToMaker':
        return TakerOrderCancellationReason.toMaker;
      default:
        return TakerOrderCancellationReason.none;
    }
  }

  MakerOrderCancellationReason _getMakerOrderCancellationReason(String reason) {
    switch (reason) {
      case 'Cancelled':
        return MakerOrderCancellationReason.cancelled;
      case 'Fulfilled':
        return MakerOrderCancellationReason.fulfilled;
      case 'InsufficientBalance':
        return MakerOrderCancellationReason.insufficientBalance;
      default:
        return MakerOrderCancellationReason.none;
    }
  }
}

class OrderStatus {
  OrderStatus({this.takerOrderStatus, this.makerOrderStatus});
  final TakerOrderStatus? takerOrderStatus;
  final MakerOrderStatus? makerOrderStatus;
}

class TakerOrderStatus {
  TakerOrderStatus({required this.order, required this.cancellationReason});
  final TakerOrderCancellationReason cancellationReason;
  final MyOrder order;
}

class MakerOrderStatus {
  MakerOrderStatus({required this.order, required this.cancellationReason});
  final MakerOrderCancellationReason cancellationReason;
  final MyOrder order;
}

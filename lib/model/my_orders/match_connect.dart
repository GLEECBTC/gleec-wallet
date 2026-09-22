import 'package:web_dex/model/my_orders/order_model_validation.dart';

class MatchConnect {
  MatchConnect({
    required this.destPubKey,
    required this.makerOrderUuid,
    required this.method,
    required this.senderPubkey,
    required this.takerOrderUuid,
  });

  /// Throws [FormatException] on a malformed payload.
  factory MatchConnect.fromJson(Map<String, dynamic> json) => MatchConnect(
        destPubKey:
            orderBoundedText(json['dest_pub_key'] ?? '', 'dest_pub_key'),
        makerOrderUuid: orderUuid(
          json['maker_order_uuid'],
          'maker_order_uuid',
          allowEmpty: true,
        ),
        method: orderBoundedText(json['method'] ?? '', 'method'),
        senderPubkey:
            orderBoundedText(json['sender_pubkey'] ?? '', 'sender_pubkey'),
        takerOrderUuid: orderUuid(
          json['taker_order_uuid'],
          'taker_order_uuid',
          allowEmpty: true,
        ),
      );

  String destPubKey;
  String makerOrderUuid;
  String method;
  String senderPubkey;
  String takerOrderUuid;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'dest_pub_key': destPubKey,
        'maker_order_uuid': makerOrderUuid,
        'method': method,
        'sender_pubkey': senderPubkey,
        'taker_order_uuid': takerOrderUuid,
      };
}

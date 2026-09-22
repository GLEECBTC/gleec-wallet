import 'package:rational/rational.dart';
import 'package:web_dex/model/my_orders/order_model_validation.dart';
import 'package:web_dex/shared/utils/utils.dart';

class MatchRequest {
  MatchRequest({
    this.action = '',
    this.base = '',
    required this.baseAmount,
    this.destPubKey = '',
    this.method = '',
    this.rel = '',
    required this.relAmount,
    this.senderPubkey = '',
    this.uuid = '',
    this.makerOrderUuid = '',
    this.takerOrderUuid = '',
  });

  /// Throws [FormatException] on a malformed payload.
  factory MatchRequest.fromJson(Map<String, dynamic> json) {
    return MatchRequest(
      action: orderBoundedText(json['action'] ?? '', 'action'),
      base: orderAssetSymbol(json['base'], 'base'),
      baseAmount: orderRational(
        json['base_amount_fraction'],
        json['base_amount'],
        'base_amount',
      ),
      destPubKey: orderBoundedText(json['dest_pub_key'] ?? '', 'dest_pub_key'),
      method: orderBoundedText(json['method'] ?? '', 'method'),
      rel: orderAssetSymbol(json['rel'], 'rel'),
      relAmount: orderRational(
        json['rel_amount_fraction'],
        json['rel_amount'],
        'rel_amount',
      ),
      senderPubkey:
          orderBoundedText(json['sender_pubkey'] ?? '', 'sender_pubkey'),
      uuid: orderUuid(json['uuid'], 'uuid', allowEmpty: true),
      makerOrderUuid: orderUuid(
        json['maker_order_uuid'],
        'maker_order_uuid',
        allowEmpty: true,
      ),
      takerOrderUuid: orderUuid(
        json['taker_order_uuid'],
        'taker_order_uuid',
        allowEmpty: true,
      ),
    );
  }

  String action;
  String base;
  Rational baseAmount;
  String destPubKey;
  String method;
  String rel;
  Rational relAmount;
  String senderPubkey;
  String uuid;
  String makerOrderUuid;
  String takerOrderUuid;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'action': action,
        'base': base,
        'base_amount': baseAmount.toDouble().toString(),
        'base_amount_fraction': rat2fract(baseAmount),
        'dest_pub_key': destPubKey,
        'method': method,
        'rel': rel,
        'rel_amount': relAmount.toDouble().toString(),
        'rel_amount_fraction': rat2fract(relAmount),
        'sender_pubkey': senderPubkey,
        'uuid': uuid,
        'maker_order_uuid': makerOrderUuid,
        'taker_order_uuid': takerOrderUuid,
      };
}

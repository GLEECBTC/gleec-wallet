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

  factory MatchRequest.fromJson(Map<String, dynamic> json) {
    final baseAmount = orderRational(
      json['base_amount_fraction'],
      json['base_amount'],
      'base_amount',
    );
    final relAmount = orderRational(
      json['rel_amount_fraction'],
      json['rel_amount'],
      'rel_amount',
    );
    final base = orderAssetSymbol(json['base'], 'base');
    final rel = orderAssetSymbol(json['rel'], 'rel');
    if (base == rel) throw const FormatException('Invalid identical pair');

    return MatchRequest(
      action: orderBoundedText(json['action'] ?? '', 'action'),
      base: base,
      baseAmount: baseAmount,
      destPubKey: orderBoundedText(
        json['dest_pub_key'] ?? '',
        'dest_pub_key',
        maximum: maximumOrderEvidenceLength,
      ),
      method: orderBoundedText(json['method'] ?? '', 'method'),
      rel: rel,
      relAmount: relAmount,
      senderPubkey: orderBoundedText(
        json['sender_pubkey'] ?? '',
        'sender_pubkey',
        maximum: maximumOrderEvidenceLength,
      ),
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

  final String action;
  final String base;
  final Rational baseAmount;
  final String destPubKey;
  final String method;
  final String rel;
  final Rational relAmount;
  final String senderPubkey;
  final String uuid;
  final String makerOrderUuid;
  final String takerOrderUuid;

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

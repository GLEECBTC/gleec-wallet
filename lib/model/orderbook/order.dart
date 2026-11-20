import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart'
    show NumericValue, OrderInfo;
import 'package:rational/rational.dart';
import 'package:uuid/uuid.dart';
import 'package:web_dex/shared/utils/utils.dart';

class Order {
  Order({
    required this.base,
    required this.rel,
    required this.direction,
    required this.price,
    required this.maxVolume,
    this.address,
    this.uuid,
    this.pubkey,
    this.isMine,
    this.minVolume,
    this.minVolumeRel,
  });

  factory Order.fromJson(
    Map<String, dynamic> json, {
    required OrderDirection direction,
    required String otherCoin,
  }) {
    return Order(
      base: json['coin'],
      rel: otherCoin,
      direction: direction,
      address: json['address'],
      uuid: json['uuid'],
      pubkey: json['pubkey'],
      isMine: json['is_mine'] as bool?,
      price: fract2rat(json['price_fraction']) ?? Rational.parse(json['price']),
      maxVolume:
          fract2rat(json['base_max_volume_fraction']) ??
          Rational.parse(json['base_max_volume']),
      minVolume:
          fract2rat(json['base_min_volume_fraction']) ??
          Rational.parse(json['base_min_volume']),
      minVolumeRel:
          fract2rat(json['rel_min_volume_fraction']) ??
          Rational.parse(json['rel_min_volume']),
    );
  }

  factory Order.fromOrderInfo(
    OrderInfo info, {
    required String base,
    required String rel,
    required OrderDirection direction,
  }) {
    final Rational? price = info.price?.toRational();

    final Rational? maxVolume =
        (info.baseMaxVolume ?? info.baseMaxVolumeAggregated)?.toRational();

    if (price == null || maxVolume == null) {
      throw ArgumentError('Invalid price or maxVolume in OrderInfo');
    }

    final Rational? minVolume = info.baseMinVolume?.toRational();

    final Rational? minVolumeRel =
        info.relMinVolume?.toRational() ??
        (minVolume != null ? minVolume * price : null);

    return Order(
      base: base,
      rel: rel,
      direction: direction,
      price: price,
      maxVolume: maxVolume,
      address: info.address?.addressData,
      uuid: info.uuid,
      pubkey: info.pubkey,
      isMine: info.isMine,
      minVolume: minVolume,
      minVolumeRel: minVolumeRel,
    );
  }

  final String base;
  final String rel;
  final OrderDirection direction;
  final Rational maxVolume;
  final Rational price;
  final String? address;
  final String? uuid;
  final String? pubkey;
  final bool? isMine;
  final Rational? minVolume;
  final Rational? minVolumeRel;

  bool get isBid => direction == OrderDirection.bid;
  bool get isAsk => direction == OrderDirection.ask;
}

enum OrderDirection { bid, ask }

// This const is used to identify and highlight newly created
// order preview in maker form orderbook (instead of isTarget flag)
final String orderPreviewUuid = const Uuid().v1();

extension NumericValueExtension on NumericValue {
  Rational toRational() {
    if (rational != null) {
      return rational!;
    }
    if (fraction != null) {
      final fractionRat = fract2rat(fraction!.toJson(), false);
      if (fractionRat != null) {
        return fractionRat;
      }
    }
    final decimal = this.decimal.trim();
    if (decimal.isEmpty) {
      throw ArgumentError('NumericValue has empty decimal string');
    }
    return Rational.parse(decimal);
  }
}

// ignore_for_file: avoid_dynamic_calls

import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:web_dex/model/orderbook/order.dart';
import 'package:web_dex/shared/utils/utils.dart';

// Define the AddressType enum
enum AddressType { transparent, shielded }

class BestOrders {
  BestOrders({this.result, this.error});

  factory BestOrders.fromJson(Map<String, dynamic> json) {
    final ordersMap = <String, List<BestOrder>>{};
    final orders = json['result']['orders'] as JsonMap? ?? {};
    for (final String key in orders.keys) {
      final bestOrders = <BestOrder>[];
      final bestOrdersJson = orders[key] as List<dynamic>;
      for (final dynamic result in bestOrdersJson) {
        bestOrders.add(
          BestOrder.fromJson(result as Map<String, dynamic>? ?? {}),
        );
      }
      ordersMap.putIfAbsent(key, () => bestOrders);
    }
    return BestOrders(result: ordersMap);
  }

  Map<String, List<BestOrder>>? result;
  BaseError? error;
}

class BestOrder {
  const BestOrder({
    required this.price,
    required this.maxVolume,
    required this.minVolume,
    required this.coin,
    required this.address,
    required this.uuid,
    this.isMine,
    this.pubkey,
  });

  factory BestOrder.fromOrder(Order order, String? coin) {
    return BestOrder(
      price: order.price,
      maxVolume: order.maxVolume,
      minVolume: order.minVolume ?? Rational.zero,
      coin: coin ?? order.base,
      address: OrderAddress(
        addressType: order.address == null
            ? AddressType.shielded
            : AddressType.transparent,
        addressData: order.address,
      ),
      uuid: order.uuid ?? '',
      isMine: order.isMine,
      pubkey: order.pubkey,
    );
  }

  factory BestOrder.fromJson(Map<String, dynamic> json) {
    return BestOrder(
      price:
          fract2rat(json['price']['fraction'] as Map<String, dynamic>?) ??
          Rational.parse(json['price']['decimal'] as String? ?? ''),
      maxVolume:
          fract2rat(
            json['base_max_volume']['fraction'] as Map<String, dynamic>?,
          ) ??
          Rational.parse(json['base_max_volume']['decimal'] as String? ?? ''),
      minVolume:
          fract2rat(
            json['base_min_volume']['fraction'] as Map<String, dynamic>?,
          ) ??
          Rational.parse(json['base_min_volume']['decimal'] as String? ?? ''),
      coin: json['coin'] as String? ?? '',
      address: OrderAddress.fromJson(json['address'] as Map<String, dynamic>),
      uuid: json['uuid'] as String? ?? '',
      isMine: json['is_mine'] as bool?,
      pubkey: json['pubkey'] as String?,
    );
  }

  final Rational price;
  final Rational maxVolume;
  final Rational minVolume;
  final String coin;
  final OrderAddress address;
  final String uuid;

  /// KDF ownership is authoritative even when the offer hides its address.
  final bool? isMine;
  final String? pubkey;

  @override
  String toString() {
    return 'BestOrder($coin, $price)';
  }
}

class OrderAddress extends Equatable {
  const OrderAddress({required this.addressType, required this.addressData});

  const OrderAddress.transparent(String? addressData)
    : this(addressType: AddressType.transparent, addressData: addressData);

  const OrderAddress.shielded()
    : this(addressType: AddressType.shielded, addressData: null);

  factory OrderAddress.fromJson(Map<String, dynamic> json) {
    // Only [addressType] is required, since shielded addresses don't have
    // [addressData]
    if (json['address_type'] == null) {
      throw Exception('Invalid address');
    }

    // Parse the addressType string into the AddressType enum
    final typeString = json['address_type'] as String;
    final AddressType addressType;
    switch (typeString.toLowerCase()) {
      case 'transparent':
        addressType = AddressType.transparent;
      case 'shielded':
        addressType = AddressType.shielded;
      default:
        throw Exception('Unknown address type: $typeString');
    }

    return OrderAddress(
      addressType: addressType,
      addressData: json['address_data'] as String?,
    );
  }

  final AddressType addressType;
  final String? addressData;

  @override
  List<Object?> get props => [addressType, addressData];

  @override
  String toString() {
    return 'OrderAddress($addressType, $addressData)';
  }
}

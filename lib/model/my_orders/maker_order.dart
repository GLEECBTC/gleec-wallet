import 'package:rational/rational.dart';
import 'package:web_dex/model/my_orders/matches.dart';
import 'package:web_dex/model/my_orders/order_model_validation.dart';
import 'package:web_dex/shared/utils/utils.dart';

class MakerOrder {
  MakerOrder({
    required this.base,
    required this.createdAt,
    required this.availableAmount,
    required this.cancellable,
    required this.matches,
    required this.maxBaseVol,
    required this.minBaseVol,
    required this.price,
    required this.rel,
    required this.startedSwaps,
    required this.uuid,
  });

  /// Throws [FormatException] on a malformed payload.
  factory MakerOrder.fromJson(Map<String, dynamic> json) {
    return MakerOrder(
      base: orderAssetSymbol(json['base'], 'base'),
      createdAt: orderNonNegativeInt(json['created_at'] ?? 0, 'created_at'),
      // A fully matched maker order legitimately has nothing left available.
      availableAmount: orderRational(
        json['available_amount_fraction'],
        json['available_amount'],
        'available_amount',
        allowZero: true,
      ),
      cancellable: orderBool(json['cancellable'] ?? false, 'cancellable'),
      matches:
          boundedOrderMap(json['matches'] ?? <String, dynamic>{}, 'matches')
              .map(
        (String k, dynamic v) => MapEntry<String, Matches>(
          k,
          Matches.fromJson(orderStringMap(v, 'matches entry')),
        ),
      ),
      maxBaseVol: orderRational(
        json['max_base_vol_fraction'],
        json['max_base_vol'],
        'max_base_vol',
      ),
      minBaseVol: orderBoundedText(
        json['min_base_vol'] ?? '',
        'min_base_vol',
        maximum: maximumOrderNumericLength,
      ),
      price: orderRational(json['price_fraction'], json['price'], 'price'),
      rel: orderAssetSymbol(json['rel'], 'rel'),
      startedSwaps: boundedOrderList(
        json['started_swaps'] ?? <String>[],
        'started_swaps',
      ).map((dynamic x) => orderUuid(x, 'started_swaps entry')).toList(),
      uuid: orderUuid(json['uuid'], 'uuid'),
    );
  }

  String base;
  int createdAt;
  Rational availableAmount;
  bool cancellable;
  Map<String, Matches> matches;
  Rational maxBaseVol;
  String minBaseVol;
  Rational price;
  String rel;
  List<String> startedSwaps;
  String uuid;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'base': base,
        'created_at': createdAt,
        'available_amount': availableAmount.toDouble().toString(),
        'available_amount_fraction': rat2fract(availableAmount),
        'cancellable': cancellable,
        'matches': Map<dynamic, dynamic>.from(matches).map<dynamic, dynamic>(
            (dynamic k, dynamic v) => MapEntry<String, dynamic>(k, v.toJson())),
        'max_base_vol': maxBaseVol.toDouble().toString(),
        'max_base_vol_fraction': rat2fract(maxBaseVol),
        'min_base_vol': minBaseVol,
        'price': price.toDouble().toString(),
        'price_fraction': rat2fract(price),
        'rel': rel,
        'started_swaps':
            List<dynamic>.from(startedSwaps.map<dynamic>((dynamic x) => x)),
        'uuid': uuid,
      };
}

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

  factory MakerOrder.fromJson(Map<String, dynamic> json) {
    final maxBaseVol = orderRational(
      json['max_base_vol_fraction'],
      json['max_base_vol'],
      'max_base_vol',
    );
    final price = orderRational(json['price_fraction'], json['price'], 'price');
    final availableAmount = orderRational(
      json['available_amount_fraction'],
      json['available_amount'],
      'available_amount',
      allowZero: true,
    );
    if (availableAmount > maxBaseVol) {
      throw const FormatException('Available amount exceeds order volume');
    }
    final matches = <String, Matches>{};
    final rawMatches = json['matches'];
    if (rawMatches is Map) {
      for (final entry in rawMatches.entries.take(maximumOrderRelationships)) {
        try {
          final id = orderUuid(entry.key, 'match identifier');
          matches[id] = Matches.fromJson(orderStringMap(entry.value, 'match'));
        } catch (_) {
          // Auxiliary match evidence must not remove control of the live order.
        }
      }
    }
    final startedSwaps = <String>[];
    final startedSwapIds = <String>{};
    final rawStartedSwaps = json['started_swaps'];
    if (rawStartedSwaps is List) {
      for (final value in rawStartedSwaps.take(maximumOrderRelationships)) {
        try {
          final id = orderUuid(value, 'started swap identifier');
          if (startedSwapIds.add(id)) startedSwaps.add(id);
        } catch (_) {
          // Keep the cancellable core order even if one relationship is bad.
        }
      }
    }
    final minBaseVol = orderRational(
      null,
      json['min_base_vol'],
      'min_base_vol',
      allowZero: true,
    );
    if (minBaseVol > maxBaseVol) {
      throw const FormatException('Minimum volume exceeds order volume');
    }
    final base = orderAssetSymbol(json['base'], 'base');
    final rel = orderAssetSymbol(json['rel'], 'rel');
    if (base == rel) throw const FormatException('Invalid identical pair');

    return MakerOrder(
      base: base,
      createdAt: orderNonNegativeInt(json['created_at'], 'created_at'),
      availableAmount: availableAmount,
      cancellable: orderBool(json['cancellable'], 'cancellable'),
      matches: Map<String, Matches>.unmodifiable(matches),
      maxBaseVol: maxBaseVol,
      minBaseVol: json['min_base_vol'].toString(),
      price: price,
      rel: rel,
      startedSwaps: List<String>.unmodifiable(startedSwaps),
      uuid: orderUuid(json['uuid'], 'uuid'),
    );
  }

  final String base;
  final int createdAt;
  final Rational availableAmount;
  final bool cancellable;
  final Map<String, Matches> matches;
  final Rational maxBaseVol;
  final String minBaseVol;
  final Rational price;
  final String rel;
  final List<String> startedSwaps;
  final String uuid;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'base': base,
    'created_at': createdAt,
    'available_amount': availableAmount.toDouble().toString(),
    'available_amount_fraction': rat2fract(availableAmount),
    'cancellable': cancellable,
    'matches': Map<dynamic, dynamic>.from(matches).map<dynamic, dynamic>(
      (dynamic k, dynamic v) => MapEntry<String, dynamic>(k, v.toJson()),
    ),
    'max_base_vol': maxBaseVol.toDouble().toString(),
    'max_base_vol_fraction': rat2fract(maxBaseVol),
    'min_base_vol': minBaseVol,
    'price': price.toDouble().toString(),
    'price_fraction': rat2fract(price),
    'rel': rel,
    'started_swaps': List<dynamic>.from(
      startedSwaps.map<dynamic>((dynamic x) => x),
    ),
    'uuid': uuid,
  };
}

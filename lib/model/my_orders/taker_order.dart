import 'package:web_dex/model/my_orders/match_request.dart';
import 'package:web_dex/model/my_orders/matches.dart';
import 'package:web_dex/model/my_orders/order_model_validation.dart';

class TakerOrder {
  TakerOrder({
    required this.createdAt,
    required this.cancellable,
    required this.matches,
    required this.request,
  });

  factory TakerOrder.fromJson(Map<String, dynamic> json) {
    final rawMatches = json['matches'];
    final matches = <String, Matches>{};
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
    return TakerOrder(
      createdAt: orderNonNegativeInt(json['created_at'], 'created_at'),
      cancellable: orderBool(json['cancellable'], 'cancellable'),
      matches: rawMatches == null
          ? null
          : Map<String, Matches>.unmodifiable(matches),
      request: MatchRequest.fromJson(
        orderStringMap(json['request'], 'request'),
      ),
    );
  }

  final int createdAt;
  final bool cancellable;
  final Map<String, Matches>? matches;
  final MatchRequest request;

  Map<String, dynamic> toJson() {
    final Map<String, Matches>? matches = this.matches;

    return <String, dynamic>{
      'created_at': createdAt,
      'cancellable': cancellable,
      'matches': matches == null
          ? null
          : Map<String, Matches>.from(matches).map<String, dynamic>(
              (String k, Matches v) => MapEntry<String, dynamic>(k, v.toJson()),
            ),
      'request': request.toJson(),
    };
  }
}

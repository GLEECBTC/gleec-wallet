import 'package:web_dex/model/my_orders/match_connect.dart';
import 'package:web_dex/model/my_orders/match_request.dart';
import 'package:web_dex/model/my_orders/order_model_validation.dart';

class Matches {
  Matches({
    required this.connect,
    required this.connected,
    required this.lastUpdated,
    required this.request,
    required this.reserved,
  });

  /// Throws [FormatException] on a malformed payload.
  factory Matches.fromJson(Map<String, dynamic> json) => Matches(
        connect: json['connect'] == null
            ? null
            : MatchConnect.fromJson(
                orderStringMap(json['connect'], 'connect'),
              ),
        connected: json['connected'] == null
            ? null
            : MatchConnect.fromJson(
                orderStringMap(json['connected'], 'connected'),
              ),
        lastUpdated: orderNonNegativeInt(
          json['last_updated'] ?? 0,
          'last_updated',
        ),
        request: json['request'] == null
            ? null
            : MatchRequest.fromJson(
                orderStringMap(json['request'], 'request'),
              ),
        reserved: json['reserved'] == null
            ? null
            : MatchRequest.fromJson(
                orderStringMap(json['reserved'], 'reserved'),
              ),
      );

  MatchConnect? connect;
  MatchConnect? connected;
  int lastUpdated;
  MatchRequest? request;
  MatchRequest? reserved;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'connect': connect?.toJson(),
        'connected': connected?.toJson(),
        'last_updated': lastUpdated,
        'request': request?.toJson(),
        'reserved': reserved?.toJson(),
      };
}

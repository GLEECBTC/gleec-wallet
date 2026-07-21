import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/mm2/mm2_api/rpc/my_orders/my_orders_response.dart';

void main() {
  test('oversized malformed relationships do not hide live orders', () {
    final makerId = _uuid(1);
    final takerId = _uuid(2);
    final malformedMatches = <String, dynamic>{
      for (var index = 0; index < 513; index++)
        _uuid(index + 1000): 'malformed-match',
    };
    final startedSwaps = [
      for (var index = 0; index < 513; index++) _uuid(index + 2000),
    ];

    final response = MyOrdersResponse.fromJson({
      'result': {
        'maker_orders': {
          makerId: {
            'base': 'KMD',
            'created_at': 1,
            'available_amount': '1',
            'cancellable': true,
            'matches': malformedMatches,
            'max_base_vol': '2',
            'min_base_vol': '0.1',
            'price': '0.5',
            'rel': 'BTC',
            'started_swaps': startedSwaps,
            'uuid': makerId,
          },
        },
        'taker_orders': {
          takerId: {
            'created_at': 1,
            'cancellable': true,
            'matches': malformedMatches,
            'request': {
              'base': 'KMD',
              'base_amount': '1',
              'rel': 'BTC',
              'rel_amount': '2',
              'uuid': takerId,
            },
          },
        },
      },
    });

    expect(response.result.makerOrders, contains(makerId));
    final maker = response.result.makerOrders[makerId]!;
    expect(maker.cancellable, isTrue);
    expect(maker.matches, isEmpty);
    expect(maker.startedSwaps, hasLength(512));

    expect(response.result.takerOrders, contains(takerId));
    final taker = response.result.takerOrders[takerId]!;
    expect(taker.cancellable, isTrue);
    expect(taker.matches, isEmpty);
  });
}

String _uuid(int suffix) =>
    '00000000-0000-0000-0000-${suffix.toRadixString(16).padLeft(12, '0')}';

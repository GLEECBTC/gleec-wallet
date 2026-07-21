import 'dart:convert';

import 'package:test/test.dart';
import 'package:web_dex/mm2/mm2_api/rpc/my_recent_swaps/my_recent_swaps_response.dart';

void testMyRecentSwapsResponse() {
  test('parse swap with null my_info and fractions', () {
    const payload = '''
{
  "result": {
    "from_uuid": null,
    "limit": 1,
    "skipped": 0,
    "total": 1,
    "page_number": 0,
    "total_pages": 1,
    "found_records": 1,
    "swaps": [
      {
        "type": "Maker",
        "uuid": "550e8400-e29b-41d4-a716-446655440010",
        "my_order_uuid": "550e8400-e29b-41d4-a716-446655440011",
        "events": [],
        "maker_amount": "1",
        "maker_amount_fraction": null,
        "maker_coin": "MCL",
        "taker_amount": "2",
        "taker_amount_fraction": null,
        "taker_coin": "KMD",
        "gui": "dex",
        "mm_version": "2.0",
        "success_events": [],
        "error_events": [],
        "my_info": null,
        "recoverable": false,
        "maker_coin_usd_price": null,
        "taker_coin_usd_price": null,
        "is_finished": true,
        "is_success": false
      }
    ]
  }
}
''';
    final Map<String, dynamic> jsonMap =
        jsonDecode(payload) as Map<String, dynamic>;
    final MyRecentSwapsResponse response = MyRecentSwapsResponse.fromJson(
      jsonMap,
    );
    expect(response.result.fromUuid, isNull);
    expect(response.result.swaps.length, 1);
    final swap = response.result.swaps.first;
    expect(swap.myInfo, isNull);
    expect(swap.uuid, '550e8400-e29b-41d4-a716-446655440010');
  });

  test('parse swap with my_info data', () {
    const payload = '''
{
  "result": {
    "from_uuid": "550e8400-e29b-41d4-a716-446655440022",
    "limit": 1,
    "skipped": 0,
    "total": 1,
    "page_number": 0,
    "total_pages": 1,
    "found_records": 1,
    "swaps": [
      {
        "type": "Taker",
        "uuid": "550e8400-e29b-41d4-a716-446655440020",
        "my_order_uuid": "550e8400-e29b-41d4-a716-446655440021",
        "events": [],
        "maker_amount": "3",
        "taker_amount": "4",
        "maker_coin": "KMD",
        "taker_coin": "BTC",
        "gui": "dex",
        "mm_version": "2.0",
        "success_events": [],
        "error_events": [],
        "my_info": {
          "my_coin": "KMD",
          "other_coin": "BTC",
          "my_amount": "3",
          "other_amount": "4",
          "started_at": 1
        },
        "recoverable": false
      }
    ]
  }
}
''';
    final Map<String, dynamic> jsonMap =
        jsonDecode(payload) as Map<String, dynamic>;
    final MyRecentSwapsResponse response = MyRecentSwapsResponse.fromJson(
      jsonMap,
    );
    expect(response.result.fromUuid, '550e8400-e29b-41d4-a716-446655440022');
    expect(response.result.swaps.length, 1);
    final swap = response.result.swaps.first;
    expect(swap.myInfo?.myCoin, 'KMD');
    expect(swap.myInfo?.otherCoin, 'BTC');
    expect(swap.myInfo?.myAmount, 3);
    expect(swap.myInfo?.otherAmount, 4);
    expect(swap.myInfo?.startedAt, 1);
  });

  test('malformed auxiliary evidence does not hide a recoverable swap', () {
    final response = MyRecentSwapsResponse.fromJson({
      'result': {
        'swaps': [
          {
            'type': 'Taker',
            'uuid': '550e8400-e29b-41d4-a716-446655440030',
            'my_order_uuid': 'malformed-order-reference',
            'events': [
              {
                'timestamp': 2,
                'event': {'type': 'Started'},
              },
              'malformed-event',
              {
                'timestamp': 1,
                'event': {'type': 'Negotiated'},
              },
              {
                'timestamp': 3,
                'event': {'type': 'Negotiated'},
              },
            ],
            'maker_amount': '3',
            'taker_amount': '4',
            'maker_coin': 'KMD',
            'taker_coin': 'BTC',
            'gui': List.filled(200, 'x').join(),
            'mm_version': {'malformed': true},
            'success_events': ['Finished', 7, 'Finished'],
            'error_events': [
              'Failed',
              {'malformed': true},
            ],
            'my_info': 'malformed',
            'recoverable': true,
          },
        ],
      },
    });

    expect(response.result.swaps, hasLength(1));
    final swap = response.result.swaps.single;
    expect(swap.recoverable, isTrue);
    expect(swap.myOrderUuid, isEmpty);
    expect(swap.events.map((event) => event.event.type), [
      'Started',
      'Negotiated',
    ]);
    expect(swap.successEvents, ['Finished']);
    expect(swap.errorEvents, ['Failed']);
    expect(swap.gui, isEmpty);
    expect(swap.mmVersion, isEmpty);
    expect(swap.myInfo, isNull);
  });
}

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
        "uuid": "uuid1",
        "my_order_uuid": "order1",
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
    expect(swap.uuid, 'uuid1');
  });

  test('parse swap with my_info data', () {
    const payload = '''
{
  "result": {
    "from_uuid": "uuid_prev",
    "limit": 1,
    "skipped": 0,
    "total": 1,
    "page_number": 0,
    "total_pages": 1,
    "found_records": 1,
    "swaps": [
      {
        "type": "Taker",
        "uuid": "uuid2",
        "my_order_uuid": "order2",
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
    expect(response.result.fromUuid, 'uuid_prev');
    expect(response.result.swaps.length, 1);
    final swap = response.result.swaps.first;
    expect(swap.myInfo?.myCoin, 'KMD');
    expect(swap.myInfo?.otherCoin, 'BTC');
    expect(swap.myInfo?.myAmount, 3);
    expect(swap.myInfo?.otherAmount, 4);
    expect(swap.myInfo?.startedAt, 1);
  });
}

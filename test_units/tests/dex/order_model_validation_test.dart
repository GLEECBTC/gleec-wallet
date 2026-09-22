import 'package:flutter_test/flutter_test.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/mm2/mm2_api/rpc/my_orders/my_orders_response.dart';
import 'package:web_dex/model/my_orders/order_model_validation.dart';
import 'package:web_dex/model/trading_entity_id.dart';

const String _uuidA = '11111111-2222-3333-4444-555555555555';
const String _uuidB = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

Map<String, dynamic> _makerOrder({String base = 'KMD'}) => <String, dynamic>{
  'base': base,
  'rel': 'BTC',
  'created_at': 1700000000000,
  'available_amount': '1.5',
  'cancellable': true,
  'matches': <String, dynamic>{},
  'max_base_vol': '2.0',
  'min_base_vol': '0.1',
  'price': '0.5',
  'started_swaps': <String>[],
  'uuid': _uuidA,
};

void testOrderModelValidation() {
  group('normalizeTradingEntityUuid', () {
    test('canonicalises case and surrounding whitespace', () {
      expect(normalizeTradingEntityUuid('  ${_uuidA.toUpperCase()}  '), _uuidA);
    });

    test('rejects anything that is not a well-formed UUID', () {
      for (final value in <Object?>[
        null,
        42,
        '',
        'not-a-uuid',
        // Wrong group lengths.
        '1111111-2222-3333-4444-555555555555',
        '11111111-2222-3333-4444-5555555555555',
        // Non-hex character.
        '1111111g-2222-3333-4444-555555555555',
        // Braced and unhyphenated spellings are not KDF's contract.
        '{11111111-2222-3333-4444-555555555555}',
        '11111111222233334444555555555555',
      ]) {
        expect(
          normalizeTradingEntityUuid(value),
          isNull,
          reason: 'should reject ${value.runtimeType} "$value"',
        );
      }
    });
  });

  group('orderRational', () {
    test('prefers the exact fraction over the lossy decimal', () {
      final value = orderRational(
        <String, dynamic>{'numer': '1', 'denom': '3'},
        '0.333',
        'price',
      );
      expect(value, Rational(BigInt.one, BigInt.from(3)));
    });

    test('falls back to the decimal when the fraction is unusable', () {
      expect(
        orderRational(
          <String, dynamic>{'numer': '1', 'denom': '0'},
          '2.5',
          'price',
        ),
        Rational.parse('2.5'),
      );
      expect(orderRational(null, '2.5', 'price'), Rational.parse('2.5'));
    });

    test('rejects non-positive values unless zero is allowed', () {
      expect(() => orderRational(null, '0', 'price'), throwsFormatException);
      expect(() => orderRational(null, '-1', 'price'), throwsFormatException);
      expect(
        orderRational(null, '0', 'available_amount', allowZero: true),
        Rational.zero,
      );
      expect(
        () => orderRational(null, '-1', 'available_amount', allowZero: true),
        throwsFormatException,
      );
    });

    test('rejects unparseable and oversized numerics', () {
      expect(() => orderRational(null, 'abc', 'price'), throwsFormatException);
      expect(
        () => orderRational(null, '9' * 200, 'price'),
        throwsFormatException,
        reason: 'an unbounded numeric string must not be parsed',
      );
      expect(
        () => orderRational(
          <String, dynamic>{'numer': '9' * 200, 'denom': '1'},
          null,
          'price',
        ),
        throwsFormatException,
      );
    });
  });

  group('orderNonNegativeInt', () {
    test('accepts in-range epochs', () {
      expect(orderNonNegativeInt(1700000000000, 'created_at'), 1700000000000);
      expect(orderNonNegativeInt('0', 'created_at'), 0);
    });

    test('rejects negatives, non-numerics and out-of-range values', () {
      for (final value in <Object?>[null, -1, '-1', '1.5', 'abc', '9' * 25]) {
        expect(
          () => orderNonNegativeInt(value, 'created_at'),
          throwsFormatException,
          reason: 'should reject "$value"',
        );
      }
      expect(
        () => orderNonNegativeInt(
          maximumOrderEpochMilliseconds + 1,
          'created_at',
        ),
        throwsFormatException,
      );
    });
  });

  group('orderAssetSymbol', () {
    test('accepts real ticker spellings', () {
      for (final symbol in ['KMD', 'USDT-ERC20', 'BTC.segwit', 'ETH_1']) {
        expect(orderAssetSymbol(symbol, 'base'), symbol);
      }
    });

    test('rejects empty, padded and oversized symbols', () {
      for (final value in <Object?>[null, '', ' KMD', 'KMD ', '-KMD', 'A' * 65]) {
        expect(
          () => orderAssetSymbol(value, 'base'),
          throwsFormatException,
          reason: 'should reject "$value"',
        );
      }
    });
  });

  group('orderUuid', () {
    test('normalises, and honours allowEmpty', () {
      expect(orderUuid(_uuidA.toUpperCase(), 'uuid'), _uuidA);
      expect(orderUuid(null, 'uuid', allowEmpty: true), '');
      expect(orderUuid('', 'uuid', allowEmpty: true), '');
      expect(() => orderUuid(null, 'uuid'), throwsFormatException);
      expect(
        () => orderUuid('nope', 'uuid', allowEmpty: true),
        throwsFormatException,
        reason: 'allowEmpty covers absence, not malformed content',
      );
    });
  });

  group('bounded collections', () {
    test('reject oversized maps and lists', () {
      final oversizedMap = <String, dynamic>{
        for (var i = 0; i <= maximumOrderRelationships; i++) '$i': i,
      };
      expect(
        () => boundedOrderMap(oversizedMap, 'matches'),
        throwsFormatException,
      );
      expect(
        () => boundedOrderList(
          List<int>.generate(maximumOrderRelationships + 1, (i) => i),
          'started_swaps',
        ),
        throwsFormatException,
      );
    });

    test('reject values of the wrong shape', () {
      expect(() => boundedOrderMap('nope', 'matches'), throwsFormatException);
      expect(
        () => boundedOrderList(<String, dynamic>{}, 'started_swaps'),
        throwsFormatException,
      );
    });
  });

  group('MyOrdersResponse parsing', () {
    test('parses a well-formed payload', () {
      final response = MyOrdersResponse.fromJson(<String, dynamic>{
        'result': <String, dynamic>{
          'maker_orders': <String, dynamic>{_uuidA: _makerOrder()},
          'taker_orders': <String, dynamic>{},
        },
      });

      expect(response.result.makerOrders.keys, [_uuidA]);
      expect(response.result.makerOrders[_uuidA]!.base, 'KMD');
      expect(response.result.takerOrders, isEmpty);
    });

    test('drops only the malformed order, keeping the valid ones', () {
      final malformed = _makerOrder()..['price'] = 'not-a-number';
      final response = MyOrdersResponse.fromJson(<String, dynamic>{
        'result': <String, dynamic>{
          'maker_orders': <String, dynamic>{
            _uuidA: _makerOrder(),
            _uuidB: malformed,
          },
          'taker_orders': <String, dynamic>{},
        },
      });

      expect(
        response.result.makerOrders.keys,
        [_uuidA],
        reason: 'one bad record must not empty the whole order list',
      );
    });

    test('drops entries whose key is not a canonical uuid', () {
      final response = MyOrdersResponse.fromJson(<String, dynamic>{
        'result': <String, dynamic>{
          'maker_orders': <String, dynamic>{'not-a-uuid': _makerOrder()},
          'taker_orders': <String, dynamic>{},
        },
      });

      expect(response.result.makerOrders, isEmpty);
    });

    test('normalises the key so guards can match it', () {
      final response = MyOrdersResponse.fromJson(<String, dynamic>{
        'result': <String, dynamic>{
          'maker_orders': <String, dynamic>{_uuidA.toUpperCase(): _makerOrder()},
          'taker_orders': <String, dynamic>{},
        },
      });

      expect(response.result.makerOrders.keys, [_uuidA]);
    });

    test('tolerates missing order collections', () {
      final response = MyOrdersResponse.fromJson(<String, dynamic>{
        'result': <String, dynamic>{},
      });

      expect(response.result.makerOrders, isEmpty);
      expect(response.result.takerOrders, isEmpty);
    });

    test('caps the number of records it will materialise', () {
      final many = <String, dynamic>{};
      for (var i = 0; i < maximumOrderRecords + 50; i++) {
        final uuid = normalizeTradingEntityUuid(
          '${i.toString().padLeft(8, '0')}-2222-3333-4444-555555555555',
        )!;
        many[uuid] = _makerOrder();
      }

      final response = MyOrdersResponse.fromJson(<String, dynamic>{
        'result': <String, dynamic>{
          'maker_orders': many,
          'taker_orders': <String, dynamic>{},
        },
      });

      expect(response.result.makerOrders.length, maximumOrderRecords);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trade_preimage/trade_preimage_response.dart';
import 'package:web_dex/model/trade_preimage_extended_fee_info.dart';

void main() {
  test('accepts bounded high-precision repeating fee evidence', () {
    const decimal = '0.33333333333333333333333333333333333333333333333333';
    final fee = TradePreimageExtendedFeeInfo.fromJson(
      _feeJson(coin: 'KMD', amount: decimal, numerator: '1', denominator: '3'),
    );

    expect(fee.amount, decimal);
    expect(fee.amountRational, Rational(BigInt.one, BigInt.from(3)));
  });

  test('rejects oversized rational components before BigInt parsing', () {
    final oversized = List<String>.filled(300, '9').join();

    expect(
      () => TradePreimageExtendedFeeInfo.fromJson(
        _feeJson(
          coin: 'KMD',
          amount: '1',
          numerator: oversized,
          denominator: '1',
        ),
      ),
      throwsFormatException,
    );
  });

  test('rejects unbounded total fee collections', () {
    final fee = _feeJson(
      coin: 'KMD',
      amount: '0.01',
      numerator: '1',
      denominator: '100',
    );
    final response = <String, dynamic>{
      'mmrpc': '2.0',
      'result': <String, dynamic>{
        'base_coin_fee': fee,
        'rel_coin_fee': {...fee, 'coin': 'BTC'},
        'total_fees': List<Map<String, dynamic>>.generate(17, (_) => fee),
      },
    };

    expect(
      () => TradePreimageResponse.fromJson(response),
      throwsFormatException,
    );
  });
}

Map<String, dynamic> _feeJson({
  required String coin,
  required String amount,
  required String numerator,
  required String denominator,
}) => <String, dynamic>{
  'coin': coin,
  'amount': amount,
  'amount_fraction': <String, dynamic>{
    'numer': numerator,
    'denom': denominator,
  },
  'paid_from_trading_vol': false,
};

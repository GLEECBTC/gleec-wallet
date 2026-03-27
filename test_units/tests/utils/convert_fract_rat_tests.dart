import 'package:rational/rational.dart';
import 'package:test/test.dart';
import 'package:web_dex/shared/utils/utils.dart';

void testRatToFracAndViseVersa() {
  test('fract2rat and rat2fract converts valid map', () {
    Map<String, dynamic> validFract = {'numer': '3', 'denom': '4'};
    Rational? result = fract2rat(validFract, false);
    expect(result, isNotNull);
    expect(result!.numerator, equals(BigInt.from(3)));
    expect(result.denominator, equals(BigInt.from(4)));

    final fract = rat2fract(result, false);
    expect(fract, validFract);
    expect(fract!['numer'], '3');
    expect(fract['denom'], '4');

    final Rational result2 = Rational.parse('0.25');
    final fract2 = rat2fract(result2, false);
    expect(fract2!['numer'], '1');
    expect(fract2['denom'], '4');
  });

  test('fract2rat returns null for null input', () {
    Rational? result = fract2rat(null, false);
    expect(result, isNull);

    final fract = rat2fract(null, false);
    expect(fract, isNull);
  });

  test('fract2rat returns null for invalid input', () {
    Map<String, dynamic> invalidFract = {'numer': 'abc', 'denom': 'xyz'};
    Rational? result = fract2rat(invalidFract, false);
    expect(result, isNull);
  });

  test('fract2rat handles very large integers without precision loss', () {
    // 10^50 / 10^20 = 10^30; Rational normalizes to lowest terms.
    final numer = '100000000000000000000000000000000000000000000000000';
    final denom = '100000000000000000000';
    final rat = fract2rat({'numer': numer, 'denom': denom}, false)!;
    final expectedValue = Rational(BigInt.parse(numer), BigInt.parse(denom));
    expect(rat, expectedValue);
    expect(rat.numerator, BigInt.parse('1000000000000000000000000000000'));
    expect(rat.denominator, BigInt.one);
    final back = rat2fract(rat, false)!;
    expect(back['numer'], '1000000000000000000000000000000');
    expect(back['denom'], '1');
  });

  test('fract2rat correctly parses strings that would overflow double', () {
    final numer = '340282366920938463463374607431768211457'; // > 2^128
    final denom = '1';
    final rat = fract2rat({'numer': numer, 'denom': denom}, false)!;
    expect(rat.numerator, BigInt.parse(numer));
    expect(rat.denominator, BigInt.one);
  });
}

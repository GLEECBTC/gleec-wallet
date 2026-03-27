import 'package:rational/rational.dart';
import 'package:test/test.dart';
import 'package:web_dex/views/dex/dex_helpers.dart';

void testGetSellAmount() {
  test('getSellAmount calculates sell amount main cases', () {
    Rational maxSellAmount = Rational.fromInt(100);
    double fraction = 0.75;
    Rational result = getFractionOfAmount(maxSellAmount, fraction);
    expect(result, equals(Rational.fromInt(75)));

    Rational maxSellAmount2 = Rational.fromInt(100);
    double fraction2 = 0.0;
    Rational result2 = getFractionOfAmount(maxSellAmount2, fraction2);
    expect(result2, Rational.zero);

    Rational maxSellAmount3 = Rational.fromInt(100);
    double fraction3 = 1.5;
    Rational result3 = getFractionOfAmount(maxSellAmount3, fraction3);
    Rational expected = Rational.fromInt(150);
    expect(result3, expected);
  });

  test('getSellAmount and strange inputs', () {
    Rational maxSellAmount = Rational.zero;
    double fraction = 0.75;
    Rational? result = getFractionOfAmount(maxSellAmount, fraction);
    expect(result, Rational.zero);

    Rational maxSellAmount2 = Rational.parse('123e53');
    double fraction2 = 1e-53;
    Rational? result2 = getFractionOfAmount(maxSellAmount2, fraction2);
    expect(result2, Rational.parse('123'));
  });
}

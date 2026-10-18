import 'package:rational/rational.dart';
import 'package:test/test.dart';
import 'package:web_dex/views/dex/dex_helpers.dart';

void testUpdateSellAmount() {
  test(
    'updateSellAmount updates buyAmount correctly when price is provided',
    () {
      final sellAmount = Rational.fromInt(100);
      final price = Rational.fromInt(2);
      var result = processBuyAmountAndPrice(sellAmount, price, null);
      expect(result, equals((Rational.fromInt(200), price)));

      final sellAmount2 = Rational.parse('1e10');
      final price2 = Rational.parse('1e40');
      var result2 = processBuyAmountAndPrice(sellAmount2, price2, null);
      expect(result2, equals((Rational.parse('1e50'), price2)));

      final sellAmount3 = Rational.parse('1e-65');
      final price3 = Rational.parse('1e-5');
      var result3 = processBuyAmountAndPrice(sellAmount3, price3, null);
      expect(result3, equals((Rational.parse('1e-70'), price3)));
    },
  );

  test(
    'updateSellAmount updates values correctly when buyAmount is provided',
    () {
      Rational? sellAmount = Rational.fromInt(100);
      Rational? buyAmount = Rational.fromInt(2000);

      var result = processBuyAmountAndPrice(sellAmount, null, buyAmount);
      expect(result, equals((buyAmount, Rational.fromInt(20))));

      Rational? sellAmount2 = Rational.parse('1e10');
      Rational? buyAmount2 = Rational.parse('1e40');

      var result2 = processBuyAmountAndPrice(sellAmount2, null, buyAmount2);
      expect(result2, equals((buyAmount2, Rational.parse('1e30'))));
    },
  );

  test('updateSellAmount returns null when input is null', () {
    Rational? sellAmount;
    Rational? price = Rational.fromInt(2);
    Rational? buyAmount = Rational.fromInt(200);

    var result = processBuyAmountAndPrice(sellAmount, price, buyAmount);
    expect(result, isNull);

    Rational? sellAmount2 = Rational.fromInt(100);
    Rational? price2;
    Rational? buyAmount2;

    var result2 = processBuyAmountAndPrice(sellAmount2, price2, buyAmount2);
    expect(result2, isNull);
  });

  test(
    'updateSellAmount handles division by zero when buyAmount is provided',
    () {
      Rational? sellAmount = Rational.fromInt(0);
      Rational? price;
      Rational? buyAmount = Rational.fromInt(200);

      var result = processBuyAmountAndPrice(sellAmount, price, buyAmount);
      expect(result, equals((Rational.fromInt(200), null)));
    },
  );
}

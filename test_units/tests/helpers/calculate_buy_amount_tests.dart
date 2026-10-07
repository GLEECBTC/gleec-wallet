import 'package:rational/rational.dart';
import 'package:test/test.dart';
import 'package:web_dex/mm2/mm2_api/rpc/best_orders/best_orders.dart';
import 'package:web_dex/views/dex/dex_helpers.dart';

void testCalculateBuyAmount() {
  test('Calculation sellAmount on selectedOrder', () {
    final BestOrder bestOrder = BestOrder(
      price: Rational.fromInt(2),
      maxVolume: Rational.fromInt(3),
      address: const OrderAddress.transparent(''),
      coin: 'KMD',
      minVolume: Rational.fromInt(1),
      uuid: '',
    );

    expect(
      calculateBuyAmount(
        sellAmount: Rational.fromInt(2),
        selectedOrder: bestOrder,
      ),
      Rational.fromInt(4),
    );
    expect(
      calculateBuyAmount(
        sellAmount: Rational.parse('0.1'),
        selectedOrder: bestOrder,
      ),
      Rational.parse('0.2'),
    );
    expect(
      calculateBuyAmount(
        sellAmount: Rational.parse('1e-30'),
        selectedOrder: bestOrder,
      ),
      Rational.parse('2e-30'),
    );

    final BestOrder bestOrder2 = BestOrder(
      price: Rational.parse('1e-30'),
      maxVolume: Rational.fromInt(100),
      address: const OrderAddress.transparent(''),
      coin: 'KMD',
      minVolume: Rational.fromInt(1),
      uuid: '',
    );
    expect(
      calculateBuyAmount(
        sellAmount: Rational.parse('1e-30'),
        selectedOrder: bestOrder2,
      ),
      Rational.parse('1e-60'),
    );
    expect(
      calculateBuyAmount(
        sellAmount: Rational.parse('1e70'),
        selectedOrder: bestOrder2,
      ),
      Rational.parse('1e40'),
    );
    expect(
      calculateBuyAmount(
        sellAmount: Rational.parse('123456789012345678901234567890'),
        selectedOrder: bestOrder2,
      ),
      Rational.parse('0.123456789012345678901234567890'),
    );
    final BestOrder bestOrder3 = BestOrder(
      price: Rational.parse('1e10'),
      maxVolume: Rational.fromInt(100),
      address: const OrderAddress.transparent(''),
      coin: 'KMD',
      minVolume: Rational.fromInt(1),
      uuid: '',
    );
    expect(
      calculateBuyAmount(
        sellAmount: Rational.parse('12345678901234567890123456789'),
        selectedOrder: bestOrder3,
      ),
      Rational.parse('12345678901234567890123456789e10'),
    );
    expect(
      calculateBuyAmount(
        sellAmount: Rational.parse('12345678901234567890123456789e20'),
        selectedOrder: bestOrder3,
      ),
      Rational.parse('12345678901234567890123456789e30'),
    );
  });
  test('Negative tests', () {
    final BestOrder bestOrder = BestOrder(
      price: Rational.fromInt(2),
      maxVolume: Rational.fromInt(3),
      address: const OrderAddress.transparent(''),
      coin: 'KMD',
      minVolume: Rational.fromInt(1),
      uuid: '',
    );
    expect(calculateBuyAmount(sellAmount: null, selectedOrder: null), isNull);
    expect(
      calculateBuyAmount(sellAmount: Rational.fromInt(2), selectedOrder: null),
      isNull,
    );
    expect(
      calculateBuyAmount(sellAmount: null, selectedOrder: bestOrder),
      isNull,
    );
  });
}

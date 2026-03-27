import 'package:test/test.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';

import '../utils/test_util.dart';

void main() {
  testCoinsStateUsdConversion();
}

void testCoinsStateUsdConversion() {
  final coin = setCoin(coinAbbr: 'TRX', usdPrice: 4.0);
  final state = CoinsState(
    coins: {'TRX': coin},
    walletCoins: {'TRX': coin},
    pubkeys: const {},
    prices: {'TRX': coin.usdPrice!},
  );

  test('typed USD conversion handles numeric values safely', () {
    expect(state.getUsdPriceForAmount(1.1, 'TRX'), closeTo(4.4, 1e-12));
  });

  test(
    'legacy string conversion returns null for display-formatted values',
    () {
      expect(state.getUsdPriceByAmount('1.1 TRX', 'TRX'), isNull);
    },
  );

  test('legacy string conversion still supports numeric strings', () {
    expect(state.getUsdPriceByAmount('1.1', 'TRX'), closeTo(4.4, 1e-12));
  });
}

// TODO: revisit or migrate to the SDK, since it mostly deals with the sdk
import 'package:test/test.dart';

void testGetTotal24Change() {
  // late final KomodoDefiSdk sdk;

  // setUp(() {
  //   sdk = KomodoDefiSdk();
  // });

  test('getTotal24Change calculates total change', () {
    //   List<Coin> coins = [
    //     setCoin(
    //       balance: 1.0,
    //       usdPrice: 10,
    //       change24h: 0.05,
    //     ),
    //   ];

    //   double? result = getTotal24Change(coins, sdk);
    //   expect(result, equals(0.05));

    //   // Now total USD balance is 10*3.0 + 10*1.0 = 40
    //   // -0.1*3.0 + 0.05*1.0 = -0.25
    //   coins.add(
    //     setCoin(
    //       balance: 3.0,
    //       usdPrice: 10,
    //       change24h: -0.1,
    //     ),
    //   );

    //   double? result2 = getTotal24Change(coins, sdk);
    //   // -0.06250000000000001 if use double
    //   expect(result2, equals(-0.0625));
    // });

    // test('getTotal24Change calculates total change', () {
    //   List<Coin> coins = [
    //     setCoin(
    //       balance: 1.0,
    //       usdPrice: 1,
    //       change24h: 0.1,
    //     ),
    //     setCoin(
    //       balance: 1.0,
    //       usdPrice: 1,
    //       change24h: -0.1,
    //     ),
    //   ];

    //   double? result = getTotal24Change(coins, sdk);
    //   expect(result, equals(0.0));

    //   // Now total USD balance is 1.0
    //   // 45.235*1.0 + -45.23*1.0 = 0.005 USD
    //   // 0.005 / 2.0 = 0.0025
    //   List<Coin> coins2 = [
    //     setCoin(
    //       balance: 1.0,
    //       usdPrice: 1,
    //       change24h: 45.235,
    //     ),
    //     setCoin(
    //       balance: 1.0,
    //       usdPrice: 1,
    //       change24h: -45.23,
    //     ),
    //   ];

    //   double? result2 = getTotal24Change(coins2, sdk);
    //   expect(result2, equals(0.0025));
    // });

    // test('getTotal24Change and a huge input', () {
    //   List<Coin> coins = [
    //     setCoin(
    //       balance: 1.0,
    //       usdPrice: 10,
    //       change24h: 0.05,
    //       coinAbbr: 'KMD',
    //     ),
    //     setCoin(
    //       balance: 2.0,
    //       usdPrice: 10,
    //       change24h: 0.1,
    //       coinAbbr: 'BTC',
    //     ),
    //     setCoin(
    //       balance: 2.0,
    //       usdPrice: 10,
    //       change24h: 0.1,
    //       coinAbbr: 'LTC',
    //     ),
    //     setCoin(
    //       balance: 5.0,
    //       usdPrice: 12,
    //       change24h: -34.0,
    //       coinAbbr: 'ETH',
    //     ),
    //     setCoin(
    //       balance: 4.0,
    //       usdPrice: 12,
    //       change24h: 34.0,
    //       coinAbbr: 'XMR',
    //     ),
    //     setCoin(
    //       balance: 3.0,
    //       usdPrice: 12,
    //       change24h: 0.0,
    //       coinAbbr: 'XRP',
    //     ),
    //     setCoin(
    //       balance: 2.0,
    //       usdPrice: 12,
    //       change24h: 0.0,
    //       coinAbbr: 'DASH',
    //     ),
    //     setCoin(
    //       balance: 1.0,
    //       usdPrice: 12,
    //       change24h: 0.0,
    //       coinAbbr: 'ZEC',
    //     ),
    //   ];
    //   double? result = getTotal24Change(coins, sdk);
    //   // -1.7543478260869563 if use double
    //   expect(result, equals(-1.7543478260869565));
    // });

    // test('getTotal24Change returns null for empty or null input', () {
    //   double? resultEmpty = getTotal24Change([], sdk);
    //   double? resultNull = getTotal24Change(null, sdk);

    //   expect(resultEmpty, isNull);
    //   expect(resultNull, isNull);

    //   List<Coin> coins = [
    //     setCoin(
    //       balance: 0.0,
    //       usdPrice: 10,
    //       change24h: 0.05,
    //     ),
    //     setCoin(
    //       balance: 0.0,
    //       usdPrice: 40,
    //       change24h: 0.05,
    //     ),
    //   ];
    //   double? resultZeroBalance = getTotal24Change(coins, sdk);
    //   expect(resultZeroBalance, isNull);

    //   List<Coin> coins2 = [
    //     setCoin(
    //       balance: 10.0,
    //       usdPrice: 10,
    //       change24h: 0,
    //     ),
    //     setCoin(
    //       balance: 10.0,
    //       usdPrice: 40,
    //       change24h: 0,
    //     ),
    //   ];

    //   double? resultNoChangeFor24h = getTotal24Change(coins2, sdk);
    //   expect(resultNoChangeFor24h, 0);
  }, skip: true);
}

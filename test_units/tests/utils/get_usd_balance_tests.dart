// TODO: revisit or migrate to the SDK, since it mostly deals with the sdk
import 'package:test/test.dart';
// import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
// import 'package:mockito/mockito.dart';

// import 'test_util.dart';

// class MockKomodoDefiSdk extends Mock implements KomodoDefiSdk {}

// class MockBalanceManager extends Mock implements BalanceManager {}

void testUsdBalanceFormatter() {
  //   late MockKomodoDefiSdk sdk;
  //   late MockBalanceManager balanceManager;

  //   setUp(() {
  //     sdk = MockKomodoDefiSdk();
  //     balanceManager = MockBalanceManager();
  //     when(sdk.balances).thenReturn(balanceManager);
  //   });

  test('Get formatted USD balance using SDK balance', () async {
    //     final coin = setCoin(usdPrice: 10.12);
    //     when(balanceManager.getBalance(coin.id))
    //         .thenAnswer((_) async => BalanceInfo(spendable: 1.0, unspendable: 0));
    //     expect(await coin.getFormattedUsdBalance(sdk), '\$10.12');

    //     final zeroCoin = setCoin(usdPrice: 0);
    //     when(balanceManager.getBalance(zeroCoin.id))
    //         .thenAnswer((_) async => BalanceInfo(spendable: 1.0, unspendable: 0));
    //     expect(await zeroCoin.getFormattedUsdBalance(sdk), '\$0.00');

    //     final nullPriceCoin = setCoin(usdPrice: null);
    //     expect(await nullPriceCoin.getFormattedUsdBalance(sdk), '\$0.00');

    //     final smallPriceCoin = setCoin(usdPrice: 0.0000001);
    //     when(balanceManager.getBalance(smallPriceCoin.id))
    //         .thenAnswer((_) async => BalanceInfo(spendable: 1.0, unspendable: 0));
    //     expect(await smallPriceCoin.getFormattedUsdBalance(sdk), '\$0.0000001');

    //     final largePriceCoin = setCoin(usdPrice: 123456789);
    //     when(balanceManager.getBalance(largePriceCoin.id))
    //         .thenAnswer((_) async => BalanceInfo(spendable: 1.0, unspendable: 0));
    //     expect(await largePriceCoin.getFormattedUsdBalance(sdk), '\$123456789.00');

    //     final zeroBalanceCoin = setCoin(usdPrice: 123456789);
    //     when(balanceManager.getBalance(zeroBalanceCoin.id))
    //         .thenAnswer((_) async => BalanceInfo(spendable: 0.0, unspendable: 0));
    //     expect(await zeroBalanceCoin.getFormattedUsdBalance(sdk), '\$0.00');
  }, skip: true);
}

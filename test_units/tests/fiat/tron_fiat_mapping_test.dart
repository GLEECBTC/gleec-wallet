import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/fiat/base_fiat_provider.dart';
import 'package:web_dex/bloc/fiat/fiat_order_status.dart';
import 'package:web_dex/bloc/fiat/models/models.dart';
import 'package:web_dex/model/coin_type.dart';

class _TestFiatProvider extends BaseFiatProvider {
  @override
  Future<FiatBuyOrderInfo> buyCoin(
    String accountReference,
    String source,
    ICurrency target,
    String walletAddress,
    String paymentMethodId,
    String sourceAmount,
    String returnUrlOnSuccess,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<List<FiatCurrency>> getFiatList() {
    throw UnimplementedError();
  }

  @override
  Future<List<CryptoCurrency>> getCoinList() {
    throw UnimplementedError();
  }

  @override
  Future<FiatPriceInfo> getPaymentMethodPrice(
    String source,
    ICurrency target,
    String sourceAmount,
    FiatPaymentMethod paymentMethod,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<List<FiatPaymentMethod>> getPaymentMethodsList(
    String source,
    ICurrency target,
    String sourceAmount,
  ) {
    throw UnimplementedError();
  }

  @override
  String getProviderId() => 'test';

  @override
  String get providerIconPath => '';

  @override
  Stream<FiatOrderStatus> watchOrderStatus(String orderId) {
    throw UnimplementedError();
  }
}

void main() {
  group('TRON fiat mapping', () {
    final provider = _TestFiatProvider();

    test('native TRX resolves to trx coin type', () {
      expect(provider.getCoinType('TRX', coinSymbol: 'TRX'), CoinType.trx);
      expect(provider.getCoinType('TRX'), CoinType.trx);
    });

    test('TRON tokens resolve to trc20 coin type', () {
      expect(provider.getCoinType('TRON', coinSymbol: 'USDT'), CoinType.trc20);
    });

    test('native TRX abbreviation stays unchanged', () {
      final currency = CryptoCurrency(
        symbol: 'TRX',
        name: 'TRON',
        chainType: CoinType.trx,
        minPurchaseAmount: Decimal.zero,
      );

      expect(currency.getAbbr(), 'TRX');
    });

    test('TRC20 token abbreviation gets TRC20 suffix', () {
      final currency = CryptoCurrency(
        symbol: 'USDT',
        name: 'Tether',
        chainType: CoinType.trc20,
        minPurchaseAmount: Decimal.zero,
      );

      expect(currency.getAbbr(), 'USDT-TRC20');
    });
  });
}

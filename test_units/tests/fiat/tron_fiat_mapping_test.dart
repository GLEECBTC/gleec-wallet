import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/fiat/banxa_fiat_provider.dart';
import 'package:web_dex/bloc/fiat/base_fiat_provider.dart';
import 'package:web_dex/bloc/fiat/fiat_order_status.dart';
import 'package:web_dex/bloc/fiat/models/models.dart';
import 'package:web_dex/bloc/fiat/ramp/ramp_fiat_provider.dart';
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

class _TestBanxaFiatProvider extends BanxaFiatProvider {
  _TestBanxaFiatProvider(this._coinsResponse);

  final Map<String, dynamic> _coinsResponse;

  @override
  Future<dynamic> apiRequest(
    String method,
    String endpoint, {
    Map<String, String>? queryParams,
    Map<String, dynamic>? body,
  }) async {
    if (queryParams?['endpoint'] == '/api/coins') {
      return _coinsResponse;
    }

    throw UnimplementedError('Unexpected Banxa API request');
  }
}

class _TestBanxaPaymentMethodsProvider extends BanxaFiatProvider {
  int paymentMethodsRequests = 0;

  @override
  Future<dynamic> apiRequest(
    String method,
    String endpoint, {
    Map<String, String>? queryParams,
    Map<String, dynamic>? body,
  }) async {
    if (queryParams?['endpoint'] == '/api/payment-methods') {
      paymentMethodsRequests += 1;
      return {
        'data': {'payment_methods': <Map<String, dynamic>>[]},
      };
    }

    throw UnimplementedError('Unexpected Banxa API request');
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

    test('Ramp asset codes use the TRON prefix', () {
      final ramp = RampFiatProvider();

      expect(
        ramp.getFullCoinCode(
          CryptoCurrency(
            symbol: 'TRX',
            name: 'TRON',
            chainType: CoinType.trx,
            minPurchaseAmount: Decimal.zero,
          ),
        ),
        'TRON_TRX',
      );
      expect(
        ramp.getFullCoinCode(
          CryptoCurrency(
            symbol: 'USDT',
            name: 'Tether',
            chainType: CoinType.trc20,
            minPurchaseAmount: Decimal.zero,
          ),
        ),
        'TRON_USDT',
      );
    });

    test(
      'Banxa keeps native TRX while filtering unsupported BEP20 TRX',
      () async {
        final provider = _TestBanxaFiatProvider({
          'data': {
            'coins': [
              {
                'coin_code': 'TRX',
                'coin_name': 'TRON',
                'blockchains': [
                  {'code': 'TRX', 'min_value': '10'},
                  {'code': 'BNB', 'min_value': '10'},
                ],
              },
            ],
          },
        });

        final coins = await provider.getCoinList();

        expect(coins, hasLength(1));
        expect(coins.single.symbol, 'TRX');
        expect(coins.single.chainType, CoinType.trx);
      },
    );

    test('Banxa payment methods allow native TRX', () async {
      final provider = _TestBanxaPaymentMethodsProvider();

      final methods = await provider.getPaymentMethodsList(
        'USD',
        CryptoCurrency(
          symbol: 'TRX',
          name: 'TRON',
          chainType: CoinType.trx,
          minPurchaseAmount: Decimal.zero,
        ),
        '100',
      );

      expect(methods, isEmpty);
      expect(provider.paymentMethodsRequests, 1);
    });

    test('Banxa payment methods allow native AVAX', () async {
      final provider = _TestBanxaPaymentMethodsProvider();

      final methods = await provider.getPaymentMethodsList(
        'USD',
        CryptoCurrency(
          symbol: 'AVAX',
          name: 'Avalanche',
          chainType: CoinType.avx20,
          minPurchaseAmount: Decimal.zero,
        ),
        '100',
      );

      expect(methods, isEmpty);
      expect(provider.paymentMethodsRequests, 1);
    });

    test('Banxa payment methods still block unsupported BEP20 TRX', () async {
      final provider = _TestBanxaPaymentMethodsProvider();

      final methods = await provider.getPaymentMethodsList(
        'USD',
        CryptoCurrency(
          symbol: 'TRX',
          name: 'TRON (BEP20)',
          chainType: CoinType.bep20,
          minPurchaseAmount: Decimal.zero,
        ),
        '100',
      );

      expect(methods, isEmpty);
      expect(provider.paymentMethodsRequests, 0);
    });
  });
}

import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/fiat/base_fiat_provider.dart';
import 'package:web_dex/bloc/fiat/fiat_order_status.dart';
import 'package:web_dex/bloc/fiat/models/models.dart';
import 'package:web_dex/model/coin_type.dart';

class BanxaFiatProvider extends BaseFiatProvider {
  BanxaFiatProvider();
  final String providerId = 'Banxa';
  final String apiEndpoint = '/api/v1/banxa';
  static final _log = Logger('BanxaFiatProvider');

  bool _isUnsupportedCoinForChain(String coinCode, CoinType coinType) {
    switch (coinCode) {
      case 'AVAX':
      case 'DOT':
      case 'FIL':
      case 'TRX':
        return coinType == CoinType.bep20;
      case 'TON':
        return coinType == CoinType.erc20;
      default:
        return banxaUnsupportedCoinsList.contains(coinCode);
    }
  }

  bool _isUnsupportedCurrency(ICurrency target) {
    if (target is! CryptoCurrency) {
      return false;
    }

    return _isUnsupportedCoinForChain(target.configSymbol, target.chainType);
  }

  @override
  String getProviderId() {
    return providerId;
  }

  @override
  String get providerIconPath => '$assetsPath/fiat/providers/banxa_icon.svg';

  FiatOrderStatus _parseStatusFromResponse(Map<String, dynamic> response) {
    final statusString = response['data']?['order']?['status'] as String?;

    return FiatOrderStatus.fromString(statusString ?? '');
  }

  Future<dynamic> _getPaymentMethods(
    String source,
    ICurrency target, {
    String? sourceAmount,
  }) => apiRequest(
    'GET',
    apiEndpoint,
    queryParams: {
      'endpoint': '/api/payment-methods',
      'source': source,
      'target': target.configSymbol,
    },
  );

  Future<dynamic> _getPricesWithPaymentMethod(
    String source,
    ICurrency target,
    String sourceAmount,
    FiatPaymentMethod paymentMethod,
  ) => apiRequest(
    'GET',
    apiEndpoint,
    queryParams: {
      'endpoint': '/api/prices',
      'source': source,
      'target': target.configSymbol,
      'source_amount': sourceAmount,
      'payment_method_id': paymentMethod.id,
    },
  );

  Future<dynamic> _createOrder(Map<String, dynamic> payload) => apiRequest(
    'POST',
    apiEndpoint,
    queryParams: {'endpoint': '/api/orders'},
    body: payload,
  );

  Future<dynamic> _getOrder(String orderId) => apiRequest(
    'GET',
    apiEndpoint,
    queryParams: {'endpoint': '/api/orders', 'order_id': orderId},
  );

  Future<dynamic> _getFiats() => apiRequest(
    'GET',
    apiEndpoint,
    queryParams: {'endpoint': '/api/fiats', 'orderType': 'buy'},
  );

  Future<dynamic> _getCoins() => apiRequest(
    'GET',
    apiEndpoint,
    queryParams: {'endpoint': '/api/coins', 'orderType': 'buy'},
  );

  // These will be in BLOC:
  @override
  Stream<FiatOrderStatus> watchOrderStatus(String orderId) async* {
    FiatOrderStatus? lastStatus;

    // TODO: At the moment we're polling the API for order status. We can
    // further optimise this by listening for the status redirect page post
    // message, but adds the challenge that we add further web-only code that
    // needs to be re-implemented for mobile/desktop.
    while (true) {
      final response = await _getOrder(
        orderId,
      ).catchError((e) => Future<void>.error('Error fetching order: $e'));

      _log.fine('Fiat order status response:\n${jsonEncode(response)}');
      final status = _parseStatusFromResponse(
        response as Map<String, dynamic>? ?? {},
      );
      final isCompleted =
          status == FiatOrderStatus.success || status == FiatOrderStatus.failed;

      if (status != lastStatus) {
        lastStatus = status;

        yield status;
      }

      if (isCompleted) break;

      await Future<void>.delayed(const Duration(seconds: 5));
    }
  }

  @override
  Future<List<FiatCurrency>> getFiatList() async {
    final response = await _getFiats();
    final data = response['data']['fiats'] as List<dynamic>;
    return data
        .map(
          (item) => FiatCurrency(
            symbol: item['fiat_code'] as String,
            name: item['fiat_name'] as String,
            minPurchaseAmount: Decimal.zero,
          ),
        )
        .toList();
  }

  @override
  Future<List<CryptoCurrency>> getCoinList() async {
    // TODO: add model classes to parse responses like these when migrating to
    // the SDK
    final response = await _getCoins();
    final data = response['data']['coins'] as List<dynamic>;

    final List<CryptoCurrency> currencyList = [];
    for (final item in data) {
      final coinCode = item['coin_code'] as String;
      final coinName = item['coin_name'] as String;
      final blockchains = item['blockchains'] as List<dynamic>;

      for (final blockchain in blockchains) {
        final coinType = getCoinType(
          blockchain['code'] as String,
          coinSymbol: coinCode,
        );
        if (coinType == null) {
          continue;
        }
        if (_isUnsupportedCoinForChain(coinCode, coinType)) {
          _log.warning('Banxa does not support $coinCode on ${coinType.name}');
          continue;
        }

        // Parse min_value which can be a string, int, or double
        final dynamic minValue = blockchain['min_value'];
        Decimal minPurchaseAmount;

        if (minValue == null) {
          minPurchaseAmount = Decimal.fromInt(0);
        } else if (minValue is String) {
          minPurchaseAmount = Decimal.fromJson(minValue);
        } else if (minValue is int) {
          minPurchaseAmount = Decimal.fromInt(minValue);
        } else if (minValue is double) {
          minPurchaseAmount = Decimal.parse(minValue.toString());
        } else {
          // Default to zero for any other unexpected types
          minPurchaseAmount = Decimal.fromInt(0);
          _log.warning(
            'Unexpected type for min_value: ${minValue.runtimeType}',
          );
        }

        currencyList.add(
          CryptoCurrency(
            symbol: coinCode,
            name: coinName,
            chainType: coinType,
            minPurchaseAmount: minPurchaseAmount,
          ),
        );
      }
    }

    return currencyList;
  }

  @override
  Future<List<FiatPaymentMethod>> getPaymentMethodsList(
    String source,
    ICurrency target,
    String sourceAmount,
  ) async {
    try {
      if (_isUnsupportedCurrency(target)) {
        _log.warning('Banxa does not support ${target.getAbbr()}');
        return [];
      }

      final response = await _getPaymentMethods(
        source,
        target,
        sourceAmount: sourceAmount,
      );
      final List<FiatPaymentMethod> paymentMethods =
          (response['data']['payment_methods'] as List)
              .map(
                (json) => FiatPaymentMethod.fromJson(
                  json as Map<String, dynamic>? ?? {},
                ),
              )
              .toList();

      final List<Future<FiatPriceInfo>> priceFutures = [];
      for (final paymentMethod in paymentMethods) {
        final futurePrice = getPaymentMethodPrice(
          source,
          target,
          sourceAmount,
          paymentMethod,
        );
        priceFutures.add(futurePrice);
      }

      // Wait for all futures to complete
      final List<FiatPriceInfo> prices = await Future.wait(priceFutures);

      // Combine price information with payment methods
      for (int i = 0; i < paymentMethods.length; i++) {
        paymentMethods[i] = paymentMethods[i].copyWith(priceInfo: prices[i]);
      }

      return paymentMethods;
    } catch (e, s) {
      _log.severe('Failed to get payment methods list', e, s);
      return [];
    }
  }

  @override
  Future<FiatPriceInfo> getPaymentMethodPrice(
    String source,
    ICurrency target,
    String sourceAmount,
    FiatPaymentMethod paymentMethod,
  ) async {
    try {
      final response =
          await _getPricesWithPaymentMethod(
                source,
                target,
                sourceAmount,
                paymentMethod,
              )
              as Map<String, dynamic>? ??
          {};
      final responseData = response['data'] as Map<String, dynamic>? ?? {};
      final prices = responseData['prices'] as List;
      return FiatPriceInfo.fromJson(
        prices.first as Map<String, dynamic>? ?? {},
      );
    } catch (e, s) {
      _log.severe('Failed to get payment method price', e, s);
      return FiatPriceInfo.zero;
    }
  }

  @override
  Future<FiatBuyOrderInfo> buyCoin(
    String accountReference,
    String source,
    ICurrency target,
    String walletAddress,
    String paymentMethodId,
    String sourceAmount,
    String returnUrlOnSuccess,
  ) async {
    final payload = {
      'account_reference': accountReference,
      'source': source,
      'target': target.configSymbol,
      'wallet_address': walletAddress,
      'payment_method_id': paymentMethodId,
      'source_amount': sourceAmount,
      'return_url_on_success': returnUrlOnSuccess,
    };

    _log.finer('Fiat buy coin order payload: ${jsonEncode(payload)}');
    final response = await _createOrder(payload);
    _log.finer('Fiat buy coin order response: ${jsonEncode(response)}');
    return FiatBuyOrderInfo.fromJson(response as Map<String, dynamic>? ?? {});
  }

  @override
  String? getCoinChainId(CryptoCurrency currency) {
    switch (currency.chainType) {
      case CoinType.bep20:
        return 'BNB'; // It's BSC usually, different for this provider
      default:
        break;
    }

    return super.getCoinChainId(currency);
  }
}

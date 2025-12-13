import 'dart:async';
import 'dart:math';

import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/fiat/base_fiat_provider.dart';
import 'package:web_dex/bloc/fiat/fiat_order_status.dart';
import 'package:web_dex/bloc/fiat/models/models.dart';
import 'package:web_dex/bloc/fiat/ramp/models/host_assets_config.dart';
import 'package:web_dex/bloc/fiat/ramp/models/onramp_purchase_quotation/onramp_purchase_quotation.dart';
import 'package:web_dex/bloc/fiat/ramp/ramp_api_utils.dart';

const logoUrl = 'https://app.gleec.com/icons/logo_icon.webp';

class RampFiatProvider extends BaseFiatProvider {
  RampFiatProvider();
  final String providerId = 'Ramp';
  final String apiEndpoint = '/api/v1/ramp';
  final _log = Logger('RampFiatProvider');

  String get orderDomain =>
      kDebugMode ? 'https://app.demo.ramp.network' : 'https://app.ramp.network';
  String get hostId => kDebugMode
      ? '3uvh7c9nj9hxz97wam8kohzqkogtx4om5uhd6d9c'
      : 'dc8v2qap3ks2mpezf4p2znxuzy5f684oxy7cgstc';

  @override
  String get providerIconPath => '$assetsPath/fiat/providers/ramp_icon.svg';

  @override
  String getProviderId() {
    return providerId;
  }

  String getFullCoinCode(CryptoCurrency target) {
    return '${getCoinChainId(target)}_${target.configSymbol}';
  }

  Future<dynamic> _getPaymentMethods(
    String source,
    CryptoCurrency target, {
    String? sourceAmount,
  }) => apiRequest(
    'POST',
    apiEndpoint,
    queryParams: {'endpoint': '/onramp/quote/all'},
    body: {
      'fiatCurrency': source,
      'cryptoAssetSymbol': getFullCoinCode(target),
      // fiatValue has to be a number, and not a string. Force it to be a
      // double here to ensure that it is in the expected format.
      'fiatValue': sourceAmount != null
          ? Decimal.tryParse(sourceAmount)?.toDouble()
          : null,
    },
  );

  Future<dynamic> _getPricesWithPaymentMethod(
    String source,
    CryptoCurrency target,
    String sourceAmount,
    FiatPaymentMethod paymentMethod,
  ) => apiRequest(
    'POST',
    apiEndpoint,
    queryParams: {'endpoint': '/onramp/quote/all'},
    body: {
      'fiatCurrency': source,
      'cryptoAssetSymbol': getFullCoinCode(target),
      'fiatValue': Decimal.tryParse(sourceAmount)?.toDouble(),
    },
  );

  Future<dynamic> _getFiats() =>
      apiRequest('GET', apiEndpoint, queryParams: {'endpoint': '/currencies'});

  Future<dynamic> _getCoins({String? currencyCode}) => apiRequest(
    'GET',
    apiEndpoint,
    queryParams: {
      'endpoint': '/assets',
      if (currencyCode != null) 'currencyCode': currencyCode,
    },
  );

  @override
  Future<List<FiatCurrency>> getFiatList() async {
    final raw = await _getFiats();
    final data = RampApiUtils.validateResponse<List<Map<String, dynamic>>>(
      raw,
      context: '_getFiats',
    );

    return data
        .where((item) => item['onrampAvailable'] as bool? ?? false)
        .map(
          (item) => FiatCurrency(
            symbol: item['fiatCurrency'] as String,
            name: item['name'] as String,
            minPurchaseAmount: Decimal.zero,
          ),
        )
        .toList();
  }

  @override
  Future<List<CryptoCurrency>> getCoinList() async {
    try {
      final raw = await _getCoins();
      final response = RampApiUtils.validateResponse<Map<String, dynamic>>(
        raw,
        context: '_getCoins',
      );

      final config = HostAssetsConfig.fromJson(response);

      return config.assets
          .map((asset) {
            final coinType = getCoinType(asset.chain);
            if (coinType == null) {
              return null;
            }

            if (rampUnsupportedCoinsList.contains(asset.symbol)) {
              _log.warning('Ramp does not support ${asset.symbol}');
              return null;
            }

            return CryptoCurrency(
              symbol: asset.symbol,
              name: asset.name,
              chainType: coinType,
              minPurchaseAmount: asset.minPurchaseAmount ?? Decimal.zero,
            );
          })
          .where((e) => e != null)
          .cast<CryptoCurrency>()
          .toList();
    } catch (e, s) {
      _log.severe('Failed to parse coin list from Ramp', e, s);
      return [];
    }
  }

  // Turns `APPLE_PAY` to `Apple Pay`
  String _formatMethodName(String methodName) {
    return methodName
        .split('_')
        .map((str) => str[0].toUpperCase() + str.substring(1).toLowerCase())
        .join(' ');
  }

  @override
  Future<List<FiatPaymentMethod>> getPaymentMethodsList(
    String source,
    ICurrency target,
    String sourceAmount,
  ) async {
    try {
      if (target is! CryptoCurrency) {
        throw ArgumentError('Target currency must be a CryptoCurrency');
      }

      final List<FiatPaymentMethod> paymentMethodsList = [];

      final paymentMethodsFuture = _getPaymentMethods(
        source,
        target,
        sourceAmount: sourceAmount,
      );
      final coinsFuture = _getCoins(currencyCode: source);
      final results = await Future.wait([paymentMethodsFuture, coinsFuture]);

      final quoteResult = RampQuoteResult.fromJson(
        results[0] as Map<String, dynamic>,
      );
      final coins = HostAssetsConfig.fromJson(
        results[1] as Map<String, dynamic>,
      );

      final asset = quoteResult.asset;
      final sourceAmountValue = Decimal.parse(sourceAmount);

      quoteResult.paymentMethods.forEach((
        String key,
        RampQuoteResultForPaymentMethod value,
      ) {
        _log.fine('Processing payment method key $key: $value');
        final feeAmount = value.baseRampFee / sourceAmountValue;

        final method = {
          'id': key,
          'name': _formatMethodName(key),
          'transaction_fees': [
            {
              'fees': [
                {'amount': feeAmount.toDouble()},
              ],
            },
          ],
          'transaction_limits': [
            {
              'fiat_code': source,
              'min':
                  (asset.hasValidMinPurchaseAmount()
                          ? asset.minPurchaseAmount
                          : coins.minPurchaseAmount)
                      .toString(),
              'max':
                  (asset.hasValidMaxPurchaseAmount()
                          ? asset.maxPurchaseAmount
                          : coins.maxPurchaseAmount)
                      .toString(),
            },
          ],
          'price_info': {
            'coin_amount': getFormattedCryptoAmount(
              value.cryptoAmount.toString(),
              asset.decimals,
            ),
            'fiat_amount': value.fiatValue.toString(),
          },
        };
        paymentMethodsList.add(FiatPaymentMethod.fromJson(method));
      });
      return paymentMethodsList;
    } catch (e, s) {
      _log.severe('Failed to get payment methods list', e, s);
      return [];
    }
  }

  Decimal _getPaymentMethodFee(FiatPaymentMethod paymentMethod) {
    return paymentMethod.transactionFees.first.fees.first.amount;
  }

  Decimal _getFeeAdjustedPrice(FiatPaymentMethod paymentMethod, Decimal price) {
    final fee = _getPaymentMethodFee(paymentMethod);
    if (fee >= Decimal.one) {
      throw ArgumentError.value(fee, 'fee', 'Fee ratio must be < 1');
    }
    return (price / (Decimal.one - fee)).toDecimal(
      scaleOnInfinitePrecision: scaleOnInfinitePrecision,
    );
  }

  String getFormattedCryptoAmount(String cryptoAmount, int decimals) {
    final amount = Decimal.parse(cryptoAmount);
    final factor = Decimal.parse(pow(10, decimals).toString());
    return (amount / factor)
        .toDecimal(scaleOnInfinitePrecision: scaleOnInfinitePrecision)
        .toStringAsFixed(decimals);
  }

  @override
  Future<FiatPriceInfo> getPaymentMethodPrice(
    String source,
    ICurrency target,
    String sourceAmount,
    FiatPaymentMethod paymentMethod,
  ) async {
    if (target is! CryptoCurrency) {
      throw ArgumentError('Target currency must be a CryptoCurrency');
    }

    final response = await _getPricesWithPaymentMethod(
      source,
      target,
      sourceAmount,
      paymentMethod,
    );
    final asset = response['asset'];
    final prices = asset['price'] as Map<String, dynamic>? ?? {};
    if (!prices.containsKey(source)) {
      return Future.error(
        'Price information not available for the currency: $source',
      );
    }
    final price = Decimal.parse(prices[source].toString());

    final priceInfo = {
      'fiat_code': source,
      'coin_code': target.configSymbol,
      'spot_price_including_fee': _getFeeAdjustedPrice(
        paymentMethod,
        price,
      ).toString(),
      'coin_amount': getFormattedCryptoAmount(
        response[paymentMethod.id]['cryptoAmount'] as String,
        asset['decimals'] as int,
      ),
    };

    return FiatPriceInfo.fromJson(priceInfo);
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
    if (target is! CryptoCurrency) {
      throw ArgumentError('Target currency must be a CryptoCurrency');
    }

    final payload = {
      'hostApiKey': hostId,
      'hostAppName': appShortTitle,
      'hostLogoUrl': logoUrl,
      'userAddress': walletAddress,
      'finalUrl': returnUrlOnSuccess,
      'defaultFlow': 'ONRAMP',
      'enabledFlows': 'ONRAMP',
      'fiatCurrency': source,
      'fiatValue': sourceAmount,
      'defaultAsset': getFullCoinCode(target),
      'hideExitButton': 'true',
      // 'variant': 'hosted', // desktop, mobile, auto, hosted-mobile
      // if(coinsBloc.walletCoins.isNotEmpty)
      //   "swapAsset": coinsBloc.walletCoins.map((e) => e.abbr).toList().toString(),
      // "swapAsset": fullAssetCode, // This limits the crypto asset list at the redirect page
    };

    final queryString = payload.entries
        .map((entry) {
          return '${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent(entry.value)}';
        })
        .join('&');

    final checkoutUrl = '$orderDomain?$queryString';
    return FiatBuyOrderInfo.fromCheckoutUrl(checkoutUrl);
  }

  @override
  Stream<FiatOrderStatus> watchOrderStatus(String orderId) {
    throw UnsupportedError(
      'Ramp integration relies on console.log and/or postMessage '
      'callbacks from a webpage',
    );
  }
}

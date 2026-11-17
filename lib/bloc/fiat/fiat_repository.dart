import 'package:decimal/decimal.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/fiat/base_fiat_provider.dart';
import 'package:web_dex/bloc/fiat/fiat_order_status.dart';
import 'package:web_dex/bloc/fiat/models/models.dart';

class FiatRepository {
  FiatRepository(this.fiatProviders, this._coinsRepo);

  static final _log = Logger('FiatRepository');

  final List<BaseFiatProvider> fiatProviders;
  final CoinsRepo _coinsRepo;

  String? _paymentMethodFiat;
  ICurrency? _paymentMethodsCoin;
  List<FiatPaymentMethod>? _paymentMethodsList;

  BaseFiatProvider? _getPaymentMethodProvider(FiatPaymentMethod paymentMethod) {
    for (final provider in fiatProviders) {
      if (provider.getProviderId() == paymentMethod.providerId) {
        return provider;
      }
    }
    return null;
  }

  Stream<FiatOrderStatus> watchOrderStatus(
    FiatPaymentMethod paymentMethod,
    String orderId,
  ) async* {
    final provider = _getPaymentMethodProvider(paymentMethod);
    if (provider == null) yield* Stream.error('Provider not found');

    yield* provider!.watchOrderStatus(orderId);
  }

  Future<List<ICurrency>> _getListFromProviders(
    Future<List<ICurrency>> Function(BaseFiatProvider) getList,
    bool isCoin,
  ) async {
    Object? providerFailure;
    final futures = fiatProviders.map((provider) async {
      try {
        return await getList(provider);
      } catch (e) {
        providerFailure ??= e;
        _log.warning(
          'Failed to get currency list from ${provider.getProviderId()}',
        );
        return <ICurrency>[];
      }
    });

    final results = await Future.wait(futures);
    final currencyMap = <String, ICurrency>{};
    final knownCoins = _coinsRepo.getKnownCoinsMap();

    for (final currencyList in results) {
      for (final currency in currencyList) {
        final isCoinSupported = knownCoins.containsKey(currency.getAbbr());
        if (isCoin && (currency.isFiat || !isCoinSupported)) {
          _log.fine(
            'Skipping ${currency.getAbbr()} because it is not a coin or '
            'not supported (${currency.configSymbol})',
          );
          continue;
        }

        bool isCoinSegwitKnown(String coinTicker) =>
            currency.isCrypto && knownCoins.containsKey('$coinTicker-segwit');
        if (isCoinSegwitKnown(currency.getAbbr())) {
          final segwitCoin = knownCoins['${currency.getAbbr()}-segwit'];
          final segwitCurrency = (currency as CryptoCurrency).copyWith(
            symbol: segwitCoin!.id.id,
          );
          currencyMap.putIfAbsent(segwitCoin.id.id, () => segwitCurrency);
        }

        currencyMap.putIfAbsent(currency.getAbbr(), () => currency);
      }
    }

    if (currencyMap.isEmpty && providerFailure != null) {
      throw providerFailure!;
    }
    return currencyMap.values.toList()
      ..sort((a, b) => a.symbol.compareTo(b.symbol));
  }

  Future<List<FiatCurrency>> getFiatList() async {
    final currencies = await _getListFromProviders(
      (provider) => provider.getFiatList(),
      false,
    );

    final fiatCurrencies = currencies.cast<FiatCurrency>().toList()
      ..sort((a, b) => currencySorter(a.getAbbr(), b.getAbbr()));

    return fiatCurrencies;
  }

  // Order fiat list by common currencies first (fixed order), then the
  // remaining are sorted alphabetically
  int currencySorter(String a, String b) {
    const List<String> commonCurrencies = ['USD', 'EUR', 'GBP'];

    if (commonCurrencies.contains(a) && commonCurrencies.contains(b)) {
      return commonCurrencies.indexOf(a).compareTo(commonCurrencies.indexOf(b));
    } else if (commonCurrencies.contains(a)) {
      return -1;
    } else if (commonCurrencies.contains(b)) {
      return 1;
    } else {
      return a.compareTo(b);
    }
  }

  Future<List<CryptoCurrency>> getCoinList() async {
    final currencies = await _getListFromProviders(
      (provider) => provider.getCoinList(),
      true,
    );

    return currencies.cast<CryptoCurrency>().toList();
  }

  Decimal? _calculateCoinAmount(
    String fiatAmount,
    Decimal spotPriceIncludingFee,
  ) {
    if (fiatAmount.isEmpty || spotPriceIncludingFee == Decimal.zero) {
      _log.info('Fiat amount or spot price is zero, returning null');
      return null;
    }

    try {
      final fiat = Decimal.parse(fiatAmount);

      final coinAmount = fiat / spotPriceIncludingFee;
      return coinAmount.toDecimal(
        scaleOnInfinitePrecision: scaleOnInfinitePrecision,
      );
    } catch (e, s) {
      _log.shout('Failed to calculate coin amount', e, s);
      return null;
    }
  }

  Decimal _calculateSpotPriceIncludingFee(FiatPaymentMethod paymentMethod) {
    // Use the previous coin and fiat amounts to estimate the spot price
    // including fee.
    final coinAmount = paymentMethod.priceInfo.coinAmount;
    final fiatAmount = paymentMethod.priceInfo.fiatAmount;
    final spotPriceIncludingFee = fiatAmount / coinAmount;
    return spotPriceIncludingFee.toDecimal(
      scaleOnInfinitePrecision: scaleOnInfinitePrecision,
    );
  }

  List<FiatPaymentMethod>? _getPaymentListEstimate(
    List<FiatPaymentMethod> paymentMethodsList,
    String sourceAmount,
    CryptoCurrency target,
    String source,
  ) {
    if (target != _paymentMethodsCoin || source != _paymentMethodFiat) {
      _paymentMethodsCoin = null;
      _paymentMethodFiat = null;
      _paymentMethodsList = null;
      return null;
    }

    try {
      return paymentMethodsList.map((method) {
        final Decimal spotPriceIncludingFee = _calculateSpotPriceIncludingFee(
          method,
        );

        final coinAmount = _calculateCoinAmount(
          sourceAmount,
          spotPriceIncludingFee,
        );

        return method.copyWith(
          priceInfo: method.priceInfo.copyWith(
            coinAmount: coinAmount,
            fiatAmount: Decimal.tryParse(sourceAmount) ?? Decimal.zero,
          ),
        );
      }).toList();
    } catch (e, s) {
      _log.shout('Fiat payment list estimation failed', e, s);
      return null;
    }
  }

  Stream<List<FiatPaymentMethod>> getPaymentMethodsList(
    String source,
    CryptoCurrency target,
    String sourceAmount,
  ) async* {
    if (_paymentMethodsList != null) {
      // Try to estimate the payment list based on the cached one
      // This is to display temporary values while the new list is being fetched
      // This is not a perfect solution
      _paymentMethodsList = _getPaymentListEstimate(
        _paymentMethodsList!,
        sourceAmount,
        target,
        source,
      );
      if (_paymentMethodsList != null) {
        _paymentMethodsCoin = target;
        _paymentMethodFiat = source;
        yield _paymentMethodsList!;
      }
    }

    Object? providerFailure;
    final futures = fiatProviders.map((provider) async {
      try {
        final paymentMethods = await provider.getPaymentMethodsList(
          source,
          target,
          sourceAmount,
        );
        return paymentMethods
            .map(
              (method) => method.copyWith(
                providerId: provider.getProviderId(),
                providerIconAssetPath: provider.providerIconPath,
              ),
            )
            .toList();
      } catch (e) {
        providerFailure ??= e;
        _log.warning(
          'Failed to fetch payment methods from ${provider.getProviderId()}',
        );
        return <FiatPaymentMethod>[];
      }
    });

    final results = await Future.wait(futures);
    _paymentMethodsList = results.expand((x) => x).toList();
    if (_paymentMethodsList!.isEmpty && providerFailure != null) {
      _paymentMethodsList = null;
      _paymentMethodsCoin = null;
      _paymentMethodFiat = null;
      throw providerFailure!;
    }
    _paymentMethodsList = _addRelativePercentField(_paymentMethodsList!);

    _paymentMethodsCoin = target;
    _paymentMethodFiat = source;
    yield _paymentMethodsList!;
  }

  Future<FiatPriceInfo> getPaymentMethodPrice(
    String source,
    ICurrency target,
    String sourceAmount,
    FiatPaymentMethod buyPaymentMethod,
  ) async {
    final provider = _getPaymentMethodProvider(buyPaymentMethod);
    if (provider == null) return Future.error('Provider not found');

    return provider.getPaymentMethodPrice(
      source,
      target,
      sourceAmount,
      buyPaymentMethod,
    );
  }

  Future<FiatBuyOrderInfo> buyCoin({
    required String accountReference,
    required String source,
    required ICurrency target,
    required String walletAddress,
    required FiatPaymentMethod paymentMethod,
    required String sourceAmount,
    required String returnUrlOnSuccess,
  }) async {
    final provider = _getPaymentMethodProvider(paymentMethod);
    if (provider == null) return Future.error('Provider not found');

    return provider.buyCoin(
      accountReference,
      source,
      target,
      walletAddress,
      paymentMethod.id,
      sourceAmount,
      returnUrlOnSuccess,
    );
  }

  List<FiatPaymentMethod> _addRelativePercentField(
    List<FiatPaymentMethod> paymentMethodsList,
  ) {
    if (paymentMethodsList.isEmpty) {
      return paymentMethodsList;
    }

    // Add a relative percent value to each payment method
    // based on the payment method with the highest `coin_amount`
    try {
      final coinAmounts = _paymentMethodsList!
          .map((method) => method.priceInfo.coinAmount)
          .toList();
      final maxCoinAmount = coinAmounts.reduce((a, b) => a > b ? a : b);
      return _paymentMethodsList!.map((method) {
        final coinAmount = method.priceInfo.coinAmount;
        if (coinAmount == Decimal.zero) {
          return method;
        }
        if (coinAmount == maxCoinAmount) {
          return method.copyWith(relativePercent: Decimal.zero);
        }

        final relativeValue =
            (coinAmount - maxCoinAmount) / maxCoinAmount.abs();

        return method.copyWith(
          relativePercent: relativeValue.toDecimal(
            scaleOnInfinitePrecision: scaleOnInfinitePrecision,
          ),
        );
      }).toList()..sort((a, b) {
        if (a.relativePercent == Decimal.zero) return -1;
        if (b.relativePercent == Decimal.zero) return 1;
        return b.relativePercent.compareTo(a.relativePercent);
      });
    } catch (e, s) {
      _log.shout(
        'Failed to add relative percent field to payment methods list',
        e,
        s,
      );
      return paymentMethodsList;
    }
  }
}

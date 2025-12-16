import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:web_dex/bloc/fiat/fiat_order_status.dart';
import 'package:web_dex/bloc/fiat/models/models.dart';
import 'package:web_dex/model/coin_type.dart';
import 'package:web_dex/shared/utils/window/window.dart';

const String domain = 'https://fiat-ramps.gleec.com';

abstract class BaseFiatProvider {
  String getProviderId();

  String get providerIconPath;

  Stream<FiatOrderStatus> watchOrderStatus(String orderId);

  Future<List<FiatCurrency>> getFiatList();

  Future<List<CryptoCurrency>> getCoinList();

  Future<List<FiatPaymentMethod>> getPaymentMethodsList(
    String source,
    ICurrency target,
    String sourceAmount,
  );

  Future<FiatPriceInfo> getPaymentMethodPrice(
    String source,
    ICurrency target,
    String sourceAmount,
    FiatPaymentMethod paymentMethod,
  );

  Future<FiatBuyOrderInfo> buyCoin(
    String accountReference,
    String source,
    ICurrency target,
    String walletAddress,
    String paymentMethodId,
    String sourceAmount,
    String returnUrlOnSuccess,
  );

  static final _log = Logger('BaseFiatProvider');

  /// Makes an API request to the fiat provider. Uses the test mode if the app
  /// is in debug mode.
  @protected
  Future<dynamic> apiRequest(
    String method,
    String endpoint, {
    Map<String, String>? queryParams,
    Map<String, dynamic>? body,
  }) async {
    final domainUri = Uri.parse(domain);
    Uri url;

    // Add `is_test_mode` query param to all requests if we are in debug mode
    final passedQueryParams = <String, dynamic>{}
      ..addAll(queryParams ?? {})
      ..addAll({'is_test_mode': kDebugMode ? 'true' : 'false'});

    url = Uri(
      scheme: domainUri.scheme,
      host: domainUri.host,
      // Remove the leading '/' if it exists in /api/fiats kind of an endpoint
      path: endpoint.startsWith('/') ? endpoint.substring(1) : endpoint,
      query: Uri(queryParameters: passedQueryParams).query,
    );

    final headers = {'Content-Type': 'application/json'};

    http.Response response;
    try {
      if (method == 'GET') {
        response = await http.get(url, headers: headers);
      } else {
        response = await http.post(
          url,
          headers: headers,
          body: json.encode(body),
        );
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return json.decode(response.body);
      } else {
        _log.warning('Request failed with status: ${response.statusCode}');
        dynamic decoded;
        try {
          decoded = json.decode(response.body);
        } catch (_) {
          decoded = response.body;
        }
        return Future.error(decoded as Object);
      }
    } catch (e, s) {
      _log.severe('Network error', e, s);
      return Future.error('Network error: $e');
    }
  }

  String? getCoinChainId(CryptoCurrency currency) {
    switch (currency.chainType) {
      // These exist in the current fiat provider coin lists:
      case CoinType.utxo:
        // BTC, BCH, DOGE, LTC
        return currency.configSymbol;
      case CoinType.erc20:
        return 'ETH';
      case CoinType.bep20:
        return 'BSC'; // It is BNB for some providers like Banxa
      case CoinType.tendermint:
        return 'ATOM';
      case CoinType.avx20:
        return 'AVAX';
      case CoinType.etc:
        return 'ETC';
      case CoinType.ftm20:
        return 'FTM';
      case CoinType.arb20:
        return 'ARB';
      case CoinType.base20:
        return 'BASE';
      case CoinType.hrc20:
        return 'HARMONY';
      case CoinType.plg20:
        return 'MATIC';
      case CoinType.mvr20:
        return 'MOVR';
      default:
        return null;
    }

    // These are not offered yet by the providers:
    /*
    case CoinType.qrc20:
      return 'QRC-20';
    case CoinType.smartChain:
      return 'Smart Chain';
    case CoinType.hco20:
      return 'HCO-20';
    case CoinType.sbch:
      return 'SmartBCH';
    case CoinType.ubiq:
      return 'Ubiq';
    case CoinType.krc20:
      return 'KRC-20';
    case CoinType.iris:
      return 'Iris';
    case CoinType.slp:
      return 'SLP';
      */

    // These exist in coin config but not in CoinType structure yet:
    // ARBITRUM

    // These chain IDs are not supported yet by Gleec Wallet:
    // ADA / CARDANO
    // AVAX-X
    // ALGO
    // ARWEAVE
    // ASTR
    // BAJU
    // BNC
    // BOBA
    // BSV
    // BSX
    // CELO
    // CRO
    // DINGO
    // DOT
    // EGLD
    // ELROND
    // EOS
    // FIL
    // FLOW
    // FLR
    // GOERLI
    // GLMR
    // HBAR
    // KDA
    // KINT
    // KSM
    // KUSAMA
    // LOOPRING
    // MCK
    // METIS
    // MOB
    // NEAR
    // POLKADOT
    // RON
    // SEPOLIA
    // SOL
    // SOLANA
    // STARKNET
    // TERNOA
    // TERRA
    // TEZOS
    // TRON
    // WAX
    // XCH
    // XDAI
    // XLM
    // XPRT
    // XRP
    // XTZ
    // ZILLIQA
  }

  // TODO: migrate to SDK [CoinSubClass] ticker/formatted getters
  CoinType? getCoinType(String chain) {
    switch (chain) {
      case 'BTC':
      case 'BCH':
      case 'DOGE':
      case 'LTC':
        return CoinType.utxo;
      case 'ETH':
        return CoinType.erc20;
      case 'BSC':
      case 'BNB':
        return CoinType.bep20;
      case 'ATOM':
        return CoinType.tendermint;
      case 'AVAX':
        return CoinType.avx20;
      case 'ETC':
        return CoinType.etc;
      case 'FTM':
        return CoinType.ftm20;
      case 'ARBITRUM':
      case 'ARB':
        return CoinType.arb20;
      case 'BASE':
        return CoinType.base20;
      case 'HARMONY':
        return CoinType.hrc20;
      case 'MATIC':
        return CoinType.plg20;
      case 'MOVR':
        return CoinType.mvr20;
      default:
        return null;
    }
  }

  /// Provides the base URL to the intermediate html page that is used to
  /// bypass CORS restrictions so that console.log and postMessage events
  /// can be received and handled.
  static String fiatWrapperPageUrl(String providerUrl) {
    final encodedUrl = base64Encode(utf8.encode(providerUrl));

    return '${getOriginUrl()}/assets/assets/'
        'web_pages/fiat_widget.html?fiatUrl=$encodedUrl';
  }

  /// Provides the URL to the checkout handler HTML page that posts the payment
  /// status received from the fiat provider to the Gleec Wallet app. The
  /// `window.opener.postMessage` function is used for this purpose, and should
  /// be handled by the Gleec Wallet app.
  static String checkoutCallbackUrl() {
    const pagePath = 'assets/assets/web_pages/checkout_status_redirect.html';
    return '${getOriginUrl()}/$pagePath';
  }

  /// Provides the URL to the checkout handler HTML page that posts the payment
  /// status received from the fiat provider to the Gleec Wallet app.
  static String successUrl(String accountReference) {
    final baseUrl = checkoutCallbackUrl();

    final queryString =
        {'account_reference': accountReference, 'status': 'success'}.entries
            .map<String>((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
            .join('&');

    return '$baseUrl?$queryString';
  }
}

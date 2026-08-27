import 'dart:async';
import 'dart:convert';

import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/mm2/mm2.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api_nft.dart';
import 'package:web_dex/mm2/mm2_api/rpc/active_swaps/active_swaps_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:web_dex/mm2/mm2_api/rpc/best_orders/best_orders_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/cancel_order/cancel_order_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/directly_connected_peers/get_directly_connected_peers.dart';
import 'package:web_dex/mm2/mm2_api/rpc/directly_connected_peers/get_directly_connected_peers_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/disable_coin/disable_coin_req.dart';
import 'package:web_dex/mm2/mm2_api/rpc/import_swaps/import_swaps_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/import_swaps/import_swaps_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/kmd_rewards_info/kmd_rewards_info_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/market_maker_bot/market_maker_bot_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/max_maker_vol/max_maker_vol_req.dart';
import 'package:web_dex/mm2/mm2_api/rpc/max_maker_vol/max_maker_vol_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/max_taker_vol/max_taker_vol_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/max_taker_vol/max_taker_vol_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/min_trading_vol/min_trading_vol.dart';
import 'package:web_dex/mm2/mm2_api/rpc/min_trading_vol/min_trading_vol_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/my_orders/my_orders_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/my_orders/my_orders_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/my_recent_swaps/my_recent_swaps_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/my_recent_swaps/my_recent_swaps_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/my_swap_status/my_swap_status_req.dart';
import 'package:web_dex/mm2/mm2_api/rpc/my_tx_history/my_tx_history_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/my_tx_history/my_tx_history_v2_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/order_status/order_status_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/order_status/order_status_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/orderbook_depth/orderbook_depth_req.dart';
import 'package:web_dex/mm2/mm2_api/rpc/orderbook_depth/orderbook_depth_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/recover_funds_of_swap/recover_funds_of_swap_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/recover_funds_of_swap/recover_funds_of_swap_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/rpc_error.dart';
import 'package:web_dex/mm2/mm2_api/rpc/sell/sell_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/send_raw_transaction/send_raw_transaction_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/send_raw_transaction/send_raw_transaction_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/setprice/setprice_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/show_priv_key/show_priv_key_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/show_priv_key/show_priv_key_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/stop/stop_req.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trade_preimage/trade_preimage_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trade_preimage/trade_preimage_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/validateaddress/validateaddress_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/version/version_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/withdraw/withdraw_request.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/shared/utils/utils.dart';

class Mm2Api {
  Mm2Api({required MM2 mm2, required KomodoDefiSdk sdk})
    : _sdk = sdk,
      _mm2 = mm2 {
    nft = Mm2ApiNft(_mm2.call);
  }

  final MM2 _mm2;

  // Ideally we will transition cleanly over to the SDK, but for methods
  // which are deeply intertwined with the app and are broken by HD wallet
  // changes, we will tie into the SDK here.
  final KomodoDefiSdk _sdk;

  late Mm2ApiNft nft;
  VersionResponse? _versionResponse;

  Future<void> dispose() async {
    nft.dispose();
  }

  Future<void> disableCoin(String coinId) async {
    try {
      await _mm2.call(DisableCoinReq(coin: coinId));
    } catch (e, s) {
      log(
        'Error disabling $coinId: $e',
        path: 'api=> disableCoin => _call',
        trace: s,
        isError: true,
      ).ignore();
      return;
    }
  }

  @Deprecated('Use balance from KomoDefiSdk instead')
  Future<String?> getBalance(String abbr) async {
    final sdkAsset = _sdk.assets.assetsFromTicker(abbr).single;
    final cached = _sdk.pubkeys.lastKnown(sdkAsset.id);
    final addresses = cached ?? await sdkAsset.getPubkeys(_sdk);

    return addresses.balance.total.toString();
  }

  Future<MaxTakerVolResponse?> _fallbackToBalanceTaker(String abbr) async {
    final balance = await getBalance(abbr);
    if (balance == null) {
      log(
        'Failed to retrieve balance for fallback construction of MaxTakerVolResponse for $abbr',
        path: 'api => _fallbackToBalanceTaker',
        isError: true,
      ).ignore();
      return null;
    }
    final rational = Rational.parse(balance);
    final result = MaxTakerVolumeResponseResult(
      numer: rational.numerator.toString(),
      denom: rational.denominator.toString(),
    );

    return MaxTakerVolResponse(coin: abbr, result: result);
  }

  Future<Map<String, dynamic>?> getActiveSwaps(
    ActiveSwapsRequest request,
  ) async {
    try {
      return await _mm2.call(request) as Map<String, dynamic>?;
    } catch (e, s) {
      log(
        'Error getting active swaps: $e',
        path: 'api => getActiveSwaps',
        trace: s,
        isError: true,
      ).ignore();
      return <String, dynamic>{'error': 'something went wrong'};
    }
  }

  Future<Map<String, dynamic>?> validateAddress(
    String coinAbbr,
    String address,
  ) async {
    try {
      return await _mm2.call(
        ValidateAddressRequest(coin: coinAbbr, address: address),
      );
    } catch (e, s) {
      log(
        'Error validating address $coinAbbr: $e',
        path: 'api => validateAddress',
        trace: s,
        isError: true,
      ).ignore();
      return null;
    }
  }

  Future<Map<String, dynamic>?> withdraw(WithdrawRequest request) async {
    try {
      return await _mm2.call(request) as Map<String, dynamic>?;
    } catch (e, s) {
      log(
        'Error withdrawing ${request.params.coin}: $e',
        path: 'api => withdraw',
        trace: s,
        isError: true,
      ).ignore();
      return null;
    }
  }

  Future<SendRawTransactionResponse> sendRawTransaction(
    SendRawTransactionRequest request,
  ) async {
    try {
      final response = await _mm2.call(request) as Map<String, dynamic>?;
      if (response == null) {
        return SendRawTransactionResponse(
          txHash: null,
          error: TextError(error: 'null response'),
        );
      }
      return SendRawTransactionResponse.fromJson(response);
    } catch (e, s) {
      log(
        'Error sending raw transaction ${request.coin}: $e',
        path: 'api => sendRawTransaction',
        trace: s,
        isError: true,
      ).ignore();
      return SendRawTransactionResponse(
        txHash: null,
        error: TextError(error: 'null response'),
      );
    }
  }

  Future<Map<String, dynamic>?> getTransactionsHistory(
    MyTxHistoryRequest request,
  ) async {
    try {
      return await _mm2.call(request) as Map<String, dynamic>?;
    } catch (e, s) {
      log(
        'Error sending raw transaction ${request.coin}: $e',
        path: 'api => getTransactions',
        trace: s,
        isError: true,
      ).ignore();
      return null;
    }
  }

  Future<Map<String, dynamic>?> getTransactionsHistoryV2(
    MyTxHistoryV2Request request,
  ) async {
    try {
      return await _mm2.call(request) as Map<String, dynamic>?;
    } catch (e, s) {
      log(
        'Error sending raw transaction ${request.params.coin}: $e',
        path: 'api => getTransactions',
        trace: s,
        isError: true,
      ).ignore();
      return null;
    }
  }

  Future<Map<String, dynamic>?> getRewardsInfo(
    KmdRewardsInfoRequest request,
  ) async {
    try {
      return await _mm2.call(request) as Map<String, dynamic>?;
    } catch (e, s) {
      log(
        'Error getting rewards info: $e',
        path: 'api => getRewardsInfo',
        trace: s,
        isError: true,
      ).ignore();
      return null;
    }
  }

  Future<Map<String, dynamic>?> getBestOrders(BestOrdersRequest request) async {
    try {
      final Map<String, dynamic>? response = await retry(
        () async {
          final Map<String, dynamic>? resp =
              await _mm2.call(request) as Map<String, dynamic>?;
          if (resp == null) {
            throw Exception('null response');
          }
          if (resp['error'] != null) {
            // Throw to allow a quick retry during transient auth/session races
            throw Exception(resp['error'].toString());
          }
          return resp;
        },
        maxAttempts: 4,
        backoffStrategy: const LinearBackoff(
          initialDelay: Duration(milliseconds:  500),
          increment: Duration(milliseconds: 250),
          maxDelay: Duration(seconds: 3),
        ),
      );
      return response;
    } catch (e, s) {
      log(
        'Error getting best orders ${request.coin}: $e',
        path: 'api => getBestOrders',
        trace: s,
        isError: true,
      ).ignore();
      return <String, dynamic>{'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> sell(SellRequest request) async {
    try {
      return await _mm2.call(request);
    } catch (e, s) {
      log(
        'Error sell ${request.base}/${request.rel}: $e',
        path: 'api => sell',
        trace: s,
        isError: true,
      ).ignore();
      return <String, dynamic>{'error': e};
    }
  }

  Future<Map<String, dynamic>?> setprice(SetPriceRequest request) async {
    try {
      return await _mm2.call(request) as Map<String, dynamic>?;
    } catch (e, s) {
      log(
        'Error setprice ${request.base}/${request.rel}: $e',
        path: 'api => setprice',
        trace: s,
        isError: true,
      ).ignore();
      return <String, dynamic>{'error': e};
    }
  }

  /// [beforeMutation] runs immediately before the request leaves the client and
  /// may throw to abort it. Callers use it to re-verify that the wallet the
  /// cancellation was authorised against is still the live one.
  Future<Map<String, dynamic>> cancelOrder(
    CancelOrderRequest request, {
    Future<void> Function()? beforeMutation,
  }) async {
    await beforeMutation?.call();
    try {
      return await _mm2.call(request);
    } catch (e, s) {
      log(
        'Error cancelOrder ${request.uuid}: $e',
        path: 'api => cancelOrder',
        trace: s,
        isError: true,
      ).ignore();
      return <String, dynamic>{'error': e};
    }
  }

  Future<Map<String, dynamic>> getSwapStatus(MySwapStatusReq request) async {
    try {
      return await _mm2.call(request);
    } catch (e, s) {
      log(
        'Error sell getting swap status ${request.uuid}: $e',
        path: 'api => getSwapStatus',
        trace: s,
        isError: true,
      ).ignore();
      return <String, dynamic>{'error': 'something went wrong'};
    }
  }

  Future<MyOrdersResponse?> getMyOrders() async {
    try {
      if (!await _mm2.isSignedIn()) {
        return null;
      }

      final MyOrdersRequest request = MyOrdersRequest();
      final response = await _mm2.call(request);
      if (response['error'] != null) {
        return null;
      }
      return MyOrdersResponse.fromJson(response);
    } catch (e, s) {
      log(
        'Error getting my orders: $e',
        path: 'api => getMyOrders',
        trace: s,
        isError: true,
      ).ignore();
      return null;
    }
  }

  Future<String> getRawSwapData(MyRecentSwapsRequest request) async {
    return jsonEncode(await _mm2.call(request));
  }

  Future<MyRecentSwapsResponse?> getMyRecentSwaps(
    MyRecentSwapsRequest request,
  ) async {
    try {
      final response = await _mm2.call(request);
      if (response['error'] != null) {
        return null;
      }
      return MyRecentSwapsResponse.fromJson(response);
    } catch (e, s) {
      log(
        'Error getting my recent swaps: $e',
        path: 'api => getMyRecentSwaps',
        trace: s,
        isError: true,
      ).ignore();
      return null;
    }
  }

  Future<OrderStatusResponse?> getOrderStatus(String uuid) async {
    try {
      final OrderStatusRequest request = OrderStatusRequest(uuid: uuid);
      final response = await _mm2.call(request);
      if (response['error'] != null) {
        return null;
      }
      return OrderStatusResponse.fromJson(response);
    } catch (e, s) {
      log(
        'Error getting order status $uuid: $e',
        path: 'api => getOrderStatus',
        trace: s,
        isError: true,
      ).ignore();
      return null;
    }
  }

  Future<ImportSwapsResponse?> importSwaps(ImportSwapsRequest request) async {
    try {
      final JsonMap response = await _mm2.call(request);
      if (response['error'] != null) {
        return null;
      }
      return ImportSwapsResponse.fromJson(response);
    } catch (e, s) {
      log(
        'Error import swaps : $e',
        path: 'api => importSwaps',
        trace: s,
        isError: true,
      ).ignore();
      return null;
    }
  }

  /// [beforeMutation] runs immediately before the request leaves the client and
  /// may throw to abort it. Callers use it to re-verify that the wallet the
  /// recovery was authorised against is still the live one.
  Future<RecoverFundsOfSwapResponse?> recoverFundsOfSwap(
    RecoverFundsOfSwapRequest request, {
    Future<void> Function()? beforeMutation,
  }) async {
    await beforeMutation?.call();
    try {
      final JsonMap json = await _mm2.call(request);
      if (json['error'] != null) {
        log(
          'Error recovering funds of swap ${request.uuid}: ${json['error']}',
          path: 'api => recoverFundsOfSwap',
          isError: true,
        ).ignore();
        return null;
      }
      return RecoverFundsOfSwapResponse.fromJson(json);
    } catch (e, s) {
      log(
        'Error recovering funds of swap ${request.uuid}: $e',
        path: 'api => recoverFundsOfSwap',
        trace: s,
        isError: true,
      ).ignore();
      return null;
    }
  }

  Future<MaxTakerVolResponse?> getMaxTakerVolume(
    MaxTakerVolRequest request,
  ) async {
    try {
      final JsonMap json = await _mm2.call(request);
      if (json['error'] != null) {
        return await _fallbackToBalanceTaker(request.coin);
      }
      return MaxTakerVolResponse.fromJson(json);
    } catch (e, s) {
      log(
        'Error getting max taker volume ${request.coin}: $e',
        path: 'api => getMaxTakerVolume',
        trace: s,
        isError: true,
      ).ignore();
      return _fallbackToBalanceTaker(request.coin);
    }
  }

  Future<MaxMakerVolResponse?> getMaxMakerVolume(
    MaxMakerVolRequest request,
  ) async {
    try {
      final JsonMap json = await _mm2.call(request);
      if (json['error'] != null) {
        return await _fallbackToBalanceMaker(request.coin);
      }
      return MaxMakerVolResponse.fromJson(json);
    } catch (e, s) {
      log(
        'Error getting max maker volume ${request.coin}: $e',
        path: 'api => getMaxMakerVolume',
        trace: s,
        isError: true,
      ).ignore();
      return null;
    }
  }

  Future<MaxMakerVolResponse?> _fallbackToBalanceMaker(String coinAbbr) async {
    final balance = await getBalance(coinAbbr);
    if (balance == null) {
      log(
        'Failed to retrieve balance for fallback construction of MaxMakerVolResponse for $coinAbbr',
        path: 'api => _fallbackToBalanceMaker',
        isError: true,
      ).ignore();
      return null;
    }
    final rational = Rational.parse(balance);
    final result = MaxMakerVolResponseValue(
      decimal: rational.toString(),
      numer: rational.numerator.toString(),
      denom: rational.denominator.toString(),
    );

    return MaxMakerVolResponse(coin: coinAbbr, volume: result, balance: result);
  }

  Future<MinTradingVolResponse?> getMinTradingVol(
    MinTradingVolRequest request,
  ) async {
    try {
      final JsonMap json = await _mm2.call(request);
      if (json['error'] != null) {
        return null;
      }
      return MinTradingVolResponse.fromJson(json);
    } catch (e, s) {
      log(
        'Error getting min trading volume ${request.coin}: $e',
        path: 'api => getMinTradingVol',
        trace: s,
        isError: true,
      ).ignore();
      return null;
    }
  }

  Future<OrderBookDepthResponse?> getOrderBookDepth(
    List<List<String>> pairs,
    CoinsRepo coinsRepository,
  ) async {
    final request = OrderBookDepthReq(pairs: pairs);
    try {
      final JsonMap json = await _mm2.call(request);
      if (json['error'] != null) {
        return null;
      }
      return OrderBookDepthResponse.fromJson(json, coinsRepository);
    } catch (e, s) {
      log(
        'Error getting orderbook depth $request: $e',
        path: 'api => getOrderBookDepth',
        trace: s,
      ).ignore();
    }
    return null;
  }

  Future<
    ApiResponse<
      TradePreimageRequest,
      TradePreimageResponseResult,
      Map<String, dynamic>
    >
  >
  getTradePreimage(TradePreimageRequest request) async {
    try {
      final JsonMap responseJson = await _mm2.call(request);
      if (responseJson['error'] != null) {
        return ApiResponse(request: request, error: responseJson);
      }
      return ApiResponse(
        request: request,
        result: TradePreimageResponse.fromJson(responseJson).result,
      );
    } catch (e, s) {
      log(
        'Error getting trade preimage ${request.base}/${request.rel}: $e',
        path: 'api => getTradePreimage',
        trace: s,
        isError: true,
      ).ignore();
      return ApiResponse(request: request);
    }
  }

  /// Start or stop the market maker bot.
  /// The [MarketMakerBotRequest.method] field determines whether the start
  /// or stop method is called.
  ///
  /// The [MarketMakerBotRequest] is sent to the MM2 RPC API.
  ///
  /// The response, or exceptions, are logged.
  ///
  /// Throws [Exception] if an error occurs.
  Future<void> startStopMarketMakerBot(
    MarketMakerBotRequest marketMakerBotRequest,
  ) async {
    try {
      final JsonMap response = await _mm2.call(marketMakerBotRequest.toJson());
      log(
        response.toString(),
        path: 'api => ${marketMakerBotRequest.method} => _call',
      ).ignore();

      if (response['error'] != null) {
        throw RpcException(RpcError.fromJson(response));
      }
    } catch (e, s) {
      log(
        'Error starting or stopping simple market maker bot: $e',
        path: 'api => start_simple_market_maker_bot => _call',
        trace: s,
        isError: true,
      ).ignore();
      rethrow;
    }
  }

  Future<String?> version() async {
    _versionResponse ??= await _getMm2Version();

    return _versionResponse?.result;
  }

  Future<VersionResponse?> _getMm2Version() async {
    try {
      final String versionResult = await mm2.version();
      return VersionResponse(result: versionResult);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> stop() async {
    await _mm2.call(StopReq());
  }

  Future<ShowPrivKeyResponse?> showPrivKey(ShowPrivKeyRequest request) async {
    try {
      final JsonMap json = await _mm2.call(request);
      if (json['error'] != null) {
        return null;
      }
      return ShowPrivKeyResponse.fromJson(json);
    } catch (e, s) {
      log(
        'Error getting privkey ${request.coin}: $e',
        path: 'api => showPrivKey',
        trace: s,
        isError: true,
      ).ignore();
      return null;
    }
  }

  Future<GetDirectlyConnectedPeersResponse> getDirectlyConnectedPeers(
    GetDirectlyConnectedPeers request,
  ) async {
    try {
      final JsonMap json = await _mm2.call(request);
      if (json['error'] != null) {
        log(
          'Error getting directly connected peers: ${json['error']}',
          isError: true,
          path: 'api => getDirectlyConnectedPeers',
        ).ignore();
        throw Exception('Failed to get directly connected peers');
      }

      return GetDirectlyConnectedPeersResponse.fromJson(json);
    } catch (e, s) {
      log(
        'Error getting directly connected peers',
        path: 'api => getDirectlyConnectedPeers',
        trace: s,
        isError: true,
      ).ignore();
      rethrow;
    }
  }
}

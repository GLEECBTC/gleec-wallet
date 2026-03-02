import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:web_dex/mm2/mm2_api/rpc/best_orders/best_orders.dart';
import 'package:web_dex/mm2/mm2_api/rpc/best_orders/best_orders_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/max_maker_vol/max_maker_vol_req.dart';
import 'package:web_dex/mm2/mm2_api/rpc/max_maker_vol/max_maker_vol_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/max_taker_vol/max_taker_vol_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/max_taker_vol/max_taker_vol_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/min_trading_vol/min_trading_vol.dart';
import 'package:web_dex/mm2/mm2_api/rpc/min_trading_vol/min_trading_vol_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/my_recent_swaps/my_recent_swaps_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/my_swap_status/my_swap_status_req.dart';
import 'package:web_dex/mm2/mm2_api/rpc/sell/sell_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/sell/sell_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trade_preimage/trade_preimage_errors.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trade_preimage/trade_preimage_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trade_preimage/trade_preimage_response.dart';
import 'package:web_dex/model/data_from_service.dart';
import 'package:web_dex/model/swap.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/model/trade_preimage.dart';
import 'package:web_dex/services/mappers/trade_preimage_mappers.dart';
import 'package:web_dex/shared/utils/utils.dart';

class DexRepository {
  DexRepository(this._mm2Api);

  final Mm2Api _mm2Api;
  final _rpcCache = _RpcRequestCache();

  static const Duration _tradePreimageCacheTtl = Duration(seconds: 2);
  static const Duration _maxVolumeCacheTtl = Duration(seconds: 5);
  static const Duration _minVolumeCacheTtl = Duration(seconds: 10);

  Future<SellResponse> sell(SellRequest request) async {
    try {
      final Map<String, dynamic> response = await _mm2Api.sell(request);
      return SellResponse.fromJson(response);
    } catch (e) {
      return SellResponse(error: TextError.fromString(e.toString()));
    }
  }

  Future<DataFromService<TradePreimage, BaseError>> getTradePreimage(
    String base,
    String rel,
    Rational price,
    String swapMethod, [
    Rational? volume,
    bool max = false,
  ]) async {
    final cacheKey =
        'trade_preimage:$base:$rel:${price.toString()}:$swapMethod:${volume?.toString() ?? 'null'}:$max';

    return _rpcCache.getOrCreate(
      cacheKey,
      ttl: _tradePreimageCacheTtl,
      request: () async {
        final request = TradePreimageRequest(
          base: base,
          rel: rel,
          price: price,
          volume: volume,
          swapMethod: swapMethod,
          max: max,
        );
        final ApiResponse<
          TradePreimageRequest,
          TradePreimageResponseResult,
          Map<String, dynamic>
        >
        response = await _mm2Api.getTradePreimage(request);

        final Map<String, dynamic>? error = response.error;
        final TradePreimageResponseResult? result = response.result;
        if (error != null) {
          return DataFromService(
            error: tradePreimageErrorFactory.getError(error, response.request),
          );
        }
        if (result == null) {
          return DataFromService(error: TextError(error: 'Something wrong'));
        }
        try {
          return DataFromService(
            data: mapTradePreimageResponseResultToTradePreimage(
              result,
              response.request,
            ),
          );
        } catch (e, s) {
          log(
            e.toString(),
            path:
                'swaps_service => getTradePreimage => mapTradePreimageResponseToTradePreimage',
            trace: s,
            isError: true,
          );
          return DataFromService(error: TextError(error: 'Something wrong'));
        }
      },
    );
  }

  Future<Rational?> getMaxTakerVolume(String coinAbbr) async {
    return _rpcCache.getOrCreate<Rational?>(
      'max_taker_vol:$coinAbbr',
      ttl: _maxVolumeCacheTtl,
      request: () async {
        final MaxTakerVolResponse? response = await _mm2Api.getMaxTakerVolume(
          MaxTakerVolRequest(coin: coinAbbr),
        );
        if (response == null) {
          return null;
        }

        return fract2rat(response.result.toJson());
      },
    );
  }

  Future<Rational?> getMaxMakerVolume(String coinAbbr) async {
    return _rpcCache.getOrCreate<Rational?>(
      'max_maker_vol:$coinAbbr',
      ttl: _maxVolumeCacheTtl,
      request: () async {
        final MaxMakerVolResponse? response = await _mm2Api.getMaxMakerVolume(
          MaxMakerVolRequest(coin: coinAbbr),
        );
        if (response == null) {
          return null;
        }

        return fract2rat(response.volume.toFractionalJson());
      },
    );
  }

  Future<Rational?> getMinTradingVolume(String coinAbbr) async {
    return _rpcCache.getOrCreate<Rational?>(
      'min_trading_vol:$coinAbbr',
      ttl: _minVolumeCacheTtl,
      request: () async {
        final MinTradingVolResponse? response = await _mm2Api.getMinTradingVol(
          MinTradingVolRequest(coin: coinAbbr),
        );
        if (response == null) {
          return null;
        }

        return fract2rat(response.result.toJson());
      },
    );
  }

  Future<List<Swap>?> getRecentSwaps(MyRecentSwapsRequest request) async {
    return null;
  }

  Future<BestOrders> getBestOrders(BestOrdersRequest request) async {
    // Only allow best_orders when user is on Swap (DEX) or Bridge pages
    final MainMenuValue current = routingState.selectedMenu;
    final bool isTradingPage =
        current == MainMenuValue.dex || current == MainMenuValue.bridge;
    if (!isTradingPage) {
      // Not an error – we intentionally suppress best_orders away from trading pages
      return BestOrders(result: <String, List<BestOrder>>{});
    }

    // Testing aid: opt-in random failure in debug mode
    if (kDebugMode &&
        kSimulateBestOrdersFailure &&
        Random().nextDouble() < kSimulatedBestOrdersFailureRate) {
      return BestOrders(
        error: TextError(error: 'Simulated best_orders failure (debug)'),
      );
    }

    Map<String, dynamic>? response;
    try {
      response = await _mm2Api.getBestOrders(request);
    } catch (e, s) {
      log(
        'best_orders request failed: $e',
        trace: s,
        path: 'api => getBestOrders',
        isError: true,
      ).ignore();
      return BestOrders(error: TextError.fromString(e.toString()));
    }

    if (response == null) {
      return BestOrders(
        error: TextError(error: 'best_orders returned null response'),
      );
    }

    final String? errorText = response['error'] as String?;
    if (errorText != null && errorText.isNotEmpty) {
      // Map known "no orders" network condition to empty result so UI shows a
      // graceful "Nothing found" instead of an error panel.
      final String? errorType = response['error_type'] as String?;
      final String? errorPath = response['error_path'] as String?;
      final bool isNoOrdersNetworkCondition =
          errorPath == 'best_orders' &&
          errorType == 'P2PError' &&
          errorText.contains('No response from any peer');

      // Mm2Api.getBestOrders may wrap MM2 errors in an Exception() during
      // retry handling, yielding text like: "Exception: No response from any peer"
      // (without error_type/error_path). Treat these as "no orders" as well.
      final bool isWrappedNoOrdersText = errorText.toLowerCase().contains(
        'no response from any peer',
      );

      if (isNoOrdersNetworkCondition || isWrappedNoOrdersText) {
        return BestOrders(result: <String, List<BestOrder>>{});
      }

      log(
        'best_orders returned error: $errorText',
        path: 'api => getBestOrders',
        isError: true,
      ).ignore();
      return BestOrders(error: TextError(error: errorText));
    }

    final Map<String, dynamic>? result =
        response['result'] as Map<String, dynamic>?;
    if (result == null || result.isEmpty) {
      // No error and no result → no liquidity available
      return BestOrders(result: <String, List<BestOrder>>{});
    }

    try {
      return BestOrders.fromJson(response);
    } catch (e, s) {
      log('Error parsing best_orders response: $e', trace: s, isError: true);

      return BestOrders(
        error: TextError(
          error: 'Something went wrong! Unexpected response format.',
        ),
      );
    }
  }

  Future<Swap> getSwapStatus(String swapUuid) async {
    final response = await _mm2Api.getSwapStatus(
      MySwapStatusReq(uuid: swapUuid),
    );

    if (response['error'] != null) {
      throw TextError(error: response['error']);
    }

    return Swap.fromJson(response['result']);
  }

  Future<void> waitOrderbookAvailability({
    int retries = 10,
    int interval = 300,
  }) async {
    BestOrders orders;

    for (int attempt = 0; attempt < retries; attempt++) {
      orders = await getBestOrders(
        BestOrdersRequest(
          coin: defaultDexCoin,
          type: BestOrdersRequestType.number,
          number: 1,
          action: 'sell',
        ),
      );

      if (orders.result?.isNotEmpty ?? false) {
        return;
      }

      await Future.delayed(Duration(milliseconds: interval));
    }
  }
}

class _RpcRequestCache {
  final Map<String, _RpcCacheEntry<dynamic>> _resolved = {};
  final Map<String, Future<dynamic>> _inFlight = {};

  Future<T> getOrCreate<T>(
    String key, {
    required Duration ttl,
    required Future<T> Function() request,
  }) async {
    final now = DateTime.now();
    final cached = _resolved[key];
    if (cached != null && now.difference(cached.cachedAt) < ttl) {
      return cached.value as T;
    }

    final inFlight = _inFlight[key];
    if (inFlight != null) {
      return await inFlight as T;
    }

    final future = request();
    _inFlight[key] = future;
    try {
      final value = await future;
      _resolved[key] = _RpcCacheEntry(value: value, cachedAt: DateTime.now());
      return value;
    } finally {
      _inFlight.remove(key);
    }
  }
}

class _RpcCacheEntry<T> {
  _RpcCacheEntry({required this.value, required this.cachedAt});

  final T value;
  final DateTime cachedAt;
}

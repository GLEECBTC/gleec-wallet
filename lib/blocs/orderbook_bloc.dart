import 'dart:async';

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart'
    show NumericValue, OrderInfo, OrderbookResponse;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart'
    show KomodoDefiSdk, OrderbookEvent;
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/blocs/bloc_base.dart';
import 'package:web_dex/shared/utils/utils.dart';

class OrderbookBloc implements BlocBase {
  OrderbookBloc({required KomodoDefiSdk sdk}) : _sdk = sdk {
    _timer = Timer.periodic(
      _fallbackPollingInterval,
      (_) async => await _updateOrderbooks(),
    );
  }

  static const Duration _fallbackPollingInterval = Duration(seconds: 15);
  static const Duration _streamStaleTimeout = Duration(seconds: 20);

  final KomodoDefiSdk _sdk;
  Timer? _timer;

  // keys are 'base/rel' Strings
  final Map<String, OrderbookSubscription> _subscriptions = {};

  @override
  void dispose() {
    _timer?.cancel();

    final pairs = _subscriptions.keys.toList();
    for (final pair in pairs) {
      _removeSubscription(pair).ignore();
    }
  }

  OrderbookResult? getInitialData(String base, String rel) {
    final String pair = '$base/$rel';
    final OrderbookSubscription? subscription = _subscriptions[pair];

    return subscription?.initialData;
  }

  Stream<OrderbookResult?> getOrderbookStream(String base, String rel) {
    final String pair = '$base/$rel';
    final OrderbookSubscription? subscription = _subscriptions[pair];

    if (subscription != null) {
      return subscription.stream;
    } else {
      final controller = StreamController<OrderbookResult?>.broadcast();
      final sink = controller.sink;
      final stream = controller.stream;

      _subscriptions[pair] = OrderbookSubscription(
        initialData: null,
        controller: controller,
        sink: sink,
        stream: stream,
      );

      _ensureStreamSubscription(pair);
      _fetchOrderbook(pair).ignore();
      return _subscriptions[pair]!.stream;
    }
  }

  Future<void> _updateOrderbooks() async {
    final List<String> pairs = List.of(_subscriptions.keys);
    final List<String> pairsWithoutListeners = [];

    for (String pair in pairs) {
      final OrderbookSubscription? subscription = _subscriptions[pair];
      if (subscription == null) {
        continue;
      }
      if (!subscription.controller.hasListener) {
        pairsWithoutListeners.add(pair);
        continue;
      }

      final lastUpdateAt = subscription.lastUpdateAt;
      final hasFreshStreamUpdate =
          lastUpdateAt != null &&
          DateTime.now().difference(lastUpdateAt) < _streamStaleTimeout;
      if (hasFreshStreamUpdate) {
        continue;
      }

      await _fetchOrderbook(pair);
    }

    for (final pair in pairsWithoutListeners) {
      await _removeSubscription(pair);
    }
  }

  Future<void> _removeSubscription(String pair) async {
    final subscription = _subscriptions.remove(pair);
    if (subscription == null) return;

    await subscription.streamSubscription?.cancel();
    await subscription.controller.close();
  }

  void _ensureStreamSubscription(String pair) {
    final subscription = _subscriptions[pair];
    if (subscription == null) return;
    if (subscription.streamSubscription != null ||
        subscription.streamInitializing) {
      return;
    }

    final coins = pair.split('/');
    subscription.streamInitializing = true;

    () async {
      try {
        final streamSubscription = await _sdk.subscribeToOrderbook(
          base: coins[0],
          rel: coins[1],
        );

        streamSubscription
          ..onData((event) => _onOrderbookEvent(pair, event))
          ..onError((Object error, StackTrace trace) {
            log(
              'Orderbook stream error for pair $pair',
              path: 'OrderbookBloc._ensureStreamSubscription',
              trace: trace,
              isError: true,
            ).ignore();
          });

        final activeSubscription = _subscriptions[pair];
        if (activeSubscription == null) {
          await streamSubscription.cancel();
          return;
        }
        activeSubscription.streamSubscription = streamSubscription;
      } catch (e, s) {
        log(
          'Failed to subscribe orderbook stream for pair $pair',
          path: 'OrderbookBloc._ensureStreamSubscription',
          trace: s,
          isError: true,
        ).ignore();
      } finally {
        final activeSubscription = _subscriptions[pair];
        if (activeSubscription != null) {
          activeSubscription.streamInitializing = false;
        }
      }
    }().ignore();
  }

  void _onOrderbookEvent(String pair, OrderbookEvent event) {
    final subscription = _subscriptions[pair];
    if (subscription == null) return;

    try {
      final response = _mapStreamEventToResponse(event);
      final result = OrderbookResult(response: response);
      subscription.initialData = result;
      subscription.lastUpdateAt = DateTime.now();
      subscription.sink.add(result);
    } catch (e, s) {
      log(
        'Failed to map orderbook stream event for pair $pair',
        path: 'OrderbookBloc._onOrderbookEvent',
        trace: s,
        isError: true,
      ).ignore();
      _fetchOrderbook(pair).ignore();
    }
  }

  Future<void> _fetchOrderbook(String pair) async {
    final OrderbookSubscription? subscription = _subscriptions[pair];
    if (subscription == null) return;

    final List<String> coins = pair.split('/');

    try {
      final OrderbookResponse response = await _sdk.client.rpc.orderbook
          .orderbook(base: coins[0], rel: coins[1]);

      final result = OrderbookResult(response: response);
      subscription.initialData = result;
      subscription.lastUpdateAt = DateTime.now();
      subscription.sink.add(result);
    } catch (e, s) {
      log(
        // Exception message can contain RPC pass, so avoid displaying it and logging it
        'Unexpected orderbook error for pair $pair',
        path: 'OrderbookBloc._fetchOrderbook',
        trace: s,
        isError: true,
      ).ignore();
      final result = OrderbookResult(error: 'Unexpected error for pair $pair');
      subscription.initialData = result;
      subscription.sink.add(result);
    }
  }

  OrderbookResponse _mapStreamEventToResponse(OrderbookEvent event) {
    final asks = event.asks.map(_mapOrderInfo).toList();
    final bids = event.bids.map(_mapOrderInfo).toList();

    return OrderbookResponse(
      mmrpc: '2.0',
      base: event.base,
      rel: event.rel,
      bids: bids,
      asks: asks,
      numBids: bids.length,
      numAsks: asks.length,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  OrderInfo _mapOrderInfo(Map<String, dynamic> orderData) {
    final price = orderData['price']?.toString();
    final maxVolume = orderData['max_volume']?.toString();

    if (price == null || maxVolume == null) {
      throw ArgumentError('Orderbook stream entry is missing price/max_volume');
    }

    final minVolume = orderData['min_volume']?.toString();
    final priceValue = NumericValue(decimal: price);
    final maxVolumeValue = NumericValue(decimal: maxVolume);

    return OrderInfo(
      uuid: orderData['uuid']?.toString(),
      pubkey: orderData['pubkey']?.toString(),
      price: priceValue,
      baseMaxVolume: maxVolumeValue,
      baseMaxVolumeAggregated: maxVolumeValue,
      baseMinVolume: minVolume == null
          ? null
          : NumericValue(decimal: minVolume),
    );
  }
}

class OrderbookSubscription {
  OrderbookSubscription({
    required this.initialData,
    required this.controller,
    required this.sink,
    required this.stream,
  });

  OrderbookResult? initialData;
  final StreamController<OrderbookResult?> controller;
  final Sink<OrderbookResult?> sink;
  final Stream<OrderbookResult?> stream;
  StreamSubscription<OrderbookEvent>? streamSubscription;
  DateTime? lastUpdateAt;
  bool streamInitializing = false;
}

class OrderbookResult {
  const OrderbookResult({this.response, this.error});

  final OrderbookResponse? response;
  final String? error;

  bool get hasError => error != null;
}

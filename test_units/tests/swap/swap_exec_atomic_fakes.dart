import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/bloc/dex_repository.dart';
import 'package:web_dex/mm2/mm2_api/rpc/order_status/cancellation_reason.dart';
import 'package:web_dex/mm2/mm2_api/rpc/sell/sell_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/sell/sell_response.dart';
import 'package:web_dex/model/my_orders/my_order.dart';
import 'package:web_dex/model/swap.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/services/orders_service/my_orders_service.dart';
import 'package:web_dex/shared/swap/atomic_swap_execution.dart';
import 'package:web_dex/shared/swap/atomic_swap_source.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

import 'swap_exec_fakes.dart';
import 'swap_test_fixtures.dart';

/// A DEX repository that places orders and reports swaps from a script.
class FakeDex implements DexRepository {
  final List<SellRequest> sells = [];
  SellResponse sellResponse = SellResponse(
    result: SellResponseResult(uuid: 'a-1'),
  );
  Object? sellError;

  /// Swaps KDF knows, by uuid. An unknown uuid answers as KDF does: an error.
  final Map<String, Swap> swaps = {};
  int statusCalls = 0;

  /// Thrown by every status read while set: an engine that cannot be read.
  Object? statusError;

  /// Holds every status read until completed.
  Completer<void>? statusGate;

  @override
  Future<SellResponse> sellOrThrow(SellRequest request) async {
    sells.add(request);
    final error = sellError;
    if (error != null) throw error;
    return sellResponse;
  }

  @override
  Future<Swap> getSwapStatus(String swapUuid) async {
    statusCalls++;
    await statusGate?.future;
    final error = statusError;
    if (error != null) throw error;
    final swap = swaps[swapUuid];
    if (swap == null) {
      throw TextError(error: 'lp_swap:1140] No swap with uuid $swapUuid');
    }
    return swap;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// An order service answering order status from a script.
class FakeOrders implements MyOrdersService {
  /// Taker orders KDF still knows, with their cancellation reason.
  final Map<String, TakerOrderCancellationReason> takers = {};

  /// Maker orders KDF knows.
  final Set<String> makers = {};
  final List<String> cancelled = [];
  String? cancelError;
  int statusCalls = 0;

  /// Thrown by every strict status read while set: an engine that cannot be
  /// read. The lenient read answers null instead, as the real one does.
  Object? statusError;

  @override
  Future<OrderStatus?> getStatus(String uuid) async {
    statusCalls++;
    return statusError == null ? _statusOf(uuid) : null;
  }

  @override
  Future<OrderStatus> getStatusOrThrow(String uuid) async {
    statusCalls++;
    final error = statusError;
    if (error != null) throw error;
    return _statusOf(uuid) ??
        (throw TextError(
          error: 'lp_ordermatch:5805] Order with uuid $uuid is not found',
        ));
  }

  OrderStatus? _statusOf(String uuid) {
    final reason = takers[uuid];
    if (reason != null) {
      return OrderStatus(
        takerOrderStatus: TakerOrderStatus(
          order: _order(uuid, TradeSide.taker),
          cancellationReason: reason,
        ),
      );
    }
    if (makers.contains(uuid)) {
      return OrderStatus(
        makerOrderStatus: MakerOrderStatus(
          order: _order(uuid, TradeSide.maker),
          cancellationReason: MakerOrderCancellationReason.none,
        ),
      );
    }
    return null;
  }

  @override
  Future<String?> cancelOrder(
    String uuid, {
    Future<void> Function()? beforeMutation,
  }) async {
    cancelled.add(uuid);
    return cancelError;
  }

  MyOrder _order(String uuid, TradeSide side) => MyOrder(
    base: 'ETH',
    orderType: side,
    rel: 'USDC-ERC20',
    relAmount: Rational.fromInt(3000),
    uuid: uuid,
    baseAmount: Rational.one,
    createdAt: 0,
    cancelable: true,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const takerErrorEvents = [
  'StartFailed',
  'NegotiateFailed',
  'TakerFeeSendFailed',
  'MakerPaymentValidateFailed',
  'MakerPaymentWaitConfirmFailed',
  'TakerPaymentTransactionFailed',
  'TakerPaymentWaitConfirmFailed',
  'TakerPaymentDataSendFailed',
  'TakerPaymentWaitForSpendFailed',
  'MakerPaymentSpendFailed',
  'TakerPaymentWaitRefundStarted',
  'TakerPaymentRefundStarted',
  'TakerPaymentRefunded',
  'TakerPaymentRefundedByWatcher',
  'TakerPaymentRefundFailed',
  'TakerPaymentRefundFinished',
];

const makerErrorEvents = [
  'StartFailed',
  'NegotiateFailed',
  'TakerFeeValidateFailed',
  'MakerPaymentTransactionFailed',
  'MakerPaymentDataSendFailed',
  'MakerPaymentWaitConfirmFailed',
  'TakerPaymentValidateFailed',
  'TakerPaymentWaitConfirmFailed',
  'TakerPaymentSpendFailed',
  'TakerPaymentSpendConfirmFailed',
  'MakerPaymentWaitRefundStarted',
  'MakerPaymentRefundStarted',
  'MakerPaymentRefunded',
  'MakerPaymentRefundFailed',
  'MakerPaymentRefundFinished',
];

/// An atomic swap as KDF reports it, selling 1 [sell] for 3000 [buy] — as the
/// taker unless [maker]. [txHashes] attaches a transaction hash to an event.
Swap atomicSwapOf(
  String uuid,
  List<String> events, {
  bool maker = false,
  Map<String, String> txHashes = const {},
  DateTime? at,
  String sell = 'ETH',
  String buy = 'USDC-ERC20',
}) {
  final start = (at ?? DateTime.utc(2026, 9)).millisecondsSinceEpoch;
  return Swap.fromJson({
    'type': maker ? 'Maker' : 'Taker',
    'uuid': uuid,
    'my_order_uuid': 'order-$uuid',
    'events': [
      for (final (index, type) in events.indexed)
        {
          'timestamp': start + index * 1000,
          'event': {
            'type': type,
            if (txHashes[type] != null) 'data': {'tx_hash': txHashes[type]},
          },
        },
    ],
    'maker_amount': maker ? '1' : '3000',
    'maker_coin': maker ? sell : buy,
    'taker_amount': maker ? '3000' : '1',
    'taker_coin': maker ? buy : sell,
    'success_events': const ['Started', 'Finished'],
    'error_events': maker ? makerErrorEvents : takerErrorEvents,
  });
}

/// An atomic quote whose plan sells [volume] ETH at [price] USDC each.
SwapQuote atomicQuoteOf({String volume = '1', String price = '3000'}) =>
    quoteOf(
      id: 'atomic',
      source: SwapLiquiditySource.atomic,
      routeKind: SwapRouteKind.direct,
      order: null,
      sell: volume,
      guaranteed: '2990',
      payload: AtomicSwapPlan(
        base: eth,
        rel: usdc,
        volume: d(volume),
        price: d(price),
      ),
    );

/// An atomic executor over a scripted DEX on a fake clock, recording what
/// the handle it hands out reports.
class AtomicRig {
  AtomicRig(this.async, {this.misses = 3});

  static const pollInterval = Duration(seconds: 3);

  final FakeAsync async;
  final int misses;
  final dex = FakeDex();
  final orders = FakeOrders();
  late final executor = AtomicSwapExecutor(
    dexRepository: dex,
    orders: orders,
    networks: () => execNetworks,
    resolveAsset: resolveTicker,
    pollInterval: pollInterval,
    missesBeforeNoMatch: misses,
  );
  final List<SwapExecutionSnapshot> seen = [];
  var done = false;
  SwapExecutionHandle? handle;
  Object? error;

  SwapExecutionSnapshot get latest => handle!.latest;

  /// Starts [quote]; its first poll has not run yet.
  void start([SwapQuote? quote]) {
    executor.start(quote ?? atomicQuoteOf()).then(_follow, onError: _fail);
    async.flushMicrotasks();
  }

  /// Re-attaches to [id]; its first poll has not run yet.
  void resume(String id) {
    executor.resume(id).then((h) {
      if (h != null) _follow(h);
    }, onError: _fail);
    async.flushMicrotasks();
  }

  /// Runs the first poll.
  void firstPoll() => async.elapse(Duration.zero);

  /// Runs the next [count] polls.
  void polls([int count = 1]) => async.elapse(pollInterval * count);

  void _follow(SwapExecutionHandle h) {
    handle = h;
    h.updates.listen(seen.add, onDone: () => done = true);
  }

  void _fail(Object e) => error = e;
}

/// Runs [body] on a fake clock. A stream's end is delivered through the real
/// event loop even then, so the event queue is pumped once more before the
/// rig is handed back for the checks that need it.
Future<AtomicRig> onFakeClock(
  void Function(AtomicRig rig) body, {
  int misses = 3,
}) async {
  late AtomicRig rig;
  fakeAsync((async) => body(rig = AtomicRig(async, misses: misses)));
  await pumpEventQueue();
  return rig;
}

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/dex_repository.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/mm2/mm2_api/rpc/my_swap_status/my_swap_status_req.dart';
import 'package:web_dex/mm2/mm2_api/rpc/order_status/cancellation_reason.dart';
import 'package:web_dex/mm2/mm2_api/rpc/order_status/order_status_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/sell/sell_request.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/services/orders_service/my_orders_service.dart';
import 'package:web_dex/shared/swap/atomic_swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';

import 'swap_exec_atomic_fakes.dart';
import 'swap_exec_fakes.dart';

/// Covers the strict order status read, and the atomic executor over the real
/// DEX repository and order service when KDF answers, in its own words, that
/// it has no record of an order or a swap.
void main() {
  late _StatusRpc rpc;
  setUp(() => rpc = _StatusRpc());

  group('the strict order status read', () {
    late MyOrdersService orders;
    setUp(() => orders = MyOrdersService(rpc));

    test('reads a taker order and why it stopped', () async {
      rpc.orderAnswer = _takerAnswer('TimedOut');

      final status = await orders.getStatusOrThrow('a-1');

      expect(
        status.takerOrderStatus!.cancellationReason,
        TakerOrderCancellationReason.timedOut,
      );
      expect(status.takerOrderStatus!.order.uuid, 'a-1');
      expect(status.makerOrderStatus, isNull);
    });

    test('reads a maker order', () async {
      rpc.orderAnswer = {
        'type': 'Maker',
        'order': _makerOrder,
        'cancellation_reason': 'Cancelled',
      };

      final status = await orders.getStatusOrThrow('m-1');

      expect(
        status.makerOrderStatus!.cancellationReason,
        MakerOrderCancellationReason.cancelled,
      );
      expect(status.takerOrderStatus, isNull);
    });

    test('gives an error from KDF in its own words', () async {
      rpc.orderAnswer = {'error': 'Order with uuid a-1 is not found'};

      await expectLater(
        orders.getStatusOrThrow('a-1'),
        throwsA(
          isA<TextError>().having(
            (e) => e.error,
            'error',
            'Order with uuid a-1 is not found',
          ),
        ),
      );
    });

    test('throws what a call that got no answer threw', () async {
      final cause = TimeoutException('no answer from KDF');
      rpc.orderError = cause;

      await expectLater(orders.getStatusOrThrow('a-1'), throwsA(same(cause)));
    });

    test('leaves the lenient read as it was: the status, or null', () async {
      rpc.lenientAnswer = OrderStatusResponse.fromJson(
        _takerAnswer('Fulfilled'),
      );
      expect(
        (await orders.getStatus('a-1'))!.takerOrderStatus!.cancellationReason,
        TakerOrderCancellationReason.fulfilled,
      );

      rpc.lenientAnswer = null;
      expect(await orders.getStatus('a-1'), isNull);
    });
  });

  test('KDF saying it has neither the order nor a swap ends an unmatched '
      'order as no match', () {
    fakeAsync((async) {
      rpc
        ..swapAnswer = {'error': 'lp_swap:1140] No swap with uuid a-1'}
        ..orderAnswer = {
          'error':
              'lp_ordermatch:5805] my_orders_storage:319] Order with uuid a-1 '
              'is not found',
        };
      final executor = AtomicSwapExecutor(
        dexRepository: DexRepository(rpc),
        orders: MyOrdersService(rpc),
        networks: () => execNetworks,
        resolveAsset: resolveTicker,
      );
      SwapExecutionHandle? handle;
      executor.start(atomicQuoteOf()).then((h) => handle = h);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      expect(handle!.latest.isTerminal, isFalse);

      async.elapse(const Duration(seconds: 3));
      expect(handle!.latest.outcome!.kind, SwapOutcomeKind.noMatch);
      expect(handle!.latest.fundsMovement, SwapFundsMovement.none);
    });
  });
}

Map<String, dynamic> _takerAnswer(String reason) => {
  'type': 'Taker',
  'order': {
    'created_at': 1758800000000,
    'cancellable': false,
    'request': {
      'base': 'ETH',
      'rel': 'USDC-ERC20',
      'base_amount': '1',
      'rel_amount': '3000',
    },
  },
  'cancellation_reason': reason,
};

const _makerOrder = {
  'base': 'ETH',
  'rel': 'USDC-ERC20',
  'available_amount': '1',
  'max_base_vol': '1',
  'price': '3000',
  'uuid': '9f1c2e3d-4b5a-4c6d-8e7f-0a1b2c3d4e5f',
};

/// The RPC layer, answering each read from a script.
class _StatusRpc implements Mm2Api {
  Map<String, dynamic> swapAnswer = {};
  Map<String, dynamic> orderAnswer = {};
  Object? orderError;
  OrderStatusResponse? lenientAnswer;

  @override
  Future<Map<String, dynamic>> sellOrThrow(SellRequest request) async => {
    'result': {'uuid': 'a-1'},
  };

  @override
  Future<Map<String, dynamic>> getSwapStatus(MySwapStatusReq request) async =>
      swapAnswer;

  @override
  Future<Map<String, dynamic>> orderStatusOrThrow(String uuid) async {
    final error = orderError;
    if (error != null) throw error;
    return orderAnswer;
  }

  @override
  Future<OrderStatusResponse?> getOrderStatus(String uuid) async =>
      lenientAnswer;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

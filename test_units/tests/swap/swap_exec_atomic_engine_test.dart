import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/dex_repository.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/mm2/mm2_api/rpc/my_swap_status/my_swap_status_req.dart';
import 'package:web_dex/mm2/mm2_api/rpc/sell/sell_request.dart';
import 'package:web_dex/services/orders_service/my_orders_service.dart';
import 'package:web_dex/shared/swap/atomic_swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';

import 'swap_exec_atomic_fakes.dart';
import 'swap_exec_fakes.dart';

/// Covers the atomic executor over the real DEX repository and order service,
/// with only the RPC layer scripted: what a lost or failed engine call turns
/// into by the time it reaches the swap screens.
void main() {
  late _Rpc rpc;
  late AtomicSwapExecutor executor;

  setUp(() {
    rpc = _Rpc();
    executor = AtomicSwapExecutor(
      dexRepository: DexRepository(rpc),
      orders: MyOrdersService(rpc),
      networks: () => execNetworks,
      resolveAsset: resolveTicker,
    );
  });

  test('an order the engine refused is a refusal with its words', () async {
    rpc.sellAnswer = {'error': 'Not enough ETH for the swap'};

    await expectLater(
      executor.start(atomicQuoteOf()),
      throwsA(
        isA<SwapStartRejectedException>().having(
          (e) => e.detail,
          'detail',
          'Not enough ETH for the swap',
        ),
      ),
    );
  });

  test('an order the engine placed is followed from matching', () {
    fakeAsync((async) {
      SwapExecutionHandle? handle;
      executor.start(atomicQuoteOf()).then((h) => handle = h);
      async.flushMicrotasks();

      expect(rpc.sells.single.orderType, SellBuyOrderType.fillOrKill);
      expect(handle!.id, 'a-1');
      expect(handle!.latest.stage, SwapProgressStage.matching);
    });
  });

  test(
    'a request whose answer was lost is unconfirmed, never refused',
    () async {
      rpc.sellError = TimeoutException('no answer from KDF');

      await expectLater(
        executor.start(atomicQuoteOf()),
        throwsA(isA<SwapStartUnconfirmedException>()),
      );
    },
  );

  test(
    'an engine that stops answering is not proof the order never matched',
    () {
      fakeAsync((async) {
        SwapExecutionHandle? handle;
        executor.start(atomicQuoteOf()).then((h) => handle = h);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 30));

        expect(handle!.latest.isTerminal, isFalse);
      });
    },
  );
}

/// The RPC layer, with KDF unreachable once the order is placed: status reads
/// fail as the real `Mm2Api` reports them — `{'error': 'something went wrong'}`
/// from `my_swap_status`, whose call's exception it swallows, and the call's
/// own exception from the strict `order_status` read. A `sell` whose call
/// threw throws too, as the strict entry point lets it through.
class _Rpc implements Mm2Api {
  final List<SellRequest> sells = [];
  Map<String, dynamic> sellAnswer = {
    'result': {'uuid': 'a-1'},
  };
  Object? sellError;

  @override
  Future<Map<String, dynamic>> sellOrThrow(SellRequest request) async {
    sells.add(request);
    final error = sellError;
    if (error != null) throw error;
    return sellAnswer;
  }

  @override
  Future<Map<String, dynamic>> getSwapStatus(MySwapStatusReq request) async => {
    'error': 'something went wrong',
  };

  @override
  Future<Map<String, dynamic>> orderStatusOrThrow(String uuid) async =>
      throw TimeoutException('no answer from KDF');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/bloc/dex_repository.dart';
import 'package:web_dex/mm2/mm2.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/mm2/mm2_api/rpc/sell/sell_request.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/services/orders_service/my_orders_service.dart';
import 'package:web_dex/shared/swap/atomic_swap_execution.dart';
import 'package:web_dex/shared/swap/atomic_swap_source.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

import 'swap_exec_atomic_fakes.dart';
import 'swap_exec_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers how an atomic start tells KDF refusing the order from a request
/// that got no answer, at every layer down to the RPC call: only a refusal
/// may be offered again, since a lost answer may hide a placed order.
void main() {
  group('the RPC layer', () {
    // Never initialised, so every call throws before reaching KDF, as a call
    // whose answer was lost does.
    late Mm2Api api;
    setUp(() => api = Mm2Api(mm2: MM2(), sdk: KomodoDefiSdk()));

    SellRequest request() => SellRequest(
      base: 'ETH',
      rel: 'USDC-ERC20',
      volume: Rational.one,
      price: Rational.fromInt(3000),
      orderType: SellBuyOrderType.fillOrKill,
    );

    test('the strict sell throws what the call threw, where the legacy one '
        'answers with it', () async {
      await expectLater(api.sellOrThrow(request()), throwsStateError);
      expect((await api.sell(request()))['error'], isStateError);
    });

    test('the strict order status read throws what the call threw', () async {
      await expectLater(api.orderStatusOrThrow('a-1'), throwsStateError);
    });
  });

  group('over the real DEX repository', () {
    late _SellRpc rpc;
    late AtomicSwapExecutor executor;

    setUp(() {
      rpc = _SellRpc();
      executor = AtomicSwapExecutor(
        dexRepository: DexRepository(rpc),
        orders: MyOrdersService(rpc),
        networks: () => execNetworks,
        resolveAsset: resolveTicker,
      );
    });

    Future<Object> startError([SwapQuote? quote]) async {
      try {
        await executor.start(quote ?? atomicQuoteOf());
      } on Object catch (error) {
        return error;
      }
      fail('the start should not have succeeded');
    }

    test('a call that threw is unconfirmed, keeping what it threw', () async {
      final cause = StateError('connection reset');
      rpc.error = cause;

      expect(
        await startError(),
        isA<SwapStartUnconfirmedException>().having(
          (e) => e.cause,
          'cause',
          same(cause),
        ),
      );
    });

    test('the SDK saying the request never reached KDF is unconfirmed, '
        'not a refusal', () async {
      rpc.answer = {
        'code': -1,
        'error': 'ConnectionError',
        'message': 'Remote KDF request failed',
      };

      expect(
        await startError(),
        isA<SwapStartUnconfirmedException>().having(
          (e) => e.cause,
          'cause',
          isA<TextError>().having(
            (e) => e.error,
            'error',
            'Remote KDF request failed',
          ),
        ),
      );
    });

    test('an answer the SDK could not read is unconfirmed', () async {
      rpc.answer = {'code': 200, 'error': 'InvalidKdfResponse'};

      expect(
        await startError(),
        isA<SwapStartUnconfirmedException>().having(
          (e) => e.cause,
          'cause',
          isA<TextError>().having(
            (e) => e.error,
            'error',
            'InvalidKdfResponse',
          ),
        ),
      );
    });

    test('KDF refusing with an HTTP error status is still a refusal', () async {
      // The SDK's HTTP transport keeps only the status of a legacy refusal.
      const httpError = '{"error":"HTTP Error","status":500}';
      rpc.answer = {
        'code': 500,
        'error': httpError,
        'message': 'Remote KDF returned HTTP 500',
      };

      expect(
        await startError(),
        isA<SwapStartRejectedException>().having(
          (e) => e.detail,
          'detail',
          httpError,
        ),
      );
    });

    test(
      'a wallet-only asset is refused before anything reaches KDF',
      () async {
        final custody = assetOf('USDT-TRC20');
        final quote = quoteOf(
          source: SwapLiquiditySource.atomic,
          from: custody,
          payload: AtomicSwapPlan(
            base: custody,
            rel: usdc,
            volume: d('10'),
            price: d('1'),
          ),
        );

        expect(
          await startError(quote),
          isA<SwapStartRejectedException>().having(
            (e) => e.detail,
            'detail',
            'Wallet-only assets cannot be submitted to the DEX.',
          ),
        );
        expect(rpc.sells, isEmpty);
      },
    );
  });
}

/// The RPC layer's strict `sell`: KDF's answer, or what the call threw.
class _SellRpc implements Mm2Api {
  final List<SellRequest> sells = [];
  Map<String, dynamic> answer = {};
  Object? error;

  @override
  Future<Map<String, dynamic>> sellOrThrow(SellRequest request) async {
    sells.add(request);
    final error = this.error;
    if (error != null) throw error;
    return answer;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

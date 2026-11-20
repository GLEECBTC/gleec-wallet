import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart'
    show RpcDispatchRejected;
import 'package:web_dex/services/wallet_access/wallet_operation_gate.dart';
import 'package:web_dex/shared/swap/atomic_swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

import 'swap_exec_atomic_fakes.dart';
import 'swap_exec_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the registry when an engine answers late: after a sign-out, or
/// after another screen already opened the same swap, and a start refused
/// locally before its request could leave.
void main() {
  group('an answer that lands after sign-out', () {
    late _SlowExecutor engine;
    late SwapExecutionRegistry registry;

    setUp(() {
      engine = _SlowExecutor();
      registry = testSwapRegistry(
        executors: [engine],
        inFlight: () async => const [],
      );
    });

    tearDown(() => registry.dispose());

    test('to a start stays unconfirmed with its known id, unfollowed and '
        'unannounced in the replacement session', () async {
      final started = <SwapExecutionSnapshot>[];
      final subscription = registry.started.listen(started.add);

      final starting = registry.start(quoteOf(), registry.beginSubmission());
      final unconfirmed = expectLater(
        starting,
        throwsA(
          isA<SwapStartUnconfirmedException>().having(
            (error) => error.executionId,
            'known execution id',
            'routed-1',
          ),
        ),
      );
      await registry.reset();
      engine.gate.complete();
      await unconfirmed;
      await pumpEventQueue();

      expect(registry.current, isEmpty);
      expect(started, isEmpty);
      expect(engine.handle!.closed, isTrue);
      await subscription.cancel();
    });

    test('to a re-attach ends the watch without following the swap', () async {
      final seen = <SwapExecutionSnapshot>[];
      var ended = false;
      registry.watch('r-1').listen(seen.add, onDone: () => ended = true);
      await pumpEventQueue();

      await registry.reset();
      engine.gate.complete();
      await pumpEventQueue();

      expect(ended, isTrue);
      expect(seen, isEmpty);
      expect(registry.current, isEmpty);
      expect(engine.handle!.closed, isTrue);
    });
  });

  group('a start refused before its request could leave', () {
    const locked = WalletOperationDenied(WalletOperationDenial.locked);
    late WalletOperationGate lock;

    SwapExecutionRegistry registryOf(SwapExecutor executor) {
      final registry = SwapExecutionRegistry(
        executors: [executor],
        inFlight: () async => const [],
        currentSession: () => testSwapAuth.currentSession,
        isSessionCurrent: testSwapAuth.isSessionContextCurrent,
        operationGate: lock,
      );
      addTearDown(registry.dispose);
      return registry;
    }

    final refused = throwsA(
      isA<SwapStartRejectedException>().having(
        (error) => error.reason,
        'reason',
        SwapStartRejection.notAvailable,
      ),
    );

    setUp(() {
      lock = WalletOperationGate()
        ..attachWallet(
          'wallet',
          sessionIdentity: Object(),
          allowOperations: true,
        );
    });

    test('by the app lock is rejected without asking the executor, and '
        'unlocking does not revive it', () async {
      final engine = FakeExecutor(SwapLiquiditySource.routed);
      final registry = registryOf(engine);
      final submission = registry.beginSubmission();
      lock.block();

      await expectLater(registry.start(quoteOf(), submission), refused);
      expect(registry.beginSubmission, throwsA(locked));
      lock.allow(walletEntryId: 'wallet');
      await expectLater(registry.start(quoteOf(), submission), refused);

      expect(engine.started, isEmpty);
    });

    test('by the app lock as the executor asks to dispatch is '
        'rejected', () async {
      final engine = _PreparingExecutor();
      final registry = registryOf(engine);
      final rejection = expectLater(
        registry.start(quoteOf(), registry.beginSubmission()),
        refused,
      );

      lock.block();
      engine.ready.complete();
      await rejection;

      expect(engine.sent, isFalse);
    });

    test('by an executor reading the lock before it dispatches is '
        'rejected', () async {
      final registry = registryOf(_RefusingExecutor(locked, dispatches: false));

      await expectLater(
        registry.start(quoteOf(), registry.beginSubmission()),
        refused,
      );
    });

    test('by the transport before an executor asked to dispatch is '
        'rejected', () async {
      final registry = registryOf(
        _RefusingExecutor(const RpcDispatchRejected(locked), dispatches: false),
      );

      await expectLater(
        registry.start(quoteOf(), registry.beginSubmission()),
        refused,
      );
    });

    for (final Object error in [locked, const RpcDispatchRejected(locked)]) {
      test('is never read into ${error.runtimeType} once dispatch began, '
          'which only the executor can place', () async {
        final registry = registryOf(_RefusingExecutor(error, dispatches: true));

        await expectLater(
          registry.start(quoteOf(), registry.beginSubmission()),
          throwsA(same(error)),
        );
      });
    }
  });

  test('two watches handed the same handle both follow it, and it stays '
      'open', () async {
    final executor = FakeExecutor(SwapLiquiditySource.routed);
    final handle = executor.resumable['r-1'] = FakeHandle(
      snapshotOf(id: 'r-1'),
    );
    final registry = testSwapRegistry(
      executors: [executor],
      inFlight: () async => const [],
    );
    final first = <SwapExecutionSnapshot>[];
    final second = <SwapExecutionSnapshot>[];
    registry.watch('r-1').listen(first.add);
    registry.watch('r-1').listen(second.add);
    await pumpEventQueue();

    handle.push(snapshotOf(id: 'r-1', outcome: completed()));
    await pumpEventQueue();

    expect(handle.closed, isFalse);
    expect(first.last.isSuccess, isTrue);
    expect(second.last.isSuccess, isTrue);
    await registry.dispose();
  });

  test('an atomic swap opened after it finished is not announced as newly '
      'finished', () async {
    final dex = FakeDex()
      ..swaps['a-9'] = atomicSwapOf('a-9', [
        'Started',
        'Negotiated',
        'TakerFeeSent',
        'MakerPaymentReceived',
        'TakerPaymentSent',
        'MakerPaymentSpent',
        'Finished',
      ]);
    final registry = testSwapRegistry(
      executors: [
        AtomicSwapExecutor(
          auth: testSwapAuth,
          dexRepository: dex,
          orders: FakeOrders(),
          networks: () => execNetworks,
          resolveAsset: resolveTicker,
        ),
      ],
      inFlight: () async => const [],
    );
    final notices = <SwapExecutionNotice>[];
    final subscription = registry.notices.listen(notices.add);

    final seen = await registry
        .watch('a-9', source: SwapLiquiditySource.atomic)
        .toList();
    await pumpEventQueue();

    expect(seen.map((s) => s.isSuccess), [isTrue]);
    expect(registry.snapshotOf('a-9')!.isSuccess, isTrue);
    expect(notices, isEmpty);
    await subscription.cancel();
    await registry.dispose();
  });
}

/// Asks to dispatch only once [ready] completes, then sends.
class _PreparingExecutor implements SwapExecutor {
  final Completer<void> ready = Completer<void>();
  bool sent = false;

  @override
  SwapLiquiditySource get source => SwapLiquiditySource.routed;

  @override
  Future<SwapExecutionHandle> start(
    SwapQuote quote, {
    required SwapExecutionAuthorization authorization,
  }) async {
    await ready.future;
    authorization.beforeDispatch();
    sent = true;
    return FakeHandle(snapshotOf(id: 'routed-1'));
  }

  @override
  Future<SwapExecutionHandle?> resume(String id) async => null;
}

/// Throws [error], before or after the registry's dispatch boundary.
class _RefusingExecutor implements SwapExecutor {
  _RefusingExecutor(this.error, {required this.dispatches});

  final Object error;
  final bool dispatches;

  @override
  SwapLiquiditySource get source => SwapLiquiditySource.routed;

  @override
  Future<SwapExecutionHandle> start(
    SwapQuote quote, {
    required SwapExecutionAuthorization authorization,
  }) async {
    if (dispatches) authorization.beforeDispatch();
    throw error;
  }

  @override
  Future<SwapExecutionHandle?> resume(String id) async => null;
}

/// Opens a handle only once [gate] completes, as an engine slow to answer.
class _SlowExecutor implements SwapExecutor {
  final Completer<void> gate = Completer<void>();
  FakeHandle? handle;

  @override
  SwapLiquiditySource get source => SwapLiquiditySource.routed;

  @override
  Future<SwapExecutionHandle> start(
    SwapQuote quote, {
    required SwapExecutionAuthorization authorization,
  }) {
    authorization.beforeDispatch();
    return _open('routed-1');
  }

  @override
  Future<SwapExecutionHandle?> resume(String id) => _open(id);

  Future<FakeHandle> _open(String id) async {
    await gate.future;
    return handle = FakeHandle(snapshotOf(id: id));
  }
}

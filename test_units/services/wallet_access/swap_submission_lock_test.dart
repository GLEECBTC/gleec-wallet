import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/services/wallet_access/wallet_operation_gate.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

import '../../tests/swap/swap_test_fixtures.dart';

class _DelayedExecutor extends FakeExecutor {
  _DelayedExecutor() : super(SwapLiquiditySource.routed);
  final preparing = Completer<void>();
  final ready = Completer<void>();

  @override
  Future<SwapExecutionHandle> start(
    SwapQuote quote, {
    required SwapExecutionAuthorization authorization,
  }) async {
    preparing.complete();
    await ready.future;
    return super.start(quote, authorization: authorization);
  }
}

void main() {
  group('Swap submission lock boundary', () {
    late WalletOperationGate gate;
    late TestSwapAuth auth;
    late SwapExecutionRegistry registry;

    SwapExecutionRegistry create(FakeExecutor executor) =>
        SwapExecutionRegistry(
          executors: [executor],
          inFlight: () async => [],
          currentSession: () => auth.currentSession,
          isSessionCurrent: auth.isSessionContextCurrent,
          operationGate: gate,
        );

    setUp(() {
      gate = WalletOperationGate()
        ..attachWallet('entry', allowOperations: true);
      auth = TestSwapAuth();
    });
    tearDown(() => registry.dispose());

    test('lock and unlock invalidate an earlier confirmed swap', () async {
      final executor = FakeExecutor(SwapLiquiditySource.routed);
      registry = create(executor);
      final submission = registry.beginSubmission();
      gate.block();
      gate.allow(walletEntryId: 'entry');
      await expectLater(
        registry.start(quoteOf(), submission),
        throwsA(isA<WalletOperationDenied>()),
      );
      expect(executor.started, isEmpty);
      expect(registry.current, isEmpty);
    });

    test('locking during preparation prevents its later dispatch', () async {
      final executor = _DelayedExecutor();
      registry = create(executor);
      final operation = registry.start(quoteOf(), registry.beginSubmission());
      final rejected = expectLater(
        operation,
        throwsA(isA<WalletOperationDenied>()),
      );
      await executor.preparing.future;
      gate.block();
      gate.allow(walletEntryId: 'entry');
      executor.ready.complete();
      await rejected;
      expect(executor.started, isEmpty);
    });

    test(
      'an accepted swap keeps tracking after the application locks',
      () async {
        final executor = FakeExecutor(SwapLiquiditySource.routed);
        registry = create(executor);
        final started = await registry.start(
          quoteOf(),
          registry.beginSubmission(),
        );
        gate.block();
        executor.lastStarted!.push(
          snapshotOf(id: started.id, outcome: completed()),
        );
        await pumpEventQueue();
        expect(executor.started, hasLength(1));
        expect(
          registry.snapshotOf(started.id)!.outcome!.kind,
          SwapOutcomeKind.completed,
        );
      },
    );
  });
}

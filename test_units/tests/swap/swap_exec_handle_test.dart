import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';

import 'swap_test_fixtures.dart';

/// Covers the handle both executors hand out: a replaying, de-duplicating
/// view over the engine's snapshots that can be let go of without stopping
/// the swap.
void main() {
  late StreamController<SwapExecutionSnapshot> engine;
  late StreamSwapExecutionHandle handle;
  late int cancels;
  late int closes;

  final running = snapshotOf(id: 'h-1', stage: SwapProgressStage.preparing);
  final sending = snapshotOf(id: 'h-1', stage: SwapProgressStage.sending);
  final done = snapshotOf(id: 'h-1', outcome: completed());

  setUp(() {
    engine = StreamController<SwapExecutionSnapshot>.broadcast();
    cancels = 0;
    closes = 0;
    handle = StreamSwapExecutionHandle(
      initial: running,
      source: engine.stream,
      cancel: () async => cancels++,
      onClose: () async => closes++,
    );
  });

  test('is identified by its latest snapshot', () {
    expect(handle.id, 'h-1');
    expect(handle.latest, running);
  });

  test('replays the latest snapshot to each listener, then follows', () async {
    final early = <SwapExecutionSnapshot>[];
    handle.updates.listen(early.add);
    engine.add(sending);
    await pumpEventQueue();
    final late = <SwapExecutionSnapshot>[];
    handle.updates.listen(late.add);
    engine.add(done);
    await pumpEventQueue();

    expect(early, [running, sending, done]);
    expect(late, [sending, done]);
    expect(handle.latest, done);
  });

  test('drops a snapshot equal to the latest', () async {
    final seen = <SwapExecutionSnapshot>[];
    handle.updates.listen(seen.add);
    engine
      ..add(snapshotOf(id: 'h-1', stage: SwapProgressStage.preparing))
      ..add(sending)
      ..add(snapshotOf(id: 'h-1', stage: SwapProgressStage.sending));
    await pumpEventQueue();

    expect(seen, [running, sending]);
  });

  test('passes the engine\'s errors on and keeps following', () async {
    final errors = <Object>[];
    final seen = <SwapExecutionSnapshot>[];
    handle.updates.listen(seen.add, onError: errors.add);
    engine
      ..addError(StateError('status read failed'))
      ..add(sending);
    await pumpEventQueue();

    expect(errors.single, isStateError);
    expect(seen.last, sending);
  });

  test(
    'ends with the engine, and a late listener gets the last word',
    () async {
      var ended = false;
      handle.updates.listen(null, onDone: () => ended = true);
      engine.add(done);
      await engine.close();
      await pumpEventQueue();

      expect(ended, isTrue);
      expect(await handle.updates.toList(), [done]);
    },
  );

  test('one listener leaving does not stop the others', () async {
    final leaving = <SwapExecutionSnapshot>[];
    final staying = <SwapExecutionSnapshot>[];
    final subscription = handle.updates.listen(leaving.add);
    handle.updates.listen(staying.add);
    await pumpEventQueue();

    await subscription.cancel();
    engine.add(sending);
    await pumpEventQueue();

    expect(leaving, [running]);
    expect(staying, [running, sending]);
    expect(engine.hasListener, isTrue);
  });

  test('cancel asks the engine', () async {
    await handle.cancel();
    expect(cancels, 1);
  });

  test('closing lets go of the engine and ends every listener', () async {
    var ended = false;
    handle.updates.listen(null, onDone: () => ended = true);

    await handle.close();
    engine.add(sending);
    await pumpEventQueue();

    expect(closes, 1);
    expect(ended, isTrue);
    expect(engine.hasListener, isFalse);
    expect(handle.latest, running);
    expect(cancels, 0);
  });

  test('closing twice is harmless, with or without a close hook', () async {
    final bare = StreamSwapExecutionHandle(
      initial: running,
      source: const Stream<SwapExecutionSnapshot>.empty(),
      cancel: () async {},
    );
    await bare.close();
    await bare.close();
    await handle.close();
    await handle.close();

    expect(await bare.updates.toList(), [running]);
    expect(closes, 2);
  });

  group('exceptions explain themselves', () {
    test('a refused start names its reason and detail', () {
      expect(
        const SwapStartRejectedException(
          SwapStartRejection.notAvailable,
          detail: 'PairNotSupported: no pair',
        ).toString(),
        'SwapStartRejectedException(notAvailable): PairNotSupported: no pair',
      );
    });

    test('a lost start answer names its cause', () {
      expect(
        const SwapStartUnconfirmedException('timeout').toString(),
        'Could not confirm whether the swap started: timeout',
      );
    });

    test('a refused cancel names its reason', () {
      expect(
        const SwapCancelRefusedException(
          SwapCancelRefusal.alreadySent,
        ).toString(),
        'SwapCancelRefusedException(alreadySent)',
      );
    });

    test('a lost cancel answer names its cause', () {
      expect(
        const SwapCancelUnconfirmedException('reset').toString(),
        'Could not confirm cancelling the swap: reset',
      );
    });
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/mm2/mm2.dart';

class _InitializationAuth extends Fake implements KomodoDefiLocalAuth {
  _InitializationAuth({this.failure});

  final Object? failure;
  int getUsersCalls = 0;

  @override
  Future<List<KdfUser>> getUsers() async {
    getUsersCalls++;
    if (failure case final Object error) throw error;
    return const [];
  }
}

class _InitializationSdk extends Fake implements KomodoDefiSdk {
  _InitializationSdk(this.ready, {Object? usersFailure})
    : auth = _InitializationAuth(failure: usersFailure);

  final Future<void> ready;
  int initializeCalls = 0;

  @override
  final _InitializationAuth auth;

  @override
  Future<void> initialize() {
    initializeCalls++;
    return ready;
  }
}

void main() {
  group('MM2 initialization boundaries', () {
    test(
      'concurrent and repeated calls retain an initialization failure',
      () async {
        final ready = Completer<void>();
        final sdk = _InitializationSdk(ready.future);
        final engine = MM2(sdk: sdk);
        final failure = StateError('Candidate verification failed');

        final first = engine.initialize();
        final concurrent = engine.initialize();
        expect(concurrent, same(first));
        final firstError = expectLater(first, throwsA(same(failure)));
        final concurrentError = expectLater(concurrent, throwsA(same(failure)));
        // Initialization reaches the injected SDK after the catalog check.
        await Future<void>.delayed(Duration.zero);
        ready.completeError(failure);
        await Future.wait([firstError, concurrentError]);

        final repeated = engine.initialize();
        expect(repeated, same(first));
        await expectLater(repeated, throwsA(same(failure)));
        expect(sdk.initializeCalls, 1);
        expect(sdk.auth.getUsersCalls, 0);
      },
    );

    test('failure after SDK setup never exposes the initialized SDK', () async {
      final failure = StateError('Engine startup failed');
      final sdk = _InitializationSdk(Future.value(), usersFailure: failure);
      final engine = MM2(sdk: sdk);
      await expectLater(engine.initialize(), throwsA(same(failure)));
      await expectLater(engine.initialize(), throwsA(same(failure)));
      expect(sdk.initializeCalls, 1);
      expect(sdk.auth.getUsersCalls, 1);
    });

    test('successful callers share one fully initialized SDK', () async {
      final ready = Completer<void>();
      final sdk = _InitializationSdk(ready.future);
      final engine = MM2(sdk: sdk);
      final first = engine.initialize();
      final concurrent = engine.initialize();
      expect(concurrent, same(first));
      ready.complete();
      expect(await first, same(sdk));
      expect(await concurrent, same(sdk));
      expect(engine.initialize(), same(first));
      expect(await engine.initialize(), same(sdk));
      expect(sdk.initializeCalls, 1);
      expect(sdk.auth.getUsersCalls, 1);
    });
  });
}

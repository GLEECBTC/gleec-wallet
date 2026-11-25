// The analyzer does not treat test_units as tests, so MM2.createSdk's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/app_config/solana_build_config.dart';
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

/// Answers the legacy `version` request the engine gate sends.
class _VersionClient extends Fake implements ApiClient {
  _VersionClient(this.version);

  final String version;
  final methods = <Object?>[];

  @override
  Future<JsonMap> executeRpc(JsonMap request) async {
    methods.add(request['method']);
    return {'result': version, 'datetime': '2026-11-25T00:00:00+00:00'};
  }
}

class _InitializationSdk extends Fake implements KomodoDefiSdk {
  _InitializationSdk(this.ready, {Object? usersFailure, String? engineVersion})
    : auth = _InitializationAuth(failure: usersFailure),
      client = _VersionClient(engineVersion ?? _productionVersion);

  final Future<void> ready;
  int initializeCalls = 0;

  @override
  final _InitializationAuth auth;

  @override
  final _VersionClient client;

  @override
  Future<void> initialize() {
    initializeCalls++;
    return ready;
  }
}

class _ConfigOnlySdk extends Fake implements KomodoDefiSdk {}

final _productionVersion =
    '3.2.0-beta_${SolanaBuildConfig.productionEngineCommit.substring(0, 7)}';

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
      expect(sdk.client.methods, ['version']);
    });
  });

  group('MM2 Solana engine gate', () {
    test('a production build refuses an engine it does not pin', () async {
      final sdk = _InitializationSdk(
        Future.value(),
        engineVersion: '3.2.0-beta_46769c4',
      );
      final engine = MM2(sdk: sdk, solana: const SolanaBuildConfig());
      await expectLater(engine.initialize(), throwsStateError);
      // The refusal sticks: no later caller gets the SDK.
      await expectLater(engine.initialize(), throwsStateError);
      expect(sdk.client.methods, ['version']);
    });

    test('a build without Solana never checks the engine', () async {
      final sdk = _InitializationSdk(
        Future.value(),
        engineVersion: '3.2.0-beta_46769c4',
      );
      final engine = MM2(
        sdk: sdk,
        solana: const SolanaBuildConfig(enabled: false),
      );
      expect(await engine.initialize(), same(sdk));
      expect(sdk.client.methods, isEmpty);
    });

    test('a production build is refused before the SDK exists', () {
      expect(
        () => MM2(
          sdk: _ConfigOnlySdk(),
          solana: const SolanaBuildConfig(devnetTradingEnabled: true),
        ),
        throwsStateError,
      );
    });
  });

  group('MM2 Solana SDK configuration', () {
    late KomodoDefiSdkConfig? passed;

    setUp(() {
      final createSdk = MM2.createSdk;
      addTearDown(() => MM2.createSdk = createSdk);
      passed = null;
      MM2.createSdk = ({config, onLog}) {
        passed = config;
        return _ConfigOnlySdk();
      };
    });

    test('production keeps the updatable catalog and default storage', () {
      MM2(solana: const SolanaBuildConfig());
      expect(
        passed?.solanaCapabilities,
        const SolanaCapabilities(enabled: true),
      );
      expect(passed?.assetsAutoUpdate, isTrue);
      expect(passed?.assetsStorageNamespace, isNull);
    });

    test('a disabled build exposes no Solana capability', () {
      MM2(solana: const SolanaBuildConfig(enabled: false));
      expect(passed?.solanaCapabilities, const SolanaCapabilities());
      expect(passed?.assetsAutoUpdate, isTrue);
      expect(passed?.assetsStorageNamespace, isNull);
    });

    test('a candidate freezes and isolates its catalog snapshot', () {
      const digest =
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
      MM2(
        solana: const SolanaBuildConfig(
          devnetTradingEnabled: true,
          engineCommit: 'b1ff8f05c880d6f118124cac9ef615aa9d91bb39',
          coinsCommit: 'ca20611537fe84f9398d1a63f3d27a4386fb161d',
          catalogSha256: digest,
          storageNamespace: 'solana-preview-0123456789ab',
          previewOrigin: 'http://localhost:18471',
        ),
      );
      expect(
        passed?.solanaCapabilities,
        const SolanaCapabilities(enabled: true, devnetTradingEnabled: true),
      );
      expect(passed?.assetsAutoUpdate, isFalse);
      expect(passed?.assetsStorageNamespace, 'solana-preview-0123456789ab');
    });
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/services/security/private_key_export_service.dart';
import 'package:web_dex/services/wallet_access/wallet_operation_gate.dart';

import 'private_key_export_test_support.dart';

void main() => testPrivateKeyExportService();

void testPrivateKeyExportService() {
  group('SDK private key export password boundary', () {
    late _Auth auth;
    late _Security security;
    late SdkPrivateKeyExportService service;
    late WalletOperationGate gate;
    setUp(() {
      auth = _Auth();
      security = _Security(auth);
      gate = WalletOperationGate();
      service = SdkPrivateKeyExportService(
        _Sdk(auth, security),
        operationGate: gate,
      );
    });
    tearDown(() => auth.changes.close());

    test(
      'installed app lock refuses an export without a captured permit',
      () async {
        gate.attachWallet('entry', allowOperations: true);
        final access = await service.begin();
        await expectLater(
          service.authenticateAndExport(
            access,
            SensitiveString(exportPasswordSentinel),
          ),
          throwsA(isA<PrivateKeyExportException>()),
        );
        expect(auth.calls, 0);
        expect(security.exports, 0);
      },
    );

    for (final interruption in ['lock', 'switch', 'background and resume']) {
      test('$interruption revokes a queued private-key export', () async {
        gate.attachWallet('entry', allowOperations: true);
        final permit = gate.capture();
        final access = await service.begin();
        if (interruption == 'switch') {
          gate.attachWallet('other', allowOperations: true);
        } else {
          gate.block();
          if (interruption == 'background and resume') {
            gate.allow(walletEntryId: 'entry');
          }
        }
        await expectLater(
          service.authenticateAndExport(
            access,
            SensitiveString(exportPasswordSentinel),
            ensureAuthorized: permit.ensureCurrent,
          ),
          throwsA(isA<PrivateKeyExportException>()),
        );
        expect(auth.calls, 0);
        expect(security.exports, 0);
      });
    }

    for (final method in ['get_mnemonic', 'get_private_keys']) {
      test('lock before $method transport prevents its dispatch', () async {
        gate.attachWallet('entry', allowOperations: true);
        final permit = gate.capture();
        final access = await service.begin();
        final waiting = Completer<void>();
        final release = Completer<void>();
        Future<void> beforeDispatch() async {
          waiting.complete();
          await release.future;
        }

        if (method == 'get_mnemonic') {
          auth.beforeDispatch = beforeDispatch;
        } else {
          security.beforeDispatch = beforeDispatch;
        }
        final rejected = expectLater(
          service.authenticateAndExport(
            access,
            SensitiveString(exportPasswordSentinel),
            ensureAuthorized: permit.ensureCurrent,
          ),
          throwsA(isA<PrivateKeyExportException>()),
        );
        await waiting.future;
        gate.block();
        release.complete();
        await rejected;
        expect(auth.dispatches, method == 'get_mnemonic' ? 0 : 1);
        expect(security.exports, 0);
      });
    }

    test(
      'returned private keys retain their original app-lock permit',
      () async {
        gate.attachWallet('entry', allowOperations: true);
        final permit = gate.capture();
        final access = await service.begin();
        await service.authenticateAndExport(
          access,
          SensitiveString(exportPasswordSentinel),
          ensureAuthorized: permit.ensureCurrent,
        );
        gate.block();
        gate.allow(walletEntryId: 'entry');
        expect(
          () => service.ensureCurrentSync(access),
          throwsA(isA<PrivateKeyExportException>()),
        );
      },
    );

    test('new authorization cannot adopt an older pending export', () async {
      final access = await service.begin();
      final firstReply = Completer<Mnemonic>();
      auth.pending = firstReply;
      final rejected = expectLater(
        service.authenticateAndExport(
          access,
          SensitiveString(exportPasswordSentinel),
        ),
        throwsA(isA<PrivateKeyExportException>()),
      );
      await auth.started.future;
      await Future<void>.delayed(Duration.zero);
      auth.pending = null;
      final replacement = await service.authenticateAndExport(
        access,
        SensitiveString(exportPasswordSentinel),
      );
      expect(replacement.hasKeys, isTrue);
      firstReply.complete(Mnemonic.plaintext(_mnemonicSentinel));
      await rejected;
      expect(security.exports, 1);
    });

    test('wrong password never starts key extraction', () async {
      final access = await service.begin();
      auth.error = AuthException(
        'synthetic secret error detail',
        type: AuthExceptionType.incorrectPassword,
      );
      await expectLater(
        service.authenticateAndExport(
          access,
          SensitiveString(exportPasswordSentinel),
        ),
        throwsA(
          isA<PrivateKeyExportException>().having(
            (e) => e.reason,
            'reason',
            PrivateKeyExportError.incorrectPassword,
          ),
        ),
      );
      expect(auth.calls, 1);
      expect(security.exports, 0);
    });

    test(
      'non-password failures are not described as incorrect passwords',
      () async {
        final access = await service.begin();
        auth.error = AuthException(
          'synthetic connection detail',
          type: AuthExceptionType.apiConnectionError,
        );
        await expectLater(
          service.authenticateAndExport(
            access,
            SensitiveString(exportPasswordSentinel),
          ),
          throwsA(
            isA<PrivateKeyExportException>().having(
              (e) => e.reason,
              'reason',
              PrivateKeyExportError.unavailable,
            ),
          ),
        );
        expect(security.exports, 0);
      },
    );

    test(
      'mnemonic is used only inside adapter and is absent from its result',
      () async {
        final access = await service.begin();
        final result = await service.authenticateAndExport(
          access,
          SensitiveString(exportPasswordSentinel),
        );
        expect(result.hasKeys, isTrue);
        expect(
          result.outcomes
              .where((outcome) => outcome.isSuccess)
              .map((outcome) => outcome.assetId.id),
          ['BTC', 'ETH'],
        );
        for (final outcome in result.outcomes.where(
          (outcome) =>
              outcome.assetId.subClass == CoinSubClass.trx ||
              outcome.assetId.subClass == CoinSubClass.trc20,
        )) {
          expect(outcome.failure, PrivateKeyExportFailure.unsupportedProtocol);
          expect(outcome.keys, isEmpty);
        }
        expect(security.exports, 1);
        expect(result.toJson().toString(), isNot(contains(_mnemonicSentinel)));
        expect('$result $access', isNot(contains(_mnemonicSentinel)));
        expect('$result $access', isNot(contains(exportPasswordSentinel)));
      },
    );

    test(
      'same-wallet generation change during password verification prevents extraction',
      () async {
        final access = await service.begin();
        auth.pending = Completer<Mnemonic>();
        final verificationStarted = auth.started.future;
        final result = service.authenticateAndExport(
          access,
          SensitiveString(exportPasswordSentinel),
        );
        await verificationStarted;
        auth.invalidate();
        auth.pending!.complete(Mnemonic.plaintext(_mnemonicSentinel));
        await expectLater(
          result,
          throwsA(
            isA<PrivateKeyExportException>().having(
              (e) => e.reason,
              'reason',
              PrivateKeyExportError.sessionChanged,
            ),
          ),
        );
        expect(security.exports, 0);
      },
    );

    test('session change after extraction rejects the returned keys', () async {
      final access = await service.begin();
      security.pending = Completer<PrivateKeyExportResult>();
      final result = service.authenticateAndExport(
        access,
        SensitiveString(exportPasswordSentinel),
      );
      await security.started.future;
      auth.invalidate();
      security.pending!.complete(exportTestResult());
      await expectLater(
        result,
        throwsA(
          isA<PrivateKeyExportException>().having(
            (e) => e.reason,
            'reason',
            PrivateKeyExportError.sessionChanged,
          ),
        ),
      );
    });

    test(
      'source epoch signal is exposed before any completed logout state',
      () async {
        final received = <void>[];
        final subscription = service.sessionChanges.listen(received.add);
        final access = await service.begin();
        auth.invalidate();
        expect(received, hasLength(1));
        expect(
          () => service.ensureCurrentSync(access),
          throwsA(isA<PrivateKeyExportException>()),
        );
        await subscription.cancel();
      },
    );
  });
}

const _mnemonicSentinel = 'synthetic mnemonic never leaves the adapter';

class _Sdk extends Fake implements KomodoDefiSdk {
  _Sdk(this.auth, this.security);
  @override
  final KomodoDefiLocalAuth auth;
  @override
  final SecurityManager security;
}

class _Auth extends Fake implements KomodoDefiLocalAuth {
  final changes = StreamController<int>.broadcast(sync: true);
  final started = Completer<void>();
  int generation = 1;
  int calls = 0;
  int dispatches = 0;
  Future<void> Function()? beforeDispatch;
  Object? error;
  Completer<Mnemonic>? pending;

  @override
  Stream<int> get authGenerationChanges => changes.stream;

  void invalidate() {
    generation++;
    changes.add(generation);
  }

  @override
  Future<Mnemonic> getMnemonicPlainText(String walletPassword) async {
    calls++;
    if (!started.isCompleted) started.complete();
    await beforeDispatch?.call();
    RpcDispatchGuard.ensureCurrent('get_mnemonic');
    dispatches++;
    if (error case final error?) throw error;
    return pending == null
        ? Mnemonic.plaintext(_mnemonicSentinel)
        : await pending!.future;
  }
}

class _Security extends Fake implements SecurityManager {
  _Security(this.auth);
  final _Auth auth;
  final started = Completer<void>();
  int exports = 0;
  Future<void> Function()? beforeDispatch;
  Completer<PrivateKeyExportResult>? pending;

  @override
  Future<PrivateKeyExportSession> captureExportSession() async =>
      _Session(auth.generation);

  @override
  void ensureExportSessionCurrentSync(PrivateKeyExportSession session) {
    if (auth.generation != session.generation) {
      throw const PrivateKeyExportSessionChangedException();
    }
  }

  @override
  Future<void> ensureExportSessionCurrent(
    PrivateKeyExportSession session,
  ) async {
    ensureExportSessionCurrentSync(session);
  }

  @override
  Future<PrivateKeyExportResult> exportPrivateKeys({
    PrivateKeyExportRequest request = const PrivateKeyExportRequest(),
    PrivateKeyExportSession? session,
  }) async {
    await beforeDispatch?.call();
    RpcDispatchGuard.ensureCurrent('get_private_keys');
    exports++;
    if (!started.isCompleted) started.complete();
    return pending == null ? exportTestResult() : await pending!.future;
  }
}

class _Session extends Fake implements PrivateKeyExportSession {
  _Session(this.generation);
  @override
  final int generation;
  @override
  WalletId get walletId => const WalletId(
    name: 'Synthetic wallet',
    pubkeyHash: 'synthetic-hash',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
  );
}

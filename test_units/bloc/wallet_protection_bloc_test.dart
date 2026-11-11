import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/wallet_protection/wallet_protection_bloc.dart';
import 'package:web_dex/services/wallet_access/unlock_coordinator.dart';
import 'package:web_dex/services/wallet_access/wallet_operation_gate.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';

final _id = WalletId.withPubkeyHash(
  'Gleec Wallet',
  const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
  'setup-fixture',
);

class _Access extends Fake implements WalletAccessService {
  bool managerPending = false;
  @override
  bool get isPasswordManagerPending => managerPending;
  bool supported = true;
  String entry = 'setup-entry';
  int generation = 0;
  int capabilityReads = 0;
  bool protected = false;
  WalletAccessFailure? failure;
  Completer<void>? pending;
  Completer<void>? pendingStatus;
  final requests = <WalletId>[];
  @override
  final unlockCoordinator = WalletUnlockCoordinator(
    operationGate: WalletOperationGate(),
  );
  final activity = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get changes => activity.stream;
  @override
  Future<WalletAccessStatus> status({WalletId? walletId}) async {
    expect(walletId, _id);
    await pendingStatus?.future;
    return WalletAccessStatus(
      entryId: entry,
      protection: protected
          ? CredentialProtection.passkey
          : CredentialProtection.browserLocal,
      hasManagedCredential: true,
      requiresAuthentication: protected,
      generatedPassword: true,
    );
  }

  @override
  void Function() captureSensitiveOperation(WalletId walletId) {
    final captured = generation;
    return () {
      if (captured != generation) {
        throw const WalletAccessException(WalletAccessFailure.staleOperation);
      }
    };
  }

  @override
  Future<CredentialCapabilities> capabilities() async {
    capabilityReads++;
    return CredentialCapabilities(
      available: true,
      protection: CredentialProtection.browserLocal,
      passkeyCandidate: supported,
    );
  }

  @override
  Future<void> enrollPasskey({
    required WalletId walletId,
    String? password,
  }) async {
    requests.add(walletId);
    await pending?.future;
    if (failure != null) throw WalletAccessException(failure!);
    protected = true;
  }
}

Future<WalletProtectionBloc> _ready(_Access access) async {
  final bloc = WalletProtectionBloc(access: access, walletId: _id);
  addTearDown(() async {
    await bloc.close();
    await access.activity.close();
    await access.unlockCoordinator.dispose();
  });
  await bloc.stream
      .firstWhere((state) => !state.loading)
      .timeout(const Duration(seconds: 2));
  return bloc;
}

void main() {
  group('Wallet protection presentation boundary', () {
    test(
      'pending provider save blocks setup until completion without starting a ceremony',
      () async {
        final access = _Access()..managerPending = true;
        final bloc = await _ready(access);
        expect(bloc.state.waitingForPasswordManager, isTrue);
        bloc.add(
          const WalletProtectionRequested(WalletProtectionAction.passkey),
        );
        await Future<void>.delayed(Duration.zero);
        expect(access.requests, isEmpty);
        final ready = bloc.stream.firstWhere(
          (state) => !state.waitingForPasswordManager,
        );
        access.managerPending = false;
        access.activity.add(null);
        await ready.timeout(const Duration(seconds: 2));
        expect(access.requests, isEmpty);
        final completed = bloc.stream.firstWhere(
          (state) => state.completed != null,
        );
        bloc.add(
          const WalletProtectionRequested(WalletProtectionAction.passkey),
        );
        await completed.timeout(const Duration(seconds: 2));
        expect(access.requests, [_id]);
      },
    );
    test(
      'provider activity disables setup before a slow metadata refresh completes',
      () async {
        final access = _Access();
        final bloc = await _ready(access);
        final status = Completer<void>();
        access.pendingStatus = status;
        access.managerPending = true;
        final waiting = bloc.stream.firstWhere(
          (state) => state.waitingForPasswordManager,
        );
        access.activity.add(null);
        await waiting.timeout(const Duration(seconds: 2));
        expect(access.requests, isEmpty);
        access.pendingStatus = null;
        access.managerPending = false;
        final ready = bloc.stream.firstWhere(
          (state) => !state.waitingForPasswordManager,
        );
        access.activity.add(null);
        await ready.timeout(const Duration(seconds: 2));
        status.complete();
        expect(access.requests, isEmpty);
      },
    );

    test('loading and refresh never start an authenticator ceremony', () async {
      final access = _Access();
      final bloc = await _ready(access);
      expect(bloc.state.canCreatePasskey, isTrue);
      bloc.add(const WalletProtectionRefreshed());
      await Future<void>.delayed(Duration.zero);
      expect(access.requests, isEmpty);
      expect(bloc.state.status!.requiresAuthentication, isFalse);
    });

    test(
      'return from an owned system prompt only refreshes status, without another ceremony',
      () async {
        final access = _Access();
        final bloc = await _ready(access);
        final before = access.capabilityReads;
        await access.unlockCoordinator.runSystemPrompt(() async {});
        await Future<void>.delayed(Duration.zero);
        expect(access.capabilityReads, greaterThan(before));
        expect(access.requests, isEmpty);
        expect(bloc.state.loading, isFalse);
      },
    );

    test(
      'duplicate clicks create one wallet-bound operation and publish confirmed state',
      () async {
        final access = _Access()..pending = Completer<void>();
        final bloc = await _ready(access);
        final finished = bloc.stream.firstWhere(
          (state) => state.completed != null,
        );
        bloc.add(
          const WalletProtectionRequested(WalletProtectionAction.passkey),
        );
        bloc.add(
          const WalletProtectionRequested(WalletProtectionAction.passkey),
        );
        await Future<void>.delayed(Duration.zero);
        expect(access.requests, [_id]);
        expect(bloc.state.busy, isTrue);
        expect(bloc.state.status!.requiresAuthentication, isFalse);
        access.pending!.complete();
        final state = await finished.timeout(const Duration(seconds: 2));
        expect(state.status!.protection, CredentialProtection.passkey);
        expect(state.status!.requiresAuthentication, isTrue);
        expect(access.requests, [_id]);
      },
    );

    for (final failure in [
      WalletAccessFailure.canceled,
      WalletAccessFailure.prfUnavailable,
      WalletAccessFailure.staleOperation,
    ]) {
      test('$failure preserves access with no automatic retry', () async {
        final access = _Access()..failure = failure;
        final bloc = await _ready(access);
        final failed = bloc.stream.firstWhere((state) => state.failure != null);
        bloc.add(
          const WalletProtectionRequested(WalletProtectionAction.passkey),
        );
        final state = await failed.timeout(const Duration(seconds: 2));
        expect(state.failure, failure);
        expect(state.status!.requiresAuthentication, isFalse);
        expect(state.status!.hasManagedCredential, isTrue);
        expect(state.completed, isNull);
        expect(state.busy, isFalse);
        await Future<void>.delayed(Duration.zero);
        expect(access.requests, [_id]);
      });
    }

    test('unsupported new enrollment never starts a prompt', () async {
      final access = _Access()..supported = false;
      final bloc = await _ready(access);
      expect(bloc.state.canCreatePasskey, isFalse);
      final failed = bloc.stream.firstWhere((state) => state.failure != null);
      bloc.add(const WalletProtectionRequested(WalletProtectionAction.passkey));
      await failed.timeout(const Duration(seconds: 2));
      expect(access.requests, isEmpty);
    });

    test(
      'same name and keys with a new catalog entry cannot inherit setup intent',
      () async {
        final access = _Access();
        final bloc = await _ready(access);
        access.entry = 'replacement-entry';
        final failed = bloc.stream.firstWhere((state) => state.failure != null);
        bloc.add(
          const WalletProtectionRequested(WalletProtectionAction.passkey),
        );
        final state = await failed.timeout(const Duration(seconds: 2));
        expect(state.failure, WalletAccessFailure.staleOperation);
        expect(access.requests, isEmpty);
        expect(state.status!.entryId, 'setup-entry');
      },
    );

    test(
      'credential input is absent from event diagnostics and every state',
      () async {
        const password = 'synthetic-protection-input-never-log';
        const event = WalletProtectionRequested(
          WalletProtectionAction.passkey,
          password: password,
        );
        expect(event.toString(), isNot(contains(password)));
        final access = _Access();
        final bloc = await _ready(access);
        final states = <WalletProtectionState>[];
        final subscription = bloc.stream.listen(states.add);
        final finished = bloc.stream.firstWhere(
          (state) => state.completed != null,
        );
        bloc.add(event);
        await finished.timeout(const Duration(seconds: 2));
        expect(
          states.map((state) => state.toString()).join(),
          isNot(contains(password)),
        );
        await subscription.cancel();
      },
    );
  });
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_session.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/services/file_loader/file_loader.dart';
import 'package:web_dex/services/storage/base_storage.dart';
import 'package:web_dex/services/wallet_access/platform/credential_backend.dart';
import 'package:web_dex/services/wallet_access/unlock_coordinator.dart';
import 'package:web_dex/services/wallet_access/wallet_access_record.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/services/wallet_access/wallet_credential_cleanup.dart';
import 'package:web_dex/services/wallet_access/wallet_operation_gate.dart';

const _password = 'Synthetic-password-123456!';
const _entry = 'test-wallet-entry-0001';
const _hash = '1111111111111111111111111111111111111111';
const _recordsKey = 'wallet_access_records_v1';
const _options = AuthOptions(derivationMethod: DerivationMethod.hdWallet);

KdfUser _user({
  String name = 'Wallet',
  String id = _entry,
  Map<String, dynamic> metadata = const {},
}) => KdfUser(
  walletId: WalletId.withPubkeyHash(name, _options, _hash),
  isBip39Seed: true,
  metadata: {'_wallet_entry_id': id, 'type': 'hdwallet', ...metadata},
);

class _Storage extends BaseStorage {
  final values = <String, dynamic>{};
  String? failWrite;
  bool throwAfterPendingDelete = false;
  bool Function(String key, dynamic value)? failOneWrite;
  bool failAfterWrite = false;
  @override
  Future<dynamic> read(String key) async =>
      values[key] == null ? null : jsonDecode(jsonEncode(values[key]));
  @override
  Future<bool> write(String key, dynamic data) async {
    if (failWrite == key) return false;
    final fail = failOneWrite?.call(key, data) ?? false;
    if (fail) failOneWrite = null;
    if (fail && !failAfterWrite) return false;
    values[key] = jsonDecode(jsonEncode(data));
    return !fail;
  }

  @override
  Future<bool> delete(String key) async {
    values.remove(key);
    if (throwAfterPendingDelete && key == 'wallet_access_pending_v1') {
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
    return true;
  }
}

class _Backend extends CredentialBackend {
  final values = <String, String>{};
  final infos = <String, CredentialRecordInfo>{};
  final deviceEvents = StreamController<void>.broadcast(sync: true);
  final protectionEvents = StreamController<void>.broadcast(sync: true);
  Completer<String?>? pendingRead;
  Completer<void>? readReached;
  Completer<void>? pendingCancel;
  Completer<void>? cancelReached;
  Future<PasswordManagerOutcome> Function()? onSave;
  Future<void> Function()? onProtectedWrite;
  Future<String?> Function()? onProtectedReadback;
  bool failDelete = false;
  bool failCancel = false;
  bool failNextWrite = false;
  bool failAfterWrite = false;
  bool failNextRead = false;
  int? failReadAt;
  int writes = 0;
  int prepares = 0;
  int reads = 0;
  final readReasons = <String>[];
  int passkeyReplacements = 0;
  int passwordDeletionGrants = 0;
  WalletAccessFailure? replacementFailure;
  WalletAccessFailure? metadataFailure;
  @override
  Stream<void> get deviceLocked => deviceEvents.stream;
  @override
  Stream<void> get protectionChanged => protectionEvents.stream;
  @override
  Future<CredentialCapabilities> capabilities() async =>
      const CredentialCapabilities(
        available: true,
        protection: CredentialProtection.appLocal,
      );
  @override
  Future<CredentialRecordInfo?> metadata(String key) async {
    if (metadataFailure != null) throw WalletAccessException(metadataFailure!);
    return infos[key];
  }

  @override
  Future<void> write(
    String key,
    String value, {
    required bool requireAuthentication,
  }) async {
    writes++;
    if (requireAuthentication) await onProtectedWrite?.call();
    final fail = failNextWrite;
    failNextWrite = false;
    if (fail && !failAfterWrite) {
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
    values[key] = value;
    infos[key] = CredentialRecordInfo(
      protection: requireAuthentication
          ? CredentialProtection.authenticationBound
          : CredentialProtection.appLocal,
      enrolled: requireAuthentication,
    );
    if (fail) {
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
  }

  @override
  Future<String?> read(
    String key, {
    required String reason,
    bool requireAuthentication = false,
    bool automatic = false,
    String? purpose,
  }) async {
    reads++;
    if (failNextRead || reads == failReadAt) {
      failNextRead = false;
      failReadAt = null;
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
    readReasons.add(reason);
    if (purpose == 'verifyWrite' && onProtectedReadback != null) {
      return onProtectedReadback!();
    }
    if (readReached?.isCompleted == false) readReached!.complete();
    return pendingRead == null ? values[key] : pendingRead!.future;
  }

  @override
  Future<String?> prepareDelete(String key, {required String reason}) async {
    prepares++;
    return 'synthetic-delete-token';
  }

  @override
  Future<void> replacePasskeyAfterPasswordVerification(
    String key,
    String value, {
    required int expectedRevision,
    required String label,
  }) async {
    passkeyReplacements++;
    if (replacementFailure != null) {
      throw WalletAccessException(replacementFailure!);
    }
    final info = infos[key];
    if (info?.protection != CredentialProtection.passkey ||
        info?.revision != expectedRevision) {
      throw const WalletAccessException(WalletAccessFailure.staleOperation);
    }
    values[key] = value;
    infos[key] = CredentialRecordInfo(
      protection: CredentialProtection.passkey,
      enrolled: true,
      revision: expectedRevision + 1,
    );
  }

  @override
  Future<String?> prepareDeleteAfterPasswordVerification(
    String key, {
    required int expectedRevision,
  }) async {
    if (infos[key]?.protection != CredentialProtection.passkey ||
        infos[key]?.revision != expectedRevision) {
      throw const WalletAccessException(WalletAccessFailure.staleOperation);
    }
    passwordDeletionGrants++;
    return 'synthetic-delete-token';
  }

  @override
  Future<void> delete(String key, {String? authorization}) async {
    if (failDelete) {
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
    if (infos[key]?.enrolled == true && authorization == null) {
      throw const WalletAccessException(WalletAccessFailure.unavailable);
    }
    values.remove(key);
    infos.remove(key);
  }

  @override
  Future<void> cancel() async {
    if (failCancel) throw StateError('synthetic cancel failure');
    if (cancelReached?.isCompleted == false) cancelReached!.complete();
    await pendingCancel?.future;
  }

  @override
  Future<PasswordManagerOutcome> savePassword({
    required String username,
    required String password,
    required String title,
  }) async => await onSave?.call() ?? PasswordManagerOutcome.unknown;
}

class _Auth extends Fake implements KomodoDefiLocalAuth {
  final sessions = AuthSessionTracker();
  final users = <KdfUser>[];
  KdfUser? active;
  final hooks = <Future<void> Function(WalletId)>[];
  final registrations = <({String name, String id, String password})>[];
  final metadataUpdates = <Map<String, dynamic>>[];
  final verifiedWallets = <WalletId>[];
  Completer<void>? verificationReached;
  Completer<void>? pendingVerification;
  Completer<void>? passwordChangeReached;
  Completer<void>? pendingPasswordChange;
  bool collideOnce = false;
  bool failCreationOnce = false;
  bool failCreationAfterCommitOnce = false;
  bool failEncryptedReadOnce = false;
  bool ownedCollision = false;
  bool discardMetadataWrite = false;
  void Function()? afterMetadataWrite;
  String enginePassword = _password;
  String? failPasswordChange;
  bool cleanupSucceeds = true;
  int cleanupAttempts = 0;
  void activate(KdfUser user) {
    active = user;
    sessions.observe(user);
  }

  @override
  Future<KdfUser?> get currentUser async => active;
  @override
  Future<List<KdfUser>> getUsers() async => List.of(users);
  @override
  Future<bool> retryWalletDeletionCleanup(
    WalletDeletionCommittedException committed,
  ) async {
    cleanupAttempts++;
    if (!cleanupSucceeds) throw committed;
    return true;
  }

  @override
  void onWalletDeletion(Future<void> Function(WalletId) hook) =>
      hooks.add(hook);
  @override
  Future<AuthSessionContext> captureSessionContext() async {
    sessions.observe(active);
    return sessions.current ?? (throw const AuthSessionChangedException());
  }

  @override
  void ensureSessionContextCurrent(AuthSessionContext context) {
    if (!sessions.isCurrent(context)) throw const AuthSessionChangedException();
  }

  @override
  Future<void> verifyPassword({
    required String password,
    required WalletId expectedWalletId,
    AuthSessionContext? expectedSession,
  }) async {
    verifiedWallets.add(expectedWalletId);
    if (verificationReached?.isCompleted == false) {
      verificationReached!.complete();
    }
    await pendingVerification?.future;
    RpcDispatchGuard.ensureCurrent('get_mnemonic');
    if (expectedSession != null) ensureSessionContextCurrent(expectedSession);
    if (active?.walletId != expectedWalletId) {
      throw const AuthSessionChangedException();
    }
    if (password != enginePassword) {
      throw AuthException(
        'Incorrect password',
        type: AuthExceptionType.incorrectPassword,
      );
    }
  }

  @override
  Future<KdfUser> updateMetadataForSession(
    AuthSessionContext context,
    Map<String, dynamic> updates,
  ) async {
    ensureSessionContextCurrent(context);
    metadataUpdates.add(Map.of(updates));
    final current = active!;
    final updated = current.copyWith(
      metadata: {...current.metadata, ...updates},
    );
    if (!discardMetadataWrite) {
      final index = users.indexWhere(
        (user) =>
            user.metadata['_wallet_entry_id'] ==
            current.metadata['_wallet_entry_id'],
      );
      users[index] = updated;
      activate(updated);
    }
    afterMetadataWrite?.call();
    return updated;
  }

  @override
  Future<KdfUser> signIn({
    required String walletName,
    required String password,
    AuthOptions options = _options,
  }) async {
    final user = users.firstWhere((user) => user.walletId.name == walletName);
    activate(user);
    return user;
  }

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
    WalletId? expectedWalletId,
    AuthSessionContext? expectedSession,
  }) async {
    if (passwordChangeReached?.isCompleted == false) {
      passwordChangeReached!.complete();
    }
    await pendingPasswordChange?.future;
    RpcDispatchGuard.ensureCurrent('change_mnemonic_password');
    if (expectedSession != null) ensureSessionContextCurrent(expectedSession);
    if (active?.walletId != expectedWalletId ||
        currentPassword != enginePassword) {
      throw AuthException(
        'Incorrect password',
        type: AuthExceptionType.incorrectPassword,
      );
    }
    final failure = failPasswordChange;
    failPasswordChange = null;
    if (failure == 'before') {
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
    enginePassword = newPassword;
    if (failure == 'after') {
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
  }

  @override
  Future<KdfUser> register({
    required String walletName,
    required String password,
    AuthOptions options = _options,
    Mnemonic? mnemonic,
    Map<String, dynamic> initialMetadata = const {},
    String? provisioningId,
  }) async {
    registrations.add((
      name: walletName,
      id: provisioningId!,
      password: password,
    ));
    if (collideOnce || ownedCollision) {
      collideOnce = false;
      throw AuthException(
        'collision',
        type: AuthExceptionType.walletAlreadyExists,
        details: {'canRetryWithDifferentName': !ownedCollision},
      );
    }
    if (failCreationOnce) {
      failCreationOnce = false;
      throw StateError('interrupted engine startup');
    }
    final existing = users.where(
      (user) => user.metadata['_wallet_entry_id'] == provisioningId,
    );
    if (existing.isNotEmpty) {
      activate(existing.single);
      return existing.single;
    }
    final user = _user(name: walletName, id: provisioningId);
    users.add(user);
    enginePassword = password;
    activate(user);
    if (failCreationAfterCommitOnce) {
      failCreationAfterCommitOnce = false;
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
    return user;
  }

  @override
  Future<Mnemonic> getMnemonicEncrypted() async {
    if (failEncryptedReadOnce) {
      failEncryptedReadOnce = false;
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
    return Mnemonic.encrypted(
      EncryptedMnemonicData.fromJson(
        EncryptedMnemonicData.encryptedDataExample,
      ),
    );
  }
}

class _Sdk extends Fake implements KomodoDefiSdk {
  _Sdk(this.auth);
  @override
  final KomodoDefiLocalAuth auth;
  WalletDeletionManager? deletionManager;
  @override
  WalletDeletionManager get walletDeletion => deletionManager!;
}

class _Mm2Api extends Fake implements Mm2Api {}

class _FileLoader extends Fake implements FileLoader {}

class _NoPendingTransfers extends Fake
    implements PendingGaslessTransferRepository {
  @override
  Future<List<PendingGaslessTransfer>> list(WalletId walletId) async => [];
}

void main() {
  group('WalletAccessService authority and recovery', () {
    late _Storage storage;
    late _Backend backend;
    late _Auth auth;
    late _Sdk sdk;
    late WalletUnlockCoordinator coordinator;
    late WalletAccessService service;
    late Duration monotonic;
    setUp(() {
      monotonic = Duration.zero;
      storage = _Storage();
      backend = _Backend();
      auth = _Auth();
      sdk = _Sdk(auth);
      coordinator = WalletUnlockCoordinator(
        operationGate: WalletOperationGate(),
        monotonicNow: () => monotonic,
      );
      service = WalletAccessService(
        sdk: sdk,
        storage: storage,
        backend: backend,
        unlockCoordinator: coordinator,
        monotonicNow: () => monotonic,
      );
    });
    tearDown(() async {
      await service.dispose();
      await auth.sessions.dispose();
      await backend.deviceEvents.close();
      await backend.protectionEvents.close();
    });
    Future<KdfUser> install({
      bool protected = true,
      bool passkey = false,
    }) async {
      final user = _user();
      auth.users.add(user);
      auth.activate(user);
      final record = WalletAccessRecord(
        entryId: _entry,
        walletName: 'Wallet',
        isHd: true,
        pubkeyHash: _hash,
        phase: 'ready',
        protection: passkey
            ? CredentialProtection.passkey
            : protected
            ? CredentialProtection.authenticationBound
            : CredentialProtection.appLocal,
        requiresAuthentication: protected,
      );
      await storage.write(_recordsKey, {_entry: record.toJson()});
      await backend.write(
        record.credentialKey,
        _password,
        requireAuthentication: protected,
      );
      if (passkey) {
        backend.infos[record.credentialKey] = const CredentialRecordInfo(
          protection: CredentialProtection.passkey,
          enrolled: true,
          revision: 7,
        );
      }
      await service.didAuthenticate(user, password: _password);
      return user;
    }

    Matcher stale() => throwsA(
      isA<WalletAccessException>().having(
        (e) => e.failure,
        'failure',
        WalletAccessFailure.staleOperation,
      ),
    );

    group('optional password-manager activity', () {
      for (final canceled in [false, true]) {
        test(
          'covers fresh verification and provider completion, canceled=$canceled',
          () async {
            final user = await install(protected: false);
            auth.verificationReached = Completer<void>();
            auth.pendingVerification = Completer<void>();
            final saveReached = Completer<void>();
            final reply = Completer<PasswordManagerOutcome>();
            backend.onSave = () {
              saveReached.complete();
              return reply.future;
            };
            final pending = service.saveToPasswordManager(
              walletId: user.walletId,
            );
            final result = canceled
                ? expectLater(pending, throwsA(isA<WalletAccessException>()))
                : expectLater(
                    pending,
                    completion(PasswordManagerOutcome.unknown),
                  );
            expect(service.isPasswordManagerPending, isTrue);
            await auth.verificationReached!.future;
            expect(service.isPasswordManagerPending, isTrue);
            expect(saveReached.isCompleted, isFalse);
            auth.pendingVerification!.complete();
            await saveReached.future;
            expect(service.isPasswordManagerPending, isTrue);
            if (canceled) {
              reply.completeError(
                const WalletAccessException(WalletAccessFailure.canceled),
              );
            } else {
              reply.complete(PasswordManagerOutcome.unknown);
            }
            await result;
            expect(service.isPasswordManagerPending, isFalse);
            expect(coordinator.state.isLocked, isFalse);
          },
        );
      }
      test(
        'a queued optional save cannot clear another save’s activity',
        () async {
          final user = await install(protected: false);
          final firstReached = Completer<void>();
          final secondReached = Completer<void>();
          final firstReply = Completer<PasswordManagerOutcome>();
          final secondReply = Completer<PasswordManagerOutcome>();
          var calls = 0;
          backend.onSave = () {
            calls++;
            if (calls == 1) {
              firstReached.complete();
              return firstReply.future;
            }
            secondReached.complete();
            return secondReply.future;
          };
          final first = service.saveToPasswordManager(walletId: user.walletId);
          await firstReached.future;
          final second = service.saveToPasswordManager(walletId: user.walletId);
          expect(service.isPasswordManagerPending, isTrue);
          firstReply.complete(PasswordManagerOutcome.unknown);
          await first;
          await secondReached.future;
          expect(service.isPasswordManagerPending, isTrue);
          secondReply.complete(PasswordManagerOutcome.unknown);
          await second;
          expect(service.isPasswordManagerPending, isFalse);
        },
      );
    });

    group('sensitive operation foreground authority', () {
      for (final deleting in [false, true]) {
        test(
          'immediate return before native reply succeeds, deleting=$deleting',
          () async {
            final user = await install();
            coordinator.setBackgroundGrace(Duration.zero);
            backend.readReached = Completer<void>();
            backend.pendingRead = Completer<String?>();
            final pending = deleting
                ? service.credentialForDeletion(user.wallet)
                : service.authorize(walletId: user.walletId);
            await backend.readReached!.future;
            coordinator.background();
            coordinator.resume();
            expect(coordinator.state.isLocked, isTrue);
            backend.pendingRead!.complete(_password);
            expect(await pending, _password);
            expect(coordinator.state.isLocked, isFalse);
          },
        );
      }
      for (final immediate in [false, true]) {
        test(
          'authorization waits for native return, immediate=$immediate',
          () async {
            final user = await install();
            if (immediate) coordinator.setBackgroundGrace(Duration.zero);
            backend.readReached = Completer<void>();
            backend.pendingRead = Completer<String?>();
            final beforeVerification = auth.verifiedWallets.length;
            final pending = service.authorize(walletId: user.walletId);
            await backend.readReached!.future;
            coordinator.inactive();
            coordinator.background();
            backend.pendingRead!.complete(_password);
            await Future<void>.delayed(Duration.zero);
            expect(auth.verifiedWallets.length, beforeVerification);
            expect(coordinator.operationGate.allowsOperations, isFalse);
            coordinator.resume();
            expect(await pending, _password);
            final permit = service.captureSensitiveOperation(user.walletId);
            expect(permit, returnsNormally);
            coordinator.inactive();
            expect(permit, throwsA(anything));
            coordinator.resume();
            expect(permit, throwsA(anything));
          },
        );
      }
      test('locked settings cannot read managed credentials', () async {
        final user = await install();
        coordinator.lock();
        final reads = backend.reads;
        await expectLater(service.authorize(walletId: user.walletId), stale());
        expect(backend.reads, reads);
        expect(await service.unlockCurrent(), isTrue);
      });
      test(
        'inactivity rejects queued sensitive credential verification',
        () async {
          final user = await install();
          auth.verificationReached = Completer<void>();
          auth.pendingVerification = Completer<void>();
          final pending = service.authorize(
            walletId: user.walletId,
            password: _password,
          );
          final rejected = expectLater(pending, stale());
          await auth.verificationReached!.future;
          coordinator.inactive();
          auth.pendingVerification!.complete();
          await rejected;
        },
      );
      test(
        'inactivity rejects password change waiting for engine dispatch',
        () async {
          final user = await install();
          auth.passwordChangeReached = Completer<void>();
          auth.pendingPasswordChange = Completer<void>();
          final pending = service.changePassword(
            walletId: user.walletId,
            currentPassword: _password,
            newPassword: 'Replacement-Secret-6789!',
          );
          final rejected = expectLater(pending, stale());
          await auth.passwordChangeReached!.future;
          coordinator.inactive();
          auth.pendingPasswordChange!.complete();
          await rejected;
          expect(auth.enginePassword, _password);
        },
      );
      test('queued password-manager status cannot cross an app lock', () async {
        final user = await install();
        auth.verificationReached = Completer<void>();
        auth.pendingVerification = Completer<void>();
        final authorization = expectLater(
          service.authorize(walletId: user.walletId, password: _password),
          stale(),
        );
        await auth.verificationReached!.future;
        final outcome = expectLater(
          service.recordPasswordManagerOutcome(
            walletId: user.walletId,
            outcome: PasswordManagerOutcome.accepted,
          ),
          stale(),
        );
        coordinator.lock();
        auth.pendingVerification!.complete();
        await authorization;
        await outcome;
        expect(
          (await service.status(walletId: user.walletId)).passwordManager,
          PasswordManagerOutcome.unavailable,
        );
      });
    });

    group('interactive protection persistence foreground return', () {
      for (final rotating in [false, true]) {
        for (final resumeFirst in [false, true]) {
          test(
            'write and readback wait independently, rotating=$rotating resumeFirst=$resumeFirst',
            () async {
              final user = await install(protected: rotating);
              coordinator.setBackgroundGrace(Duration.zero);
              const replacement = 'Replacement-Secret-6789!';
              final expectedSecret = rotating ? replacement : _password;
              final writeReached = Completer<void>();
              final finishWrite = Completer<void>();
              final readbackReached = Completer<void>();
              final finishReadback = Completer<String?>();
              backend.onProtectedWrite = () {
                writeReached.complete();
                return finishWrite.future;
              };
              backend.onProtectedReadback = () {
                readbackReached.complete();
                return finishReadback.future;
              };
              var completed = false;
              final pending =
                  (rotating
                          ? service.changePassword(
                              walletId: user.walletId,
                              currentPassword: _password,
                              newPassword: replacement,
                            )
                          : service.enrollDevice(
                              walletId: user.walletId,
                              password: _password,
                            ))
                      .then((_) => completed = true);
              await writeReached.future;
              coordinator.inactive();
              coordinator.background();
              if (resumeFirst) coordinator.resume();
              finishWrite.complete();
              if (!resumeFirst) {
                await Future<void>.delayed(Duration.zero);
                expect(readbackReached.isCompleted, isFalse);
                expect(coordinator.operationGate.allowsOperations, isFalse);
                coordinator.resume();
              }
              await readbackReached.future;
              coordinator.inactive();
              coordinator.background();
              if (resumeFirst) coordinator.resume();
              finishReadback.complete(expectedSecret);
              if (!resumeFirst) {
                await Future<void>.delayed(Duration.zero);
                expect(completed, isFalse);
                expect(coordinator.operationGate.allowsOperations, isFalse);
                coordinator.resume();
              }
              await pending;
              expect(completed, isTrue);
              expect(auth.enginePassword, expectedSecret);
              expect(coordinator.state.requiresAuthentication, isTrue);
              expect(coordinator.state.isLocked, isFalse);
              expect(coordinator.operationGate.allowsOperations, isTrue);
            },
          );
        }
      }
    });

    group('owned export destination authority', () {
      Matcher revoked() => throwsA(
        anyOf(
          isA<WalletOperationDenied>(),
          isA<WalletAccessException>().having(
            (error) => error.failure,
            'failure',
            WalletAccessFailure.staleOperation,
          ),
        ),
      );

      for (final seconds in [29, 31]) {
        for (final resumeFirst in [false, true]) {
          test(
            'picker ${seconds}s, resumeFirst=$resumeFirst preserves one scoped export',
            () async {
              final user = await install();
              final authorization = await service.captureSensitiveExport(
                user.walletId,
              );
              final oldPermit = service.captureSensitiveOperation(
                user.walletId,
              );
              final selected = Completer<String?>();
              final opened = Completer<void>();
              final reads = backend.reads;
              final verified = auth.verifiedWallets.length;
              final pending = authorization.selectDestination(() {
                opened.complete();
                return selected.future;
              });
              await opened.future;
              coordinator.inactive();
              coordinator.background();
              monotonic += Duration(seconds: seconds);
              expect(authorization.ensureCurrent, revoked());
              expect(oldPermit, revoked());
              expect(coordinator.beginUnlock(automatic: true), isNull);
              if (resumeFirst) coordinator.resume();
              selected.complete('synthetic-destination-token');
              if (!resumeFirst) {
                await Future<void>.delayed(Duration.zero);
                expect(backend.reads, reads);
                expect(authorization.ensureCurrent, revoked());
                coordinator.resume();
              }
              expect(await pending, 'synthetic-destination-token');
              expect(backend.reads - reads, seconds == 31 ? 1 : 0);
              expect(
                auth.verifiedWallets.length - verified,
                seconds == 31 ? 1 : 0,
              );
              expect(authorization.ensureCurrent, returnsNormally);
              expect(oldPermit, revoked());
              coordinator.inactive();
              expect(authorization.ensureCurrent, revoked());
            },
          );
        }
      }
      for (final resumeFirst in [false, true]) {
        test(
          'immediate picker return authorizes once, resumeFirst=$resumeFirst',
          () async {
            final user = await install();
            coordinator.setBackgroundGrace(Duration.zero);
            final authorization = await service.captureSensitiveExport(
              user.walletId,
            );
            final selected = Completer<String?>();
            final opened = Completer<void>();
            final reads = backend.reads;
            final pending = authorization.selectDestination(() {
              opened.complete();
              return selected.future;
            });
            await opened.future;
            coordinator.background();
            expect(coordinator.state.isLocked, isTrue);
            if (resumeFirst) coordinator.resume();
            selected.complete('synthetic-destination-token');
            if (!resumeFirst) {
              await Future<void>.delayed(Duration.zero);
              coordinator.resume();
            }
            expect(await pending, 'synthetic-destination-token');
            expect(backend.reads - reads, 1);
            expect(authorization.ensureCurrent, returnsNormally);
          },
        );
      }
      test('cancelled picker never reauthorizes or allows a write', () async {
        final user = await install();
        coordinator.setBackgroundGrace(Duration.zero);
        final authorization = await service.captureSensitiveExport(
          user.walletId,
        );
        final selected = Completer<String?>();
        final opened = Completer<void>();
        final reads = backend.reads;
        final pending = authorization.selectDestination(() {
          opened.complete();
          return selected.future;
        });
        await opened.future;
        coordinator.background();
        selected.complete(null);
        await Future<void>.delayed(Duration.zero);
        coordinator.resume();
        expect(await pending, isNull);
        expect(backend.reads, reads);
        expect(coordinator.state.isLocked, isTrue);
        expect(authorization.ensureCurrent, revoked());
        expect(coordinator.beginUnlock(automatic: true), isNull);
      });
      for (final interruption in [
        'manual lock',
        'device lock',
        'wallet switch',
        'switch back',
        'second inactivity',
      ]) {
        test(
          '$interruption cancels destination without reauthorization',
          () async {
            final user = await install();
            final authorization = await service.captureSensitiveExport(
              user.walletId,
            );
            final selected = Completer<String?>();
            final opened = Completer<void>();
            final reads = backend.reads;
            final pending = authorization.selectDestination(() {
              opened.complete();
              return selected.future;
            });
            final rejected = expectLater(pending, stale());
            await opened.future;
            coordinator.background();
            selected.complete('synthetic-destination-token');
            await Future<void>.delayed(Duration.zero);
            switch (interruption) {
              case 'manual lock':
                coordinator.lock();
              case 'device lock':
                coordinator.deviceLocked();
              case 'wallet switch':
                coordinator.attachWallet(
                  'other-entry',
                  requiresAuthentication: true,
                );
              case 'switch back':
                coordinator.attachWallet(
                  'other-entry',
                  requiresAuthentication: true,
                );
                coordinator.attachWallet(
                  _entry,
                  requiresAuthentication: true,
                  authenticated: true,
                );
              case 'second inactivity':
                coordinator.inactive();
            }
            coordinator.resume();
            await rejected;
            expect(backend.reads, reads);
            expect(authorization.ensureCurrent, revoked());
          },
        );
      }
      test(
        'password-only export waits for explicit password unlock after picker',
        () async {
          final user = await install();
          final records =
              await storage.read(_recordsKey) as Map<String, dynamic>;
          final record = WalletAccessRecord.fromJson(
            records[_entry] as Map<String, dynamic>,
          );
          await storage.write(_recordsKey, {
            _entry: record
                .copyWith(
                  managed: false,
                  protection: CredentialProtection.password,
                )
                .toJson(),
          });
          await service.didAuthenticate(user, password: _password);
          coordinator.setBackgroundGrace(Duration.zero);
          final authorization = await service.captureSensitiveExport(
            user.walletId,
          );
          final selected = Completer<String?>();
          final opened = Completer<void>();
          final reads = backend.reads;
          var completed = false;
          final pending = authorization
              .selectDestination(() {
                opened.complete();
                return selected.future;
              })
              .then((value) {
                completed = true;
                return value;
              });
          await opened.future;
          coordinator.background();
          coordinator.resume();
          selected.complete('synthetic-destination-token');
          await Future<void>.delayed(Duration.zero);
          expect(completed, isFalse);
          expect(backend.reads, reads);
          expect(coordinator.state.isLocked, isTrue);
          expect(await service.unlockCurrent(password: _password), isTrue);
          expect(await pending, 'synthetic-destination-token');
          expect(backend.reads, reads);
          expect(authorization.ensureCurrent, returnsNormally);
        },
      );

      test(
        'same-wallet SDK reauthentication revokes destination authority',
        () async {
          final user = await install();
          final authorization = await service.captureSensitiveExport(
            user.walletId,
          );
          auth.sessions.observe(null);
          auth.activate(user);
          var opened = false;
          await expectLater(
            authorization.selectDestination(() async {
              opened = true;
              return 'synthetic-destination-token';
            }),
            throwsA(isA<AuthSessionChangedException>()),
          );
          expect(opened, isFalse);
          expect(
            authorization.ensureCurrent,
            throwsA(isA<AuthSessionChangedException>()),
          );
        },
      );

      test('one authorization cannot select two destinations', () async {
        final user = await install();
        final authorization = await service.captureSensitiveExport(
          user.walletId,
        );
        var calls = 0;
        Future<String?> select() async {
          calls++;
          return 'synthetic-destination-token';
        }

        expect(await authorization.selectDestination(select), isNotNull);
        await expectLater(authorization.selectDestination(select), stale());
        expect(calls, 1);
      });
      for (final resumeFirst in [false, true]) {
        test(
          'fresh export unlock also waits for native return, resumeFirst=$resumeFirst',
          () async {
            final user = await install();
            coordinator.setBackgroundGrace(Duration.zero);
            final authorization = await service.captureSensitiveExport(
              user.walletId,
            );
            final selected = Completer<String?>();
            final opened = Completer<void>();
            backend.readReached = Completer<void>();
            backend.pendingRead = Completer<String?>();
            var completed = false;
            final pending = authorization
                .selectDestination(() {
                  opened.complete();
                  return selected.future;
                })
                .then((value) {
                  completed = true;
                  return value;
                });
            await opened.future;
            coordinator.background();
            coordinator.resume();
            selected.complete('synthetic-destination-token');
            await backend.readReached!.future;
            coordinator.inactive();
            coordinator.background();
            if (resumeFirst) coordinator.resume();
            backend.pendingRead!.complete(_password);
            if (!resumeFirst) {
              await Future<void>.delayed(Duration.zero);
              expect(completed, isFalse);
              expect(authorization.ensureCurrent, revoked());
              coordinator.resume();
            }
            expect(await pending, 'synthetic-destination-token');
            expect(authorization.ensureCurrent, returnsNormally);
          },
        );
      }
    });

    group('prepared deletion dispatch authorization', () {
      for (final immediate in [false, true]) {
        test(
          'managed deletion waits for its native prompt resume, immediate=$immediate',
          () async {
            final user = await install();
            if (immediate) coordinator.setBackgroundGrace(Duration.zero);
            backend.readReached = Completer<void>();
            backend.pendingRead = Completer<String?>();
            var completed = false;
            final pending = service.credentialForDeletion(user.wallet).then((
              value,
            ) {
              completed = true;
              return value;
            });
            await backend.readReached!.future;
            coordinator.inactive();
            coordinator.background();
            backend.pendingRead!.complete(_password);
            await Future<void>.delayed(Duration.zero);
            expect(completed, isFalse);
            expect(coordinator.operationGate.allowsOperations, isFalse);
            coordinator.resume();
            expect(await pending, _password);
            expect(
              service.deletionAuthorizationValidator(user.wallet),
              returnsNormally,
            );
            expect(backend.prepares, 1);
          },
        );
      }

      for (final cleanupSucceeds in [true, false]) {
        test(
          'committed deletion has accurate outcome when metadata retry succeeds=$cleanupSucceeds',
          () async {
            final user = await install(passkey: true);
            auth.cleanupSucceeds = cleanupSucceeds;
            var deleteCalls = 0;
            sdk.deletionManager = WalletDeletionManager(
              readWallets: () async => auth.users,
              pendingTransfers: _NoPendingTransfers(),
              deleteWallet:
                  ({
                    required walletName,
                    required password,
                    required validateTarget,
                  }) async {
                    await validateTarget(user);
                    RpcDispatchGuard.ensureCurrent('delete_wallet');
                    deleteCalls++;
                    auth.users.remove(user);
                    auth.active = null;
                    await auth.hooks.single(user.walletId);
                    throw WalletDeletionCommittedException(
                      walletId: user.walletId,
                      entryId: _entry,
                    );
                  },
            );
            final repository = WalletsRepository(
              sdk,
              _Mm2Api(),
              storage,
              walletAccess: service,
              fileLoader: _FileLoader(),
            );
            final review = await repository.prepareWalletDeletion(user.wallet);
            final password = await service.credentialForDeletion(
              user.wallet,
              password: _password,
            );
            final pending = repository.deleteWallet(
              user.wallet,
              password: password,
              acknowledgedReview: review,
            );
            if (cleanupSucceeds) {
              expect((await pending).status, WalletDeletionStatus.deleted);
            } else {
              await expectLater(
                pending,
                throwsA(isA<WalletDeletionCommittedException>()),
              );
            }
            expect(deleteCalls, 1);
            expect(auth.cleanupAttempts, 1);
            expect(auth.users, isEmpty);
            expect(backend.values['gleec.wallet.$_entry'], isNull);
            expect(await service.hasPendingCredentialCleanup, isFalse);
          },
        );
      }

      test(
        'repository carries the proof through review to final SDK dispatch',
        () async {
          final user = await install(passkey: true);
          final reached = Completer<void>();
          final resume = Completer<void>();
          var dispatched = false;
          sdk.deletionManager = WalletDeletionManager(
            readWallets: () async => auth.users,
            pendingTransfers: _NoPendingTransfers(),
            deleteWallet:
                ({
                  required walletName,
                  required password,
                  required validateTarget,
                }) async {
                  await validateTarget(user);
                  reached.complete();
                  await resume.future;
                  RpcDispatchGuard.ensureCurrent('delete_wallet');
                  dispatched = true;
                },
          );
          final repository = WalletsRepository(
            sdk,
            _Mm2Api(),
            storage,
            walletAccess: service,
            fileLoader: _FileLoader(),
          );
          final review = await repository.prepareWalletDeletion(user.wallet);
          final password = await service.credentialForDeletion(
            user.wallet,
            password: _password,
          );
          final pending = repository.deleteWallet(
            user.wallet,
            password: password,
            acknowledgedReview: review,
          );
          final rejected = expectLater(
            pending,
            throwsA(isA<RpcDispatchRejected>()),
          );
          await reached.future;
          coordinator.lock();
          resume.complete();
          await rejected;
          expect(dispatched, isFalse);
          expect(auth.users, contains(user));
        },
      );

      test('unprepared wallet cannot capture deletion authority', () async {
        final user = await install();
        expect(
          () => service.deletionAuthorizationValidator(user.wallet),
          stale(),
        );
      });

      for (final mutation in [
        'lock',
        'device lock',
        'background',
        'switch',
        'expire',
        'replace proof',
      ]) {
        test('$mutation rejects a queued deletion before dispatch', () async {
          final user = await install(passkey: true);
          await service.credentialForDeletion(user.wallet, password: _password);
          final ensureCurrent = service.deletionAuthorizationValidator(
            user.wallet,
          );
          final reached = Completer<void>();
          final resume = Completer<void>();
          var dispatched = false;
          final pending = RpcDispatchGuard.run(ensureCurrent, () async {
            reached.complete();
            await resume.future;
            RpcDispatchGuard.ensureCurrent('delete_wallet');
            dispatched = true;
          }, methods: const {'delete_wallet'});
          final rejected = expectLater(
            pending,
            throwsA(isA<RpcDispatchRejected>()),
          );
          await reached.future;
          switch (mutation) {
            case 'lock':
              coordinator.lock();
            case 'device lock':
              coordinator.deviceLocked();
            case 'background':
              coordinator.inactive();
            case 'switch':
              coordinator.attachWallet(
                'another-entry',
                requiresAuthentication: false,
              );
            case 'expire':
              monotonic = const Duration(seconds: 60);
            case 'replace proof':
              await service.credentialForDeletion(
                user.wallet,
                password: _password,
              );
          }
          resume.complete();
          await rejected;
          expect(dispatched, isFalse);
          expect(auth.users, contains(user));
        });
      }

      test(
        'proof binds the exact wallet and permits dispatch before expiry',
        () async {
          final user = await install(passkey: true);
          await service.credentialForDeletion(user.wallet, password: _password);
          final ensureCurrent = service.deletionAuthorizationValidator(
            user.wallet,
          );
          expect(
            () => service.deletionAuthorizationValidator(
              _user(name: 'Other').wallet,
            ),
            stale(),
          );
          monotonic = const Duration(seconds: 59);
          expect(ensureCurrent, returnsNormally);
        },
      );

      test(
        'password-only wallets also receive a bounded app authorization',
        () async {
          final user = await install();
          await storage.write(_recordsKey, <String, dynamic>{});
          await service.credentialForDeletion(user.wallet, password: _password);
          final ensureCurrent = service.deletionAuthorizationValidator(
            user.wallet,
          );
          expect(ensureCurrent, returnsNormally);
          service.invalidatePendingOperations();
          expect(ensureCurrent, stale());
        },
      );
    });

    group('explicit lost-passkey password recovery', () {
      test(
        'replacement requires fresh proof and never reads the old provider',
        () async {
          final user = await install(passkey: true);
          final generation = coordinator.authorizationGeneration;
          final reads = backend.reads;
          final proofs = auth.verifiedWallets.length;
          backend.pendingRead = Completer<String?>();
          await service.replacePasskeyUsingPassword(
            walletId: user.walletId,
            password: _password,
          );
          expect(auth.verifiedWallets.length, proofs + 1);
          expect(backend.reads, reads);
          expect(backend.passkeyReplacements, 1);
          expect(backend.infos['gleec.wallet.$_entry']?.revision, 8);
          expect(coordinator.authorizationGeneration, generation);
          expect(auth.users, [user]);
        },
      );
      for (final action in ['replace', 'delete']) {
        test('wrong password cannot authorize $action', () async {
          final user = await install(passkey: true);
          await expectLater(
            action == 'replace'
                ? service.replacePasskeyUsingPassword(
                    walletId: user.walletId,
                    password: 'wrong',
                  )
                : service.credentialForDeletion(user.wallet, password: 'wrong'),
            throwsA(isA<AuthException>()),
          );
          expect(backend.passkeyReplacements, 0);
          expect(backend.passwordDeletionGrants, 0);
          expect(backend.infos['gleec.wallet.$_entry']?.revision, 7);
        });
        test(
          'lock during password verification cannot authorize $action',
          () async {
            final user = await install(passkey: true);
            auth.verificationReached = Completer<void>();
            auth.pendingVerification = Completer<void>();
            final pending = action == 'replace'
                ? service.replacePasskeyUsingPassword(
                    walletId: user.walletId,
                    password: _password,
                  )
                : service.credentialForDeletion(
                    user.wallet,
                    password: _password,
                  );
            final failed = expectLater(pending, stale());
            await auth.verificationReached!.future;
            coordinator.lock();
            auth.pendingVerification!.complete();
            await failed;
            expect(backend.passkeyReplacements, 0);
            expect(backend.passwordDeletionGrants, 0);
            expect(coordinator.operationGate.allowsOperations, isFalse);
          },
        );
      }
      test(
        'canceled replacement retains old protection and credential',
        () async {
          final user = await install(passkey: true);
          backend.replacementFailure = WalletAccessFailure.canceled;
          await expectLater(
            service.replacePasskeyUsingPassword(
              walletId: user.walletId,
              password: _password,
            ),
            throwsA(isA<WalletAccessException>()),
          );
          expect(backend.infos['gleec.wallet.$_entry']?.revision, 7);
          expect(backend.values['gleec.wallet.$_entry'], _password);
          expect(
            (await service.status()).protection,
            CredentialProtection.passkey,
          );
        },
      );
      test(
        'password authorizes deletion without an old-provider read',
        () async {
          final user = await install(passkey: true);
          final reads = backend.reads;
          final proofs = auth.verifiedWallets.length;
          final value = await service.credentialForDeletion(
            user.wallet,
            password: _password,
          );
          expect(value, _password);
          expect(auth.verifiedWallets.length, proofs + 1);
          expect(backend.reads, reads);
          expect(backend.prepares, 0);
          expect(backend.passwordDeletionGrants, 1);
        },
      );
      test(
        'inactive wallet deletion never switches wallets to obtain proof',
        () async {
          final user = await install(passkey: true);
          final other = _user(name: 'Other', id: 'test-other-entry');
          auth.users.add(other);
          auth.activate(other);
          await expectLater(
            service.credentialForDeletion(user.wallet, password: _password),
            throwsA(
              isA<WalletAccessException>().having(
                (error) => error.failure,
                'failure',
                WalletAccessFailure.walletMustBeUnlocked,
              ),
            ),
          );
          expect(auth.active, other);
          expect(backend.passwordDeletionGrants, 0);
        },
      );
    });

    group('display name', () {
      Matcher failsWith(WalletAccessFailure failure) => throwsA(
        isA<WalletAccessException>().having(
          (error) => error.failure,
          'failure',
          failure,
        ),
      );

      test(
        'fresh managed authorization changes only presentation metadata',
        () async {
          final user = await install();
          final originalLastWallet = await storage.read(
            'wallet_access_last_v1',
          );
          final originalRecords = await storage.read(_recordsKey);
          final originalCredentials = Map.of(backend.values);
          final originalSession = await auth.captureSessionContext();
          final originalGeneration = coordinator.authorizationGeneration;
          final originalReads = backend.reads;
          final originalVerifications = auth.verifiedWallets.length;

          await service.renameDisplayName(
            walletId: user.walletId,
            name: '  Everyday wallet  ',
          );

          final renamed = auth.users.single;
          expect(renamed.wallet.displayName, 'Everyday wallet');
          expect(renamed.wallet.name, user.wallet.name);
          expect(renamed.wallet.id, user.wallet.id);
          expect(renamed.walletId, user.walletId);
          expect(renamed.metadata, {
            ...user.metadata,
            'display_name': 'Everyday wallet',
          });
          expect(auth.metadataUpdates, [
            {'display_name': 'Everyday wallet'},
          ]);
          expect(await auth.captureSessionContext(), originalSession);
          expect(coordinator.authorizationGeneration, originalGeneration);
          expect(
            await storage.read('wallet_access_last_v1'),
            originalLastWallet,
          );
          expect(await storage.read(_recordsKey), originalRecords);
          expect(backend.values, originalCredentials);
          expect(backend.reads, originalReads + 1);
          expect(backend.readReasons.last, 'Rename this wallet');
          expect(auth.verifiedWallets.length, originalVerifications + 1);
          expect(auth.verifiedWallets.last, user.walletId);
          expect((await service.lastWallet())!.displayName, 'Everyday wallet');
          expect((await service.lastWallet())!.name, user.walletId.name);
        },
      );

      for (final entry in <String, String>{
        'empty': '',
        'only spaces': '   ',
        '65 Unicode code points': List.filled(65, '\u{1f680}').join(),
        'embedded newline': 'Wallet\nTwo',
        'embedded tab': 'Wallet\tTwo',
        'NUL': 'Wallet\u0000Two',
        'DEL': 'Wallet\u007fTwo',
        'C1 control': 'Wallet\u0085Two',
        'line separator': 'Wallet\u2028Two',
        'paragraph separator': 'Wallet\u2029Two',
      }.entries) {
        test('rejects ${entry.key} before authorization', () async {
          final user = await install();
          final reads = backend.reads;
          final verifications = auth.verifiedWallets.length;
          await expectLater(
            service.renameDisplayName(
              walletId: user.walletId,
              name: entry.value,
            ),
            failsWith(WalletAccessFailure.invalidName),
          );
          expect(backend.reads, reads);
          expect(auth.verifiedWallets.length, verifications);
          expect(auth.metadataUpdates, isEmpty);
          expect(auth.users.single.metadata, user.metadata);
        });
      }

      test(
        'accepts exactly 64 Unicode code points rather than UTF-16 units',
        () async {
          final user = await install();
          final name = List.filled(64, '\u{1f680}').join();
          expect(name.length, greaterThan(64));
          await service.renameDisplayName(
            walletId: user.walletId,
            name: name,
            password: _password,
          );
          expect(auth.users.single.wallet.displayName, name);
        },
      );

      for (final hasDisplayName in [false, true]) {
        test(
          'rejects another entry\'s ${hasDisplayName ? 'display' : 'canonical fallback'} name without prompting',
          () async {
            final user = await install();
            final other = _user(
              name: hasDisplayName ? 'Other canonical wallet' : 'Savings',
              id: 'other-entry-with-the-same-seed',
              metadata: hasDisplayName ? {'display_name': 'Savings'} : {},
            );
            auth.users.add(other);
            final reads = backend.reads;
            final verifications = auth.verifiedWallets.length;
            await expectLater(
              service.renameDisplayName(
                walletId: user.walletId,
                name: '  sAvInGs  ',
              ),
              failsWith(WalletAccessFailure.nameAlreadyUsed),
            );
            expect(backend.reads, reads);
            expect(auth.verifiedWallets.length, verifications);
            expect(auth.metadataUpdates, isEmpty);
            expect(auth.users, [user, other]);
          },
        );
      }

      test(
        'allows the current entry to keep its own name with new casing',
        () async {
          final user = await install();
          await service.renameDisplayName(
            walletId: user.walletId,
            name: 'wAlLeT',
            password: _password,
          );
          await service.renameDisplayName(
            walletId: user.walletId,
            name: 'WALLET',
            password: _password,
          );
          expect(auth.users.single.wallet.displayName, 'WALLET');
          expect(auth.users.single.walletId, user.walletId);
        },
      );

      test(
        'wrong password cannot reuse an already authenticated session',
        () async {
          final user = await install();
          await expectLater(
            service.renameDisplayName(
              walletId: user.walletId,
              name: 'Savings',
              password: 'incorrect synthetic credential',
            ),
            throwsA(
              isA<AuthException>().having(
                (error) => error.type,
                'type',
                AuthExceptionType.incorrectPassword,
              ),
            ),
          );
          expect(auth.metadataUpdates, isEmpty);
          expect(auth.users.single.metadata, user.metadata);
        },
      );

      for (final device in [false, true]) {
        test(
          'late rename authorization cannot cross ${device ? 'device' : 'manual'} lock',
          () async {
            final user = await install();
            backend.pendingRead = Completer<String?>();
            backend.readReached = Completer<void>();
            final renaming = service.renameDisplayName(
              walletId: user.walletId,
              name: 'Savings',
            );
            final rejected = expectLater(renaming, stale());
            await backend.readReached!.future;
            if (device) {
              backend.deviceEvents.add(null);
            } else {
              coordinator.lock();
            }
            backend.pendingRead!.complete(_password);
            await rejected;
            expect(auth.metadataUpdates, isEmpty);
            expect(auth.users.single.metadata, user.metadata);
            expect(coordinator.state.isLocked, isTrue);
            expect(coordinator.operationGate.allowsOperations, isFalse);
          },
        );
      }

      test(
        'revoked service attempt cannot commit after password verification',
        () async {
          final user = await install();
          auth.pendingVerification = Completer<void>();
          auth.verificationReached = Completer<void>();
          final renaming = service.renameDisplayName(
            walletId: user.walletId,
            name: 'Savings',
            password: _password,
          );
          final rejected = expectLater(renaming, stale());
          await auth.verificationReached!.future;
          service.invalidatePendingOperations();
          auth.pendingVerification!.complete();
          await rejected;
          expect(auth.metadataUpdates, isEmpty);
        },
      );

      test(
        'same-name same-seed replacement cannot inherit rename authorization',
        () async {
          final user = await install();
          auth.pendingVerification = Completer<void>();
          auth.verificationReached = Completer<void>();
          final renaming = service.renameDisplayName(
            walletId: user.walletId,
            name: 'Savings',
            password: _password,
          );
          final rejected = expectLater(
            renaming,
            throwsA(isA<AuthSessionChangedException>()),
          );
          await auth.verificationReached!.future;
          final replacement = _user(id: 'replacement-entry');
          auth.users[0] = replacement;
          auth.activate(replacement);
          auth.pendingVerification!.complete();
          await rejected;
          expect(auth.metadataUpdates, isEmpty);
          expect(auth.users.single.metadata, replacement.metadata);
        },
      );

      test('locked wallet rejects settings rename and stays locked', () async {
        final user = await install();
        coordinator.lock();
        final generation = coordinator.authorizationGeneration;
        await expectLater(
          service.renameDisplayName(
            walletId: user.walletId,
            name: 'Savings',
            password: _password,
          ),
          stale(),
        );
        expect(auth.metadataUpdates, isEmpty);
        expect(coordinator.authorizationGeneration, generation);
        expect(coordinator.state.isLocked, isTrue);
        expect(coordinator.operationGate.allowsOperations, isFalse);
      });

      test('missing metadata readback cannot report success', () async {
        final user = await install();
        auth.discardMetadataWrite = true;
        await expectLater(
          service.renameDisplayName(
            walletId: user.walletId,
            name: 'Savings',
            password: _password,
          ),
          failsWith(WalletAccessFailure.storageFailed),
        );
        expect(auth.metadataUpdates, hasLength(1));
        expect(auth.users.single.metadata, user.metadata);
      });

      test(
        'lock before metadata readback rejects completion without reopening',
        () async {
          final user = await install();
          auth.afterMetadataWrite = coordinator.lock;
          await expectLater(
            service.renameDisplayName(
              walletId: user.walletId,
              name: 'Savings',
              password: _password,
            ),
            stale(),
          );
          expect(auth.users.single.wallet.displayName, 'Savings');
          expect(coordinator.state.isLocked, isTrue);
          expect(coordinator.operationGate.allowsOperations, isFalse);
        },
      );
    });

    for (final device in [false, true]) {
      test(
        'late managed unlock cannot cross ${device ? 'device' : 'manual'} lock',
        () async {
          final user = await install();
          backend.pendingRead = Completer<String?>();
          backend.readReached = Completer<void>();
          final signingIn = service.signInManaged(user.wallet);
          final rejected = expectLater(signingIn, stale());
          await backend.readReached!.future;
          if (device) {
            backend.deviceEvents.add(null);
          } else {
            coordinator.lock();
          }
          backend.pendingRead!.complete(_password);
          await rejected;
          expect(coordinator.state.isLocked, isTrue);
          expect(coordinator.operationGate.allowsOperations, isFalse);
        },
      );
    }
    test(
      'late sensitive verification cannot complete after manual lock',
      () async {
        final user = await install();
        auth.pendingVerification = Completer<void>();
        auth.verificationReached = Completer<void>();
        final attempt = service.authorize(
          walletId: user.walletId,
          password: _password,
        );
        final rejected = expectLater(attempt, stale());
        await auth.verificationReached!.future;
        coordinator.lock();
        auth.pendingVerification!.complete();
        await rejected;
      },
    );
    test(
      'manual lock prevents a late enrollment from writing protection',
      () async {
        final user = await install();
        final writes = backend.writes;
        auth.pendingVerification = Completer<void>();
        auth.verificationReached = Completer<void>();
        final enrolling = service.enrollDevice(
          walletId: user.walletId,
          password: _password,
        );
        final rejected = expectLater(enrolling, stale());
        await auth.verificationReached!.future;
        coordinator.lock();
        auth.pendingVerification!.complete();
        await rejected;
        expect(backend.writes, writes);
      },
    );
    test(
      'normal same-wallet engine attachment does not revoke unlock operation',
      () async {
        final user = await install();
        backend.pendingRead = Completer<String?>();
        backend.readReached = Completer<void>();
        final attempt = service.signInManaged(user.wallet);
        await backend.readReached!.future;
        await service.observeEngineUser(user);
        backend.pendingRead!.complete(_password);
        expect(await attempt, user);
        expect(coordinator.operationGate.allowsOperations, isTrue);
      },
    );
    test(
      'external protection locks formerly unattended session before reload',
      () async {
        await install(protected: false);
        expect(coordinator.operationGate.allowsOperations, isTrue);
        backend.infos['gleec.wallet.$_entry'] = const CredentialRecordInfo(
          protection: CredentialProtection.passkey,
          enrolled: true,
        );
        backend.protectionEvents.add(null);
        expect(coordinator.operationGate.allowsOperations, isFalse);
        await Future<void>.delayed(Duration.zero);
        expect(coordinator.state.isLocked, isTrue);
        expect(coordinator.state.requiresAuthentication, isTrue);
      },
    );
    test(
      'same-seed replacement cannot authenticate the old immutable entry',
      () async {
        final user = await install();
        auth.activate(_user(id: 'replacement-entry'));
        await expectLater(
          service.didAuthenticate(user, password: _password),
          stale(),
        );
      },
    );
    test(
      'typed sign-in completion keeps its original authorization generation',
      () async {
        final user = await install();
        final attempt = service.captureAuthenticationAttempt();
        coordinator.lock();
        await expectLater(
          service.didAuthenticate(
            user,
            expectedAttempt: attempt,
            password: _password,
          ),
          stale(),
        );
        expect(coordinator.operationGate.allowsOperations, isFalse);
      },
    );
    for (final invalidated in [false, true]) {
      test(
        'verified password remains usable with ${invalidated ? 'invalidated' : 'missing'} vault',
        () async {
          final user = await install();
          coordinator.lock();
          if (invalidated) {
            backend.metadataFailure = WalletAccessFailure.invalidated;
          } else {
            backend.infos.clear();
            backend.values.clear();
          }
          final attempt = service.captureAuthenticationAttempt();
          await auth.verifyPassword(
            password: _password,
            expectedWalletId: user.walletId,
          );
          await service.didAuthenticate(
            user,
            expectedAttempt: attempt,
            password: _password,
          );
          final status = await service.status();
          expect(coordinator.operationGate.allowsOperations, isTrue);
          expect(status.requiresAuthentication, isTrue);
          expect(status.hasManagedCredential, isFalse);
          final persisted = await storage.read(_recordsKey) as Map;
          expect((persisted[_entry] as Map)['requiresAuthentication'], isTrue);
        },
      );
    }
    test('cancel failure cannot prevent durable explicit sign-out', () async {
      await install();
      backend.failCancel = true;
      await service.signOut();
      expect(await service.automaticEntrySuppressed, isTrue);
      expect(coordinator.state.coversContent, isTrue);
      expect(coordinator.operationGate.allowsOperations, isFalse);
      await service.observeEngineUser(null);
      expect(coordinator.state.hasWallet, isFalse);
    });
    test(
      'superseded sign-out never suppresses a newer verified sign-in',
      () async {
        final user = await install();
        backend.pendingCancel = Completer<void>();
        backend.cancelReached = Completer<void>();
        final signingOut = service.signOut();
        await backend.cancelReached!.future;
        service.invalidatePendingOperations();
        final attempt = service.captureAuthenticationAttempt();
        await service.didAuthenticate(
          user,
          expectedAttempt: attempt,
          password: _password,
        );
        backend.pendingCancel!.complete();
        await signingOut;
        expect(await service.automaticEntrySuppressed, isFalse);
        expect(coordinator.state.coversContent, isFalse);
        expect(coordinator.operationGate.allowsOperations, isTrue);
      },
    );
    test(
      'sign-out covers an unattended wallet until engine shutdown',
      () async {
        await install(protected: false);
        final signingOut = service.signOut();
        expect(coordinator.state.coversContent, isTrue);
        expect(coordinator.operationGate.allowsOperations, isFalse);
        await signingOut;
        expect(coordinator.state.hasWallet, isTrue);
        expect(coordinator.state.coversContent, isTrue);
        expect(await service.unlockCurrent(password: _password), isFalse);
        await service.observeEngineUser(null);
        expect(coordinator.state.hasWallet, isFalse);
        expect(coordinator.state.coversContent, isFalse);
        expect(coordinator.operationGate.allowsOperations, isFalse);
      },
    );
    test(
      'failed sign-out persistence keeps a recoverable locked session',
      () async {
        await install();
        storage.failWrite = 'wallet_access_signed_out_v1';
        await expectLater(
          service.signOut(),
          throwsA(isA<WalletAccessException>()),
        );
        expect(coordinator.state.hasWallet, isTrue);
        expect(coordinator.state.coversContent, isTrue);
        expect(coordinator.operationGate.allowsOperations, isFalse);
        expect(await service.unlockCurrent(password: _password), isTrue);
        expect(coordinator.state.coversContent, isFalse);
        expect(coordinator.operationGate.allowsOperations, isTrue);
      },
    );
    test(
      'failed sign-out recovery restores unattended protection status',
      () async {
        await install(protected: false);
        storage.failWrite = 'wallet_access_signed_out_v1';
        await expectLater(
          service.signOut(),
          throwsA(isA<WalletAccessException>()),
        );
        expect(coordinator.state.coversContent, isTrue);
        expect(await service.unlockCurrent(), isTrue);
        expect(coordinator.state.requiresAuthentication, isFalse);
        expect(coordinator.operationGate.allowsOperations, isTrue);
      },
    );
    test(
      'instant creation avoids canonical and editable display names',
      () async {
        final existing = _user(
          name: 'Gleec Wallet',
          metadata: {'display_name': 'Gleec Wallet 2'},
        );
        auth.users.add(existing);
        final created = await service.createWallet(
          walletType: WalletType.hdwallet,
          initialMetadata: {},
        );
        expect(created.walletId.name, 'Gleec Wallet 3');
        expect(auth.registrations.map((registration) => registration.name), [
          'Gleec Wallet 3',
        ]);
        expect(auth.users.first, existing);
        expect(auth.users.first.wallet.displayName, 'Gleec Wallet 2');
        expect(created.metadata['_wallet_entry_id'], isNot(_entry));
      },
    );
    test(
      'safe name collision retries same credential and entry under a new name',
      () async {
        auth.collideOnce = true;
        final user = await service.createWallet(
          walletType: WalletType.hdwallet,
          initialMetadata: {'has_backup': false},
        );
        expect(auth.registrations.map((e) => e.name), [
          'Gleec Wallet',
          'Gleec Wallet 2',
        ]);
        expect(auth.registrations.map((e) => e.id).toSet(), hasLength(1));
        expect(auth.registrations.map((e) => e.password).toSet(), hasLength(1));
        expect(user.walletId.name, 'Gleec Wallet 2');
        expect(backend.writes, 1);
      },
    );
    test(
      'owned collision preserves pending wallet and never chooses a new name',
      () async {
        auth.ownedCollision = true;
        await expectLater(
          service.createWallet(
            walletType: WalletType.hdwallet,
            initialMetadata: {},
          ),
          throwsA(isA<AuthException>()),
        );
        expect(auth.registrations, hasLength(1));
        expect(
          await storage.read('wallet_access_pending_v1'),
          auth.registrations.single.id,
        );
      },
    );
    test('interrupted creation retries its original ID and password', () async {
      auth.failCreationOnce = true;
      await expectLater(
        service.createWallet(
          walletType: WalletType.hdwallet,
          initialMetadata: {},
        ),
        throwsStateError,
      );
      await service.createWallet(
        walletType: WalletType.hdwallet,
        initialMetadata: {},
      );
      expect(auth.registrations.map((e) => e.id).toSet(), hasLength(1));
      expect(auth.registrations.map((e) => e.password).toSet(), hasLength(1));
      expect(backend.writes, 1);
    });
    for (final key in [
      'wallet_access_last_v1',
      'wallet_access_signed_out_v1',
    ]) {
      test('creation retry retains the wallet after $key fails', () async {
        storage.failWrite = key;
        await expectLater(
          service.createWallet(
            walletType: WalletType.hdwallet,
            initialMetadata: {},
          ),
          throwsA(isA<WalletAccessException>()),
        );
        final original = auth.users.single;
        expect(coordinator.operationGate.allowsOperations, isFalse);
        storage.failWrite = null;
        final resumed = await service.createWallet(
          walletType: WalletType.hdwallet,
          initialMetadata: {},
        );
        expect(
          WalletAccessService.entryId(resumed),
          WalletAccessService.entryId(original),
        );
        expect(auth.users, hasLength(1));
        expect(
          auth.registrations.map((entry) => entry.id).toSet(),
          hasLength(1),
        );
        expect(
          auth.registrations.map((entry) => entry.password).toSet(),
          hasLength(1),
        );
      });
    }
    test(
      'post-commit pending cleanup cannot report a failed creation',
      () async {
        storage.throwAfterPendingDelete = true;
        final user = await service.createWallet(
          walletType: WalletType.hdwallet,
          initialMetadata: {},
        );
        expect(auth.users, [user]);
        expect(coordinator.operationGate.allowsOperations, isTrue);
        expect((await service.lastWallet())?.name, user.walletId.name);
      },
    );
    for (final boundary in [
      'engine commit',
      'encrypted wallet readback',
      'ready before write',
      'ready after write',
      'last after write',
      'signed out after write',
    ]) {
      test(
        'process restart resumes original creation after $boundary',
        () async {
          switch (boundary) {
            case 'engine commit':
              auth.failCreationAfterCommitOnce = true;
            case 'encrypted wallet readback':
              auth.failEncryptedReadOnce = true;
            case 'ready before write':
            case 'ready after write':
              storage.failAfterWrite = boundary == 'ready after write';
              storage.failOneWrite = (key, data) =>
                  key == _recordsKey &&
                  data is Map &&
                  data.values.any(
                    (dynamic value) =>
                        value is Map && value['phase'] == 'ready',
                  );
            case 'last after write':
              storage.failAfterWrite = true;
              storage.failOneWrite = (key, _) => key == 'wallet_access_last_v1';
            case 'signed out after write':
              storage.failAfterWrite = true;
              storage.failOneWrite = (key, _) =>
                  key == 'wallet_access_signed_out_v1';
          }
          await expectLater(
            service.createWallet(
              walletType: WalletType.hdwallet,
              initialMetadata: {},
            ),
            throwsA(isA<WalletAccessException>()),
          );
          final original = auth.users.single;
          await service.dispose();
          auth.active = null;
          auth.sessions.observe(null);
          coordinator = WalletUnlockCoordinator(
            operationGate: WalletOperationGate(),
          );
          service = WalletAccessService(
            sdk: _Sdk(auth),
            storage: storage,
            backend: backend,
            unlockCoordinator: coordinator,
          );
          await service.initialize();
          final resumed = await service.createWallet(
            walletType: WalletType.hdwallet,
            initialMetadata: {},
          );
          expect(
            WalletAccessService.entryId(resumed),
            WalletAccessService.entryId(original),
          );
          expect(auth.users, [original]);
          expect(
            auth.registrations.map((entry) => entry.password).toSet(),
            hasLength(1),
          );
          expect(backend.writes, 1);
          expect(coordinator.operationGate.allowsOperations, isTrue);
        },
      );
    }
    group('password rotation persistence failures', () {
      const replacement = 'Replacement-Secret-6789!';
      for (final boundary in [
        'journal before write',
        'journal after write',
        'engine before change',
        'engine after change',
        'vault before write',
        'vault after write',
        'vault readback',
        'ready before write',
        'ready after write',
        'last wallet',
        'sign out metadata',
      ]) {
        test('restart preserves access after $boundary fails', () async {
          final user = await install();
          bool recordPhase(String key, dynamic data, String phase) =>
              key == _recordsKey &&
              data is Map &&
              data[_entry] is Map &&
              data[_entry]['phase'] == phase;
          switch (boundary) {
            case 'journal before write':
            case 'journal after write':
              storage.failAfterWrite = boundary == 'journal after write';
              storage.failOneWrite = (key, data) =>
                  recordPhase(key, data, 'rotating');
            case 'engine before change':
              auth.failPasswordChange = 'before';
            case 'engine after change':
              auth.failPasswordChange = 'after';
            case 'vault before write':
            case 'vault after write':
              backend.failNextWrite = true;
              backend.failAfterWrite = boundary == 'vault after write';
            case 'vault readback':
              backend.failReadAt = backend.reads + 2;
            case 'ready before write':
            case 'ready after write':
              storage.failAfterWrite = boundary == 'ready after write';
              storage.failOneWrite = (key, data) =>
                  recordPhase(key, data, 'ready');
            case 'last wallet':
              storage.failOneWrite = (key, _) => key == 'wallet_access_last_v1';
            case 'sign out metadata':
              storage.failOneWrite = (key, _) =>
                  key == 'wallet_access_signed_out_v1';
          }
          await expectLater(
            service.changePassword(
              walletId: user.walletId,
              newPassword: replacement,
            ),
            throwsA(
              isA<WalletAccessException>().having(
                (error) => error.failure,
                'failure',
                WalletAccessFailure.storageFailed,
              ),
            ),
          );
          final persisted = jsonEncode(storage.values);
          expect(persisted, isNot(contains(_password)));
          expect(persisted, isNot(contains(replacement)));
          await service.dispose();
          auth.active = null;
          auth.sessions.observe(null);
          coordinator = WalletUnlockCoordinator(
            operationGate: WalletOperationGate(),
          );
          service = WalletAccessService(
            sdk: _Sdk(auth),
            storage: storage,
            backend: backend,
            unlockCoordinator: coordinator,
          );
          await service.initialize();
          if (boundary == 'journal before write') {
            // The failed durable reservation must not change the engine.
            expect(auth.enginePassword, _password);
            await service.signInManaged(user.wallet);
          } else {
            await service.recoverPasswordRotation(user.wallet, replacement);
            await auth.signIn(
              walletName: user.walletId.name,
              password: replacement,
            );
            await service.didAuthenticate(user, password: replacement);
            expect(auth.enginePassword, replacement);
            expect(backend.values['gleec.wallet.$_entry'], replacement);
          }
          expect(auth.users, [user]);
          expect((await service.lastWallet())?.name, user.walletId.name);
          expect(coordinator.operationGate.allowsOperations, isTrue);
        });
      }
    });
    for (final boundary in [
      'vault write',
      'vault readback',
      'metadata write',
    ]) {
      test(
        'enrollment at $boundary failure never restores unattended access',
        () async {
          final user = await install(protected: false);
          if (boundary == 'vault write') {
            backend.failNextWrite = true;
            backend.failAfterWrite = true;
          } else if (boundary == 'vault readback') {
            backend.failReadAt = backend.reads + 2;
          } else {
            storage.failOneWrite = (key, _) => key == _recordsKey;
          }
          await expectLater(
            service.enrollDevice(walletId: user.walletId),
            throwsA(isA<WalletAccessException>()),
          );
          expect(backend.infos['gleec.wallet.$_entry']?.enrolled, isTrue);
          final status = await service.status(walletId: user.walletId);
          expect(status.requiresAuthentication, isTrue);
          expect(status.protection, CredentialProtection.authenticationBound);
          await service.signInManaged(user.wallet);
          expect(auth.users, [user]);
        },
      );
    }
    test(
      'failed credential-record persistence never invokes wallet registration',
      () async {
        storage.failWrite = _recordsKey;
        await expectLater(
          service.createWallet(
            walletType: WalletType.hdwallet,
            initialMetadata: {},
          ),
          throwsA(isA<WalletAccessException>()),
        );
        expect(auth.registrations, isEmpty);
      },
    );
    test(
      'deletion cleanup failure stays journaled and explicit retry completes',
      () async {
        final user = await install();
        await service.credentialForDeletion(user.wallet);
        expect(await service.hasPendingCredentialCleanup, isFalse);
        backend.failDelete = true;
        auth.users.clear();
        auth.active = null;
        await expectLater(
          auth.hooks.single(user.walletId),
          throwsA(isA<WalletAccessException>()),
        );
        expect(coordinator.operationGate.allowsOperations, isFalse);
        await expectLater(
          service.finishDeletion(user.wallet),
          throwsA(isA<WalletAccessException>()),
        );
        expect(await service.hasPendingCredentialCleanup, isTrue);
        backend.failDelete = false;
        await service.retryCredentialCleanup();
        expect(await service.hasPendingCredentialCleanup, isFalse);
        expect(backend.values, isEmpty);
        expect(await storage.read(_recordsKey), isEmpty);
      },
    );
    test(
      'restart cleanup never automatically prompts for protected credentials',
      () async {
        final user = await install();
        await service.credentialForDeletion(user.wallet);
        backend.failDelete = true;
        await expectLater(
          auth.hooks.single(user.walletId),
          throwsA(isA<WalletAccessException>()),
        );
        final preparations = backend.prepares;
        final cleanup = WalletCredentialCleanup(storage, backend);
        await cleanup.resume({});
        expect(backend.prepares, preparations);
        expect(await cleanup.hasPending, isTrue);
      },
    );
  });

  group('wallet display name metadata', () {
    test(
      'round-trip and copies retain display name without changing identity',
      () {
        final original = _user(metadata: {'display_name': 'Savings'}).wallet;
        final configJson = original.config.toJson();
        expect(configJson['display_name'], 'Savings');
        expect(WalletConfig.fromJson(configJson).displayName, 'Savings');
        for (final copied in [
          Wallet.fromJson(original.toJson()),
          original.copy(),
          original.copyWith(),
          original.copyWith(config: original.config.copyWith()),
        ]) {
          expect(copied.displayName, 'Savings');
          expect(copied.config.displayName, 'Savings');
          expect(copied.name, original.name);
          expect(copied.id, original.id);
          expect(copied.config.pubKey, original.config.pubKey);
          expect(copied.config.type, original.config.type);
        }
        final edited = original.config.copyWith(displayName: 'Travel');
        expect(edited.displayName, 'Travel');
        expect(original.config.displayName, 'Savings');
      },
    );

    test('legacy and blank display names fall back to the canonical name', () {
      for (final value in [null, '', '   ']) {
        final wallet = Wallet.fromJson({
          'id': 'original-id',
          'name': 'Canonical wallet',
          'config': {if (value != null) 'display_name': value},
        });
        expect(wallet.displayName, 'Canonical wallet');
        expect(wallet.copy().displayName, 'Canonical wallet');
        expect(wallet.copyWith().displayName, 'Canonical wallet');
        expect(
          Wallet.fromJson(wallet.toJson()).displayName,
          'Canonical wallet',
        );
      }
    });

    test(
      'SDK metadata maps a trimmed label without replacing engine identity',
      () {
        final user = _user(metadata: {'display_name': '  Everyday  '});
        final wallet = user.wallet;
        expect(wallet.displayName, 'Everyday');
        expect(wallet.name, user.walletId.name);
        expect(wallet.id, user.walletId.name);
        expect(wallet.config.pubKey, user.walletId.pubkeyHash);
        expect(wallet.config.displayName, '  Everyday  ');
        for (final invalid in [null, 7, <String, dynamic>{}]) {
          expect(
            _user(metadata: {'display_name': invalid}).wallet.displayName,
            'Wallet',
          );
        }
      },
    );
  });
}

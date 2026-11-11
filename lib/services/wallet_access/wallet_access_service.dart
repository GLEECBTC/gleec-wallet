import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:uuid/uuid.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/storage/base_storage.dart';

import 'password_rotation_envelope.dart';
import 'platform/credential_backend.dart';
import 'platform/credential_backend_factory.dart';
import 'unlock_coordinator.dart';
import 'wallet_access_lock.dart';
import 'wallet_access_record.dart';
import 'wallet_access_types.dart';
import 'wallet_credential_cleanup.dart';

export 'wallet_access_types.dart';

/// Coordinates the wallet engine, credential vault and non-secret journal.
/// The engine session remains independent of the app's interaction lock.
class WalletAccessService {
  WalletAccessService({
    required KomodoDefiSdk sdk,
    required BaseStorage storage,
    CredentialBackend? backend,
    WalletUnlockCoordinator? unlockCoordinator,
    Duration Function()? monotonicNow,
  }) : _sdk = sdk,
       _storage = storage,
       _backend = backend ?? createCredentialBackend(),
       _monotonicNow = monotonicNow ?? _createMonotonicClock(),
       unlockCoordinator = unlockCoordinator ?? WalletUnlockCoordinator() {
    _cleanup = WalletCredentialCleanup(_storage, _backend);
    _deviceLockSubscription = _backend.deviceLocked.listen((_) {
      this.unlockCoordinator.deviceLocked();
      _cleanup.revokeAuthorizations();
      unawaited(_backend.cancel().catchError((Object _) {}));
    });
    _protectionSubscription = _backend.protectionChanged.listen((_) {
      _revision++;
      this.unlockCoordinator.protectionChanged();
      _cleanup.revokeAuthorizations();
      unawaited(_backend.cancel().catchError((Object _) {}));
      unawaited(_reloadProtection().catchError((Object _) {}));
      _changes.add(null);
    });
    _sdk.auth.onWalletDeletion(_onDeleted);
  }

  static const deviceEnrollmentEnabled = bool.fromEnvironment(
    'WALLET_DEVICE_ENROLLMENT_ENABLED',
    defaultValue: true,
  );
  static const passkeyEnrollmentEnabled = bool.fromEnvironment(
    'WALLET_PASSKEY_ENROLLMENT_ENABLED',
    defaultValue: true,
  );
  static const immediateLockRequired = bool.fromEnvironment(
    'WALLET_IMMEDIATE_LOCK_REQUIRED',
  );
  static const _recordsKey = 'wallet_access_records_v1';
  static const _pendingKey = 'wallet_access_pending_v1';
  static const _lastKey = 'wallet_access_last_v1';
  static const _signedOutKey = 'wallet_access_signed_out_v1';
  static const _graceKey = 'wallet_access_grace_seconds_v1';
  final KomodoDefiSdk _sdk;
  final BaseStorage _storage;
  final CredentialBackend _backend;
  final Duration Function() _monotonicNow;
  late final WalletCredentialCleanup _cleanup;
  final WalletUnlockCoordinator unlockCoordinator;
  final _changes = StreamController<void>.broadcast();
  late final StreamSubscription<void> _deviceLockSubscription;
  late final StreamSubscription<void> _protectionSubscription;
  final Object _operationOwner = Object();
  int _revision = 0;
  final _preparedDeletionIds = <String, String>{};
  final _preparedDeletionScopes = <String, _PreparedDeletionAuthorization>{};
  final _deletedEntryIds = <String, Set<String>>{};
  final _passwordOnlyEntries = <String>{};
  final _completedProvisioning = <String>{};
  KdfUser? _sessionUser;
  bool _signOutPending = false;
  int? _signOutOwner;
  bool _recoveringFailedSignOut = false;
  Object? _sessionIdentity;
  Stream<void> get changes => _changes.stream;

  Future<void> initialize() async {
    final grace = await _storage.read(_graceKey);
    unlockCoordinator.setBackgroundGrace(
      immediateLockRequired || grace == 0
          ? Duration.zero
          : const Duration(seconds: 30),
    );
    unlockCoordinator.operationGate.attachWallet(null);
    if (await _cleanup.hasIntents) {
      final users = await _sdk.auth.getUsers();
      await _cleanup.resume(users.map(entryId).toSet());
    }
  }

  Future<CredentialCapabilities> capabilities() async {
    final actual = await _backend.capabilities();
    return CredentialCapabilities(
      available: actual.available,
      protection: actual.protection,
      deviceAuthentication:
          deviceEnrollmentEnabled && actual.deviceAuthentication,
      passkeyCandidate: passkeyEnrollmentEnabled && actual.passkeyCandidate,
    );
  }

  Future<void> setBackgroundGrace(Duration duration) async {
    final seconds = immediateLockRequired || duration == Duration.zero ? 0 : 30;
    await _writeChecked(_graceKey, seconds);
    unlockCoordinator.setBackgroundGrace(Duration(seconds: seconds));
    _changes.add(null);
  }

  static String entryId(KdfUser user) {
    final id = user.metadata['_wallet_entry_id'];
    if (id is String && id.isNotEmpty) return id;
    // Compatibility only; SDK catalog migrations establish real entry IDs.
    return 'legacy-${sha256.convert(utf8.encode(jsonEncode(user.walletId.toJson())))}';
  }

  Future<Map<String, WalletAccessRecord>> _records() async {
    final raw = await _storage.read(_recordsKey);
    if (raw == null) return {};
    final map = raw is String ? jsonDecode(raw) : raw;
    if (map is! Map) {
      throw const WalletAccessException(WalletAccessFailure.invalidResponse);
    }
    return map.map(
      (key, value) => MapEntry(
        key as String,
        WalletAccessRecord.fromJson(Map<String, dynamic>.from(value as Map)),
      ),
    );
  }

  Future<void> _saveRecord(WalletAccessRecord record) =>
      withWalletAccessRecordLock(() async {
        final records = await _records();
        records[record.entryId] = record;
        await _writeChecked(
          _recordsKey,
          records.map((key, value) => MapEntry(key, value.toJson())),
        );
        _changes.add(null);
      });

  Future<void> _writeChecked(String key, Object value) async {
    if (!await _storage.write(key, value) ||
        jsonEncode(await _storage.read(key)) != jsonEncode(value)) {
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
  }

  Future<KdfUser> _resolve(WalletId walletId) async {
    final users = await _sdk.auth.getUsers();
    for (final user in users) {
      if (user.walletId == walletId) return user;
    }
    throw const WalletAccessException(WalletAccessFailure.walletUnavailable);
  }

  Future<KdfUser> _resolveWallet(Wallet wallet) async {
    final users = await _sdk.auth.getUsers();
    for (final user in users) {
      if (user.walletId.name == wallet.name &&
          user.walletId.isHd == (wallet.config.type == WalletType.hdwallet) &&
          (wallet.config.pubKey == null ||
              wallet.config.pubKey == user.walletId.pubkeyHash)) {
        return user;
      }
    }
    throw const WalletAccessException(WalletAccessFailure.walletUnavailable);
  }

  Future<WalletAccessStatus> statusForWallet(Wallet wallet) async =>
      _status(await _resolveWallet(wallet));
  Future<WalletAccessStatus> status({WalletId? walletId}) async {
    final user = walletId == null
        ? await _sdk.auth.currentUser
        : await _resolve(walletId);
    if (user == null) {
      throw const WalletAccessException(WalletAccessFailure.walletUnavailable);
    }
    return _status(user);
  }

  Future<WalletAccessStatus> _status(KdfUser user) async {
    final id = entryId(user);
    final record = (await _records())[id];
    if (record == null) {
      return WalletAccessStatus(
        entryId: id,
        protection: CredentialProtection.password,
        hasManagedCredential: false,
        requiresAuthentication: !user.wallet.isHW,
      );
    }
    if (record.pubkeyHash != null &&
        record.pubkeyHash != user.walletId.pubkeyHash) {
      throw const WalletAccessException(WalletAccessFailure.invalidResponse);
    }
    // A pending password change always needs explicit input, never autologin.
    if (record.rotationEnvelope != null) {
      return WalletAccessStatus(
        entryId: id,
        protection: CredentialProtection.password,
        hasManagedCredential: false,
        requiresAuthentication: true,
        passwordManager: record.manager,
      );
    }
    CredentialRecordInfo? actual;
    try {
      actual = record.managed
          ? await _backend.metadata(record.credentialKey)
          : null;
    } on WalletAccessException {
      if (!_passwordOnlyEntries.contains(id)) rethrow;
      return _passwordFallbackStatus(record);
    }
    if (_passwordOnlyEntries.contains(id) &&
        record.managed &&
        (actual == null ||
            (record.requiresAuthentication && !actual.enrolled))) {
      return _passwordFallbackStatus(record);
    }
    if (record.managed && actual == null) {
      throw const WalletAccessException(WalletAccessFailure.missingCredential);
    }
    if (record.requiresAuthentication && actual != null && !actual.enrolled) {
      throw const WalletAccessException(WalletAccessFailure.invalidated);
    }
    return WalletAccessStatus(
      entryId: id,
      protection: actual?.protection ?? record.protection,
      hasManagedCredential: record.managed,
      requiresAuthentication:
          record.requiresAuthentication || (actual?.enrolled ?? false),
      generatedPassword: record.generated,
      passwordManager: record.manager,
    );
  }

  WalletAccessStatus _passwordFallbackStatus(WalletAccessRecord record) =>
      WalletAccessStatus(
        entryId: record.entryId,
        protection: record.protection,
        hasManagedCredential: false,
        requiresAuthentication: true,
        generatedPassword: record.generated,
        passwordManager: record.manager,
      );

  /// One pending operation survives process death. No seed is generated here:
  /// the SDK reserves the ID and safely resumes its persisted engine wallet.
  Future<KdfUser> createWallet({
    required WalletType walletType,
    required Map<String, dynamic> initialMetadata,
    bool useDeviceProtection = true,
  }) => _runAccessOperation((revision) async {
    var pending = await _storage.read(_pendingKey);
    if (pending is String && _completedProvisioning.contains(pending)) {
      if (!await _clearCompletedProvisioning(pending)) {
        throw const WalletAccessException(WalletAccessFailure.storageFailed);
      }
      pending = null;
    }
    final records = await _records();
    WalletAccessRecord? record = pending is String ? records[pending] : null;
    if (pending != null && record == null) {
      throw const WalletAccessException(WalletAccessFailure.invalidResponse);
    }
    String password;
    if (record == null) {
      final users = await _sdk.auth.getUsers();
      final name = _nextWalletName(users);
      final id = const Uuid().v4();
      final capability = await _backend.capabilities();
      if (!capability.available) {
        throw const WalletAccessException(WalletAccessFailure.unavailable);
      }
      password = SecurityUtils.generatePasswordSecure(32);
      var protected =
          deviceEnrollmentEnabled &&
          useDeviceProtection &&
          capability.deviceAuthentication;
      final key = 'gleec.wallet.$id';
      _ensureRevision(revision);
      try {
        await unlockCoordinator.runSystemPrompt(
          () => _backend.write(key, password, requireAuthentication: protected),
        );
        if (await unlockCoordinator.runSystemPrompt(
              () => _backend.read(
                key,
                reason: 'Confirm wallet protection',
                purpose: 'verifyWrite',
                requireAuthentication: protected,
              ),
            ) !=
            password) {
          throw const WalletAccessException(WalletAccessFailure.storageFailed);
        }
      } on WalletAccessException catch (error) {
        _ensureRevision(revision);
        if (!protected || error.failure != WalletAccessFailure.canceled) {
          rethrow;
        }
        // This is an explicitly new wallet with no previous protection.
        // Cancellation never downgrades a persisted/protected wallet.
        // Nothing has been registered with KDF yet. Remove only this new
        // scratch item before honoring the choice to set protection later.
        await _backend.delete(key);
        if (await _backend.metadata(key) != null) rethrow;
        protected = false;
        await _backend.write(key, password, requireAuthentication: false);
        if (await _backend.read(key, reason: 'Confirm wallet storage') !=
            password) {
          throw const WalletAccessException(WalletAccessFailure.storageFailed);
        }
      }
      final info = await _backend.metadata(key);
      if (info == null) {
        throw const WalletAccessException(WalletAccessFailure.storageFailed);
      }
      record = WalletAccessRecord(
        entryId: id,
        walletName: name,
        isHd: walletType == WalletType.hdwallet,
        protection: info.protection,
        requiresAuthentication: info.enrolled,
      );
      await _saveRecord(record);
      await _writeChecked(_pendingKey, id);
    } else {
      password = await _readManaged(
        record,
        reason: 'Continue creating your wallet',
        revision: revision,
      );
    }
    _ensureRevision(revision);
    KdfUser? created;
    final attemptedNames = <String>{};
    while (created == null) {
      _ensureRevision(revision);
      attemptedNames.add(record!.walletName);
      try {
        created = await _sdk.auth.register(
          walletName: record.walletName,
          password: password,
          provisioningId: record.entryId,
          options: AuthOptions(
            derivationMethod: record.isHd
                ? DerivationMethod.hdWallet
                : DerivationMethod.iguana,
          ),
          initialMetadata: {
            ...initialMetadata,
            'type': record.isHd
                ? WalletType.hdwallet.name
                : WalletType.iguana.name,
          },
        );
      } on AuthException catch (error) {
        if (error.type != AuthExceptionType.walletAlreadyExists ||
            error.details?['canRetryWithDifferentName'] != true ||
            attemptedNames.length >= 100) {
          rethrow;
        }
        // SDK has proven this operation never owned a wallet at this name.
        // Keep its credential/ID; only reserve another collision-safe label.
        final users = await _sdk.auth.getUsers();
        final name = _nextWalletName(users, attemptedNames: attemptedNames);
        _ensureRevision(revision);
        record = record.copyWith(walletName: name);
        await _saveRecord(record);
      }
    }
    final user = created;
    final completedRecord = record!;
    _ensureRevision(revision);
    if (entryId(user) != completedRecord.entryId ||
        !user.walletId.hasFullIdentity) {
      throw const WalletAccessException(WalletAccessFailure.invalidResponse);
    }
    await _sdk.auth.verifyPassword(
      password: password,
      expectedWalletId: user.walletId,
    );
    final encrypted = await _sdk.auth.getMnemonicEncrypted();
    if (encrypted.isEncrypted != true) {
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
    await _saveRecord(
      completedRecord.copyWith(
        phase: 'ready',
        pubkeyHash: user.walletId.pubkeyHash,
      ),
    );
    await _didAuthenticate(user, expectedRevision: revision);
    // Last-wallet and sign-out metadata are part of the commit. Keep the
    // resume journal until they are durable: a reported failure must resume
    // this same wallet. Cleanup after publication cannot turn success into an
    // error, even if a storage adapter throws after actually deleting the key.
    await _clearCompletedProvisioning(completedRecord.entryId);
    return user;
  });

  Future<bool> _clearCompletedProvisioning(String id) async {
    try {
      final pending = await _storage.read(_pendingKey);
      if (pending != id) return pending == null;
      await _storage.delete(_pendingKey);
      return await _storage.read(_pendingKey) == null;
    } on Object {
      // The wallet is already committed; retain/retry this non-secret cleanup.
      return false;
    }
  }

  Future<String> _readManaged(
    WalletAccessRecord record, {
    required String reason,
    required _AccessRevision revision,
    bool automatic = false,
    String? purpose,
    bool waitForForeground = false,
    String? expectedCredential,
  }) async {
    _ensureRevision(revision);
    final sensitive = waitForForeground || purpose == 'delete';
    final promptGeneration = unlockCoordinator.operationGate.generation;
    if (sensitive) _ensureSensitiveForeground();
    final actual = await _backend.metadata(record.credentialKey);
    if (actual == null) {
      throw const WalletAccessException(WalletAccessFailure.missingCredential);
    }
    if (record.requiresAuthentication && !actual.enrolled) {
      throw const WalletAccessException(WalletAccessFailure.invalidated);
    }
    _ensureRevision(revision);
    final value = await unlockCoordinator.runSystemPrompt(
      () async {
        _ensureRevision(revision);
        if (sensitive) {
          _ensureSensitiveForeground();
          if (promptGeneration != unlockCoordinator.operationGate.generation) {
            throw const WalletAccessException(
              WalletAccessFailure.staleOperation,
            );
          }
        }
        final value = await _backend.read(
          record.credentialKey,
          reason: reason,
          requireAuthentication:
              record.requiresAuthentication || actual.enrolled,
          automatic: automatic,
          purpose: purpose,
        );
        if (value == null || value.isEmpty) {
          throw const WalletAccessException(
            WalletAccessFailure.missingCredential,
          );
        }
        if (expectedCredential != null && value != expectedCredential) {
          throw const WalletAccessException(WalletAccessFailure.storageFailed);
        }
        return value;
      },
      waitForForeground:
          (waitForForeground || purpose == 'delete') && actual.enrolled,
    );
    _ensureRevision(revision);
    return value;
  }

  Future<KdfUser> signInManaged(
    Wallet wallet, {
    bool automatic = false,
  }) => _runAccessOperation((revision) async {
    final user = await _resolveWallet(wallet);
    final record = (await _records())[entryId(user)];
    if (record == null || !record.managed || record.rotationEnvelope != null) {
      throw const WalletAccessException(WalletAccessFailure.missingCredential);
    }
    final password = await _readManaged(
      record,
      reason: 'Unlock your wallet',
      automatic: automatic,
      revision: revision,
    );
    _ensureRevision(revision);
    final signedIn = await _sdk.auth.signIn(
      walletName: user.walletId.name,
      password: password,
      options: user.walletId.authOptions,
    );
    await _sdk.auth.verifyPassword(
      password: password,
      expectedWalletId: signedIn.walletId,
    );
    _ensureRevision(revision);
    if (entryId(signedIn) != record.entryId ||
        signedIn.walletId != user.walletId) {
      throw const WalletAccessException(WalletAccessFailure.staleOperation);
    }
    await _didAuthenticate(signedIn, expectedRevision: revision);
    return signedIn;
  });

  Future<String> authorize({
    required WalletId walletId,
    String? password,
    String reason = 'Unlock your wallet',
  }) => _runAccessOperation(
    (revision) => _authorize(
      walletId,
      password: password,
      reason: reason,
      revision: revision,
    ),
  );

  String _nextWalletName(
    Iterable<KdfUser> users, {
    Iterable<String> attemptedNames = const [],
  }) {
    final names = {
      ...attemptedNames.map((name) => name.toLowerCase()),
      for (final user in users) user.walletId.name.toLowerCase(),
      for (final user in users) user.wallet.displayName.toLowerCase(),
    };
    var name = 'Gleec Wallet';
    for (var suffix = 2; names.contains(name.toLowerCase()); suffix++) {
      name = 'Gleec Wallet $suffix';
    }
    return name;
  }

  /// Changes presentation metadata without renaming the catalog entry or its
  /// credential binding. Authorization never refreshes the app unlock lease.
  Future<void> renameDisplayName({
    required WalletId walletId,
    required String name,
    String? password,
  }) => _runAccessOperation((revision) async {
    final label = name.trim();
    if (label.isEmpty ||
        label.runes.length > 64 ||
        RegExp(r'[\x00-\x1f\x7f-\x9f\u2028\u2029]').hasMatch(label)) {
      throw const WalletAccessException(WalletAccessFailure.invalidName);
    }
    final user = await _resolve(walletId);
    final session = await _sdk.auth.captureSessionContext();
    await _ensureUserCurrent(user, session, revision);
    final users = await _sdk.auth.getUsers();
    if (users.any(
      (other) =>
          entryId(other) != entryId(user) &&
          other.wallet.displayName.toLowerCase() == label.toLowerCase(),
    )) {
      throw const WalletAccessException(WalletAccessFailure.nameAlreadyUsed);
    }
    await _authorize(
      walletId,
      password: password,
      reason: 'Rename this wallet',
      revision: revision,
    );
    final ensureCurrent = captureSensitiveOperation(walletId);
    await _ensureUserCurrent(user, session, revision);
    ensureCurrent();
    await _sdk.auth.updateMetadataForSession(session, {'display_name': label});
    await _ensureUserCurrent(user, session, revision);
    ensureCurrent();
    final persisted = await _resolve(walletId);
    await _ensureUserCurrent(user, session, revision);
    if (entryId(persisted) != entryId(user) ||
        persisted.metadata['display_name'] != label) {
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
    _changes.add(null);
  });

  Future<String> _authorize(
    WalletId walletId, {
    String? password,
    required String reason,
    required _AccessRevision revision,
    bool forUnlock = false,
  }) async {
    _ensureRevision(revision);
    if (!forUnlock) _ensureSensitiveForeground();
    final ensurePreparationCurrent = forUnlock
        ? null
        : captureSensitiveOperation(walletId);
    final user = await _resolve(walletId);
    final session = await _sdk.auth.captureSessionContext();
    await _ensureUserCurrent(user, session, revision);
    if (password == null) {
      final record = (await _records())[entryId(user)];
      if (record == null ||
          !record.managed ||
          record.rotationEnvelope != null) {
        throw const WalletAccessException(
          WalletAccessFailure.missingCredential,
        );
      }
      ensurePreparationCurrent?.call();
      password = await _readManaged(
        record,
        reason: reason,
        revision: revision,
        waitForForeground: !forUnlock,
      );
    } else {
      ensurePreparationCurrent?.call();
    }
    _ensureRevision(revision);
    final ensureCurrent = forUnlock
        ? null
        : captureSensitiveOperation(walletId);
    Future<void> verify() => _sdk.auth.verifyPassword(
      password: password!,
      expectedWalletId: walletId,
      expectedSession: session,
    );
    if (ensureCurrent == null) {
      await verify();
    } else {
      await RpcDispatchGuard.run(
        ensureCurrent,
        verify,
        methods: const {'get_mnemonic'},
      );
      ensureCurrent();
    }
    await _ensureUserCurrent(user, session, revision);
    ensureCurrent?.call();
    return password;
  }

  void _ensureSensitiveForeground() {
    final state = unlockCoordinator.state;
    if (!state.isForeground || state.isLocked) {
      throw const WalletAccessException(WalletAccessFailure.staleOperation);
    }
  }

  /// Capture after successful authorization, before asynchronous sensitive work.
  /// Inactivity revokes this permit even if the same engine session survives.
  /// A new native ceremony needs its own verified foreground return and permit.
  void Function() captureSensitiveOperation(WalletId walletId) {
    _ensureSensitiveForeground();
    final user = _sessionUser;
    if (user == null || user.walletId != walletId) {
      throw const WalletAccessException(WalletAccessFailure.staleOperation);
    }
    final revision = _captureRevision();
    final permit = unlockCoordinator.operationGate.capture(
      expectedWalletEntryId: entryId(user),
    );
    void ensureCurrent() {
      _ensureRevision(revision);
      _ensureSensitiveForeground();
      permit.ensureCurrent();
    }

    return ensureCurrent;
  }

  /// Binds one export destination dialog to the already authorized wallet.
  /// The file chooser never unlocks the app. A grace/immediate lock may be
  /// satisfied by one fresh configured unlock; explicit locks/switches cancel.
  Future<SensitiveExportAuthorization> captureSensitiveExport(
    WalletId walletId,
  ) async {
    var validateWrite = captureSensitiveOperation(walletId);
    final revision = _captureRevision();
    final generation = unlockCoordinator.state.generation;
    final identity = _sessionIdentity;
    var selected = false;
    final session = await _sdk.auth.captureSessionContext();
    if (session.walletId != walletId) {
      throw const WalletAccessException(WalletAccessFailure.staleOperation);
    }
    void validateScope() {
      _ensureRevision(revision);
      if (generation != unlockCoordinator.state.generation ||
          !identical(identity, _sessionIdentity) ||
          _sessionUser?.walletId != walletId) {
        throw const WalletAccessException(WalletAccessFailure.staleOperation);
      }
      _sdk.auth.ensureSessionContextCurrent(session);
    }

    void ensureCurrent() {
      validateScope();
      validateWrite();
    }

    ensureCurrent();
    return SensitiveExportAuthorization._(
      ensureCurrent: ensureCurrent,
      selectDestination: (select) async {
        ensureCurrent();
        if (selected) {
          throw const WalletAccessException(WalletAccessFailure.staleOperation);
        }
        selected = true;
        final destination = await unlockCoordinator
            .runSystemDialogAwaitingForeground(select);
        validateScope();
        if (destination == null) return null;
        if (unlockCoordinator.state.isLocked) {
          final access = await status(walletId: walletId);
          validateScope();
          if (access.hasManagedCredential) {
            if (!await unlockCurrent()) {
              throw const WalletAccessException(
                WalletAccessFailure.staleOperation,
              );
            }
            validateScope();
            await unlockCoordinator.awaitVerifiedUnlockForeground();
          } else {
            // The regular lock screen supplies the user's chosen password.
            // Keep the destination private until that explicit unlock succeeds.
            await _awaitExplicitExportUnlock(validateScope);
          }
          validateScope();
        }
        validateWrite = captureSensitiveOperation(walletId);
        ensureCurrent();
        return destination;
      },
    );
  }

  Future<void> _awaitExplicitExportUnlock(void Function() validateScope) async {
    final deadline = _monotonicNow() + const Duration(minutes: 2);
    final completed = Completer<void>();
    void check() {
      if (completed.isCompleted) return;
      try {
        validateScope();
        if (_monotonicNow() >= deadline) {
          throw const WalletAccessException(WalletAccessFailure.staleOperation);
        }
        final state = unlockCoordinator.state;
        if (state.isForeground && !state.isLocked) completed.complete();
      } catch (error, trace) {
        completed.completeError(error, trace);
      }
    }

    final subscription = unlockCoordinator.changes.listen(
      (_) => check(),
      onDone: () {
        if (!completed.isCompleted) {
          completed.completeError(
            const WalletAccessException(WalletAccessFailure.staleOperation),
          );
        }
      },
    );
    try {
      check();
      await completed.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () {
          throw const WalletAccessException(WalletAccessFailure.staleOperation);
        },
      );
    } finally {
      await subscription.cancel();
    }
  }

  Future<String> credentialForDeletion(Wallet wallet, {String? password}) =>
      _runAccessOperation((revision) async {
        final user = await _resolveWallet(wallet);
        final record = (await _records())[entryId(user)];
        var value = password;
        if (value == null) {
          if (record == null ||
              !record.managed ||
              record.rotationEnvelope != null) {
            throw const WalletAccessException(
              WalletAccessFailure.missingCredential,
            );
          }
          value = await _readManaged(
            record,
            reason: 'Remove this wallet from this device',
            revision: revision,
            purpose: 'delete',
          );
        }
        _ensureRevision(revision);
        if (entryId(await _resolveWallet(wallet)) != entryId(user)) {
          throw const WalletAccessException(WalletAccessFailure.staleOperation);
        }
        final preparationStartedAt = _monotonicNow();
        if (record != null) {
          _ensureRevision(revision);
          String? token;
          final actual = record.managed && password != null
              ? await _backend.metadata(record.credentialKey)
              : null;
          if (actual?.protection == CredentialProtection.passkey) {
            // A lost provider need not prevent removal after genuine password
            // proof. Verification is for the active wallet only: never switch
            // the engine silently to authorize deletion of another entry.
            final current = await _sdk.auth.currentUser;
            if (current == null ||
                entryId(current) != entryId(user) ||
                current.walletId != user.walletId) {
              throw const WalletAccessException(
                WalletAccessFailure.walletMustBeUnlocked,
              );
            }
            final session = await _sdk.auth.captureSessionContext();
            await _authorize(
              user.walletId,
              password: value,
              reason: 'Remove this wallet from this device',
              revision: revision,
            );
            await _ensureUserCurrent(user, session, revision);
            token = await _backend.prepareDeleteAfterPasswordVerification(
              record.credentialKey,
              expectedRevision: actual!.revision,
            );
            await _ensureUserCurrent(user, session, revision);
          } else if (record.managed) {
            final requiresAuthentication =
                record.requiresAuthentication || actual?.enrolled == true;
            token = await unlockCoordinator.runSystemPrompt(() async {
              final token = await _backend.prepareDelete(
                record.credentialKey,
                reason: 'Remove this wallet from this device',
              );
              if (token == null && requiresAuthentication) {
                throw const WalletAccessException(
                  WalletAccessFailure.invalidResponse,
                );
              }
              return token;
            }, waitForForeground: requiresAuthentication);
          }
          _ensureRevision(revision);
          await _cleanup.prepare(
            record.copyWith(
              walletName: user.walletId.name,
              pubkeyHash: user.walletId.pubkeyHash,
            ),
            token,
          );
        }
        _ensureRevision(revision);
        final id = entryId(user);
        _preparedDeletionIds[jsonEncode([
              user.walletId.name,
              user.walletId.pubkeyHash,
            ])] =
            id;
        _preparedDeletionScopes[id] = _PreparedDeletionAuthorization(
          revision,
          unlockCoordinator.state.generation,
          preparationStartedAt + const Duration(seconds: 60),
        );
        return value;
      });

  /// Carries the just-prepared proof to SDK pre-stop and RPC dispatch checks.
  /// Capturing another proof, locking, switching or backgrounding revokes it.
  /// A reviewed deletion may stop the engine, but must not renew this lease.
  void Function() deletionAuthorizationValidator(Wallet wallet) {
    final identity = jsonEncode([wallet.name, wallet.config.pubKey]);
    final id = _preparedDeletionIds[identity];
    final prepared = _preparedDeletionScopes[id];
    void ensureCurrent() {
      final state = unlockCoordinator.state;
      if (id == null ||
          prepared == null ||
          _preparedDeletionIds[identity] != id ||
          !identical(_preparedDeletionScopes[id], prepared) ||
          !_isRevisionCurrent(prepared.revision) ||
          state.generation != prepared.unlockGeneration ||
          !state.isForeground ||
          (state.hasWallet && state.isLocked) ||
          _monotonicNow() >= prepared.expiresAt) {
        throw const WalletAccessException(WalletAccessFailure.staleOperation);
      }
    }

    ensureCurrent();
    return ensureCurrent;
  }

  /// Repository calls this after SDK deletion. SDK hooks are best-effort;
  /// residual credentials must instead leave a visible, retryable failure.
  Future<void> finishDeletion(Wallet wallet) async {
    final identity = jsonEncode([wallet.name, wallet.config.pubKey]);
    final deletedIds = _deletedEntryIds[identity]?.toSet() ?? <String>{};
    if (deletedIds.isEmpty) {
      // Without an in-process deletion snapshot, only already-completed
      // journal intents are eligible. Never discover a new same-name entry.
      await _cleanup.complete(wallet.name, wallet.config.pubKey);
    }
    for (final id in deletedIds) {
      await _cleanup.complete(
        wallet.name,
        wallet.config.pubKey,
        expectedEntryId: id,
      );
      _deletedEntryIds[identity]?.remove(id);
      if (_preparedDeletionIds[identity] == id) {
        _preparedDeletionIds.remove(identity);
      }
      _preparedDeletionScopes.remove(id);
    }
    _changes.add(null);
  }

  Future<bool> get hasPendingCredentialCleanup => _cleanup.hasPending;

  Future<void> retryCredentialCleanup() =>
      _runAccessOperation((revision) async {
        await _cleanup.retry(
          (key) => unlockCoordinator.runSystemPrompt(() {
            _ensureRevision(revision);
            return _backend.prepareDelete(
              key,
              reason: 'Finish removing wallet access',
            );
          }),
        );
        _changes.add(null);
      });

  Object captureAuthenticationAttempt() => _captureRevision();

  Future<void> didAuthenticate(
    KdfUser user, {
    Object? expectedAttempt,
    String? password,
  }) {
    if (expectedAttempt != null && expectedAttempt is! _AccessRevision) {
      throw const WalletAccessException(WalletAccessFailure.invalidResponse);
    }
    final revision = expectedAttempt as _AccessRevision? ?? _captureRevision();
    return withWalletAccessLock(() async {
      _ensureRevision(revision);
      final session = await _sdk.auth.captureSessionContext();
      await _ensureUserCurrent(user, session, revision);
      if (password == null && !user.wallet.isHW) {
        throw const WalletAccessException(
          WalletAccessFailure.missingCredential,
        );
      }
      if (password != null) {
        await _sdk.auth.verifyPassword(
          password: password,
          expectedWalletId: user.walletId,
          expectedSession: session,
        );
        await _ensureUserCurrent(user, session, revision);
      }
      await _didAuthenticate(
        user,
        expectedRevision: revision,
        passwordVerified: password != null,
      );
    });
  }

  Future<void> _didAuthenticate(
    KdfUser user, {
    required _AccessRevision expectedRevision,
    bool passwordVerified = false,
    void Function()? ensureAuthorized,
  }) async {
    ensureAuthorized?.call();
    _ensureRevision(expectedRevision);
    final session = await _sdk.auth.captureSessionContext();
    await _ensureUserCurrent(user, session, expectedRevision);
    if (passwordVerified) _passwordOnlyEntries.add(entryId(user));
    final status = await _status(user);
    ensureAuthorized?.call();
    _ensureRevision(expectedRevision);
    _sdk.auth.ensureSessionContextCurrent(session);
    await _writeChecked(_lastKey, {
      'entryId': entryId(user),
      'walletId': user.walletId.toJson(),
    });
    ensureAuthorized?.call();
    _ensureRevision(expectedRevision);
    _sdk.auth.ensureSessionContextCurrent(session);
    await _writeChecked(_signedOutKey, false);
    ensureAuthorized?.call();
    _ensureRevision(expectedRevision);
    _sdk.auth.ensureSessionContextCurrent(session);
    _sessionUser = user;
    _signOutPending = false;
    _signOutOwner = null;
    _recoveringFailedSignOut = false;
    _sessionIdentity = Object();
    unlockCoordinator.attachWallet(
      entryId(user),
      requiresAuthentication: status.requiresAuthentication,
      authenticated: true,
      sessionIdentity: _sessionIdentity,
    );
    _completedProvisioning.add(entryId(user));
  }

  /// SDK lifecycle repair must never renew an existing app unlock lease.
  Future<void> observeEngineUser(KdfUser? user) async {
    if (user == null) {
      _sessionUser = null;
      _sessionIdentity = null;
      _signOutPending = false;
      _signOutOwner = null;
      _recoveringFailedSignOut = false;
      _passwordOnlyEntries.clear();
      unlockCoordinator.attachWallet(null, requiresAuthentication: false);
      return;
    }
    if (_sessionUser != null &&
        entryId(_sessionUser!) == entryId(user) &&
        _sessionUser!.walletId == user.walletId) {
      return;
    }
    final revision = _captureRevision();
    final identity = Object();
    _sessionUser = user;
    _sessionIdentity = identity;
    unlockCoordinator.attachWallet(
      entryId(user),
      requiresAuthentication: !user.wallet.isHW,
      sessionIdentity: identity,
    );
    final status = await _status(user);
    if (!_isRevisionCurrent(revision) ||
        !identical(_sessionIdentity, identity)) {
      return;
    }
    unlockCoordinator.attachWallet(
      entryId(user),
      requiresAuthentication: status.requiresAuthentication,
      authenticated: false,
      sessionIdentity: _sessionIdentity,
    );
  }

  Future<Wallet?> lastWallet() async {
    if (await _storage.read(_signedOutKey) == true) return null;
    final raw = await _storage.read(_lastKey);
    if (raw is! Map || raw['entryId'] is! String) return null;
    final users = await _sdk.auth.getUsers();
    for (final user in users) {
      if (entryId(user) == raw['entryId']) return user.wallet;
    }
    return null;
  }

  Future<bool> get automaticEntrySuppressed async =>
      await _storage.read(_signedOutKey) == true;

  void invalidatePendingOperations() {
    _revision++;
    _cleanup.revokeAuthorizations();
    unawaited(_backend.cancel().catchError((Object _) {}));
  }

  Future<void> signOut() async {
    invalidatePendingOperations();
    final revision = _revision;
    _signOutOwner = revision;
    _signOutPending = true;
    _recoveringFailedSignOut = false;
    // A shutdown transition covers even unattended wallets. Keep the current
    // identity attached until the caller confirms that KDF has stopped.
    unlockCoordinator.protectionChanged();
    try {
      await _backend.cancel();
    } catch (_) {
      /* Revocation is already synchronous. */
    }
    try {
      // A canceled browser ceremony or a short metadata operation can still
      // own the access lock. Revocation above is immediate; give that owner a
      // bounded chance to finish before reporting a durable sign-out failure.
      for (var attempt = 0; ; attempt++) {
        try {
          await withWalletAccessLock(() async {
            if (_revision != revision) {
              if (_signOutOwner == revision) {
                _signOutPending = false;
                _signOutOwner = null;
                _recoveringFailedSignOut = true;
              }
              return;
            }
            await _writeChecked(_signedOutKey, true);
          });
          break;
        } on WalletAccessException catch (error) {
          if (error.failure != WalletAccessFailure.busy || attempt >= 39) {
            rethrow;
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
    } catch (_) {
      // The engine is still available. Keep it covered, but permit a new,
      // explicit credential verification to recover from failed persistence.
      if (_signOutOwner == revision) {
        _signOutPending = false;
        _signOutOwner = null;
        _recoveringFailedSignOut = true;
      }
      rethrow;
    }
  }

  Future<bool> unlockCurrent({String? password, bool automatic = false}) async {
    if (_signOutPending) return false;
    final revision = _captureRevision();
    final user = _sessionUser;
    if (user == null) return false;
    final attempt = unlockCoordinator.beginUnlock(automatic: automatic);
    if (attempt == null) return false;
    try {
      await _runAccessOperation(
        (operationRevision) => _authorize(
          user.walletId,
          password: password,
          reason: 'Unlock your wallet',
          revision: operationRevision,
          forUnlock: true,
        ),
      );
      _ensureRevision(revision);
      WalletAccessStatus? recoveredStatus;
      if (_recoveringFailedSignOut) {
        if (password != null) _passwordOnlyEntries.add(entryId(user));
        recoveredStatus = await _status(user);
        _ensureRevision(revision);
      }
      final unlocked = unlockCoordinator.completeUnlock(attempt);
      if (unlocked && password != null) _passwordOnlyEntries.add(entryId(user));
      if (unlocked && recoveredStatus != null) {
        _recoveringFailedSignOut = false;
        unlockCoordinator.attachWallet(
          entryId(user),
          requiresAuthentication: recoveredStatus.requiresAuthentication,
          authenticated: true,
          sessionIdentity: _sessionIdentity,
        );
      }
      return unlocked;
    } catch (_) {
      unlockCoordinator.cancelUnlock(attempt);
      rethrow;
    }
  }

  Future<void> enrollDevice({required WalletId walletId, String? password}) =>
      _enroll(walletId, password, passkey: false);
  Future<void> enrollPasskey({required WalletId walletId, String? password}) =>
      _enroll(walletId, password, passkey: true);

  Future<void> replacePasskeyUsingPassword({
    required WalletId walletId,
    required String password,
  }) => _runAccessOperation((revision) async {
    if (!passkeyEnrollmentEnabled) {
      throw const WalletAccessException(WalletAccessFailure.unavailable);
    }
    final user = await _resolve(walletId);
    final session = await _sdk.auth.captureSessionContext();
    await _authorize(
      walletId,
      password: password,
      reason: 'Replace this browser passkey',
      revision: revision,
    );
    final ensureCurrent = captureSensitiveOperation(walletId);
    await _ensureUserCurrent(user, session, revision);
    final record = (await _records())[entryId(user)];
    if (record == null || !record.managed || record.rotationEnvelope != null) {
      throw const WalletAccessException(WalletAccessFailure.missingCredential);
    }
    final actual = await _backend.metadata(record.credentialKey);
    await _ensureUserCurrent(user, session, revision);
    if (actual == null ||
        actual.protection != CredentialProtection.passkey ||
        !actual.enrolled ||
        actual.revision < 1) {
      throw const WalletAccessException(WalletAccessFailure.unavailable);
    }
    ensureCurrent();
    await unlockCoordinator.runSystemPrompt(
      () => _backend.replacePasskeyAfterPasswordVerification(
        record.credentialKey,
        password,
        expectedRevision: actual.revision,
        label: user.wallet.displayName,
      ),
      waitForForeground: true,
    );
    await _ensureUserCurrent(user, session, revision);
    final updated = await _backend.metadata(record.credentialKey);
    await _ensureUserCurrent(user, session, revision);
    if (updated == null ||
        updated.protection != CredentialProtection.passkey ||
        !updated.enrolled ||
        updated.revision <= actual.revision) {
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
    // The backend verified the staged envelope with a new PRF assertion before
    // promotion. Do not issue a second challenge or extend the app unlock lease.
    await _saveRecord(
      record.copyWith(
        protection: CredentialProtection.passkey,
        requiresAuthentication: true,
      ),
    );
    await _ensureUserCurrent(user, session, revision);
    _changes.add(null);
  });

  Future<void> _enroll(
    WalletId walletId,
    String? suppliedPassword, {
    required bool passkey,
  }) => _runAccessOperation((revision) async {
    if (passkey ? !passkeyEnrollmentEnabled : !deviceEnrollmentEnabled) {
      throw const WalletAccessException(WalletAccessFailure.unavailable);
    }
    final user = await _resolve(walletId);
    final session = await _sdk.auth.captureSessionContext();
    final password = await _authorize(
      walletId,
      password: suppliedPassword,
      reason: 'Protect this wallet',
      revision: revision,
    );
    final ensureCurrent = captureSensitiveOperation(walletId);
    final prior = (await _records())[entryId(user)];
    final record =
        prior ??
        WalletAccessRecord(
          entryId: entryId(user),
          walletName: user.walletId.name,
          isHd: user.walletId.isHd,
          pubkeyHash: user.walletId.pubkeyHash,
          phase: 'ready',
          protection: CredentialProtection.password,
          requiresAuthentication: true,
          managed: false,
          generated: false,
        );
    await _ensureUserCurrent(user, session, revision);
    ensureCurrent();
    if (passkey) {
      await unlockCoordinator.runSystemPrompt(
        () => _backend.enrollPasskey(
          record.credentialKey,
          password,
          label: user.walletId.name,
        ),
        waitForForeground: true,
      );
    } else {
      await _writeProtectedVerified(
        record.credentialKey,
        password,
        revision,
        waitForForeground: true,
      );
    }
    _ensureRevision(revision);
    _sdk.auth.ensureSessionContextCurrent(session);
    _ensureSensitiveForeground();
    await unlockCoordinator.runSystemPrompt(() async {
      final readback = await _backend.read(
        record.credentialKey,
        reason: 'Confirm wallet protection',
        purpose: 'verifyWrite',
        requireAuthentication: true,
      );
      if (readback != password) {
        throw const WalletAccessException(WalletAccessFailure.storageFailed);
      }
    }, waitForForeground: true);
    final ensureReadbackCurrent = captureSensitiveOperation(walletId);
    final info = await _backend.metadata(record.credentialKey);
    if (info == null || !info.enrolled) {
      throw const WalletAccessException(WalletAccessFailure.invalidResponse);
    }
    _ensureRevision(revision);
    await RpcDispatchGuard.run(
      ensureReadbackCurrent,
      () => _sdk.auth.verifyPassword(
        password: password,
        expectedWalletId: walletId,
        expectedSession: session,
      ),
      methods: const {'get_mnemonic'},
    );
    ensureReadbackCurrent();
    await _saveRecord(
      record.copyWith(
        managed: true,
        requiresAuthentication: true,
        protection: info.protection,
      ),
    );
    await _didAuthenticate(
      user,
      expectedRevision: revision,
      ensureAuthorized: ensureReadbackCurrent,
    );
  });

  Future<void> changePassword({
    required WalletId walletId,
    String? currentPassword,
    required String newPassword,
  }) => _runAccessOperation((revision) async {
    if (!SecurityUtils.checkPasswordRequirements(newPassword).isValid) {
      throw const WalletAccessException(WalletAccessFailure.incorrectPassword);
    }
    final user = await _resolve(walletId);
    final session = await _sdk.auth.captureSessionContext();
    final oldPassword = await _authorize(
      walletId,
      password: currentPassword,
      reason: 'Change wallet password',
      revision: revision,
    );
    final ensureCurrent = captureSensitiveOperation(walletId);
    var record = (await _records())[entryId(user)];
    if (record != null && record.managed) {
      final envelope = await PasswordRotationEnvelope.seal(
        newPassword,
        oldPassword,
        record.entryId,
      );
      record = record.copyWith(phase: 'rotating', rotationEnvelope: envelope);
      await _saveRecord(record);
    }
    _ensureRevision(revision);
    _sdk.auth.ensureSessionContextCurrent(session);
    await RpcDispatchGuard.run(
      ensureCurrent,
      () => _sdk.auth.updatePassword(
        currentPassword: oldPassword,
        newPassword: newPassword,
        expectedWalletId: walletId,
        expectedSession: session,
      ),
      methods: const {'change_mnemonic_password'},
    );
    await _sdk.auth.verifyPassword(
      password: newPassword,
      expectedWalletId: walletId,
    );
    _ensureRevision(revision);
    var ensureCompletionCurrent = ensureCurrent;
    if (record != null) {
      ensureCompletionCurrent = (await _finishRotation(
        record,
        newPassword,
        revision,
        waitForForeground: true,
        interactiveWalletId: walletId,
        ensureAuthorized: ensureCurrent,
      ))!;
    }
    await _didAuthenticate(
      user,
      expectedRevision: revision,
      ensureAuthorized: ensureCompletionCurrent,
    );
  });

  Future<void Function()?> _finishRotation(
    WalletAccessRecord record,
    String newPassword,
    _AccessRevision revision, {
    bool waitForForeground = false,
    WalletId? interactiveWalletId,
    void Function()? ensureAuthorized,
  }) async {
    _ensureRevision(revision);
    ensureAuthorized?.call();
    if (record.requiresAuthentication && record.managed) {
      await _writeProtectedVerified(
        record.credentialKey,
        newPassword,
        revision,
        waitForForeground: waitForForeground,
      );
      if (await _readManaged(
            record,
            reason: 'Confirm updated wallet protection',
            purpose: 'verifyWrite',
            revision: revision,
            waitForForeground: waitForForeground,
            expectedCredential: newPassword,
          ) !=
          newPassword) {
        throw const WalletAccessException(WalletAccessFailure.storageFailed);
      }
    } else {
      await _backend.delete(record.credentialKey);
      if (await _backend.metadata(record.credentialKey) != null) {
        throw const WalletAccessException(WalletAccessFailure.storageFailed);
      }
    }
    final ensureCurrent = waitForForeground
        ? record.requiresAuthentication && record.managed
              ? captureSensitiveOperation(interactiveWalletId!)
              : ensureAuthorized
        : null;
    final keepsManaged = record.requiresAuthentication && record.managed;
    await _saveRecord(
      record.copyWith(
        phase: 'ready',
        generated: false,
        managed: keepsManaged,
        requiresAuthentication: true,
        protection: keepsManaged
            ? record.protection
            : CredentialProtection.password,
        manager: PasswordManagerOutcome.offered,
        clearRotation: true,
      ),
    );
    ensureCurrent?.call();
    return ensureCurrent;
  }

  /// Called before ordinary password sign-in. A new password can recover an
  /// interrupted rotation even if KDF still uses the former generated one.
  Future<void> recoverPasswordRotation(
    Wallet wallet,
    String password,
  ) => _runAccessOperation((revision) async {
    final user = await _resolveWallet(wallet);
    final record = (await _records())[entryId(user)];
    if (record?.rotationEnvelope == null) return;
    final previous = await PasswordRotationEnvelope.open(
      password,
      record!.rotationEnvelope!,
      record.entryId,
    );
    _ensureRevision(revision);
    if (previous == null) {
      return; // Ordinary sign-in will check a supplied old password.
    }
    try {
      final active = await _sdk.auth.signIn(
        walletName: user.walletId.name,
        password: password,
        options: user.walletId.authOptions,
      );
      await _sdk.auth.verifyPassword(
        password: password,
        expectedWalletId: active.walletId,
      );
    } on AuthException catch (error) {
      if (error.type != AuthExceptionType.incorrectPassword) rethrow;
      final active = await _sdk.auth.signIn(
        walletName: user.walletId.name,
        password: previous,
        options: user.walletId.authOptions,
      );
      await _sdk.auth.verifyPassword(
        password: previous,
        expectedWalletId: active.walletId,
      );
      final session = await _sdk.auth.captureSessionContext();
      _ensureRevision(revision);
      await _sdk.auth.updatePassword(
        currentPassword: previous,
        newPassword: password,
        expectedWalletId: user.walletId,
        expectedSession: session,
      );
    }
    await _sdk.auth.verifyPassword(
      password: password,
      expectedWalletId: user.walletId,
    );
    _ensureRevision(revision);
    try {
      await _finishRotation(record, password, revision);
    } on WalletAccessException catch (error) {
      _ensureRevision(revision);
      if (error.failure == WalletAccessFailure.staleOperation) rethrow;
      // KDF has verified the supplied new password. A failed device-vault
      // repair must not prevent password-only access; retain the journal and
      // require explicit password entry until protection can be repaired.
    }
  });

  Future<PasswordManagerOutcome> saveToPasswordManager({
    required WalletId walletId,
    String? password,
  }) => _runAccessOperation((revision) async {
    final user = await _resolve(walletId);
    final secret = await _authorize(
      walletId,
      password: password,
      reason: 'Save wallet password',
      revision: revision,
    );
    _ensureRevision(revision);
    final outcome = await unlockCoordinator.runSystemPrompt(
      () => _backend.savePassword(
        username: 'gleec-${entryId(user)}',
        password: secret,
        title: user.walletId.name,
      ),
    );
    _ensureRevision(revision);
    final record = (await _records())[entryId(user)];
    _ensureRevision(revision);
    if (record != null) await _saveRecord(record.copyWith(manager: outcome));
    return outcome;
  });

  Future<void> recordPasswordManagerOutcome({
    required WalletId walletId,
    required PasswordManagerOutcome outcome,
  }) => withWalletAccessLock(() async {
    final user = await _resolve(walletId);
    final record = (await _records())[entryId(user)];
    if (record != null) await _saveRecord(record.copyWith(manager: outcome));
  });

  Future<void> _onDeleted(WalletId walletId) async {
    // SDK holds its catalog lock. Never acquire the access lock here: another
    // access operation may be waiting on that catalog. The journal owns only
    // the short record-storage lock and is safe to retry from the repository.
    final identity = jsonEncode([walletId.name, walletId.pubkeyHash]);
    final preparedId = _preparedDeletionIds[identity];
    if (preparedId != null) {
      _deletedEntryIds.putIfAbsent(identity, () => <String>{}).add(preparedId);
    }
    final preparedScope = _preparedDeletionScopes[preparedId];
    if (preparedScope != null && !_isRevisionCurrent(preparedScope.revision)) {
      _cleanup.revokeAuthorizations();
    }
    _revision++;
    unlockCoordinator.protectionChanged();
    _changes.add(null);
    final records = await _records();
    for (final record in records.values) {
      if (record.walletName == walletId.name &&
          record.pubkeyHash == walletId.pubkeyHash) {
        _deletedEntryIds
            .putIfAbsent(identity, () => <String>{})
            .add(record.entryId);
      }
    }
    await _cleanup.complete(
      walletId.name,
      walletId.pubkeyHash,
      discoverRecords: true,
    );
  }

  /// Both callers freshly verified this password against KDF first. Native
  /// repair must additionally prove that the old cryptographic key is invalid.
  Future<void> _writeProtectedVerified(
    String key,
    String password,
    _AccessRevision revision, {
    bool waitForForeground = false,
  }) async {
    _ensureRevision(revision);
    if (waitForForeground) _ensureSensitiveForeground();
    try {
      await unlockCoordinator.runSystemPrompt(
        () => _backend.write(key, password, requireAuthentication: true),
        waitForForeground: waitForForeground,
      );
    } on WalletAccessException catch (error) {
      _ensureRevision(revision);
      if (error.failure != WalletAccessFailure.invalidated) rethrow;
      if (waitForForeground) _ensureSensitiveForeground();
      await unlockCoordinator.runSystemPrompt(
        () => _backend.repairInvalidated(key, password),
        waitForForeground: waitForForeground,
      );
    }
    _ensureRevision(revision);
  }

  Future<void> _ensureUserCurrent(
    KdfUser expected,
    AuthSessionContext session,
    _AccessRevision revision,
  ) async {
    _ensureRevision(revision);
    _sdk.auth.ensureSessionContextCurrent(session);
    final current = await _sdk.auth.currentUser;
    _ensureRevision(revision);
    _sdk.auth.ensureSessionContextCurrent(session);
    if (current == null ||
        current.walletId != expected.walletId ||
        entryId(current) != entryId(expected)) {
      throw const WalletAccessException(WalletAccessFailure.staleOperation);
    }
  }

  Future<void> _reloadProtection() async {
    final revision = _captureRevision();
    final user = _sessionUser;
    if (user == null) return;
    final status = await _status(user);
    _ensureRevision(revision);
    if (_sessionUser == null || entryId(_sessionUser!) != entryId(user)) return;
    _sessionIdentity = Object();
    unlockCoordinator.attachWallet(
      entryId(user),
      requiresAuthentication: status.requiresAuthentication,
      authenticated: false,
      sessionIdentity: _sessionIdentity,
    );
  }

  Future<T> _runAccessOperation<T>(
    Future<T> Function(_AccessRevision revision) action,
  ) {
    final revision = _captureRevision();
    return withWalletAccessLock(() async {
      _ensureRevision(revision);
      try {
        return await action(revision);
      } on RpcDispatchRejected {
        throw const WalletAccessException(WalletAccessFailure.staleOperation);
      }
    });
  }

  _AccessRevision _captureRevision() => _AccessRevision(
    _operationOwner,
    _revision,
    unlockCoordinator.authorizationGeneration,
  );

  bool _isRevisionCurrent(_AccessRevision revision) =>
      identical(revision.owner, _operationOwner) &&
      revision.service == _revision &&
      revision.authorization == unlockCoordinator.authorizationGeneration;

  void _ensureRevision(_AccessRevision revision) {
    if (!_isRevisionCurrent(revision)) {
      throw const WalletAccessException(WalletAccessFailure.staleOperation);
    }
  }

  Future<void> dispose() async {
    await _deviceLockSubscription.cancel();
    await _protectionSubscription.cancel();
    await _changes.close();
    await unlockCoordinator.dispose();
  }

  static Duration Function() _createMonotonicClock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }
}

class SensitiveExportAuthorization {
  const SensitiveExportAuthorization._({
    required this.ensureCurrent,
    required this.selectDestination,
  });
  final void Function() ensureCurrent;
  final Future<String?> Function(Future<String?> Function()) selectDestination;
}

class _PreparedDeletionAuthorization {
  const _PreparedDeletionAuthorization(
    this.revision,
    this.unlockGeneration,
    this.expiresAt,
  );
  final _AccessRevision revision;
  final int unlockGeneration;
  final Duration expiresAt;
}

class _AccessRevision {
  const _AccessRevision(this.owner, this.service, this.authorization);
  final Object owner;
  final int service;
  final int authorization;
}

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/passkey_assertion_check.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/passkey_authenticator.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/passkey_envelope.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/passkey_registration.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/passkey_registration_types.dart';
import 'package:web_dex/services/wallet_access/wallet_access_types.dart';
import 'package:web_dex/services/wallet_transfer/wallet_transfer_config.dart';
import 'package:web_dex/services/wallet_transfer/wallet_transfer_secret.dart';

import 'passkey_backup_index.dart';
import 'passkey_backup_record.dart';
import 'passkey_backup_types.dart';
import 'passkey_provider_names.dart';

part 'passkey_backup_restore.dart';

/// Seals a wallet to a passkey made for its backup alone, and opens it again.
///
/// Nothing is kept until it is proven: the passkey must give the same key
/// twice, and the copy read back from the store must open to the exact
/// secret. A creation that fails once the passkey exists deletes what it
/// wrote and asks the password manager to drop the passkey.
final class PasskeyBackupService implements PasskeyBackupController {
  PasskeyBackupService({
    required this._config,
    required this._registrar,
    required this._authenticator,
    required Map<BackupStoreKind, BackupRecordStore> stores,
    required this._index,
    DateTime Function()? clock,
    Random? random,
    bool Function()? isAppleOrAndroidPlatform,
  }) : _stores = Map.unmodifiable(stores),
       _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure(),
       _platformSupported = isAppleOrAndroidPlatform ?? _appleOrAndroid;

  static const userName = 'Gleec Wallet recovery';
  static const _displayNameLength = 64;
  static const _onDevice = {'internal', 'usb', 'nfc', 'ble'};

  final WalletTransferConfig _config;
  final PasskeyRegistrar _registrar;
  final PasskeyAuthenticator _authenticator;
  final Map<BackupStoreKind, BackupRecordStore> _stores;
  final PasskeyBackupIndex _index;
  final DateTime Function() _clock;
  final Random _random;
  final bool Function() _platformSupported;
  int _generation = 0;
  bool _busy = false;

  /// Where the PRF API and synced passkeys exist: iOS 18, macOS 15 and
  /// Android. Windows answers the same support probe for sign-in only.
  static bool _appleOrAndroid() =>
      !kIsWeb &&
      switch (defaultTargetPlatform) {
        TargetPlatform.iOS ||
        TargetPlatform.macOS ||
        TargetPlatform.android => true,
        _ => false,
      };

  /// The name a password manager lists, at most 64 characters.
  static String displayNameFor(String walletName) {
    final runes = '$userName – $walletName'.runes;
    return String.fromCharCodes(runes.take(_displayNameLength));
  }

  String get _rpId {
    if (!_config.passkeyBackupConfigured) {
      throw const PasskeyBackupException(PasskeyBackupFailure.notConfigured);
    }
    return _config.backupRpId;
  }

  @override
  Future<PasskeyBackupAvailability> availability() async {
    if (!_config.passkeyBackupConfigured ||
        !_platformSupported() ||
        !await _probe(_registrar.isSupported) ||
        !await _probe(_authenticator.isSupported)) {
      return PasskeyBackupAvailability.none;
    }
    return PasskeyBackupAvailability(
      canCreate: true,
      canRestore: true,
      stores: [
        if (await _offered(BackupStoreKind.iCloudKeychain))
          BackupStoreKind.iCloudKeychain,
        if (await _offered(BackupStoreKind.googleDrive))
          BackupStoreKind.googleDrive,
        BackupStoreKind.file,
      ],
    );
  }

  @override
  Future<List<PasskeyBackupEntry>> backupsFor(String walletKey) =>
      _index.entriesFor(walletKey);

  @override
  Future<PasskeyBackupEntry> create({
    required String walletKey,
    required WalletTransferSecret secret,
    required BackupStoreKind store,
  }) => _exclusive((token) => _create(walletKey, secret, store, token));

  @override
  Future<DateTime> check(PasskeyBackupEntry entry) =>
      _exclusive((token) => _check(entry, token));

  @override
  Future<void> remove(PasskeyBackupEntry entry) => _remove(entry);

  @override
  Future<String> exportFile(PasskeyBackupEntry entry) => _export(entry);

  @override
  Future<void> markFileSaved(PasskeyBackupEntry entry) =>
      _index.markFileSaved(entry.id);

  @override
  Future<List<StoredBackup>> find(BackupStoreKind store) => _find(store);

  @override
  StoredBackup parseFile(String raw) {
    final text = raw.trim();
    final record = PasskeyBackupRecord.decode(text, expectedRpId: _rpId);
    return StoredBackup(
      id: record.id,
      store: BackupStoreKind.file,
      created: record.created,
      raw: text,
    );
  }

  @override
  Future<WalletTransferSecret> unlock(StoredBackup backup) =>
      _exclusive((token) => _open(backup.raw, token));

  /// Ends any open prompt; an operation between prompts stops at its next
  /// step and undoes what it did.
  @override
  Future<void> cancel() async {
    _generation++;
    await Future.wait([
      _registrar.cancel().catchError((Object _) {}),
      _authenticator.cancel().catchError((Object _) {}),
    ]);
  }

  Future<PasskeyBackupEntry> _create(
    String walletKey,
    WalletTransferSecret secret,
    BackupStoreKind kind,
    int token,
  ) async {
    final rpId = _rpId;
    if (walletKey.isEmpty) throw ArgumentError.value(walletKey, 'walletKey');
    final target = kind == BackupStoreKind.file ? null : await _store(kind);
    // Any sign-in comes before the passkey prompts, never between them or
    // during an undo.
    await target?.prepare();
    _ensureCurrent(token);
    final userId = _bytes(32);
    final request = PasskeyRegistrationRequest(
      rpId: rpId,
      challenge: _bytes(32),
      userId: userId,
      userName: userName,
      displayName: displayNameFor(secret.walletName),
      prfSalt: PasskeyBackupRecord.prfSalt,
    );
    final PasskeyRegistration registration;
    try {
      registration = await _registrar.register(request);
    } on WalletAccessException catch (error, stack) {
      Error.throwWithStackTrace(_backupFailure(error), stack);
    }
    RegisteredPasskey? checked;
    Uint8List? prf;
    String? written;
    try {
      _ensureCurrent(token);
      final passkey = checked = checkPasskeyRegistration(registration, request);
      // Made on another device over QR (iOS reports only `hybrid`): PRF over
      // that route has differed from what the passkey gives on a device.
      // Some Android providers report no transports at all; that says
      // nothing about where the passkey lives, so only the backup flag and
      // the reproduced key decide for them.
      if (passkey.transports.isNotEmpty &&
          !passkey.transports.any(_onDevice.contains)) {
        throw const PasskeyBackupException(
          PasskeyBackupFailure.createdElsewhere,
        );
      }
      if (!passkey.reachesOtherDevices) {
        throw const PasskeyBackupException(PasskeyBackupFailure.localOnly);
      }
      final key = prf = await _reproducedKey(rpId, passkey, userId, token);
      final record = PasskeyBackupRecord.seal(
        rpId: rpId,
        passkey: passkey,
        userHandle: userId,
        prf: key,
        secret: secret,
        created: _clock(),
        random: _random,
      );
      final raw = record.encode();
      PasskeyBackupEntry entryIn(
        PasskeyBackupEntryState state, {
        DateTime? checkedHere,
      }) => PasskeyBackupEntry(
        id: record.id,
        walletKey: walletKey,
        store: kind,
        created: record.created,
        synced: record.backupState,
        providerName: passkeyProviderName(record.aaguid),
        checkedHere: checkedHere,
        state: state,
      );
      // A store's readback below opens its copy here, with this passkey's
      // key. A file is unchecked until the user saves it: until then it
      // exists only in this app.
      final entry = target == null
          ? entryIn(PasskeyBackupEntryState.fileNotSaved)
          : entryIn(PasskeyBackupEntryState.ready, checkedHere: record.created);
      void verify(String? stored) => _verifyStored(
        stored,
        id: record.id,
        credentialId: passkey.credentialId,
        userHandle: userId,
        secret: secret,
        prf: key,
      );
      _ensureCurrent(token);
      written = record.id;
      if (target == null) {
        // The user saves the file from this copy, so it is the one proven.
        await _index.save(entry, raw);
        verify(await _index.record(record.id));
      } else {
        // Recorded first, so an app closed mid-write leaves a backup this
        // device can still finish or remove.
        await _index.save(entryIn(PasskeyBackupEntryState.unfinished), raw);
        await target.write(record.id, raw);
        final listed = await target.list();
        verify(listed.where((item) => item.id == record.id).firstOrNull?.raw);
        _ensureCurrent(token);
        await _index.save(entry, raw);
      }
      return entry;
    } catch (error, stack) {
      await _undo(
        target,
        written,
        checked?.credentialId ?? registration.credentialId,
      );
      Error.throwWithStackTrace(_backupFailure(error), stack);
    } finally {
      prf?.fillRange(0, prf.length, 0);
      // The checked passkey shares this buffer.
      final created = registration.prfOutput;
      created?.fillRange(0, created.length, 0);
    }
  }

  /// The PRF output once a second evaluation has given the same bytes: the
  /// one at creation where the provider returns it, else another sign-in.
  Future<Uint8List> _reproducedKey(
    String rpId,
    RegisteredPasskey passkey,
    Uint8List userId,
    int token,
  ) async {
    Future<Uint8List> evaluate() => _assertKey(
      rpId,
      passkey.credentialId,
      userId,
      token,
      PasskeyBackupFailure.notReproducible,
    );
    final first = await evaluate();
    try {
      final reference = passkey.prfOutput ?? await evaluate();
      try {
        if (!passkeyBytesEqual(first, reference)) {
          throw const PasskeyBackupException(
            PasskeyBackupFailure.notReproducible,
          );
        }
      } finally {
        reference.fillRange(0, reference.length, 0);
      }
      return first;
    } catch (_) {
      first.fillRange(0, first.length, 0);
      rethrow;
    }
  }

  /// One assertion for exactly [credentialId], checked, and a copy of its
  /// PRF output for the caller to wipe. Another passkey answering is
  /// [mismatch].
  Future<Uint8List> _assertKey(
    String rpId,
    Uint8List credentialId,
    Uint8List userHandle,
    int token,
    PasskeyBackupFailure mismatch,
  ) async {
    _ensureCurrent(token);
    final request = PasskeyAssertionRequest(
      rpId: rpId,
      challenge: _bytes(32),
      salt: PasskeyBackupRecord.prfSalt,
      allowCredentials: [credentialId],
    );
    final assertion = await _authenticator.getAssertion(request);
    try {
      _ensureCurrent(token);
      final handle = assertion.userHandle;
      if (!passkeyBytesEqual(assertion.credentialId, credentialId) ||
          (handle != null && !passkeyBytesEqual(handle, userHandle))) {
        throw PasskeyBackupException(mismatch);
      }
      checkPasskeyAssertion(assertion, request, expectedUserHandle: userHandle);
      return Uint8List.fromList(assertion.prf);
    } finally {
      assertion.wipe();
    }
  }

  /// The stored copy decodes to this record, for this passkey, and opens
  /// to exactly [secret]. Anything else means the store did not keep it.
  void _verifyStored(
    String? raw, {
    required String id,
    required Uint8List credentialId,
    required Uint8List userHandle,
    required WalletTransferSecret secret,
    required Uint8List prf,
  }) {
    const failed = PasskeyBackupException(PasskeyBackupFailure.storageFailed);
    if (raw == null) throw failed;
    try {
      final stored = PasskeyBackupRecord.decode(raw, expectedRpId: _rpId);
      if (stored.id != id ||
          !passkeyBytesEqual(stored.credentialId, credentialId) ||
          !passkeyBytesEqual(stored.userHandle, userHandle) ||
          !_sameSecret(stored.open(prf), secret)) {
        throw failed;
      }
    } on Exception {
      throw failed;
    }
  }

  /// Undoes a creation that failed once the passkey existed. A copy that
  /// could not be deleted opens only with a passkey reported removed.
  Future<void> _undo(
    BackupRecordStore? target,
    String? written,
    Uint8List credentialId,
  ) async {
    if (written != null) {
      try {
        await target?.delete(written);
      } on Object {
        // Left behind, it opens only with the passkey reported below.
      }
      try {
        await _index.remove(written);
      } on Object {
        // Its entry then names a backup the store no longer holds.
      }
    }
    await _reportRemoved(credentialId);
  }

  /// Best effort, and never for a passkey that still opens one of this
  /// device's backups: an id the platform got wrong must not cost one.
  Future<void> _reportRemoved(Uint8List credentialId) async {
    if (credentialId.isEmpty || credentialId.length > 1023) return;
    try {
      for (final raw in await _index.records()) {
        final Uint8List kept;
        try {
          kept = PasskeyBackupRecord.decode(
            raw,
            expectedRpId: _config.backupRpId,
          ).credentialId;
        } on Object {
          continue;
        }
        if (passkeyBytesEqual(kept, credentialId)) return;
      }
      await _registrar.reportRemoved(
        rpId: _config.backupRpId,
        credentialId: Uint8List.fromList(credentialId),
      );
    } on Object {
      // The passkey then stays in the password manager, opening nothing.
    }
  }

  Future<bool> _offered(BackupStoreKind kind) async {
    if (kind == BackupStoreKind.googleDrive && !_config.googleDriveEnabled) {
      return false;
    }
    final store = _stores[kind];
    return store != null &&
        store.kind == kind &&
        await _probe(store.isAvailable);
  }

  Future<BackupRecordStore> _store(BackupStoreKind kind) async {
    if (!await _offered(kind)) {
      throw const PasskeyBackupException(PasskeyBackupFailure.storeUnavailable);
    }
    return _stores[kind]!;
  }

  static Future<bool> _probe(Future<bool> Function() supported) async {
    try {
      return await supported();
    } on Object {
      return false;
    }
  }

  /// One ceremony at a time; [cancel] moves the generation on.
  Future<T> _exclusive<T>(Future<T> Function(int token) body) async {
    if (_busy) throw const WalletAccessException(WalletAccessFailure.busy);
    _busy = true;
    try {
      return await body(_generation);
    } finally {
      _busy = false;
    }
  }

  void _ensureCurrent(int token) {
    if (token != _generation) {
      throw const PasskeyBackupException(PasskeyBackupFailure.canceled);
    }
  }

  Uint8List _bytes(int length) => PasskeyEnvelope.randomBytes(length, _random);

  static bool _sameSecret(WalletTransferSecret a, WalletTransferSecret b) {
    final left = utf8.encode(a.seed);
    final right = utf8.encode(b.seed);
    try {
      return passkeyBytesEqual(left, right) &&
          a.walletName == b.walletName &&
          a.type == b.type &&
          a.phraseConfirmed == b.phraseConfirmed;
    } finally {
      left.fillRange(0, left.length, 0);
      right.fillRange(0, right.length, 0);
    }
  }

  /// The failures the backup screens explain. Others keep their access
  /// failure, which those screens show as they do elsewhere.
  static Object _backupFailure(Object error, {bool restoring = false}) {
    if (error is! WalletAccessException) return error;
    return switch (error.failure) {
      WalletAccessFailure.canceled => const PasskeyBackupException(
        PasskeyBackupFailure.canceled,
      ),
      WalletAccessFailure.prfUnavailable => const PasskeyBackupException(
        PasskeyBackupFailure.prfUnavailable,
      ),
      WalletAccessFailure.unavailable => const PasskeyBackupException(
        PasskeyBackupFailure.unavailable,
      ),
      WalletAccessFailure.passkeyNotFound when restoring =>
        const PasskeyBackupException(PasskeyBackupFailure.wrongPasskey),
      _ => error,
    };
  }
}

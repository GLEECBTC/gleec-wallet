import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../wallet_access_types.dart';
import 'credential_backend.dart';

CredentialBackend createCredentialBackend() => NativeCredentialBackend();

/// Native protected reads are performed by the OS, not by a Dart Boolean.
class NativeCredentialBackend extends CredentialBackend {
  NativeCredentialBackend({
    MethodChannel? channel,
    FlutterSecureStorage? linuxStorage,
    Future<Directory> Function()? supportDirectory,
  }) : _channel =
           channel ?? const MethodChannel('gleec.wallet/credential_vault'),
       _linuxStorage = linuxStorage ?? const FlutterSecureStorage(),
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'deviceLocked') _deviceLocked.add(null);
    });
  }

  final MethodChannel _channel;
  final FlutterSecureStorage _linuxStorage;
  final Future<Directory> Function() _supportDirectory;
  final _deviceLocked = StreamController<void>.broadcast();
  bool? _linuxHasSecretService;
  @override
  Stream<void> get deviceLocked => _deviceLocked.stream;

  Future<T?> _invoke<T>(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      throw const WalletAccessException(WalletAccessFailure.unavailable);
    } on PlatformException catch (error) {
      throw WalletAccessException(switch (error.code) {
        'canceled' || 'cancelled' => WalletAccessFailure.canceled,
        'unavailable' => WalletAccessFailure.unavailable,
        'invalidated' => WalletAccessFailure.invalidated,
        'lockedOut' => WalletAccessFailure.lockedOut,
        'busy' => WalletAccessFailure.busy,
        _ => WalletAccessFailure.storageFailed,
      });
    }
  }

  @override
  Future<CredentialCapabilities> capabilities() async {
    if (Platform.isLinux) {
      try {
        await _linuxStorage.read(key: 'gleec.credential.capability');
        _linuxHasSecretService = true;
      } catch (_) {
        _linuxHasSecretService = false;
      }
      return CredentialCapabilities(
        available: true,
        protection: _linuxHasSecretService!
            ? CredentialProtection.osAccountProtected
            : CredentialProtection.appLocal,
      );
    }
    final result = await _invoke<Map>('capabilities');
    if (result == null) {
      throw const WalletAccessException(WalletAccessFailure.invalidResponse);
    }
    return CredentialCapabilities(
      available: result['available'] == true,
      protection: CredentialProtection.parse(result['protection']),
      deviceAuthentication: result['deviceAuthentication'] == true,
    );
  }

  @override
  Future<CredentialRecordInfo?> metadata(String key) async {
    if (Platform.isLinux) {
      final record = await _linuxStorageOperation(() => _linuxRead(key));
      if (record == null) return null;
      return CredentialRecordInfo(
        protection: CredentialProtection.parse(record['protection']),
        enrolled: false,
      );
    }
    final result = await _invoke<Map>('metadata', {'key': key});
    if (result == null) return null;
    return CredentialRecordInfo(
      protection: CredentialProtection.parse(result['protection']),
      enrolled: result['enrolled'] == true,
      revision: (result['revision'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<void> write(
    String key,
    String value, {
    required bool requireAuthentication,
  }) async {
    if (Platform.isLinux) {
      if (requireAuthentication) {
        throw const WalletAccessException(WalletAccessFailure.unavailable);
      }
      await _linuxStorageOperation(() => _linuxWrite(key, value));
      return;
    }
    await _invoke<void>('write', {
      'key': key,
      'value': value,
      'requireAuthentication': requireAuthentication,
    });
  }

  @override
  Future<String?> read(
    String key, {
    required String reason,
    bool requireAuthentication = false,
    bool automatic = false,
    String? purpose,
  }) async {
    if (Platform.isLinux) {
      if (requireAuthentication) {
        throw const WalletAccessException(WalletAccessFailure.unavailable);
      }
      return (await _linuxStorageOperation(() => _linuxRead(key)))?['value']
          as String?;
    }
    return _invoke<String>('read', {
      'key': key,
      'reason': reason,
      'requireAuthentication': requireAuthentication,
      if (purpose != null) 'purpose': purpose,
    });
  }

  @override
  Future<String?> prepareDelete(String key, {required String reason}) async {
    if (Platform.isLinux) return null;
    return _invoke<String>('prepareDelete', {'key': key, 'reason': reason});
  }

  @override
  Future<void> delete(String key, {String? authorization}) async {
    if (Platform.isLinux) {
      await _linuxStorageOperation(() async {
        // Removal must cover both initial storage tiers, never ignore a failed
        // deletion when upgrading wallet protection. Keep the policy marker
        // until every credential copy has been removed and verified.
        final file = await _localFile(key);
        final tier = File('${file.path}.secret-service');
        if (_linuxHasSecretService == null) await capabilities();
        if (await tier.exists() || _linuxHasSecretService == true) {
          await _linuxStorage.delete(key: key);
          if (await _linuxStorage.read(key: key) != null) {
            throw const WalletAccessException(
              WalletAccessFailure.storageFailed,
            );
          }
        }
        if (await file.exists()) await file.delete();
        final pending = File('${file.path}.pending');
        if (await pending.exists()) await pending.delete();
        if (await tier.exists()) await tier.delete();
      });
      return;
    }
    await _invoke<void>('delete', {
      'key': key,
      if (authorization != null) 'authorization': authorization,
    });
  }

  @override
  Future<void> cancel() async {
    if (!Platform.isLinux) await _invoke<void>('cancel');
  }

  @override
  Future<void> repairInvalidated(String key, String value) async {
    if (Platform.isLinux) {
      throw const WalletAccessException(WalletAccessFailure.unavailable);
    }
    await _invoke<void>('repairInvalidated', {
      'key': key,
      'value': value,
      'requireAuthentication': true,
    });
  }

  @override
  Future<PasswordManagerOutcome> savePassword({
    required String username,
    required String password,
    required String title,
  }) async {
    if (Platform.isLinux) return PasswordManagerOutcome.unavailable;
    final result = await _invoke<String>('savePassword', {
      'username': username,
      'password': password,
      'title': title,
    });
    return PasswordManagerOutcome.values.firstWhere(
      (item) => item.name == result,
      orElse: () => PasswordManagerOutcome.unknown,
    );
  }

  Future<File> _localFile(String key) async {
    // Keys are opaque IDs supplied by the service, never wallet display names.
    if (!RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(key)) {
      throw const WalletAccessException(WalletAccessFailure.invalidResponse);
    }
    final root = await _supportDirectory();
    return File(p.join(root.path, 'wallet_credentials', '$key.json'));
  }

  Future<Map<String, dynamic>?> _linuxRead(String key) async {
    final file = await _localFile(key);
    final tier = File('${file.path}.secret-service');
    final usesSecretService = await tier.exists();
    // The durable policy always wins over a stale or malformed unattended file.
    // Never inspect that file when this entry has used Secret Service.
    if (!usesSecretService && await file.exists()) {
      return _decodeLinuxRecord(
        await file.readAsString(),
        CredentialProtection.appLocal,
      );
    }
    if (_linuxHasSecretService == null) await capabilities();
    if (_linuxHasSecretService == false && !usesSecretService) return null;
    final raw = await _linuxStorage.read(key: key);
    return raw == null
        ? null
        : _decodeLinuxRecord(raw, CredentialProtection.osAccountProtected);
  }

  Map<String, dynamic> _decodeLinuxRecord(
    String raw,
    CredentialProtection expected,
  ) {
    final record = jsonDecode(raw);
    if (record is! Map<String, dynamic> ||
        record['value'] is! String ||
        record['protection'] != expected.name) {
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
    return record;
  }

  Future<T> _linuxStorageOperation<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on WalletAccessException {
      rethrow;
    } catch (_) {
      // Platform, filesystem and JSON errors may embed credential contents.
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
  }

  Future<void> _restrictPermissions(String path, String mode) async {
    if ((await Process.run('chmod', [mode, path])).exitCode != 0) {
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
  }

  Future<void> _linuxWrite(String key, String value) async {
    final file = await _localFile(key);
    final existsLocally = await file.exists();
    final tier = File('${file.path}.secret-service');
    if (_linuxHasSecretService == null) await capabilities();
    if (await tier.exists() ||
        (!existsLocally && _linuxHasSecretService == true)) {
      try {
        // Preserve the storage policy even if Secret Service later disappears.
        // This marker contains no credential; a failed write never enables a
        // fallback to unattended app-local storage for the same key.
        await tier.parent.create(recursive: true);
        await _restrictPermissions(tier.parent.path, '700');
        await tier.writeAsString('1', flush: true);
        await _restrictPermissions(tier.path, '600');
        await _linuxStorage.write(
          key: key,
          value: jsonEncode({
            'value': value,
            'protection': CredentialProtection.osAccountProtected.name,
          }),
        );
        if ((await _linuxRead(key))?['value'] != value) {
          throw const WalletAccessException(WalletAccessFailure.storageFailed);
        }
        if (await file.exists()) await file.delete();
        final pending = File('${file.path}.pending');
        if (await pending.exists()) await pending.delete();
        return;
      } catch (_) {
        throw const WalletAccessException(WalletAccessFailure.storageFailed);
      }
    }
    // Explicit initial app-local tier on Linux without a Secret Service. No
    // fallback from a failed read of an existing Secret Service record.
    await file.parent.create(recursive: true);
    await _restrictPermissions(file.parent.path, '700');
    final pending = File('${file.path}.pending');
    await pending.create();
    await _restrictPermissions(pending.path, '600');
    await pending.writeAsString(
      jsonEncode({
        'value': value,
        'protection': CredentialProtection.appLocal.name,
      }),
      flush: true,
    );
    await pending.rename(file.path);
    if ((await _linuxRead(key))?['value'] != value) {
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
  }
}

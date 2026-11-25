import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../wallet_access_types.dart';
import 'credential_backend.dart';
import 'passkey/passkey_authenticator.dart';
import 'passkey/passkey_credential_backend.dart';

/// Linux has no passkey bridge, so no envelope can exist there to be read.
/// A test build may name a staging relying party; envelopes record theirs,
/// so one build never opens another's.
CredentialBackend createCredentialBackend() => Platform.isLinux
    ? NativeCredentialBackend()
    : PasskeyCredentialBackend(
        base: NativeCredentialBackend(),
        authenticator: MethodChannelPasskeyAuthenticator(),
        rpId: const String.fromEnvironment(
          'WALLET_PASSKEY_RP_ID',
          defaultValue: PasskeyCredentialBackend.relyingParty,
        ),
      );

/// Maps a native channel error code. `interrupted` means the OS dismissed the
/// prompt (a call, an app switch, the device locking): the user declined
/// nothing, so an enrolment must fail rather than read it as "set up later".
WalletAccessFailure credentialChannelFailure(
  String code, {
  required bool enrolling,
}) => switch (code) {
  'canceled' || 'cancelled' => WalletAccessFailure.canceled,
  'interrupted' =>
    enrolling ? WalletAccessFailure.unavailable : WalletAccessFailure.canceled,
  'unavailable' => WalletAccessFailure.unavailable,
  'invalidated' => WalletAccessFailure.invalidated,
  'lockedOut' => WalletAccessFailure.lockedOut,
  'busy' => WalletAccessFailure.busy,
  _ => WalletAccessFailure.storageFailed,
};

/// Whether a Secret Service provider owns, or can be started for, its name on
/// the session bus. False when the bus cannot be asked: the unattended tier
/// then stays available exactly as it was before this check existed.
Future<bool> secretServiceOnSessionBus({
  Future<ProcessResult> Function(String, List<String>) run = Process.run,
}) async {
  const bus = 'org.freedesktop.DBus';
  const object = '/org/freedesktop/DBus';
  const provider = 'org.freedesktop.secrets';
  for (final method in const ['ListNames', 'ListActivatableNames']) {
    for (final command in [
      'gdbus call --session --dest $bus --object-path $object --method $bus.$method',
      'dbus-send --session --print-reply --dest=$bus $object $bus.$method',
      'busctl --user call $bus $object $bus $method',
    ]) {
      final [tool, ...arguments] = command.split(' ');
      try {
        final result = await run(
          tool,
          arguments,
        ).timeout(const Duration(seconds: 2));
        if (result.exitCode != 0) continue;
        final names = '${result.stdout}';
        if (names.contains('"$provider"') || names.contains("'$provider'")) {
          return true;
        }
        break;
      } catch (_) {
        // Not installed or not answering; the next tool asks the same thing.
      }
    }
  }
  return false;
}

enum _LinuxSecretService { present, absent, failed }

/// Native protected reads are performed by the OS, not by a Dart Boolean.
class NativeCredentialBackend extends CredentialBackend {
  NativeCredentialBackend({
    MethodChannel? channel,
    FlutterSecureStorage? linuxStorage,
    Future<Directory> Function()? supportDirectory,
    Future<bool> Function()? linuxSecretServicePresent,
  }) : _channel =
           channel ?? const MethodChannel('gleec.wallet/credential_vault'),
       _linuxStorage = linuxStorage ?? const FlutterSecureStorage(),
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
       _linuxSecretServicePresent =
           linuxSecretServicePresent ?? secretServiceOnSessionBus {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'deviceLocked') _deviceLocked.add(null);
    });
  }

  final MethodChannel _channel;
  final FlutterSecureStorage _linuxStorage;
  final Future<Directory> Function() _supportDirectory;
  final Future<bool> Function() _linuxSecretServicePresent;
  final _deviceLocked = StreamController<void>.broadcast();
  _LinuxSecretService? _linuxSecretService;
  @override
  Stream<void> get deviceLocked => _deviceLocked.stream;

  /// [enrolling] marks a call that creates or confirms device protection.
  Future<T?> _invoke<T>(
    String method, {
    Map<String, Object?>? arguments,
    bool enrolling = false,
  }) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      throw const WalletAccessException(WalletAccessFailure.unavailable);
    } on PlatformException catch (error) {
      throw WalletAccessException(
        credentialChannelFailure(error.code, enrolling: enrolling),
      );
    }
  }

  @override
  Future<CredentialCapabilities> capabilities() async {
    if (Platform.isLinux) {
      try {
        await _linuxStorage.read(key: 'gleec.credential.capability');
        _linuxSecretService = _LinuxSecretService.present;
      } catch (_) {
        // The storage plugin reports a missing provider and a dismissed or
        // failed keyring unlock identically. Only the first may select the
        // unattended app-local tier.
        _linuxSecretService = await _linuxSecretServicePresent()
            ? _LinuxSecretService.failed
            : _LinuxSecretService.absent;
      }
      return CredentialCapabilities(
        available: true,
        protection: _linuxSecretService == _LinuxSecretService.absent
            ? CredentialProtection.appLocal
            : CredentialProtection.osAccountProtected,
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
    final result = await _invoke<Map>('metadata', arguments: {'key': key});
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
    await _invoke<void>(
      'write',
      arguments: {
        'key': key,
        'value': value,
        'requireAuthentication': requireAuthentication,
      },
      enrolling: requireAuthentication,
    );
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
    return _invoke<String>(
      'read',
      arguments: {
        'key': key,
        'reason': reason,
        'requireAuthentication': requireAuthentication,
        if (purpose != null) 'purpose': purpose,
      },
      enrolling: purpose == 'verifyWrite',
    );
  }

  @override
  Future<String?> prepareDelete(String key, {required String reason}) async {
    if (Platform.isLinux) return null;
    return _invoke<String>(
      'prepareDelete',
      arguments: {'key': key, 'reason': reason},
    );
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
        if (_linuxSecretService == null) await capabilities();
        if (await tier.exists() ||
            _linuxSecretService == _LinuxSecretService.present) {
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
    await _invoke<void>(
      'delete',
      arguments: {
        'key': key,
        if (authorization != null) 'authorization': authorization,
      },
    );
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
    await _invoke<void>(
      'repairInvalidated',
      arguments: {'key': key, 'value': value, 'requireAuthentication': true},
      enrolling: true,
    );
  }

  @override
  Future<PasswordManagerOutcome> savePassword({
    required String username,
    required String password,
    required String title,
  }) async {
    if (Platform.isLinux) return PasswordManagerOutcome.unavailable;
    final result = await _invoke<String>(
      'savePassword',
      arguments: {'username': username, 'password': password, 'title': title},
    );
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
    if (_linuxSecretService == null) await capabilities();
    if (_linuxSecretService != _LinuxSecretService.present &&
        !usesSecretService) {
      return null;
    }
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
    if (_linuxSecretService == null) await capabilities();
    final usesSecretService = await tier.exists();
    if (!usesSecretService &&
        !existsLocally &&
        _linuxSecretService == _LinuxSecretService.failed) {
      // A provider exists but did not answer. Storing this new credential
      // unattended would make that the key's permanent tier; the next
      // capabilities() call probes again.
      throw const WalletAccessException(WalletAccessFailure.unavailable);
    }
    if (usesSecretService ||
        (!existsLocally &&
            _linuxSecretService == _LinuxSecretService.present)) {
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

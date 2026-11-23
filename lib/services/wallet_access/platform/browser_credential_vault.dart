import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'passkey/passkey_envelope.dart' show passkeyBytesEqual;

part 'browser_credential_api.dart';
part 'browser_credential_crypto.dart';
part 'browser_credential_store.dart';

const _schema = 1;
const _databaseName = 'gleec-wallet-credentials-v1';
const _storeName = 'credentials';
const _eventName = 'gleecWalletProtectionChanged';
const _browserLocal = 'browserLocal';
const _passkeyPrf = 'passkeyPrf';

final class _VaultFailure implements Exception {
  const _VaultFailure(this.code);

  final String code;
}

Never _fail(String code) => throw _VaultFailure(code);

String? _errorName(Object error) {
  try {
    return (error as JSObject).getProperty<JSString?>('name'.toJS)?.toDart;
  } on Object {
    return null;
  }
}

_VaultFailure _safeFailure(Object error) {
  if (error is _VaultFailure) return error;
  return _VaultFailure(switch (_errorName(error)) {
    'AbortError' => 'aborted',
    // Browsers group dismissal, missing credentials and policy denials.
    'NotAllowedError' => 'notCompleted',
    'NotSupportedError' => 'unsupported',
    'SecurityError' => 'unavailable',
    _ => 'storageFailed',
  });
}

String _walletKey(String key) {
  if (key.isEmpty || key.length > 512) _fail('invalidResponse');
  return key;
}

String _secret(String value) {
  if (value.isEmpty || value.length > 16384) _fail('invalidResponse');
  return value;
}

@JS('Object.is')
external bool _sameObject(JSAny? first, JSAny? second);

@JS('Number.isSafeInteger')
external bool _isSafeInteger(JSAny? value);

int? _safeInteger(JSAny? value) =>
    _isSafeInteger(value) ? (value as JSNumber).toDartInt : null;

extension type _VaultEnvironment(JSObject _) implements JSObject {
  external web.Crypto? get crypto;
  external web.IDBFactory? get indexedDB;
  external _VaultNavigator? get navigator;
  external web.Document? get document;
  external web.Location? get location;
  external web.Performance? get performance;
  external JSObject? get top;
  external JSObject? get self;
  external bool? get isSecureContext;
  @JS('PublicKeyCredential')
  external JSObject? get publicKeyCredential;
  @JS('PasswordCredential')
  external JSFunction? get passwordCredential;
  @JS('BroadcastChannel')
  external JSFunction? get broadcastChannel;
  @JS('CustomEvent')
  external JSFunction? get customEvent;
  external JSFunction? get addEventListener;
  external JSFunction? get dispatchEvent;
}

extension type _VaultNavigator(JSObject _) implements JSObject {
  external web.CredentialsContainer? get credentials;
  external web.LockManager? get locks;
  external web.StorageManager? get storage;
}

extension type _VaultCrypto(JSObject _) implements JSObject {
  external web.SubtleCrypto? get subtle;
}

typedef _Origin = ({String host, String url});

final class _Operation {
  _Operation(this.generation);

  final int generation;
  final controller = web.AbortController();
  web.AbortSignal get signal => controller.signal;
}

typedef _DeletionPermit = ({
  String authorization,
  String key,
  int revision,
  int generation,
  double expires,
});

/// Browser-local credential authority shared by the app and browser probes.
/// The IndexedDB schema and WebCrypto formats are also read by older builds.
final class BrowserCredentialVault {
  BrowserCredentialVault(JSObject environment, {BrowserCredentialStore? store})
    : _environment = _VaultEnvironment(environment),
      _store =
          store ?? _IndexedDbCredentialStore(_VaultEnvironment(environment)) {
    final channel = _environment.broadcastChannel
        ?.callAsConstructor<web.BroadcastChannel>(_databaseName.toJS);
    _channel = channel;
    channel?.onmessage = ((web.MessageEvent event) {
      final data = event.data.dartify();
      if (data is! Map ||
          data['key'] is! String ||
          !data.containsKey('revision') ||
          !data.containsKey('protection') ||
          !const {
            null,
            _browserLocal,
            _passkeyPrf,
          }.contains(data['protection'])) {
        return;
      }
      final Object? revision = data['revision'];
      if (revision != null && !_isSafeInteger(revision.jsify())) return;
      cancel();
      _emit({
        'key': data['key'],
        'revision': revision,
        'protection': data['protection'],
        'external': true,
      });
    }).toJS;
    _environment.document?.addEventListener(
      'visibilitychange',
      (() {
        if (_environment.document?.visibilityState == 'hidden') cancel();
      }).toJS,
    );
    if (_environment.addEventListener != null) {
      (_environment as web.EventTarget).addEventListener(
        'pagehide',
        cancel.toJS,
      );
    }
  }

  final _VaultEnvironment _environment;
  final BrowserCredentialStore _store;
  late final web.BroadcastChannel? _channel;
  final _subscribers = <JSFunction>{};
  int _generation = 0;
  _Operation? _operation;
  _DeletionPermit? _permit;
  String? _pendingDeletion;
  bool _requestedPersistence = false;

  web.Crypto get _crypto => _environment.crypto ?? _fail('unavailable');
  web.SubtleCrypto get _subtle =>
      (_crypto as _VaultCrypto).subtle ?? _fail('unavailable');
  web.LockManager? get _locks => _environment.navigator?.locks;
  web.CredentialsContainer? get _credentials =>
      _environment.navigator?.credentials;

  _Origin _origin() {
    final location = _environment.location;
    final host = location?.hostname;
    final local = const {'localhost', '127.0.0.1', '[::1]'}.contains(host);
    final top = _environment.top;
    final self = _environment.self;
    if (_environment.isSecureContext != true ||
        (_environment.crypto as _VaultCrypto?)?.subtle == null ||
        location == null ||
        (location.protocol != 'https:' &&
            !(local && location.protocol == 'http:')) ||
        (top != null && self != null && !_sameObject(top, self))) {
      _fail('unavailable');
    }
    return (host: location.hostname, url: location.origin);
  }

  void _assertCurrent(_Operation operation) {
    if (operation.generation != _generation || operation.signal.aborted) {
      _fail('staleOperation');
    }
    if (_environment.document?.visibilityState == 'hidden') _fail('aborted');
  }

  void _clearPermits() {
    _permit = null;
    _pendingDeletion = null;
  }

  void cancel() {
    _generation++;
    _clearPermits();
    _operation?.controller.abort();
  }

  void _emit(Map<String, Object?> detail) {
    final message = _freeze(detail.jsify() as JSObject);
    for (final subscriber in _subscribers.toList()) {
      subscriber.callAsFunction(null, message);
    }
    final constructor = _environment.customEvent;
    if (constructor != null && _environment.dispatchEvent != null) {
      final event = constructor.callAsConstructor<web.CustomEvent>(
        _eventName.toJS,
        web.CustomEventInit(detail: message),
      );
      (_environment as web.EventTarget).dispatchEvent(event);
    }
  }

  void _notify(String key, BrowserCredentialRecord? record) {
    _clearPermits();
    final message = {
      'key': key,
      'revision': record?.revision,
      'protection': record?.protection,
    };
    _channel?.postMessage(message.jsify());
    _emit({...message, 'external': false});
  }

  JSFunction subscribe(JSFunction callback) {
    _subscribers.add(callback);
    return (() => _subscribers.remove(callback).toJS).toJS;
  }

  Future<T> _exclusive<T>(
    Future<T> Function(_Operation) action, {
    bool automatic = false,
  }) async {
    if (_operation != null) _fail('busy');
    final locks = _locks;
    if (automatic &&
        (locks == null || _environment.document?.hasFocus() == false)) {
      _fail('notCompleted');
    }

    final operation = _Operation(_generation);
    _operation = operation;
    Future<T> run() async {
      _assertCurrent(operation);
      return action(operation);
    }

    try {
      // IndexedDB still compares revisions when an explicit operation has
      // no Web Locks. Automatic prompts require cross-tab coordination.
      if (locks == null) return await run();
      late Future<T> held;
      Future<JSAny?> whileLocked(web.Lock? lock) async {
        held = lock == null
            ? Future<T>.error(const _VaultFailure('busy'))
            : run();
        try {
          await held;
        } on Object {
          // Carry the actual Dart failure back across the browser callback.
        }
        return null;
      }

      await locks
          .request(
            _databaseName,
            web.LockOptions(mode: 'exclusive', ifAvailable: true),
            ((web.Lock? lock) => whileLocked(lock).toJS).toJS,
          )
          .toDart;
      return await held;
    } on Object catch (error) {
      throw _safeFailure(error);
    } finally {
      _operation = null;
    }
  }

  void _requestPersistence() {
    final storage = _environment.navigator?.storage;
    if (_requestedPersistence ||
        storage == null ||
        !storage.hasProperty('persist'.toJS).toDart) {
      return;
    }
    _requestedPersistence = true;
    try {
      final pending = storage.persist().toDart;
      unawaited(pending.then<void>((_) {}, onError: (Object _) {}));
    } on Object {
      // A storage grant is best effort. It is never required to finish a write.
    }
  }

  String _issuePermit(BrowserCredentialRecord record, _Operation operation) {
    final now = _environment.performance?.now() ?? _fail('unavailable');
    final authorization = _identifier();
    _permit = (
      authorization: authorization,
      key: record.key,
      revision: record.revision!,
      generation: operation.generation,
      expires: now + const Duration(minutes: 1).inMilliseconds,
    );
    return authorization;
  }

  bool _validPermit(
    _DeletionPermit? permit,
    String? authorization,
    BrowserCredentialRecord record,
    _Operation operation,
  ) =>
      permit != null &&
      permit.authorization == authorization &&
      permit.key == record.key &&
      permit.revision == record.revision &&
      permit.generation == operation.generation &&
      (_environment.performance?.now() ?? double.infinity) < permit.expires;

  BrowserCredentialRecord _validate(
    BrowserCredentialRecord? record,
    String key,
  ) {
    final origin = _origin();
    try {
      if (record != null &&
          _sameObject(record.schema, _schema.toJS) &&
          record.key == key &&
          (record.revision ?? 0) > 0 &&
          record.origin == origin.url &&
          const {_browserLocal, _passkeyPrf}.contains(record.protection)) {
        return record;
      }
    } on Object {
      // Old or malformed records keep the vault's redacted error contract.
    }
    _fail('envelopeCorrupt');
  }

  Map<String, Object?> _metadata(BrowserCredentialRecord record) => {
    'protection': record.protection,
    'revision': record.revision,
    'enrolled': record.protection == _passkeyPrf,
  };

  Future<Map<String, Object?>> capabilities() async {
    var available = false;
    var passkeys = false;
    var automatic = false;
    try {
      _origin();
      available =
          _environment.indexedDB != null ||
          _store is! _IndexedDbCredentialStore;
      automatic = _locks != null;
      final credentialType = _environment.publicKeyCredential;
      passkeys = credentialType != null && _credentials != null && automatic;
      if (passkeys &&
          credentialType
              .getProperty<JSAny?>('getClientCapabilities'.toJS)
              .isA<JSFunction>()) {
        try {
          final supported = await credentialType
              .callMethod<JSPromise<JSObject?>>('getClientCapabilities'.toJS)
              .toDart
              .timeout(const Duration(seconds: 1), onTimeout: () => null);
          if (supported != null) {
            passkeys = _sameObject(
              supported.getProperty<JSAny?>('extension:prf'.toJS),
              true.toJS,
            );
          }
        } on Object {
          // Detection is advisory. Enrollment still proves PRF and readback.
        }
      }
    } on Object {
      available = passkeys = automatic = false;
    }
    return {
      'available': available,
      'protection': _browserLocal,
      'deviceAuthentication': false,
      'passkeys': passkeys,
      'automaticPrompt': automatic,
    };
  }

  Future<Map<String, Object?>?> metadata(String key) async {
    _walletKey(key);
    final record = await _store.get(key);
    return record == null ? null : _metadata(_validate(record, key));
  }

  Future<void> write(
    String key,
    String value, {
    required bool requireAuthentication,
  }) async {
    _walletKey(key);
    _secret(value);
    final created = await _exclusive((operation) async {
      final origin = _origin();
      final previous = await _store.get(key);
      if (previous != null) _validate(previous, key);
      if (previous?.protection == _passkeyPrf) {
        if (!requireAuthentication) _fail('invalidated');
        final encryptionKey = await _unlockKey(previous!, operation);
        // Keep the existing proof of the old envelope before resealing.
        await _decrypt(previous, encryptionKey);
        final next = _copyRecord(previous);
        next.rawRevision = (previous.revision! + 1).toJS;
        await _sealAndCommit(previous, next, value, encryptionKey, operation);
        return false;
      }
      if (requireAuthentication) _fail('unavailable');
      final encryptionKey = await _createLocalKey();
      final next = BrowserCredentialRecord(
        schema: _schema,
        key: key,
        origin: origin.url,
        protection: _browserLocal,
        revision: (previous?.revision ?? 0) + 1,
        unattendedKey: encryptionKey,
      );
      await _sealAndCommit(previous, next, value, encryptionKey, operation);
      return previous == null;
    });
    if (created) _requestPersistence();
  }

  Future<String?> read(
    String key, {
    required bool requireAuthentication,
    required bool automatic,
    String? purpose,
  }) {
    _walletKey(key);
    return _exclusive((operation) async {
      _origin();
      final stored = await _store.get(key);
      if (stored == null) return null;
      final record = _validate(stored, key);
      if (requireAuthentication && record.protection != _passkeyPrf) {
        _fail('unavailable');
      }
      final value = await _decrypt(record, await _unlockKey(record, operation));
      await _confirmCurrent(record, operation);
      if (purpose == 'delete' && !automatic) {
        _pendingDeletion = _issuePermit(record, operation);
      }
      return value;
    }, automatic: automatic);
  }

  Future<void> _confirmCurrent(
    BrowserCredentialRecord record,
    _Operation operation,
  ) async {
    _assertCurrent(operation);
    if ((await _store.get(record.key))?.revision != record.revision) {
      _fail('staleOperation');
    }
    _assertCurrent(operation);
  }

  Future<String?> prepareDelete(String key) {
    _walletKey(key);
    return _exclusive((operation) async {
      final stored = await _store.get(key);
      if (stored == null) return null;
      final record = _validate(stored, key);
      final prepared = _pendingDeletion;
      _pendingDeletion = null;
      if (_validPermit(_permit, prepared, record, operation)) return prepared;
      if (record.protection == _passkeyPrf) {
        await _decrypt(record, await _unlockKey(record, operation));
      }
      await _confirmCurrent(record, operation);
      return _issuePermit(record, operation);
    });
  }

  // Recovery callers verify the password against the current engine wallet.
  // This path changes the protected envelope without revealing its old value.
  Future<String> prepareDeleteAfterPasswordVerification(
    String key,
    int expectedRevision,
  ) {
    _walletKey(key);
    return _exclusive((operation) async {
      final record = await _verifiedPasskeyRevision(key, expectedRevision);
      _assertCurrent(operation);
      return _issuePermit(record, operation);
    });
  }

  Future<void> delete(String key, String? authorization) {
    _walletKey(key);
    return _exclusive((operation) async {
      final previous = await _store.get(key);
      final permit = _permit;
      if (permit?.authorization == authorization) _permit = null;
      if (previous != null) {
        _validate(previous, key);
        if (previous.protection == _passkeyPrf &&
            !_validPermit(permit, authorization, previous, operation)) {
          _fail('staleOperation');
        }
      }
      _assertCurrent(operation);
      await _store.remove(key, previous?.revision, operation.signal);
      if (await _store.get(key) != null) _fail('storageFailed');
      _notify(key, null);
    });
  }

  void _requirePasskeyEnrollment() {
    if (_environment.publicKeyCredential == null || _credentials == null) {
      _fail('unsupported');
    }
    if (_locks == null) _fail('unavailable');
  }

  Future<Map<String, Object?>> enrollPasskey(
    String key,
    String value,
    String label,
  ) {
    _walletKey(key);
    _secret(value);
    return _exclusive((operation) async {
      _origin();
      _requirePasskeyEnrollment();
      final previous = await _store.get(key);
      if (previous != null) {
        _validate(previous, key);
        final current = await _decrypt(
          previous,
          await _unlockKey(previous, operation),
        );
        if (current != value) _fail('invalidResponse');
      }
      return _registerPasskey(key, value, label, previous, operation);
    });
  }

  Future<BrowserCredentialRecord> _verifiedPasskeyRevision(
    String key,
    int expectedRevision,
  ) async {
    if (expectedRevision < 1) _fail('invalidResponse');
    if (_locks == null) _fail('unavailable');
    final previous = await _store.get(key) ?? _fail('walletUnavailable');
    _validate(previous, key);
    if (previous.protection != _passkeyPrf) _fail('invalidated');
    if (previous.revision != expectedRevision) _fail('staleOperation');
    return previous;
  }

  Future<Map<String, Object?>> replacePasskeyAfterPasswordVerification(
    String key,
    String value,
    int expectedRevision,
    String label,
  ) {
    _walletKey(key);
    _secret(value);
    return _exclusive((operation) async {
      final previous = await _verifiedPasskeyRevision(key, expectedRevision);
      return _registerPasskey(key, value, label, previous, operation);
    });
  }

  Future<String> savePassword(String username, String password, String title) {
    _secret(password);
    return _exclusive((_) async {
      _origin();
      final constructor = _environment.passwordCredential;
      final credentials = _credentials;
      if (constructor == null ||
          credentials == null ||
          !credentials.hasProperty('store'.toJS).toDart) {
        return 'unavailable';
      }
      try {
        final credential = constructor.callAsConstructor<web.Credential>(
          _object({'id': username, 'password': password, 'name': title}),
        );
        await credentials.store(credential).toDart;
        // A fulfilled browser request does not report a provider save decision.
        return 'unknown';
      } on Object catch (error) {
        return switch (_errorName(error)) {
          'NotAllowedError' || 'AbortError' => 'declined',
          _ => 'failed',
        };
      }
    });
  }
}

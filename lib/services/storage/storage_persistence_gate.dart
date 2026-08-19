import 'package:logging/logging.dart';
import 'package:web_dex/services/storage/base_storage.dart';
import 'package:web_dex/services/storage/storage_persistence_stub.dart'
    if (dart.library.js_interop) 'storage_persistence_web.dart';

export 'package:web_dex/services/storage/storage_persistence_stub.dart'
    if (dart.library.js_interop) 'storage_persistence_web.dart'
    show StoragePersistence;

/// Decides *when* to ask the browser for persistent storage.
///
/// The probe itself is three lines of js_interop behind a conditional import;
/// everything worth testing is the pacing, so it lives here where the VM can
/// reach it.
///
/// Timing is the whole design. Chromium auto-grants on engagement heuristics
/// and silently auto-denies otherwise, so asking on a first visit is a near
/// certain no - but denials are *not* sticky, which makes retrying on later
/// sign-ins free and often eventually successful. Firefox shows a real
/// permission prompt, and spending it on first paint, before the user knows
/// what the app is, wastes the ask. So: ask at sign-in, once per session, and
/// back off after a refusal.
class StoragePersistenceGate {
  StoragePersistenceGate({
    required BaseStorage storage,
    Future<StoragePersistence> Function()? probe,
    DateTime Function()? now,
  }) : _storage = storage,
       _probe = probe ?? requestPersistentStorage,
       _now = now ?? DateTime.now;

  static const String _backoffKey = 'storage_persistence_denied_at';
  static const Duration _denialBackoff = Duration(days: 30);

  final BaseStorage _storage;
  final Future<StoragePersistence> Function() _probe;
  final DateTime Function() _now;
  final Logger _log = Logger('StoragePersistenceGate');

  bool _askedThisSession = false;

  /// Runs the probe if it is worth running.
  ///
  /// Returns the outcome, or null when nothing was asked - callers should only
  /// report an analytics result for a non-null value, or the grant/deny rates
  /// get diluted by sessions that never probed.
  Future<StoragePersistence?> maybeRequest() async {
    if (_askedThisSession) return null;
    _askedThisSession = true;

    try {
      if (await _isBackingOff()) return null;

      final result = await _probe();
      if (result == StoragePersistence.denied) {
        await _storage.write(_backoffKey, _now().toIso8601String());
      }
      return result;
    } catch (error) {
      // Defence in depth for the wallet's storage must never be able to break
      // the auth path it hangs off.
      _log.warning('Storage persistence request failed: $error');
      return null;
    }
  }

  Future<bool> _isBackingOff() async {
    final raw = await _storage.read(_backoffKey);
    if (raw is! String) return false;
    final deniedAt = DateTime.tryParse(raw);
    if (deniedAt == null) return false;
    return _now().difference(deniedAt) < _denialBackoff;
  }
}

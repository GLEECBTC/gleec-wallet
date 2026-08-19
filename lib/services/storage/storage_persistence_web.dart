import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// The outcome of asking the browser to keep this origin's storage.
///
/// Must stay identical to the stub's copy - a conditional import presents one
/// API and the analyzer resolves whichever side matches the platform.
enum StoragePersistence { alreadyPersistent, granted, denied, unsupported }

/// Asks the browser not to evict this origin's storage under pressure.
///
/// One grant covers the whole origin, so a single call protects everything the
/// wallet depends on at once: localStorage, the Hive/IndexedDB stores,
/// `flutter_secure_storage`, and KDF's own IndexedDB where the seeds actually
/// live.
///
/// **This does close to nothing on Safari and iOS.** WebKit's 7-day cap on
/// script-writable storage is not exempted by `persist()`; the documented
/// exemption is Add-to-Home-Screen. Expect grants on Chromium and Firefox and
/// continued exposure on WebKit. Persistence is defence in depth - the real
/// protection is the user having written down their recovery phrase.
///
/// Never throws. Storage persistence is an optimisation, and a browser that
/// dislikes the question must not be able to break sign-in.
Future<StoragePersistence> requestPersistentStorage() async {
  try {
    final navigator = web.window.navigator;
    // `package:web` types `storage` as non-nullable, but it is genuinely absent
    // on older Safari and in non-secure contexts.
    if (!(navigator as JSObject).has('storage')) {
      return StoragePersistence.unsupported;
    }

    final storage = navigator.storage;

    // Cheap, never prompts, and avoids re-asking a browser that already said
    // yes - which on Firefox would mean a redundant permission prompt.
    final alreadyPersisted = await storage.persisted().toDart;
    if (alreadyPersisted.toDart) return StoragePersistence.alreadyPersistent;

    final granted = await storage.persist().toDart;
    return granted.toDart
        ? StoragePersistence.granted
        : StoragePersistence.denied;
  } catch (_) {
    return StoragePersistence.unsupported;
  }
}

import 'dart:js_interop';

import 'package:web/web.dart' as web;

String getOriginUrl() {
  return web.window.location.origin;
}

void showMessageBeforeUnload(String message) {
  web.window.onbeforeunload = (web.BeforeUnloadEvent event) {
    event
      ..preventDefault()
      ..returnValue = message;
  }.toJS;
}

/// Reloads the page, bypassing everything this client controls that could
/// serve it the build it is already running.
///
/// The dominant cause of a stale reload is the HTTP cache: the boot files are
/// served at stable names, so a client holds them for the full `max-age`.
/// **JS cannot purge the HTTP cache**, so that half is fixed by response
/// headers in `firebase.json`, not here.
///
/// What this function can do is drop the two client-side caches that would
/// otherwise survive a reload, and get out of the way of the reload itself:
///
/// - Service workers. Both deployed sites currently serve Flutter's modern
///   self-unregistering worker, which caches nothing, so in practice there is
///   usually nothing to remove. This is kept for clients still pinned by an
///   older caching `flutter_service_worker.js`, which would otherwise answer
///   the reload from its own `RESOURCES` map.
/// - `CacheStorage`. Neither the app nor the SDK writes to it, so anything
///   found there was put there by a service worker and is safe to drop.
///   Wallet data is untouched: seeds and Hive boxes live in IndexedDB and
///   `localStorage`, which `caches.delete()` cannot reach.
///
/// Never throws, and always reloads: every cleanup step is best-effort, and a
/// reload that skipped them still beats no reload at all.
Future<void> hardReloadPage() async {
  try {
    // main_layout registers a beforeunload handler on web. Left in place it
    // turns the reload into a browser confirmation dialog the user has to
    // accept, immediately after they already confirmed in our own popup.
    web.window.onbeforeunload = null;
  } catch (_) {}

  try {
    await _clearClientSideCaches().timeout(const Duration(seconds: 3));
  } catch (_) {
    // Unavailable API, insecure context, or slow cleanup. Reload regardless:
    // the headers are what the reload actually depends on.
  }

  web.window.location.reload();
}

Future<void> _clearClientSideCaches() async {
  try {
    final registrations =
        (await web.window.navigator.serviceWorker.getRegistrations().toDart)
            .toDart;
    for (final registration in registrations) {
      await registration.unregister().toDart;
    }
  } catch (_) {}

  try {
    final cacheKeys = (await web.window.caches.keys().toDart).toDart;
    for (final key in cacheKeys) {
      await web.window.caches.delete(key.toDart).toDart;
    }
  } catch (_) {}
}

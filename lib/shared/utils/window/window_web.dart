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

/// Best-effort removal of anything that can pin the client to a stale build,
/// then a full page reload.
///
/// Unregisters service workers and clears CacheStorage so the reload cannot
/// be served from a legacy caching `flutter_service_worker.js`. The browser
/// HTTP cache cannot be purged from JS, so entry files additionally rely on
/// `Cache-Control: no-cache` response headers (see firebase.json).
///
/// Never throws; the reload always runs.
Future<void> hardReloadPage() async {
  try {
    // Drop the "Are you sure you want to leave?" prompt registered by
    // showMessageBeforeUnload so the reload is not blocked by a browser
    // confirmation dialog.
    web.window.onbeforeunload = null;
  } catch (_) {}

  try {
    await _unregisterServiceWorkersAndClearCaches().timeout(
      const Duration(seconds: 3),
    );
  } catch (_) {
    // Best-effort cleanup only (insecure context, API unavailable, or
    // timeout) — always proceed to the reload.
  }

  web.window.location.reload();
}

Future<void> _unregisterServiceWorkersAndClearCaches() async {
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

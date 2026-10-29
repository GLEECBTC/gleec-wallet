import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;

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

const _reducedMotionQuery = '(prefers-reduced-motion: reduce)';

/// Whether the browser asks for less motion. Flutter 3.41's web engine does
/// not pass this to `MediaQuery`.
bool prefersReducedMotion() =>
    web.window.matchMedia(_reducedMotionQuery).matches;

/// Calls [onChange] whenever the browser's reduced-motion preference changes,
/// and returns a function that stops listening.
void Function() watchReducedMotion(void Function(bool reduce) onChange) {
  final query = web.window.matchMedia(_reducedMotionQuery);
  final listener = ((web.Event _) => onChange(query.matches)).toJS;
  query.addEventListener('change', listener);
  return () => query.removeEventListener('change', listener);
}

/// The tab icons' own addresses, kept while a badge stands in for them.
final Map<web.HTMLLinkElement, String> _tabIcons = {};
final Map<int, String> _badgedIcons = {};
var _badgeRequest = 0;

/// Marks the tab's icon with a dot of [argb], or puts the icon back when
/// [argb] is null. Best-effort: if the icon cannot be drawn, the tab keeps
/// it unmarked.
void setTabIconBadge(int? argb) {
  final request = ++_badgeRequest;
  final nodes = web.document.querySelectorAll('link[rel~="icon"]');
  final links = [
    for (var i = 0; i < nodes.length; i++)
      nodes.item(i)! as web.HTMLLinkElement,
  ];
  for (final link in links) {
    _tabIcons.putIfAbsent(link, () => link.href);
  }
  if (argb == null) {
    for (final link in links) {
      link.href = _tabIcons[link] ?? link.href;
    }
    return;
  }
  final source = links
      .where((link) => link.getAttribute('sizes') == '32x32')
      .followedBy(links)
      .map((link) => _tabIcons[link])
      .firstOrNull;
  if (source == null) return;
  unawaited(
    _badgedIcon(source, argb).then((href) {
      if (href == null || request != _badgeRequest) return;
      for (final link in links) {
        link.href = href;
      }
    }),
  );
}

/// [source] drawn at 32 px with a dot in its lower corner, as a data URL.
Future<String?> _badgedIcon(String source, int argb) async {
  final cached = _badgedIcons[argb];
  if (cached != null) return cached;
  try {
    final image = web.HTMLImageElement()..src = source;
    await image.decode().toDart;
    const size = 32;
    final canvas = web.HTMLCanvasElement()
      ..width = size
      ..height = size;
    final context = canvas.getContext('2d')! as web.CanvasRenderingContext2D;
    context.drawImage(image, 0, 0, size, size);
    for (final (radius, colour) in [
      (9.0, 'rgba(255,255,255,1)'),
      (7.0, _css(argb)),
    ]) {
      context
        ..beginPath()
        ..arc(23, 23, radius, 0, 2 * math.pi)
        ..fillStyle = colour.toJS
        ..fill();
    }
    return _badgedIcons[argb] = canvas.toDataURL('image/png');
  } catch (_) {
    return null;
  }
}

String _css(int argb) =>
    'rgba(${argb >> 16 & 0xff},${argb >> 8 & 0xff},${argb & 0xff},'
    '${(argb >> 24 & 0xff) / 255})';

/// Web-only: who blocked the main thread, not just that it was blocked.
///
/// The frame-gap metrics say how many frames never happened. They cannot say
/// why, and on web that question has exactly one interesting answer: was it
/// KDF's wasm or was it our Dart. Both run on the same thread as Flutter's
/// build and raster, so nothing in `FrameTiming` can separate them.
///
/// `long-animation-frame` (LoAF) can. Each entry carries a `scripts[]` array
/// whose entries name a `sourceURL`, which cleanly separates
/// `.../kdf/kdf/bin/kdflib.js` from `main.dart.js` with no changes to either
/// codebase.
///
/// Deliberately **not** `longtask`: its `attribution` field is
/// `TaskAttributionTiming`, designed for iframes, and for a same-document task
/// it reports `"window"` with empty fields - i.e. it confirms the thread was
/// blocked and says nothing at all about by what, which is the only part we
/// need.
///
/// Known limits, which the caller is expected to print alongside the numbers:
///
/// * **50ms floor.** LoAF does not report shorter frames, so a login made slow
///   by a thousand 20ms bloc emissions is invisible here. That shape has to be
///   caught by `Timeline` spans on the Dart side instead.
/// * **Chrome only.** No Firefox, no Safari. [installFrameAttribution] returns
///   false there rather than reporting zeroes.
/// * **Attributes to the entry point.** Wasm called synchronously from Dart is
///   credited to `main.dart.js`, so this *understates* KDF. Treat the KDF
///   number as a floor.
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Reserved keys in the snapshot map. A `~` prefix cannot collide with a URL.
const String blockingKey = '~blocking';
const String countKey = '~count';
const String totalKey = '~total';

/// Cumulative milliseconds, keyed by script source URL plus the reserved keys.
final Map<String, double> _totals = <String, double>{};

bool _installed = false;
bool _available = false;

/// Installs the observer. Idempotent; returns whether attribution is available.
bool installFrameAttribution() {
  if (_installed) return _available;
  _installed = true;

  try {
    final supported = web.PerformanceObserver.supportedEntryTypes.toDart
        .map((JSString e) => e.toDart)
        .toList();
    if (!supported.contains('long-animation-frame')) return false;

    final observer = web.PerformanceObserver(
      (web.PerformanceObserverEntryList list, web.PerformanceObserver _) {
        _consume(list);
      }.toJS,
    );

    // `buffered: true` delivers entries recorded before this ran. The recorder
    // installs early, but wasm instantiation is one of the longest tasks in the
    // session and starts before any Dart does.
    observer.observe(
      web.PerformanceObserverInit(
        type: 'long-animation-frame',
        buffered: true,
      ),
    );
    _available = true;
  } catch (_) {
    // A diagnostics probe must never be able to break startup. An unsupported
    // entry type throws in some engines rather than being absent from
    // `supportedEntryTypes`.
    _available = false;
  }
  return _available;
}

/// A copy of the running totals, or null when attribution is unavailable.
///
/// The caller diffs two of these to scope attribution to a span. Diffing rather
/// than start/stop keeps overlapping spans independent.
Map<String, double>? captureFrameAttribution() =>
    _available ? Map<String, double>.of(_totals) : null;

void _consume(web.PerformanceObserverEntryList list) {
  try {
    final entries = list.getEntries().toDart;
    for (final entry in entries) {
      // Read through `toJSON()` rather than a typed extension: `package:web`
      // 1.1.1 has no `PerformanceLongAnimationFrameTiming` type, and this also
      // keeps working if the shape gains fields.
      final json = entry.toJSON().dartify();
      if (json is! Map) continue;

      _add(totalKey, _num(json['duration']));
      _add(blockingKey, _num(json['blockingDuration']));
      _add(countKey, 1);

      final scripts = json['scripts'];
      if (scripts is! List) continue;
      for (final script in scripts) {
        if (script is! Map) continue;
        final url = script['sourceURL'];
        _add(_bucket(url is String ? url : ''), _num(script['duration']));
      }
    }
  } catch (_) {
    // Same reason as above: never throw out of a browser callback.
  }
}

/// Collapses a URL to the thing being asked about. Full URLs carry a cache-
/// busting hash and an origin, neither of which distinguishes KDF from us.
String _bucket(String url) {
  if (url.isEmpty) return 'anonymous';
  if (url.contains('kdflib')) return 'kdf-wasm';
  if (url.contains('main.dart')) return 'dart-app';
  if (url.contains('flutter')) return 'flutter-engine';
  final slash = url.lastIndexOf('/');
  return slash >= 0 && slash < url.length - 1 ? url.substring(slash + 1) : url;
}

double _num(Object? value) => value is num ? value.toDouble() : 0;

void _add(String key, double value) =>
    _totals[key] = (_totals[key] ?? 0) + value;

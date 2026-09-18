import 'dart:async';
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/analytics/frame_attribution_stub.dart'
    if (dart.library.js_interop) 'package:web_dex/analytics/frame_attribution_web.dart';
import 'package:web_dex/analytics/wallet_load_timeline.dart';
import 'package:web_dex/shared/constants.dart';

/// In-app frame-timing capture.
///
/// Answers "did this flow drop frames", which none of the other perf tooling in
/// this repo can see - `komodo_defi_harness`, the KDF probes and the wallet-load
/// timeline all measure wall-clock seconds.
///
/// Everything here is behind the const [frameTimingCaptureEnabled] gate, so a
/// normal build tree-shakes the recorder out entirely. Widgets must go through
/// the top-level [frameSpanStart] / [frameSpanEnd] functions rather than
/// touching the class, or the const guard stops being the only entry point.
///
/// Span names reuse the snake_case vocabulary of `WalletLoadMark.eventName`, so
/// a frame span lines up with the load timings printed next to it by
/// `tool/parse_wallet_load_log.dart`.
///
/// Output is one INFO line per closed span, plus a second `[gap]` line. INFO
/// survives release builds, so the numbers reach a user's "Download Logs"
/// export without a runtime toggle.
///
/// ## Why the `[gap]` line exists
///
/// Build and raster durations only describe frames that *happened*. On web a
/// long task prevents the frame from happening at all - the browser never fires
/// the rAF - so main-thread blocking shows up as **missing frames**, not as a
/// long `buildDuration`. Scoring jank purely as `max(build, raster) > budget`
/// therefore reports "few frames, all fast" for exactly the stall we are
/// hunting. The gap between consecutive `vsyncStart` timestamps is the signal
/// that does see it, on every platform.

final _log = Logger('FrameTiming');

/// How long to keep collecting after a span is closed.
///
/// The engine batches `FrameTiming` and only flushes when a *new* frame is
/// submitted and the batch is older than ~100ms. A span that emits the instant
/// it closes therefore loses its tail - which, in a stall, is the jankiest part
/// of the window and the whole reason for measuring.
const Duration _tailDrain = Duration(milliseconds: 600);

/// Installs the recorder. No-op unless the build set `FRAME_TIMING_CAPTURE`.
void initFrameTimingCapture() {
  if (!frameTimingCaptureEnabled) return;
  _FrameTimingRecorder.instance.install();
}

/// Opens a named measurement window. No-op when capture is off.
void frameSpanStart(String name) {
  if (!frameTimingCaptureEnabled) return;
  _FrameTimingRecorder.instance.startSpan(name);
}

/// Closes a named window and emits its summary. No-op when capture is off.
///
/// The summary is emitted after [_tailDrain], not synchronously, so late-flushed
/// frames still land in the window they belong to. Calling this twice for the
/// same span is harmless - the second call is ignored.
void frameSpanEnd(String name) {
  if (!frameTimingCaptureEnabled) return;
  _FrameTimingRecorder.instance.endSpan(name);
}

class _Span {
  _Span(this.name, this.startedAtMs);

  final String name;
  final int startedAtMs;

  final List<double> buildMs = <double>[];
  final List<double> rasterMs = <double>[];

  /// Engine-clock timestamps, microseconds. On web these are `performance.now()`
  /// captured at the top of the rAF callback, so consecutive [vsyncUs] deltas
  /// are exactly the frame-arrival gaps.
  final List<int> vsyncUs = <int>[];
  final List<int> rasterFinishUs = <int>[];

  /// Long-animation-frame totals as they stood when the span opened. The
  /// report diffs against a second capture, so overlapping spans stay
  /// independent. Null when attribution is unavailable (any non-Chrome
  /// browser, and every non-web platform).
  Map<String, double>? attributionAtStart;

  /// Set by `endSpan`. Frames keep arriving until the drain timer fires; the
  /// span is only removed and reported then.
  bool closing = false;
}

class _FrameTimingRecorder {
  _FrameTimingRecorder._();

  static final _FrameTimingRecorder instance = _FrameTimingRecorder._();

  final Map<String, _Span> _open = <String, _Span>{};
  bool _installed = false;

  /// Frame budget in milliseconds, derived from the display's refresh rate.
  /// 60Hz gives 16.67ms, a 120Hz ProMotion panel gives 8.33ms - which is why
  /// every emitted line carries the budget it was measured against.
  double _budgetMs = 1000 / 60;
  double _refreshHz = 60;

  bool _attributionAvailable = false;
  bool _deviceLineLogged = false;

  /// Emits the device line, once, on the first span report.
  ///
  /// Not at install time, which is where it belongs logically and where it does
  /// not survive: `install()` runs from `main()` before
  /// `AppBootstrapper.ensureInitialized` attaches the listener to
  /// `Logger.root.onRecord` (`get_logger.dart`). That is a **broadcast**
  /// stream, so a record emitted before the listener exists is dropped with no
  /// error - and the log then reaches `tool/parse_wallet_load_log.dart` with
  /// span lines but no device line, whose verdict reads
  /// "rebuild with FRAME_TIMING_CAPTURE=true" for a build that already had it.
  ///
  /// Spans close long after bootstrap, so emitting here always lands.
  void _logDeviceLine() {
    if (_deviceLineLogged) return;
    _deviceLineLogged = true;

    _log.info(
      'frames[device] refresh ${_refreshHz.toStringAsFixed(1)}Hz '
      'budget ${_budgetMs.toStringAsFixed(1)}ms '
      // defaultTargetPlatform reports the host on web, so name web explicitly.
      'platform ${kIsWeb ? 'web' : defaultTargetPlatform.name} '
      'mode ${kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug')} '
      'attribution ${_attributionAvailable ? 'loaf' : 'none'}',
    );

    if (kDebugMode) {
      _log.info(
        'frames[warning] debug build - build times measure the JIT, not the app',
      );
    }
  }

  void install() {
    if (_installed) return;
    _installed = true;

    final binding = WidgetsBinding.instance;
    _readDisplay(binding);

    // Before anything imports the KDF module, so `buffered: true` still catches
    // the wasm instantiation - one of the longest tasks in the session.
    _attributionAvailable = installFrameAttribution();

    // A throw in a timings callback would reach `catchUnhandledExceptions`,
    // which rethrows outside test mode and would take the app down. Diagnostics
    // must never do that.
    binding.addTimingsCallback((List<FrameTiming> timings) {
      try {
        _onTimings(timings);
      } catch (e, s) {
        // Not `developer.log`: that is a no-op on dart2js, i.e. silent on the
        // one platform this recorder exists for.
        _log.severe('frame timing capture failed', e, s);
      }
    });

    // Bracket the window the wallet-load timeline already reports on, so frame
    // stats print next to the load timings they belong to in
    // `tool/parse_wallet_load_log.dart`. The span name reuses that vocabulary.
    //
    // Chained, not assigned: `onMark` is a single slot, and something else may
    // already own it (or want it later). Overwriting would silently disable
    // whichever observer lost the race.
    final previous = WalletLoadTimeline.instance.onMark;
    WalletLoadTimeline.instance.onMark = (WalletLoadMark mark) {
      previous?.call(mark);
      switch (mark) {
        case WalletLoadMark.signedIn:
          startSpan('wallet_load');
        case WalletLoadMark.firstBalance:
          endSpan('wallet_load');
        default:
          break;
      }
    };
  }

  void _readDisplay(WidgetsBinding binding) {
    final views = binding.platformDispatcher.views;
    if (views.isEmpty) return;
    final hz = views.first.display.refreshRate;
    if (hz > 0) {
      _refreshHz = hz;
      _budgetMs = 1000 / hz;
    }
  }

  void startSpan(String name) {
    if (!_installed) return;
    // A second start while one is open keeps the first. `_activateCoins` can be
    // re-entered (a login racing a session restore), and replacing the span
    // there would mean the *first* `finally` closes the *second* span moments
    // after it opened - reporting a fraction of a second of frames as though it
    // were the whole fan-out. A span that has already closed is not in `_open`,
    // so a genuine second login still gets its own.
    if (_open.containsKey(name)) return;
    _open[name] = _Span(name, DateTime.now().millisecondsSinceEpoch)
      ..attributionAtStart = captureFrameAttribution();
  }

  void endSpan(String name) {
    final span = _open[name];
    if (span == null || span.closing) return;
    span.closing = true;

    final elapsedMs = DateTime.now().millisecondsSinceEpoch - span.startedAtMs;
    Timer(_tailDrain, () {
      _open.remove(name);
      try {
        _emit(span, elapsedMs);
      } catch (e, s) {
        _log.severe('frame timing report failed', e, s);
      }
    });
  }

  void _emit(_Span span, int elapsedMs) {
    _logDeviceLine();
    if (span.buildMs.isEmpty) {
      _log.info('frames[${span.name}] no frames in ${elapsedMs}ms');
      return;
    }

    final build = _Percentiles(span.buildMs);
    final raster = _Percentiles(span.rasterMs);

    // A jank frame is one where either thread blew the budget - a fast build
    // behind a slow raster still drops the frame.
    var jank = 0;
    var severe = 0;
    for (var i = 0; i < span.buildMs.length; i++) {
      final worst = span.buildMs[i] > span.rasterMs[i]
          ? span.buildMs[i]
          : span.rasterMs[i];
      if (worst > _budgetMs) jank++;
      if (worst > _budgetMs * 3) severe++;
    }
    final ratio = 100 * jank / span.buildMs.length;

    // Line 1 is unchanged, byte for byte: logs captured before the `[gap]` line
    // existed still parse, and the two can be compared directly.
    _log.info(
      'frames[${span.name}] ${span.buildMs.length} frames in ${elapsedMs}ms | '
      'build ${build.summary} | raster ${raster.summary} | '
      'jank $jank (${ratio.toStringAsFixed(1)}%) severe $severe | '
      'budget ${_budgetMs.toStringAsFixed(1)}ms',
    );

    _emitGapLine(span);
  }

  void _emitGapLine(_Span span) {
    final metrics = computeFrameGapMetrics(
      vsyncUs: span.vsyncUs,
      rasterFinishUs: span.rasterFinishUs,
      buildMs: span.buildMs,
      rasterMs: span.rasterMs,
      budgetMs: _budgetMs,
    );

    if (metrics == null) {
      _log.info(
        'frames[${span.name}][gap] '
        '${span.vsyncUs.length} frame(s), no usable frame clock - no gap data',
      );
      return;
    }

    _log.info('frames[${span.name}][gap] ${metrics.summary}');
    _emitAttributionLine(span);
  }

  /// Which script blocked the thread, over the life of this span.
  ///
  /// A diff of two cumulative snapshots rather than a start/stop counter, so
  /// two overlapping spans each get their own correct total.
  void _emitAttributionLine(_Span span) {
    final before = span.attributionAtStart;
    final after = captureFrameAttribution();
    if (before == null || after == null) {
      _log.info(
        'frames[${span.name}][attrib] unavailable '
        '(long-animation-frame is Chrome-only; no attribution)',
      );
      return;
    }

    double delta(String key) => (after[key] ?? 0) - (before[key] ?? 0);

    final sources = <String, double>{};
    for (final key in after.keys) {
      if (key.startsWith('~')) continue;
      final value = delta(key);
      if (value > 0) sources[key] = value;
    }

    final ranked = sources.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final breakdown = ranked.isEmpty
        ? 'none'
        : ranked
            .map((e) => '${e.key} ${e.value.round()}ms')
            .join(' ');

    // `blocking` is the browser's own measure of time past the 50ms threshold.
    // It is the honest headline; the per-source numbers below it are a floor,
    // because LoAF credits a whole task to its entry point - wasm invoked
    // synchronously from Dart lands under `dart-app`.
    _log.info(
      'frames[${span.name}][attrib] '
      'loaf ${delta(countKey).round()} '
      'total ${delta(totalKey).round()}ms '
      'blocking ${delta(blockingKey).round()}ms | $breakdown',
    );
  }

  void _onTimings(List<FrameTiming> timings) {
    if (_open.isEmpty) return;
    for (final t in timings) {
      final build = t.buildDuration.inMicroseconds / 1000.0;
      final raster = t.rasterDuration.inMicroseconds / 1000.0;
      final vsync = t.timestampInMicroseconds(FramePhase.vsyncStart);
      final rasterFinish = t.timestampInMicroseconds(FramePhase.rasterFinish);
      for (final span in _open.values) {
        span.buildMs.add(build);
        span.rasterMs.add(raster);
        span.vsyncUs.add(vsync);
        span.rasterFinishUs.add(rasterFinish);
      }
    }
  }
}

/// The frame-arrival view of a span: what the user actually experienced.
///
/// Deliberately outside the [frameTimingCaptureEnabled] gate and public, for
/// two reasons. The recorder is unreachable in a normal build, so the
/// arithmetic every downstream number rests on would otherwise be untestable.
/// And there are two capture paths - this recorder in the app, and
/// `measureFrames` in the integration perf suite - which must produce numbers
/// that mean the same thing, so they share one implementation rather than two
/// that drift.
class FrameGapMetrics {
  const FrameGapMetrics({
    required this.frameCount,
    required this.spanMs,
    required this.possibleFrames,
    required this.yieldPct,
    required this.fps,
    required this.stallMs,
    required this.stallPct,
    required this.missedFrames,
    required this.uiMs,
    required this.rasterMs,
    required this.gapsMs,
  });

  /// Frames the app actually produced in the window.
  final int frameCount;

  /// Window length on the *frame* clock: first vsync to last raster finish.
  final double spanMs;

  /// Frames the display offered over [spanMs] at the measured refresh rate.
  final int possibleFrames;

  /// [frameCount] as a percentage of [possibleFrames].
  ///
  /// **Only interpretable for a window in which something animated the whole
  /// time.** A window with genuine idle - nothing moving, so nothing to paint -
  /// has a low yield and no jank at all. Measured example: the hermetic
  /// coin-list scroll flow reports ~30% yield across three runs while its
  /// median gap sits at one frame budget, i.e. it painted perfectly and simply
  /// had nothing to do between flings.
  ///
  /// Read it against [gapsMs]' median, which idle does not move: a low yield
  /// with a median gap near budget is idle, and a median gap well above budget
  /// is blocking.
  final double yieldPct;

  final double fps;

  /// Time beyond one frame budget that elapsed between consecutive frames,
  /// summed. This is "how long was nothing painted".
  final double stallMs;
  final double stallPct;

  /// Refresh opportunities that went by with nothing painted.
  final int missedFrames;

  /// Σ build. Builds are strictly sequential, so this is always a real
  /// fraction of [spanMs].
  final double uiMs;

  /// Σ raster. On web this is the same thread as [uiMs] and the two add up to
  /// Flutter's share of it. On native raster is a separate thread that
  /// pipelines with the next frame's build, so there the two must **not** be
  /// summed - they can exceed [spanMs]. The `frames[device]` line records which
  /// platform a capture came from.
  final double rasterMs;

  /// Every inter-frame gap, in arrival order.
  final List<double> gapsMs;

  String get summary =>
      'yield ${yieldPct.toStringAsFixed(1)}% ($frameCount/$possibleFrames) '
      'fps ${fps.toStringAsFixed(1)} | '
      'gap ${_Percentiles(gapsMs).summary} | '
      'stall ${stallMs.round()}ms (${stallPct.toStringAsFixed(1)}%) '
      'missed $missedFrames | '
      'ui ${uiMs.round()}ms (${(100 * uiMs / spanMs).toStringAsFixed(1)}%) '
      'raster ${rasterMs.round()}ms '
      '(${(100 * rasterMs / spanMs).toStringAsFixed(1)}%) | '
      'span ${spanMs.round()}ms';
}

/// Computes [FrameGapMetrics], or null when the input cannot support them.
///
/// [spanMs] is derived from the frames themselves rather than from wall clock.
/// That is deliberate: the recorder keeps collecting for [_tailDrain] after a
/// span closes, so the exact closing boundary is fuzzy, and no portable Dart
/// clock is guaranteed to share an origin with `FrameTiming`'s. Taking both the
/// numerator (frames) and the denominator (elapsed frame time) from the same
/// kept frames makes the ratio self-consistent wherever the boundary landed -
/// the fuzz moves both together.
///
/// Returns null for fewer than two frames (no gap exists) or a non-positive
/// span (a non-monotonic clock). Both are reported as "no data" rather than as
/// a zero, because a zeroed metric reads as a passing one.
FrameGapMetrics? computeFrameGapMetrics({
  required List<int> vsyncUs,
  required List<int> rasterFinishUs,
  required List<double> buildMs,
  required List<double> rasterMs,
  required double budgetMs,
}) {
  final frames = vsyncUs.length;
  if (frames < 2 || rasterFinishUs.isEmpty || budgetMs <= 0) return null;

  final spanUs = rasterFinishUs.last - vsyncUs.first;
  if (spanUs <= 0) return null;
  final spanMs = spanUs / 1000.0;

  final gaps = <double>[];
  var stallMs = 0.0;
  var missed = 0;
  for (var i = 1; i < frames; i++) {
    final gapMs = (vsyncUs[i] - vsyncUs[i - 1]) / 1000.0;
    gaps.add(gapMs);
    if (gapMs > budgetMs) stallMs += gapMs - budgetMs;
    final slots = (gapMs / budgetMs).round() - 1;
    if (slots > 0) missed += slots;
  }

  var ui = 0.0;
  var raster = 0.0;
  for (var i = 0; i < buildMs.length; i++) {
    ui += buildMs[i];
    if (i < rasterMs.length) raster += rasterMs[i];
  }

  final possible = spanMs / budgetMs;
  return FrameGapMetrics(
    frameCount: frames,
    spanMs: spanMs,
    possibleFrames: possible.round(),
    yieldPct: 100 * frames / possible,
    fps: 1000 * frames / spanMs,
    stallMs: stallMs,
    stallPct: 100 * stallMs / spanMs,
    missedFrames: missed,
    uiMs: ui,
    rasterMs: raster,
    gapsMs: gaps,
  );
}

class _Percentiles {
  _Percentiles(List<double> values) : _sorted = List<double>.of(values)..sort();

  final List<double> _sorted;

  double _at(double q) {
    if (_sorted.isEmpty) return 0;
    final i = ((_sorted.length - 1) * q).round();
    return _sorted[i];
  }

  String get summary =>
      'p50 ${_at(0.50).toStringAsFixed(1)}ms '
      'p90 ${_at(0.90).toStringAsFixed(1)}ms '
      'p99 ${_at(0.99).toStringAsFixed(1)}ms '
      'max ${(_sorted.isEmpty ? 0 : _sorted.last).toStringAsFixed(1)}ms';
}

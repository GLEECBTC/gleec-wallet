// ignore_for_file: avoid_print

import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_dex/analytics/frame_timing_recorder.dart'
    show computeFrameGapMetrics;

/// Frame-timing capture for integration perf tests.
///
/// Uses `SchedulerBinding.addTimingsCallback` directly rather than
/// `IntegrationTestWidgetsFlutterBinding.watchPerformance`, for two reasons:
/// we need our own percentiles and a refresh-rate-aware jank count, neither of
/// which the SDK summarizer provides; and `watchPerformance` polls forever when
/// a window produces no frames, which turns a mistake into a silent 600s hang.
///
/// The engine batches FrameTiming (~100ms in profile), so a window that ends the
/// instant an action returns loses its tail. [measureFrames] pumps past the
/// batch interval before closing.
class FrameStats {
  FrameStats({
    required this.flow,
    required this.frameCount,
    required this.elapsedMs,
    required this.buildMs,
    required this.rasterMs,
    required this.jankFrames,
    required this.severeJankFrames,
    required this.budgetMs,
    required this.refreshHz,
    this.vsyncUs = const <int>[],
    this.rasterFinishUs = const <int>[],
  });

  final String flow;
  final int frameCount;
  final int elapsedMs;
  final List<double> buildMs;
  final List<double> rasterMs;
  final int jankFrames;
  final int severeJankFrames;
  final double budgetMs;
  final double refreshHz;

  /// Frame-arrival timestamps. Empty for flows captured before these were
  /// collected, in which case the gap metrics are simply absent rather than
  /// reported as zero.
  final List<int> vsyncUs;
  final List<int> rasterFinishUs;

  double get jankRatioPct =>
      frameCount == 0 ? 0 : 100 * jankFrames / frameCount;

  double _pct(List<double> values, double q) {
    if (values.isEmpty) return 0;
    final sorted = List<double>.of(values)..sort();
    return sorted[((sorted.length - 1) * q).round()];
  }

  double _max(List<double> values) =>
      values.isEmpty ? 0 : (List<double>.of(values)..sort()).last;

  double _round(double v) => double.parse(v.toStringAsFixed(2));

  /// The frame-arrival view, shared with the in-app recorder so the driven and
  /// field numbers mean the same thing.
  ///
  /// This is the half that sees a blocked main thread. Build and raster
  /// durations only describe frames that happened; on web a long task stops the
  /// frame happening at all, so the block shows up as absent frames and
  /// `jank_ratio_pct` reads as healthy.
  Map<String, dynamic>? _gapMetrics() {
    final m = computeFrameGapMetrics(
      vsyncUs: vsyncUs,
      rasterFinishUs: rasterFinishUs,
      buildMs: buildMs,
      rasterMs: rasterMs,
      budgetMs: budgetMs,
    );
    if (m == null) return null;
    return <String, dynamic>{
      'yield_pct': _round(m.yieldPct),
      'effective_fps': _round(m.fps),
      'frames_possible': m.possibleFrames,
      'span_ms': _round(m.spanMs),
      'gap_p50_ms': _round(_pct(m.gapsMs, 0.50)),
      'gap_p90_ms': _round(_pct(m.gapsMs, 0.90)),
      'gap_p99_ms': _round(_pct(m.gapsMs, 0.99)),
      'gap_worst_ms': _round(_max(m.gapsMs)),
      'stall_ms': _round(m.stallMs),
      'stall_pct': _round(m.stallPct),
      'missed_frames': m.missedFrames,
      'ui_total_ms': _round(m.uiMs),
      'raster_total_ms': _round(m.rasterMs),
    };
  }

  /// Every value must be a scalar `num`: [medianMetrics] casts them blindly.
  Map<String, dynamic> toMetrics() => <String, dynamic>{
        'frame_count': frameCount,
        'elapsed_ms': elapsedMs,
        ...?_gapMetrics(),
        'build_p50_ms': _round(_pct(buildMs, 0.50)),
        'build_p90_ms': _round(_pct(buildMs, 0.90)),
        'build_p99_ms': _round(_pct(buildMs, 0.99)),
        'build_worst_ms': _round(_max(buildMs)),
        'raster_p50_ms': _round(_pct(rasterMs, 0.50)),
        'raster_p90_ms': _round(_pct(rasterMs, 0.90)),
        'raster_p99_ms': _round(_pct(rasterMs, 0.99)),
        'raster_worst_ms': _round(_max(rasterMs)),
        'jank_frames': jankFrames,
        'jank_ratio_pct': _round(jankRatioPct),
        'severe_jank_frames': severeJankFrames,
      };
}

/// Runs [action] with frame timings recorded, and returns the summary.
///
/// [warmup] runs first and its frames are discarded - the first traversal of a
/// route carries first-build, first-shader and first-image-decode costs that are
/// real but are not the regression anyone is hunting.
Future<FrameStats> measureFrames(
  WidgetTester tester,
  String flow,
  Future<void> Function() action, {
  Future<void> Function()? warmup,
}) async {
  if (warmup != null) {
    await warmup();
    await tester.pumpAndSettle();
  }

  final binding = WidgetsBinding.instance;
  final views = binding.platformDispatcher.views;
  final refreshHz =
      views.isEmpty || views.first.display.refreshRate <= 0
          ? 60.0
          : views.first.display.refreshRate;
  final budgetMs = 1000 / refreshHz;

  final buildMs = <double>[];
  final rasterMs = <double>[];
  final vsyncUs = <int>[];
  final rasterFinishUs = <int>[];
  void collect(List<FrameTiming> timings) {
    for (final t in timings) {
      buildMs.add(t.buildDuration.inMicroseconds / 1000.0);
      rasterMs.add(t.rasterDuration.inMicroseconds / 1000.0);
      vsyncUs.add(t.timestampInMicroseconds(FramePhase.vsyncStart));
      rasterFinishUs.add(t.timestampInMicroseconds(FramePhase.rasterFinish));
    }
  }

  // Drain whatever the engine already had batched before we start counting.
  await tester.pump(const Duration(milliseconds: 300));

  final started = DateTime.now();
  binding.addTimingsCallback(collect);
  try {
    await action();
    // Pump past the batch interval so the window keeps its own tail frames.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  } finally {
    binding.removeTimingsCallback(collect);
  }
  final elapsedMs = DateTime.now().difference(started).inMilliseconds;

  var jank = 0;
  var severe = 0;
  for (var i = 0; i < buildMs.length; i++) {
    final worst = buildMs[i] > rasterMs[i] ? buildMs[i] : rasterMs[i];
    if (worst > budgetMs) jank++;
    if (worst > budgetMs * 3) severe++;
  }

  final stats = FrameStats(
    flow: flow,
    frameCount: buildMs.length,
    elapsedMs: elapsedMs,
    buildMs: buildMs,
    rasterMs: rasterMs,
    jankFrames: jank,
    severeJankFrames: severe,
    budgetMs: budgetMs,
    refreshHz: refreshHz,
    vsyncUs: vsyncUs,
    rasterFinishUs: rasterFinishUs,
  );

  print('🎞 FRAME $flow: ${stats.toMetrics()}');
  return stats;
}

/// Measures a window that ends on a *condition* rather than on settling.
///
/// [measureFrames] is the right tool for a scripted interaction, but it closes
/// with `pumpAndSettle`, and an activation window never settles: spinners
/// animate and RPCs are in flight for the whole of it, so `pumpAndSettle` runs
/// until its timeout every time.
///
/// Two things here matter more than they look:
///
/// * **The window is driven with `Future.delayed`, never `tester.pump`.** Under
///   the default `fadePointers` frame policy every `pump()` manufactures a frame
///   the app never asked for. In a window whose entire point is counting the
///   frames the app *failed* to produce, the driving loop would be supplying the
///   missing frames and reporting a healthy number.
/// * **The policy is switched to [LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive]**
///   for the duration, which is documented as mimicking real-environment frame
///   scheduling, and restored afterwards.
Future<FrameStats> measureFramesUntil(
  WidgetTester tester,
  String flow, {
  required Future<void> Function() start,
  required bool Function() done,
  Duration timeout = const Duration(minutes: 5),
  Duration poll = const Duration(milliseconds: 250),
}) async {
  final binding = WidgetsBinding.instance;
  final views = binding.platformDispatcher.views;
  final refreshHz = views.isEmpty || views.first.display.refreshRate <= 0
      ? 60.0
      : views.first.display.refreshRate;
  final budgetMs = 1000 / refreshHz;

  final buildMs = <double>[];
  final rasterMs = <double>[];
  final vsyncUs = <int>[];
  final rasterFinishUs = <int>[];
  void collect(List<FrameTiming> timings) {
    for (final t in timings) {
      buildMs.add(t.buildDuration.inMicroseconds / 1000.0);
      rasterMs.add(t.rasterDuration.inMicroseconds / 1000.0);
      vsyncUs.add(t.timestampInMicroseconds(FramePhase.vsyncStart));
      rasterFinishUs.add(t.timestampInMicroseconds(FramePhase.rasterFinish));
    }
  }

  LiveTestWidgetsFlutterBindingFramePolicy? restorePolicy;
  if (binding is LiveTestWidgetsFlutterBinding) {
    restorePolicy = binding.framePolicy;
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;
  }

  // Drain whatever the engine already had batched before we start counting.
  await tester.pump(const Duration(milliseconds: 300));

  final started = DateTime.now();
  final deadline = started.add(timeout);
  binding.addTimingsCallback(collect);
  var completed = false;
  try {
    await start();
    while (DateTime.now().isBefore(deadline)) {
      if (done()) {
        completed = true;
        break;
      }
      await Future<void>.delayed(poll);
    }
    // The engine only flushes FrameTiming when a new frame is submitted and the
    // batch is over ~100ms old, so a window that stops collecting the instant
    // its condition flips loses its tail - which in a stall is the jankiest
    // part of it.
    await Future<void>.delayed(const Duration(milliseconds: 600));
  } finally {
    binding.removeTimingsCallback(collect);
    if (binding is LiveTestWidgetsFlutterBinding && restorePolicy != null) {
      binding.framePolicy = restorePolicy;
    }
  }
  final elapsedMs = DateTime.now().difference(started).inMilliseconds;

  if (!completed) {
    // Loud, because a timed-out window still produces plausible-looking
    // numbers for a flow that never finished.
    print(
      '⚠️  FRAME $flow: condition never met within ${timeout.inSeconds}s - '
      'these numbers describe a truncated window, not the flow',
    );
  }

  var jank = 0;
  var severe = 0;
  for (var i = 0; i < buildMs.length; i++) {
    final worst = buildMs[i] > rasterMs[i] ? buildMs[i] : rasterMs[i];
    if (worst > budgetMs) jank++;
    if (worst > budgetMs * 3) severe++;
  }

  final stats = FrameStats(
    flow: flow,
    frameCount: buildMs.length,
    elapsedMs: elapsedMs,
    buildMs: buildMs,
    rasterMs: rasterMs,
    jankFrames: jank,
    severeJankFrames: severe,
    budgetMs: budgetMs,
    refreshHz: refreshHz,
    vsyncUs: vsyncUs,
    rasterFinishUs: rasterFinishUs,
  );

  print('🎞 FRAME $flow: ${stats.toMetrics()}');
  return stats;
}

/// Median across iterations. Median, not mean: one scheduling hiccup on a shared
/// runner moves a mean of three enough to trip a 30% gate by itself.
Map<String, dynamic> medianMetrics(List<FrameStats> runs) {
  if (runs.isEmpty) return <String, dynamic>{};
  final keys = runs.first.toMetrics().keys;
  final out = <String, dynamic>{};
  for (final k in keys) {
    final values = runs.map((r) => (r.toMetrics()[k] as num).toDouble()).toList()
      ..sort();
    final mid = values.length ~/ 2;
    final v = values.length.isOdd
        ? values[mid]
        : (values[mid - 1] + values[mid]) / 2;
    out[k] = double.parse(v.toStringAsFixed(2));
  }
  return out;
}

/// Records the document on the binding so the driver can write it to disk.
void reportFramePerf(
  IntegrationTestWidgetsFlutterBinding binding,
  Map<String, dynamic> document,
) {
  binding.reportData ??= <String, dynamic>{};
  binding.reportData!['frame_perf'] = document;
}

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/analytics/frame_timing_recorder.dart';

/// Pins the arithmetic behind the `frames[...][gap]` line.
///
/// Every conclusion about web activation jank rests on these numbers, and the
/// recorder that produces them is unreachable in a normal build (const gate),
/// so this exercises the extracted computation directly. The cases are chosen
/// to be the ones that would silently produce a *confident wrong answer*
/// rather than an obvious failure.
/// Runnable on its own (`flutter test test_units/tests/analytics/...`) as well
/// as through `test_units/main.dart`, which calls [testFrameGapMetrics].
void main() => testFrameGapMetrics();

void testFrameGapMetrics() {
  group('frame gap metrics:', () {
    const budget60Hz = 1000 / 60; // 16.667ms

    /// A run of frames arriving exactly on budget, with a single stall of
    /// [stallFrames] budgets inserted after [stallAfter] frames.
    ({List<int> vsync, List<int> rasterFinish}) frames({
      required int count,
      int stallAfter = -1,
      int stallFrames = 0,
      double budgetMs = budget60Hz,
    }) {
      final vsync = <int>[];
      final rasterFinish = <int>[];
      var t = 0.0;
      for (var i = 0; i < count; i++) {
        if (i == stallAfter) t += budgetMs * stallFrames;
        vsync.add((t * 1000).round());
        // 1ms of raster, so the span ends just after the last vsync.
        rasterFinish.add(((t + 1) * 1000).round());
        t += budgetMs;
      }
      return (vsync: vsync, rasterFinish: rasterFinish);
    }

    FrameGapMetrics? compute(
      ({List<int> vsync, List<int> rasterFinish}) f, {
      double build = 1,
      double raster = 1,
      double budgetMs = budget60Hz,
    }) =>
        computeFrameGapMetrics(
          vsyncUs: f.vsync,
          rasterFinishUs: f.rasterFinish,
          buildMs: List<double>.filled(f.vsync.length, build),
          rasterMs: List<double>.filled(f.vsync.length, raster),
          budgetMs: budgetMs,
        );

    test('a clean 60Hz run yields ~100% and reports no stall', () {
      final m = compute(frames(count: 60))!;

      expect(m.frameCount, 60);
      // 59 gaps of one budget, plus 1ms of trailing raster.
      expect(m.spanMs, closeTo(59 * budget60Hz + 1, 0.01));
      expect(m.yieldPct, closeTo(100, 2));
      expect(m.fps, closeTo(60, 2));
      expect(m.missedFrames, 0);
      // Not exactly zero: vsync timestamps are whole microseconds, so a 60Hz
      // gap rounds to 16667us against a 16666.67us budget and each frame
      // contributes ~0.3us of "stall". That floor is real in field captures
      // too - it is ~0.05% of a 40s span - and is why `missedFrames`, which
      // rounds to whole refresh slots, is the sturdier of the two counters.
      expect(m.stallMs, closeTo(0, 0.1));
    });

    test(
      'a blocked main thread shows up as lost yield, not as slow frames',
      () {
        // The case the old metric could not see: every frame that happens is
        // fast, but the thread was gone for 60 budgets (~1s) in the middle.
        final m = compute(
          frames(count: 60, stallAfter: 30, stallFrames: 60),
          build: 1,
          raster: 1,
        )!;

        // Not one frame blew the budget - `max(build, raster)` is 1ms.
        // The stall is only visible in the arrival gaps.
        //
        // The inserted gap is the normal budget *plus* 60 skipped budgets, so
        // it spans 61 refreshes: 60 of them painted nothing.
        expect(m.gapsMs.reduce((a, b) => a > b ? a : b),
            closeTo(61 * budget60Hz, 0.5));
        expect(m.stallMs, closeTo(60 * budget60Hz, 0.5));
        expect(m.missedFrames, 60);
        expect(m.yieldPct, lessThan(55));
      },
    );

    test(
      'idle and blocking both cut yield, and only the median tells them apart',
      () {
        // Idle: paints smoothly, then has nothing to do. This is the measured
        // shape of the hermetic scroll flow - ~30% yield, median gap at one
        // budget - and reading its yield as "the UI froze" would be wrong.
        final idleVsync = <int>[];
        var t = 0.0;
        for (var burst = 0; burst < 10; burst++) {
          for (var i = 0; i < 10; i++) {
            idleVsync.add((t * 1000).round());
            t += budget60Hz;
          }
          t += 250; // nothing animating
        }
        final idle = computeFrameGapMetrics(
          vsyncUs: idleVsync,
          rasterFinishUs: idleVsync.map((v) => v + 1000).toList(),
          buildMs: List<double>.filled(idleVsync.length, 1),
          rasterMs: List<double>.filled(idleVsync.length, 1),
          budgetMs: budget60Hz,
        )!;

        // Blocking: every gap is late, including the median.
        final blockedVsync = <int>[
          for (var i = 0; i < 100; i++) (i * 140 * 1000),
        ];
        final blocked = computeFrameGapMetrics(
          vsyncUs: blockedVsync,
          rasterFinishUs: blockedVsync.map((v) => v + 1000).toList(),
          buildMs: List<double>.filled(blockedVsync.length, 1),
          rasterMs: List<double>.filled(blockedVsync.length, 1),
          budgetMs: budget60Hz,
        )!;

        double median(List<double> v) => (List<double>.of(v)..sort())[v.length ~/ 2];

        // Both look equally bad on yield...
        expect(idle.yieldPct, lessThan(60));
        expect(blocked.yieldPct, lessThan(60));
        // ...and neither registers as jank, because every frame was 1ms.
        // Only the median gap separates them.
        expect(median(idle.gapsMs), lessThan(budget60Hz * 1.5));
        expect(median(blocked.gapsMs), greaterThan(budget60Hz * 1.5));
      },
    );

    test('missed frames count refresh slots, not gaps', () {
      // One gap of exactly 4 budgets = 3 refreshes with nothing painted.
      final m = compute(frames(count: 3, stallAfter: 1, stallFrames: 3))!;
      expect(m.missedFrames, 3);
      expect(m.gapsMs.length, 2);
    });

    test('a sub-budget gap is neither a stall nor a missed frame', () {
      // Frames arriving *faster* than budget must not produce negative stall.
      final vsync = <int>[0, 8000, 16000];
      final m = computeFrameGapMetrics(
        vsyncUs: vsync,
        rasterFinishUs: <int>[1000, 9000, 17000],
        buildMs: <double>[1, 1, 1],
        rasterMs: <double>[1, 1, 1],
        budgetMs: budget60Hz,
      )!;
      expect(m.stallMs, 0);
      expect(m.missedFrames, 0);
    });

    test('the budget is honoured, so 120Hz is judged against 8.33ms', () {
      const budget120Hz = 1000 / 120;
      // Frames arriving every 16.67ms: perfect at 60Hz, half rate at 120Hz.
      final f = frames(count: 60);

      expect(compute(f)!.yieldPct, closeTo(100, 2));
      expect(
        compute(f, budgetMs: budget120Hz)!.yieldPct,
        closeTo(50, 2),
      );
    });

    test('ui and raster are reported against the span, never summed', () {
      // Native pipelines raster with the next build, so the two can exceed the
      // span. The metric must still report both rather than a negative
      // remainder - which is why there is no "off thread" field.
      final m = compute(frames(count: 10), build: 10, raster: 10)!;
      expect(m.uiMs, closeTo(100, 0.01));
      expect(m.rasterMs, closeTo(100, 0.01));
      expect(m.uiMs + m.rasterMs, greaterThan(m.spanMs));
      expect(m.spanMs, greaterThan(0));
    });

    group('returns null rather than a zero, because zero reads as passing:',
        () {
      test('no frames', () {
        expect(
          computeFrameGapMetrics(
            vsyncUs: const <int>[],
            rasterFinishUs: const <int>[],
            buildMs: const <double>[],
            rasterMs: const <double>[],
            budgetMs: budget60Hz,
          ),
          isNull,
        );
      });

      test('a single frame has no gap to measure', () {
        expect(compute(frames(count: 1)), isNull);
      });

      test('a non-monotonic frame clock', () {
        expect(
          computeFrameGapMetrics(
            vsyncUs: const <int>[5000, 6000],
            rasterFinishUs: const <int>[100, 200], // finishes before it starts
            buildMs: const <double>[1, 1],
            rasterMs: const <double>[1, 1],
            budgetMs: budget60Hz,
          ),
          isNull,
        );
      });

      test('a zero or negative budget', () {
        expect(compute(frames(count: 10), budgetMs: 0), isNull);
      });
    });

    test('summary renders every field and stays on one line', () {
      final summary = compute(frames(count: 60, stallAfter: 30, stallFrames: 6))!
          .summary;

      expect(summary, contains('yield '));
      expect(summary, contains('fps '));
      expect(summary, contains('gap p50 '));
      expect(summary, contains('stall '));
      expect(summary, contains('missed '));
      expect(summary, contains('ui '));
      expect(summary, contains('raster '));
      expect(summary, contains('span '));
      expect(summary, isNot(contains('\n')));
    });

    test('mismatched raster list length does not throw', () {
      // The recorder appends to both lists together, but a truncated capture
      // must degrade rather than take down a diagnostics path.
      final f = frames(count: 5);
      final m = computeFrameGapMetrics(
        vsyncUs: f.vsync,
        rasterFinishUs: f.rasterFinish,
        buildMs: List<double>.filled(5, 2),
        rasterMs: const <double>[2, 2],
        budgetMs: budget60Hz,
      )!;
      expect(m.uiMs, closeTo(10, 0.01));
      expect(m.rasterMs, closeTo(4, 0.01));
    });
  });
}

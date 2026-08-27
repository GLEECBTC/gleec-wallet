// Turns a Diagnostic Logging export into wallet-load numbers.
//
// Usage:
//   dart run tool/parse_wallet_load_log.dart <log-file> [--json] [--top 20]
//
// The web build is the platform where the "balances take minutes" reports came
// from, and the Dart harness cannot measure it: on web, KDF runs as WASM on the
// **main thread**, sharing it with Flutter (COEP/COOP are commented out in
// firebase.json, so there is no cross-origin isolation and no worker). Only a
// real browser session can show that contention.
//
// What this reads (all of it already ships):
//
//   [RPC] <method> completed in <N>ms
//       komodo_defi_framework.dart. Emitted only while Diagnostic Logging is
//       on - Settings -> General -> Diagnostic Logging, which flips
//       `KomodoDefiFramework.enableDebugLogging` and
//       `KdfApiClient.enableDebugLogging` (settings_bloc.dart).
//
//   Initial activation reached <...> after <N>ms (<M> coins targeted)
//       coins_bloc.dart, at INFO, and therefore present in release builds with
//       Diagnostic Logging OFF too. This is the headline post-login number.
//
//   [ACTIVATION] Successfully activated <id> (<protocol>)
//       coins_repo.dart, behind `kDebugElectrumLogs`, which is `const true` in
//       app_config.dart - so it also ships in release.
//
//   balance[<id>] <kind> paint|fetched after <N>ms
//       balance_manager.dart. Distinguishes a cache/synthetic paint from a
//       fetched balance, which a wall-clock "first render" cannot.
//
//   getActiveUser: <N> calls in <T>ms (<R> identity RPCs), ...
//       auth_service.dart. The identity-RPC amplification, per window.
//
// What it CANNOT see, and why a HAR is still needed: Etherscan, TronGrid and
// the CEX price feeds do not go through `executeRpc`, so they never appear as
// `[RPC]` lines. If a login is slow and the RPC totals here do not explain it,
// the time is in that traffic.

import 'dart:convert';
import 'dart:io';

final _rpcLine = RegExp(r'\[RPC\]\s+(\S+)\s+completed in\s+(\d+)ms');
final _rpcFailed = RegExp(r'\[RPC\]\s+(\S+)\s+failed');
final _initialActivation = RegExp(
  r'Initial activation reached\s+(.+?)\s+after\s+(\d+)ms\s+\((\d+) coins',
);
final _assetActivated = RegExp(
  r'\[ACTIVATION\] Successfully activated\s+(\S+)',
);
final _activationTiming = RegExp(r'Activated\s+(\S+)\s+in\s+(\d+)ms\s+\((\w+)\)');
final _balancePaint = RegExp(
  r'balance\[(\S+?)\]\s+(.+?)\s+after\s+(\d+)ms',
);
final _activeUser = RegExp(
  r'getActiveUser:\s+(\d+) calls in\s+(\d+)ms\s+\((\d+) identity RPCs\),\s+'
  r'lock queue\s+(\d+)ms,\s+lock held\s+(\d+)ms',
);

// Emitted by lib/analytics/frame_timing_recorder.dart, which only runs when the
// build passed --dart-define=FRAME_TIMING_CAPTURE=true. `_frameDevice` must be
// matched before `_frameSpan`, since `device` also matches `\w+`.
// `attribution` is optional so logs captured before the LoAF probe existed
// still match.
final _frameDevice = RegExp(
  r'frames\[device\] refresh ([\d.]+)Hz budget ([\d.]+)ms '
  r'platform (\S+) mode (\S+)(?: attribution (\S+))?',
);
final _frameSpan = RegExp(
  r'frames\[(\w+)\]\s+(\d+) frames in (\d+)ms \| '
  r'build p50 ([\d.]+)ms p90 ([\d.]+)ms p99 ([\d.]+)ms max ([\d.]+)ms \| '
  r'raster p50 ([\d.]+)ms p90 ([\d.]+)ms p99 ([\d.]+)ms max ([\d.]+)ms \| '
  r'jank (\d+) \(([\d.]+)%\) severe (\d+) \| budget ([\d.]+)ms',
);

// The frame-arrival view of the same span. This is the line that matters on
// web: a long task stops the browser firing the rAF at all, so main-thread
// blocking shows up as frames that never happened, which `_frameSpan`'s
// build/raster percentiles cannot see - they only describe frames that did.
final _frameGap = RegExp(
  r'frames\[(\w+)\]\[gap\] '
  r'yield ([\d.]+)% \((\d+)/(\d+)\) fps ([\d.]+) \| '
  r'gap p50 ([\d.]+)ms p90 ([\d.]+)ms p99 ([\d.]+)ms max ([\d.]+)ms \| '
  r'stall (\d+)ms \(([\d.]+)%\) missed (\d+) \| '
  r'ui (\d+)ms \(([\d.]+)%\) raster (\d+)ms \(([\d.]+)%\) \| '
  r'span (\d+)ms',
);

// Who blocked the thread, from the long-animation-frame observer. Never a
// verdict: it is a description, and a partial one - LoAF has a 50ms floor and
// credits a whole task to its entry point, so the KDF share is a floor rather
// than a total.
final _frameAttrib = RegExp(
  r'frames\[(\w+)\]\[attrib\] '
  r'loaf (\d+) total (\d+)ms blocking (\d+)ms \| (.+)$',
);
final _frameAttribSource = RegExp(r'([\w.-]+) (\d+)ms');

/// Jank rate above which a span is called out. Deliberately loose: the budget is
/// device-dependent, so this is a smell test, not a gate.
const _jankRatioThresholdPct = 10.0;

/// Longest acceptable gap between two painted frames. Past this the UI has
/// visibly frozen rather than stuttered.
const _worstGapThresholdMs = 500.0;

/// Multiple of the frame budget the *median* gap may reach before painting is
/// called unsmooth. The median is the honest test of "when the app painted, did
/// it paint on time", because it is unmoved by idle stretches.
const _medianGapBudgetMultiple = 1.5;

/// Methods whose per-login count is the amplification story.
const _identityMethods = {'get_wallet_names', 'get_public_key_hash'};

void main(List<String> arguments) {
  final positional = arguments.where((a) => !a.startsWith('--')).toList();
  if (positional.isEmpty) {
    stderr.writeln(
      'usage: dart run tool/parse_wallet_load_log.dart <log-file> '
      '[--json] [--top N]',
    );
    exit(2);
  }
  final asJson = arguments.contains('--json');
  final topIndex = arguments.indexOf('--top');
  final top = topIndex >= 0 && topIndex + 1 < arguments.length
      ? int.tryParse(arguments[topIndex + 1]) ?? 20
      : 20;

  final file = File(positional.first);
  if (!file.existsSync()) {
    stderr.writeln('No such log file: ${file.path}');
    exit(2);
  }

  final rpcCounts = <String, int>{};
  final rpcTotalMs = <String, int>{};
  final rpcMaxMs = <String, int>{};
  final rpcFailures = <String, int>{};
  final activatedAssets = <String>[];
  final assetActivationMs = <String, int>{};
  final assetActivationStatus = <String, String>{};
  final balancePaints = <Map<String, Object?>>[];
  final activeUserWindows = <Map<String, int>>[];
  final frameSpans = <String, Map<String, Object?>>{};
  Map<String, Object?>? frameDevice;
  int? initialActivationMs;
  String? initialActivationOutcome;
  int? initialActivationCoins;

  for (final line in file.readAsLinesSync()) {
    final device = _frameDevice.firstMatch(line);
    if (device != null) {
      frameDevice = <String, Object?>{
        'refresh_hz': double.parse(device.group(1)!),
        'frame_budget_ms': double.parse(device.group(2)!),
        'platform': device.group(3),
        'mode': device.group(4),
        'attribution': device.group(5) ?? 'none',
      };
      continue;
    }
    final attrib = _frameAttrib.firstMatch(line);
    if (attrib != null) {
      final sources = <String, int>{};
      for (final m in _frameAttribSource.allMatches(attrib.group(5)!)) {
        sources[m.group(1)!] = int.parse(m.group(2)!);
      }
      (frameSpans[attrib.group(1)!] ??= <String, Object?>{}).addAll({
        'loaf_entries': int.parse(attrib.group(2)!),
        'loaf_total_ms': int.parse(attrib.group(3)!),
        'loaf_blocking_ms': int.parse(attrib.group(4)!),
        'loaf_by_source_ms': sources,
      });
      continue;
    }
    // Before `_frameSpan`, for the same reason `_frameDevice` is: both start
    // `frames[<word>]`, and only the trailing shape tells them apart.
    final gap = _frameGap.firstMatch(line);
    if (gap != null) {
      (frameSpans[gap.group(1)!] ??= <String, Object?>{}).addAll({
        'yield_pct': double.parse(gap.group(2)!),
        'frames_painted': int.parse(gap.group(3)!),
        'frames_possible': int.parse(gap.group(4)!),
        'effective_fps': double.parse(gap.group(5)!),
        'gap_p50_ms': double.parse(gap.group(6)!),
        'gap_p90_ms': double.parse(gap.group(7)!),
        'gap_p99_ms': double.parse(gap.group(8)!),
        'gap_worst_ms': double.parse(gap.group(9)!),
        'stall_ms': int.parse(gap.group(10)!),
        'stall_pct': double.parse(gap.group(11)!),
        'missed_frames': int.parse(gap.group(12)!),
        'ui_ms': int.parse(gap.group(13)!),
        'ui_pct': double.parse(gap.group(14)!),
        'raster_total_ms': int.parse(gap.group(15)!),
        'raster_pct': double.parse(gap.group(16)!),
        'span_ms': int.parse(gap.group(17)!),
      });
      continue;
    }
    final frame = _frameSpan.firstMatch(line);
    if (frame != null) {
      (frameSpans[frame.group(1)!] ??= <String, Object?>{}).addAll(<String, Object?>{
        'frame_count': int.parse(frame.group(2)!),
        'elapsed_ms': int.parse(frame.group(3)!),
        'build_p50_ms': double.parse(frame.group(4)!),
        'build_p90_ms': double.parse(frame.group(5)!),
        'build_p99_ms': double.parse(frame.group(6)!),
        'build_worst_ms': double.parse(frame.group(7)!),
        'raster_p50_ms': double.parse(frame.group(8)!),
        'raster_p90_ms': double.parse(frame.group(9)!),
        'raster_p99_ms': double.parse(frame.group(10)!),
        'raster_worst_ms': double.parse(frame.group(11)!),
        'jank_frames': int.parse(frame.group(12)!),
        'jank_ratio_pct': double.parse(frame.group(13)!),
        'severe_jank_frames': int.parse(frame.group(14)!),
        'frame_budget_ms': double.parse(frame.group(15)!),
      });
      continue;
    }
    final rpc = _rpcLine.firstMatch(line);
    if (rpc != null) {
      final method = rpc.group(1)!;
      final ms = int.parse(rpc.group(2)!);
      rpcCounts[method] = (rpcCounts[method] ?? 0) + 1;
      rpcTotalMs[method] = (rpcTotalMs[method] ?? 0) + ms;
      if (ms > (rpcMaxMs[method] ?? 0)) rpcMaxMs[method] = ms;
      continue;
    }
    final failed = _rpcFailed.firstMatch(line);
    if (failed != null) {
      final method = failed.group(1)!;
      rpcFailures[method] = (rpcFailures[method] ?? 0) + 1;
      continue;
    }
    final initial = _initialActivation.firstMatch(line);
    if (initial != null) {
      initialActivationOutcome = initial.group(1);
      initialActivationMs = int.parse(initial.group(2)!);
      initialActivationCoins = int.parse(initial.group(3)!);
      continue;
    }
    final activated = _assetActivated.firstMatch(line);
    if (activated != null) {
      activatedAssets.add(activated.group(1)!);
      continue;
    }
    final timing = _activationTiming.firstMatch(line);
    if (timing != null) {
      assetActivationMs[timing.group(1)!] = int.parse(timing.group(2)!);
      assetActivationStatus[timing.group(1)!] = timing.group(3)!;
      continue;
    }
    final paint = _balancePaint.firstMatch(line);
    if (paint != null) {
      balancePaints.add({
        'asset': paint.group(1),
        'kind': paint.group(2),
        'elapsed_ms': int.parse(paint.group(3)!),
      });
      continue;
    }
    final activeUser = _activeUser.firstMatch(line);
    if (activeUser != null) {
      activeUserWindows.add({
        'calls': int.parse(activeUser.group(1)!),
        'window_ms': int.parse(activeUser.group(2)!),
        'identity_rpcs': int.parse(activeUser.group(3)!),
        'lock_queue_ms': int.parse(activeUser.group(4)!),
        'lock_held_ms': int.parse(activeUser.group(5)!),
      });
    }
  }

  final identityRpcTotal = _identityMethods.fold<int>(
    0,
    (sum, method) => sum + (rpcCounts[method] ?? 0),
  );

  // Ungated fallback for the identity verdict: these lines ship at INFO, so
  // they survive with Diagnostic Logging off. Under-reports - `auth_service`
  // resets its counters per window and never flushes the trailing one - so it
  // is only ever used to FAIL, never to PASS.
  final getActiveUserTotal = activeUserWindows.fold<int>(
    0,
    (sum, window) => sum + window['identity_rpcs']!,
  );
  final totalRpcs = rpcCounts.values.fold<int>(0, (a, b) => a + b);

  // The scorecard the fixes are supposed to move. Each verdict states the
  // threshold inline so the output is readable without this file next to it.
  final verdicts = <String, String>{};
  if (initialActivationMs != null) {
    verdicts['initial_activation'] = initialActivationMs <= 15000
        ? 'PASS (${initialActivationMs}ms <= 15000ms)'
        : 'FAIL (${initialActivationMs}ms > 15000ms)';
  }
  // `[RPC]` lines only exist when Diagnostic Logging was on, so a normal log
  // has zero of them - and reporting `PASS (0 < 60)` off no data at all is
  // worse than saying nothing. Only the FAIL direction can be trusted from the
  // ungated getActiveUser windows: those reset per window and the trailing one
  // is never flushed, so the sum under-reports.
  final hasIdentityRpcData = _identityMethods.any(rpcCounts.containsKey);
  if (hasIdentityRpcData) {
    verdicts['identity_rpcs'] = identityRpcTotal < 60
        ? 'PASS ($identityRpcTotal < 60)'
        : 'FAIL ($identityRpcTotal >= 60; ~480 was the pre-fix figure)';
  } else if (getActiveUserTotal >= 60) {
    verdicts['identity_rpcs'] =
        'FAIL ($getActiveUserTotal getActiveUser calls >= 60; no [RPC] lines, '
        'so this is a lower bound)';
  } else {
    verdicts['identity_rpcs'] =
        'NO DATA (enable Diagnostic Logging to capture [RPC] lines)';
  }

  // A per-asset time near a multiple of 90s is the fingerprint of the old
  // retry-joins-a-dead-completer bug (the app retried at 90s and each retry
  // re-joined the wedged attempt). Worth naming explicitly, because 180s or
  // 270s otherwise just looks like "slow".
  final retryMultiples = assetActivationMs.entries
      .where((e) => e.value >= 80000 && (e.value % 90000) < 15000)
      .map((e) => '${e.key}=${e.value}ms')
      .toList();
  if (retryMultiples.isNotEmpty) {
    verdicts['retry_multiple_signature'] =
        'FAIL: ${retryMultiples.join(', ')} sit at ~90s multiples';
  } else if (assetActivationMs.isNotEmpty) {
    verdicts['retry_multiple_signature'] = 'PASS (no ~90s multiples)';
  }

  // Absence of frame data means the build did not set FRAME_TIMING_CAPTURE - a
  // build-time decision, unlike Diagnostic Logging which is a runtime toggle.
  // Reporting PASS off no data at all is worse than saying nothing.
  if (frameSpans.isEmpty) {
    verdicts['frames'] =
        'NO DATA (rebuild with --dart-define=FRAME_TIMING_CAPTURE=true)';
  } else {
    for (final entry in frameSpans.entries) {
      final span = entry.value;

      // Each of the two lines can be absent independently: an old log has no
      // `[gap]` line, and a span with fewer than two frames emits a `[gap]`
      // "no data" line instead of a parseable one. Neither may be reported as
      // a pass.
      final ratio = span['jank_ratio_pct'] as double?;
      final budget = span['frame_budget_ms'] as double?;
      if (ratio == null || budget == null) {
        verdicts['frames_${entry.key}'] = 'NO DATA (no build/raster line)';
      } else {
        verdicts['frames_${entry.key}'] = ratio > _jankRatioThresholdPct
            ? 'FAIL (${ratio.toStringAsFixed(1)}% jank > '
                '${_jankRatioThresholdPct.toStringAsFixed(1)}% at a '
                '${budget.toStringAsFixed(1)}ms budget)'
            : 'PASS (${ratio.toStringAsFixed(1)}% jank at a '
                '${budget.toStringAsFixed(1)}ms budget)';
      }

      // The frame-arrival view. Reported separately from the jank ratio above
      // rather than folded into it, because they disagree in the direction that
      // matters: every frame fast (jank PASS) while frames stopped arriving is
      // the blocked-main-thread signature.
      final yieldPct = span['yield_pct'] as double?;
      final worstGap = span['gap_worst_ms'] as double?;
      final medianGap = span['gap_p50_ms'] as double?;
      if (yieldPct == null || worstGap == null || medianGap == null) {
        verdicts['frames_${entry.key}_smoothness'] =
            'NO DATA (log predates the [gap] line, or the span had <2 frames)';
      } else {
        final gapBudget = (budget ?? 1000 / 60) * _medianGapBudgetMultiple;

        // The median is the gate, not the yield. A window containing genuine
        // idle - nothing animating, so nothing to paint - has a low yield and
        // no jank whatsoever, and gating on yield would call that a freeze.
        // The median gap is unmoved by idle: it answers "when the app did
        // paint, did it paint on time".
        verdicts['frames_${entry.key}_smoothness'] = medianGap > gapBudget
            ? 'FAIL (median gap ${medianGap.toStringAsFixed(1)}ms > '
                '${gapBudget.toStringAsFixed(1)}ms)'
            : 'PASS (median gap ${medianGap.toStringAsFixed(1)}ms at a '
                '${(budget ?? 1000 / 60).toStringAsFixed(1)}ms budget)';

        verdicts['frames_${entry.key}_worst_gap'] =
            worstGap > _worstGapThresholdMs
                ? 'FAIL (${worstGap.toStringAsFixed(0)}ms with nothing painted '
                    '> ${_worstGapThresholdMs.toStringAsFixed(0)}ms)'
                : 'PASS (worst gap ${worstGap.toStringAsFixed(0)}ms)';

        // Never PASS/FAIL: yield only means "the UI froze" for a window in
        // which something was animating the whole time. Compare it against
        // the smoothness verdict above before reading anything into it.
        verdicts['frames_${entry.key}_yield'] =
            'INFO ${yieldPct.toStringAsFixed(1)}% '
            '(painted ${span['frames_painted']} of '
            '${span['frames_possible']} offered; low yield with a passing '
            'median gap means idle, not blocking)';
      }
    }
  }

  final report = <String, Object?>{
    'initial_activation': {
      'elapsed_ms': initialActivationMs,
      'outcome': initialActivationOutcome,
      'coins_targeted': initialActivationCoins,
    },
    'rpc': {
      'total': totalRpcs,
      'identity_total': identityRpcTotal,
      'by_method': _topBy(rpcCounts, top),
      'total_ms_by_method': _topBy(rpcTotalMs, top),
      'max_ms_by_method': _topBy(rpcMaxMs, top),
      'failures': rpcFailures,
    },
    'activation': {
      'assets_activated': activatedAssets.length,
      'per_asset_ms': assetActivationMs,
      'per_asset_status': assetActivationStatus,
    },
    'balance_paints': balancePaints,
    'get_active_user_windows': activeUserWindows,
    'frames': {
      'device': frameDevice,
      'spans': frameSpans,
    },
    'verdicts': verdicts,
  };

  if (asJson) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
    return;
  }

  stdout
    ..writeln('== Wallet load ==')
    ..writeln(
      'Initial activation: '
      '${initialActivationMs ?? 'not found'}ms '
      '(${initialActivationOutcome ?? '-'}, '
      '${initialActivationCoins ?? 0} coins targeted)',
    )
    ..writeln('RPCs total: $totalRpcs, identity: $identityRpcTotal')
    ..writeln('Assets activated: ${activatedAssets.length}')
    ..writeln('');

  if (rpcCounts.isNotEmpty) {
    stdout.writeln('== RPCs by count (top $top) ==');
    for (final entry in _sorted(rpcCounts).take(top)) {
      final total = rpcTotalMs[entry.key] ?? 0;
      final max = rpcMaxMs[entry.key] ?? 0;
      stdout.writeln(
        '  ${entry.value.toString().padLeft(5)}x  '
        '${entry.key.padRight(38)} '
        'total ${total}ms  max ${max}ms',
      );
    }
    stdout.writeln('');
  }

  if (assetActivationMs.isNotEmpty) {
    stdout.writeln('== Slowest activations ==');
    for (final entry in _sorted(assetActivationMs).take(top)) {
      stdout.writeln(
        '  ${entry.value.toString().padLeft(7)}ms  ${entry.key} '
        '(${assetActivationStatus[entry.key] ?? '?'})',
      );
    }
    stdout.writeln('');
  }

  if (balancePaints.isNotEmpty) {
    stdout.writeln('== Balance emissions ==');
    for (final paint in balancePaints.take(top)) {
      stdout.writeln(
        '  ${paint['elapsed_ms'].toString().padLeft(7)}ms  '
        '${paint['asset']}  ${paint['kind']}',
      );
    }
    stdout.writeln('');
  }

  if (frameSpans.isNotEmpty) {
    stdout.writeln('== Frame timings ==');
    if (frameDevice != null) {
      stdout.writeln(
        '  device: ${frameDevice['platform']} ${frameDevice['mode']}, '
        '${frameDevice['refresh_hz']}Hz '
        '(${frameDevice['frame_budget_ms']}ms budget)',
      );
    }
    for (final entry in frameSpans.entries) {
      final v = entry.value;
      stdout.writeln(
        '  ${entry.key}: ${v['frame_count']} frames in ${v['elapsed_ms']}ms  '
        'build p90 ${v['build_p90_ms']}ms  raster p90 ${v['raster_p90_ms']}ms  '
        'jank ${v['jank_frames']} (${v['jank_ratio_pct']}%) '
        'severe ${v['severe_jank_frames']}',
      );
    }
    stdout.writeln('');
  }

  if (activeUserWindows.isNotEmpty) {
    stdout.writeln('== getActiveUser windows ==');
    for (final window in activeUserWindows) {
      stdout.writeln(
        '  ${window['calls']} calls / ${window['window_ms']}ms  '
        '(${window['identity_rpcs']} identity RPCs, '
        'queue ${window['lock_queue_ms']}ms, held ${window['lock_held_ms']}ms)',
      );
    }
    stdout.writeln('');
  }

  stdout.writeln('== Scorecard ==');
  verdicts.forEach((name, verdict) => stdout.writeln('  $name: $verdict'));

  if (rpcCounts.isEmpty) {
    stdout.writeln(
      '\nNOTE: no [RPC] lines. Diagnostic Logging was probably off for this '
      'session - turn it on (Settings > General), log out, log back in, then '
      'download the logs again. The "Initial activation reached" line above '
      'ships at INFO and is present either way.',
    );
  }
  stdout.writeln(
    '\nNOTE: Etherscan/TronGrid/CEX traffic does not go through executeRpc '
    'and never appears here. If the RPC totals do not explain the wall clock, '
    'capture a HAR.',
  );
}

List<MapEntry<String, int>> _sorted(Map<String, int> map) =>
    map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

Map<String, int> _topBy(Map<String, int> map, int top) => {
  for (final entry in _sorted(map).take(top)) entry.key: entry.value,
};

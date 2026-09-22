// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/analytics/wallet_load_timeline.dart';
import 'package:web_dex/shared/constants.dart';

import '../../helpers/restore_wallet.dart';
import 'frame_capture.dart';

/// Measure frames across the post-login activation storm.
///
/// This is the window the jank complaint is actually about, and the one no
/// existing tooling covered. `test_coin_list_scroll` measures a flow with no
/// network in it at all, and the in-app `wallet_load` span stops at
/// `WalletLoadMark.firstBalance` - defined as *one* asset having both a balance
/// and a price - while the rest of the fan-out is still competing for the
/// thread.
///
/// Single iteration, deliberately: a login is not repeatable inside one app
/// instance, because the second one activates from warm caches and measures
/// something else. Run the whole test N times and take the median across runs
/// (`tool/bench_web_jank.sh` does this).
///
/// ## Two ways in, and why the default is auto-login
///
/// With `--dart-define=PERF_AUTO_LOGIN=true` the app restores a wallet from
/// `assets/debug_data.json` during startup and this flow only measures. That is
/// preferred to driving the wallet-manager UI: [measureFramesUntil] switches
/// the binding to `benchmarkLive`, under which `pump()` requests are ignored
/// so the driving loop cannot manufacture the frames it is counting.
/// `restoreWalletToTest` needs those pumps honoured, so the two cannot share
/// a window. The UI helper uses a policy-compliant password, and test-mode
/// startup preserves Flutter's failure reporting.
///
/// The UI-driven path is kept for a build without the define.
Future<List<FrameStats>> testLoginActivation(
  WidgetTester tester, {
  bool autoLogin = perfAutoLoginEnabled,
  Duration window = const Duration(seconds: 60),
  Duration tailAfterFirstBalance = const Duration(seconds: 20),
}) async {
  final timeline = WalletLoadTimeline.instance;

  // Chained, never assigned: `onMark` is a single slot and the in-app frame
  // recorder claims it during `initFrameTimingCapture()`. Overwriting it would
  // silently disable the very recorder this flow exists to feed, and the run
  // would still report success.
  final previousObserver = timeline.onMark;
  DateTime? firstBalanceAt;
  timeline.onMark = (WalletLoadMark mark) {
    previousObserver?.call(mark);
    if (mark == WalletLoadMark.firstBalance) {
      firstBalanceAt ??= DateTime.now();
    }
  };

  try {
    if (!autoLogin) {
      print('🔍 LOGIN PERF: driving the wallet-manager UI');
      await restoreWalletToTest(tester);
    } else {
      print('🔍 LOGIN PERF: auto-login (PERF_AUTO_LOGIN); measuring only');
    }

    final openedAt = DateTime.now();

    final stats = await measureFramesUntil(
      tester,
      'login_activation_storm',
      // Only reached if `done` never fires, which it always does via the hard
      // cap below. Kept above `window` so the cap is what ends the run.
      timeout: window + const Duration(seconds: 30),
      start: () async {},
      done: () {
        final now = DateTime.now();
        // Hard cap. The seed is an unfunded testnet WIF, so `firstBalance` -
        // which needs a balance *and* a price - may legitimately never fire.
        // Without this the window would run to the timeout and report itself
        // as truncated, which reads like a failure rather than a measurement.
        if (now.difference(openedAt) >= window) return true;
        final at = firstBalanceAt;
        return at != null && now.difference(at) >= tailAfterFirstBalance;
      },
    );
    return <FrameStats>[stats];
  } finally {
    timeline.onMark = previousObserver;
  }
}

/// Pumps for [duration] without requiring the tree to go quiet.
///
/// `pumpAndSettle` cannot be used around activation: spinners animate and RPCs
/// are in flight for the whole of it, so it spins until its own timeout and
/// then throws. This is the bounded equivalent.
Future<void> pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Dismisses the alpha-testing modal without `pumpAndSettle`.
///
/// `helpers/accept_alpha_warning.dart` settles after tapping, which hangs once
/// activation is under way. Same key, bounded wait.
Future<void> acceptAlphaWarningBounded(WidgetTester tester) async {
  final button = find.byKey(const Key('accept-alpha-warning-button'));
  if (!tester.any(button)) return;
  await tester.tap(button, warnIfMissed: false);
  await pumpFor(tester, const Duration(milliseconds: 500));
}

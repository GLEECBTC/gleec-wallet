import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

extension WidgetTesterPumpExtension on WidgetTester {
  Future<void> pumpNFrames(
    int frames, {
    Duration delay = const Duration(milliseconds: 10),
  }) async {
    for (int i = 0; i < frames; i++) {
      await pump();
      await Future<void>.delayed(delay);
    }
  }

  /// Pumps frames until [finder] matches, without ever waiting for idle.
  ///
  /// `pumpAndSettle` only returns once the tree stops scheduling frames, and
  /// it gives up with `pumpAndSettle timed out` after its own ten-minute
  /// default. A swap in progress animates continuously, so it never goes idle
  /// and that default fires first - no matter what deadline the caller wrapped
  /// around it. This advances one frame at a time instead and only asks
  /// whether the target is there yet, so the deadline the caller asked for is
  /// the deadline that applies.
  Future<void> pumpUntilFound(
    Finder finder, {
    required Duration timeout,
    Duration interval = const Duration(milliseconds: 250),
    String? describeTarget,
  }) async {
    if (await pumpUntilFoundOrMissing(
      finder,
      timeout: timeout,
      interval: interval,
    )) {
      return;
    }

    throw TimeoutException(
      'Timed out after ${timeout.inMinutes}m waiting for '
      '${describeTarget ?? finder.toString()}',
    );
  }

  /// As [pumpUntilFound], but reports absence instead of throwing.
  ///
  /// For waits whose target may legitimately not arrive, where the caller has
  /// a better answer than a timeout.
  Future<bool> pumpUntilFoundOrMissing(
    Finder finder, {
    required Duration timeout,
    Duration interval = const Duration(milliseconds: 250),
  }) async {
    final endTime = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(endTime)) {
      await pump(interval);
      if (any(finder)) return true;
    }

    return false;
  }

  /// As [pumpUntilFound], then lets animations that end soon play out.
  Future<void> pumpUntilVisible(
    Finder finder, {
    Duration timeout = const Duration(seconds: 60),
    bool throwOnError = true,
  }) async {
    if (await pumpUntilFoundOrMissing(finder, timeout: timeout)) {
      await _settleBriefly();
      return;
    }

    if (!throwOnError) {
      return;
    }

    String finderDescription = '';
    try {
      finderDescription = 'Finder: $finder';
      final Widget finderWidget = widget(finder);
      finderDescription += ', Widget: $finderWidget';
    } catch (e) {
      finderDescription += ', unable to retrieve widget information';
    }

    throw TimeoutException('pumpUntilVisible timed out: $finderDescription');
  }

  /// Pumps frames until [finder] no longer matches, as [pumpUntilFound] does
  /// for a match, then lets animations that end soon play out.
  Future<void> pumpUntilDisappear(
    Finder finder, {
    // 60s to match `pumpUntil` above. At 30s this could not cover its own
    // callers: `restoreWalletToTest` ends by waiting for the wallet-manager
    // modal to disappear, and on web that wait spans a cold KDF start - measured
    // at ~45s - so the helper threw while sign-in was still legitimately in
    // progress. The import completed; only the wait did not.
    Duration timeout = const Duration(seconds: 60),
    Duration interval = const Duration(milliseconds: 250),
  }) async {
    final endTime = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(endTime)) {
      await pump(interval);
      if (!any(finder)) {
        await _settleBriefly();
        return;
      }
    }

    throw TimeoutException(
      'Timed out after ${timeout.inSeconds}s waiting for $finder to disappear',
    );
  }

  /// What `pumpAndSettle` does after a wait, capped at about two seconds, so
  /// a transition finishes before the caller taps while an animation that
  /// never stops cannot hold the test.
  Future<void> _settleBriefly() async {
    for (var i = 0; i < 40 && binding.hasScheduledFrame; i++) {
      await pump(const Duration(milliseconds: 50));
    }
  }
}

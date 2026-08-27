// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common/goto.dart' as goto;
import '../../common/widget_tester_pump_extension.dart';
import 'frame_capture.dart';

/// Scroll the coin catalogue and measure frames.
///
/// The catalogue is the right first target: it needs no login, has no network in
/// the measured window, and renders hundreds of rows each carrying a per-row
/// `CoinSparkline` (a `FutureBuilder` over cached price data). If the list janks
/// anywhere, it janks here.
///
/// Note this measures the *drag* path. `_onPointerSignal` in `wallet_main.dart`
/// intercepts mouse-wheel events into a `jumpTo`, bypassing scroll physics
/// entirely - that is a different code path with a different frame profile.
Future<List<FrameStats>> testCoinListScroll(
  WidgetTester tester, {
  int iterations = 3,
}) async {
  const scrollView = Key('wallet-page-scroll-view');

  await goto.walletPage(tester);
  await tester.pumpAndSettle();

  final finder = find.byKey(scrollView);
  await tester.pumpUntilVisible(finder);

  final runs = <FrameStats>[];
  for (var i = 0; i < iterations; i++) {
    final stats = await measureFrames(
      tester,
      'wallet_list_scroll_catalogue',
      () async {
        for (var f = 0; f < 6; f++) {
          await tester.fling(finder, const Offset(0, -400), 3000);
          await tester.pumpAndSettle();
        }
        for (var f = 0; f < 6; f++) {
          await tester.fling(finder, const Offset(0, 400), 3000);
          await tester.pumpAndSettle();
        }
      },
      // Discard the first traversal: first build, first shader compiles and
      // first sparkline decodes are real costs but not the thing being tracked.
      warmup: i == 0
          ? () async {
              await tester.fling(finder, const Offset(0, -400), 3000);
              await tester.pumpAndSettle();
              await tester.fling(finder, const Offset(0, 400), 3000);
              await tester.pumpAndSettle();
            }
          : null,
    );
    runs.add(stats);
  }

  return runs;
}

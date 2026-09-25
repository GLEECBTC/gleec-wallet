// ignore_for_file: avoid_print

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, kProfileMode, kReleaseMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_dex/main.dart' as app;
import 'package:web_dex/shared/constants.dart' show perfAutoLoginEnabled;

import '../../helpers/accept_alpha_warning.dart';
import 'frame_capture.dart';
import 'platform_env_io.dart'
    if (dart.library.js_interop) 'platform_env_web.dart';
import 'test_coin_list_scroll.dart';
import 'test_login_activation.dart';

/// Frame-timing perf suite.
///
/// Deliberately NOT in `getTestsList()` - run it explicitly:
///
///   dart run_integration_tests.dart -t perf_tests/perf_tests.dart -D macos -m profile
///
/// It asserts nothing about correctness, and it costs seconds per measurement
/// window. A perf target that reds a functional CI run teaches people to ignore
/// functional CI.
///
/// Results land in `build/frame_result.json` via the driver's
/// `responseDataCallback`. See `docs/TESTING.md` §7.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  perfWidgetTests(binding);
}

void perfWidgetTests(
  IntegrationTestWidgetsFlutterBinding binding, {
  bool skip = false,
  Duration timeout = const Duration(minutes: 15),
  // Off by default: it logs in, so it needs a funded seed and network, takes
  // minutes, and is not repeatable within one app instance. The scroll flow is
  // hermetic and stays the default.
  bool includeLoginActivation = const bool.fromEnvironment(
    'PERF_LOGIN_ACTIVATION',
  ),
  // The scroll flow costs about a minute per run and measures a different
  // question. `tool/bench_web_jank.sh` skips it so a 3-run comparison stays
  // affordable enough that people actually take the "after" measurement.
  bool skipScroll = const bool.fromEnvironment('PERF_SKIP_SCROLL'),
}) {
  return testWidgets(
    'Run frame-timing perf tests:',
    (WidgetTester tester) async {
      if (!kProfileMode && !kReleaseMode) {
        print(
          '⚠️  FRAME PERF: debug build - these numbers measure the JIT, not the '
          'app. Re-run with -m profile before recording a baseline.',
        );
      }

      tester.testTextInput.register();
      await app.main();

      // With auto-login the activation fan-out starts during `app.main()`, and
      // `pumpAndSettle` never settles while spinners animate and RPCs are in
      // flight - it spins to its own timeout and throws. Bounded pumps instead.
      if (includeLoginActivation && perfAutoLoginEnabled) {
        await pumpFor(tester, const Duration(seconds: 2));
        await acceptAlphaWarningBounded(tester);
      } else {
        await tester.pumpAndSettle();
        await acceptAlphaWarning(tester);
        await tester.pumpAndSettle();
      }

      // Every flow is caught and recorded rather than allowed to propagate.
      //
      // On web, `print` goes to the *browser* console, which `flutter drive`
      // does not forward, and `app.main()` installs `catchUnhandledExceptions`
      // which never rethrows while `testing_mode=true` - which the runner
      // always sets. A flow that throws therefore ends the run as
      // "All tests passed" with no artifact and no visible reason. Writing the
      // failure into `reportData` is the only channel that reaches the host.
      final failures = <String, String>{};

      Future<List<FrameStats>> guard(
        String flow,
        Future<List<FrameStats>> Function() run,
      ) async {
        try {
          return await run();
        } catch (e, s) {
          failures[flow] = '$e\n$s';
          return const <FrameStats>[];
        }
      }

      // Login first when it is enabled: it is the only flow that cannot be
      // repeated, and running the hermetic scroll flow first would warm exactly
      // the caches that make the login measurement meaningless.
      final loginRuns = includeLoginActivation
          ? await guard('login_activation_storm', () => testLoginActivation(tester))
          : const <FrameStats>[];

      final runs = skipScroll
          ? const <FrameStats>[]
          : await guard(
              'wallet_list_scroll_catalogue',
              () => testCoinListScroll(tester),
            );

      final views = binding.platformDispatcher.views;
      final refreshHz = views.isEmpty || views.first.display.refreshRate <= 0
          ? 60.0
          : views.first.display.refreshRate;

      reportFramePerf(binding, <String, dynamic>{
        'schema': 'gleec-frame-perf-v1',
        'iterations': runs.length,
        if (failures.isNotEmpty) 'failures': failures,
        'device': <String, dynamic>{
          // `defaultTargetPlatform` reports the HOST on web, so a web run would
          // otherwise be labelled "macOS" and could be mistaken for a native
          // one - the exact confusion that turns a non-baseline-worthy number
          // into a baseline.
          'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
          'mode': kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
          'refresh_hz': double.parse(refreshHz.toStringAsFixed(2)),
          'frame_budget_ms':
              double.parse((1000 / refreshHz).toStringAsFixed(2)),
          'severe_multiple': 3,
        },
        // `dart:io`'s Platform throws on web, and this suite has to survive
        // being pointed at `-D web-server` even though web is never
        // baseline-worthy.
        'environment': platformEnvironment(),
        'runs': [...loginRuns, ...runs]
            .map((r) => <String, dynamic>{
                  'flow': r.flow,
                  'metrics': r.toMetrics(),
                })
            .toList(),
        'median': <String, dynamic>{
          if (runs.isNotEmpty)
            'wallet_list_scroll_catalogue': medianMetrics(runs),
          // Single-run by construction, so this is the run, not a median over
          // several. Named the same way so the two read alike downstream.
          if (loginRuns.isNotEmpty)
            'login_activation_storm': medianMetrics(loginRuns),
        },
      });

      print('END PERF TESTS');
    },
    semanticsEnabled: false,
    skip: skip,
    timeout: Timeout(timeout),
  );
}

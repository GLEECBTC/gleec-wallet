// ignore_for_file: avoid_print

import 'package:integration_test/integration_test_driver.dart';

/// Splits the frame-timing document into its own file so the perf suite has a
/// stable artifact path, and leaves every other test's behaviour untouched:
/// without a `frame_perf` key this writes exactly what the default callback
/// would.
///
/// `writeResponseOnFailure` is on because the payload matters most when a test
/// fails: the driver's own failure text comes from
/// `FlutterErrorDetails.toString()`, which is empty in the profile and release
/// web builds CI runs, so `failure_*` entries recorded by `reportingFailure`
/// are the only description of what actually broke. They are printed rather
/// than only written to disk so they reach the job log, which is all a CI
/// reader gets.
Future<void> main() => integrationDriver(
  writeResponseOnFailure: true,
  responseDataCallback: (Map<String, dynamic>? data) async {
    if (data == null) return;
    final rest = Map<String, dynamic>.from(data);
    final frames = rest.remove('frame_perf');
    if (frames != null) {
      await writeResponseData(
        frames as Map<String, dynamic>,
        testOutputFilename: 'frame_result',
      );
    }
    for (final entry in rest.entries) {
      if (entry.key.startsWith('failure_')) {
        print('${entry.key}:\n${entry.value}');
      }
    }
    if (rest.isNotEmpty) await writeResponseData(rest);
  },
);

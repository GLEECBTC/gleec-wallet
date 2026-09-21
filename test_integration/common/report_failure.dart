import 'package:integration_test/integration_test.dart';

/// Runs [body] and records the real error on the binding before rethrowing.
///
/// The driver reports a failure through `FlutterErrorDetails.toString()`, which
/// is stripped in profile and release builds - exactly the modes CI runs the
/// web suites in. That leaves `Failure in method: <name>:` with nothing after
/// it, so a failing suite says only that it failed. Stashing the error and
/// stack in `reportData` routes them through the response payload instead,
/// which survives the build mode.
///
/// Pair with `writeResponseOnFailure: true` in `test_driver/integration_test.dart`;
/// without it the driver drops the payload for the failing run that needs it.
Future<void> reportingFailure(
  IntegrationTestWidgetsFlutterBinding binding,
  String name,
  Future<void> Function() body,
) async {
  try {
    await body();
  } catch (error, stack) {
    binding.reportData = <String, dynamic>{
      ...?binding.reportData,
      'failure_$name': '$error\n\n$stack',
    };
    rethrow;
  }
}

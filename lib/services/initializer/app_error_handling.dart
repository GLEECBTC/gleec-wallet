import 'dart:async';

import 'package:flutter/foundation.dart';

/// Leaves error ownership with the test binding during integration tests.
/// Production startup retains the application's guarded error reporting.
Future<void> runWithAppErrorHandling(
  Future<void> Function() startApp, {
  required bool isTestMode,
  required void Function(Object, StackTrace?) onError,
}) async {
  if (isTestMode) {
    await startApp();
    return;
  }

  await runZonedGuarded(() async {
    FlutterError.onError = (details) {
      onError(details.exception, details.stack);
    };
    await startApp();
  }, onError);
}

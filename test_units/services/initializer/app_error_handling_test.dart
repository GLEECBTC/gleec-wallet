import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/services/initializer/app_error_handling.dart';

void main() {
  testWidgets('integration startup preserves framework failure capture', (
    tester,
  ) async {
    final error = StateError('intentional framework failure');
    final originalHandler = FlutterError.onError;
    var appReports = 0;
    await runWithAppErrorHandling(
      () async {
        FlutterError.reportError(FlutterErrorDetails(exception: error));
      },
      isTestMode: true,
      onError: (_, _) => appReports++,
    );

    expect(FlutterError.onError, same(originalHandler));
    expect(tester.takeException(), same(error));
    expect(appReports, 0);
  });

  test(
    'integration startup forwards asynchronous failures to its caller',
    () async {
      final error = StateError('intentional asynchronous failure');
      var appReports = 0;
      await expectLater(
        runWithAppErrorHandling(
          () async {
            await Future<void>.value();
            throw error;
          },
          isTestMode: true,
          onError: (_, _) => appReports++,
        ),
        throwsA(same(error)),
      );
      expect(appReports, 0);
    },
  );

  testWidgets('production startup still reports framework errors', (
    tester,
  ) async {
    final originalHandler = FlutterError.onError;
    final error = StateError('intentional production failure');
    final reports = <Object>[];
    try {
      await runWithAppErrorHandling(
        () async {
          FlutterError.reportError(FlutterErrorDetails(exception: error));
        },
        isTestMode: false,
        onError: (error, _) => reports.add(error),
      );
    } finally {
      FlutterError.onError = originalHandler;
    }
    expect(reports, [error]);
    expect(tester.takeException(), isNull);
  });
}

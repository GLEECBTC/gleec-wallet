import 'package:integration_test/integration_test_driver.dart';

/// Splits the frame-timing document into its own file so the perf suite has a
/// stable artifact path, and leaves every other test's behaviour untouched:
/// without a `frame_perf` key this writes exactly what the default callback
/// would.
Future<void> main() => integrationDriver(
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
        if (rest.isNotEmpty) await writeResponseData(rest);
      },
    );

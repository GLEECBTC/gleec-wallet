import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../test_integration/runners/integration_test_runner.dart';

void main() {
  group('integration test process result', () {
    test('nonzero exit fails despite a success message', () {
      final result = ProcessResult(1, 1, 'All tests passed.', '');

      expect(didIntegrationTestProcessFail(result), isTrue);
    });

    test('zero exit with a success message passes case-insensitively', () {
      final result = ProcessResult(1, 0, 'ALL TESTS PASSED.', '');

      expect(didIntegrationTestProcessFail(result), isFalse);
    });

    for (final failure in ['Failure Details:', 'TEST FAILED']) {
      test('zero exit still fails on stderr marker $failure', () {
        final result = ProcessResult(1, 0, 'All tests passed.', failure);

        expect(didIntegrationTestProcessFail(result), isTrue);
      });
    }

    test('plural failure summary overrides an earlier success message', () {
      final result = ProcessResult(
        1,
        0,
        'All tests passed.\nSome tests failed.',
        '',
      );

      expect(didIntegrationTestProcessFail(result), isTrue);
    });

    test('zero exit without a success message fails', () {
      final result = ProcessResult(1, 0, 'Application finished.', '');

      expect(didIntegrationTestProcessFail(result), isTrue);
    });

    test('nonzero exit without output fails', () {
      final result = ProcessResult(1, -9, '', '');

      expect(didIntegrationTestProcessFail(result), isTrue);
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void testWebCredentialBridge() {
  test(
    'browser credential bridge verifies PRF, cryptography and recovery failures',
    () async {
      final result = await Process.run('node', [
        '--test',
        'test_units/services/wallet_access/web_credential_backend.test.js',
      ]).timeout(const Duration(seconds: 45));
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}

void main() => testWebCredentialBridge();

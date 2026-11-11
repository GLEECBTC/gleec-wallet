import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/utils/debug_wallet_source.dart';

void main() {
  test('asset declarations exclude local root-level wallet fixtures', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(
      RegExp(r'^\s*-\s*assets/\s*$', multiLine: true).hasMatch(pubspec),
      isFalse,
    );
    expect(pubspec, isNot(contains('assets/debug_data.json')));
  });
  test('debug wallet loading requires explicit local runtime input', () async {
    expect(await loadDebugWalletSource(), isNull);
  });
  test(
    'distributable artifact privacy verifier rejects private fixtures',
    () async {
      final result = await Process.run(
        Platform.isWindows ? 'python' : 'python3',
        ['tool/test_verify_wallet_artifacts.py'],
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
  );
  test(
    'CI signing handles literal inputs without exposing them',
    () async {
      final result = await Process.run(
        Platform.isWindows ? 'python' : 'python3',
        ['tool/test_android_signing_action.py'],
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
    skip: Platform.isWindows
        ? 'POSIX permissions are checked by Linux CI'
        : false,
  );
}

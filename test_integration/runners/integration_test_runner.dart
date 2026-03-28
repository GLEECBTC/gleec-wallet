// ignore_for_file: avoid_print

import 'dart:io';

import '../integration_test_arguments.dart';
import 'app_data.dart';

/// Runs integration tests for web or native apps using the `flutter drive`
/// command.
class IntegrationTestRunner {
  static const _chromeExecutableEnvironmentKey = 'CHROME_EXECUTABLE';

  /// Runs integration tests for web or native apps using the `flutter drive`
  /// command.
  ///
  /// [_args] is the arguments for the integration test.
  /// [testsDirectory] is the path to the directory containing the integration
  /// tests. Defaults to `integration_test/tests/`.
  ///
  /// Throws a [ProcessException] if the test fails.
  IntegrationTestRunner(
    this._args, {
    this.testsDirectory = 'integration_test/tests/',
  });

  final IntegrationTestArguments _args;
  final String testsDirectory;

  bool get isWeb => _args.device == 'web-server';
  String get _browserDimension => _args.browserDimension.replaceAll(',', 'x');
  String? get _chromeBinaryPath {
    if (_args.browserName != 'chrome') {
      return null;
    }

    final chromeBinary = Platform.environment[_chromeExecutableEnvironmentKey];
    if (chromeBinary == null || chromeBinary.isEmpty) {
      return null;
    }

    return chromeBinary;
  }

  Future<void> runTest(String test) async {
    ProcessResult result;

    print('Running test $test');

    try {
      if (isWeb) {
        result = await _runWebServerTest(test);
      } else {
        //Clear app data before tests for Desktop native app
        await clearNativeAppsData();

        // Run integration tests for native apps
        // E.g. Linux, MacOS, Windows, iOS, Android
        result = await _runNativeTest(test);
      }
    } catch (e, s) {
      print(s);
      throw Exception('Error running flutter drive Process: $e');
    }

    printProcessOutput(result);

    // Flutter drive can return failed test results just as stdout message,
    // we need to parse this message and detect test failure manually
    if (_didAnyTestFail(result)) {
      throw ProcessException(
        'flutter',
        ['test $test'],
        'Failure details are in ${_args.browserName} driver output.\n',
        -1,
      );
    }
    print('Finished Running $test\n---\n');
  }

  void printProcessOutput(ProcessResult result) {
    print('===== Process Output Start =====');
    stdout.write(result.stdout);

    if (_didAnyTestFail(result)) {
      print('----- STDERR -----');
      stderr.write(result.stderr);
      print('----- End of STDERR -----');
    }

    print('===== Process Output End =====');
  }

  Future<ProcessResult> _runNativeTest(String test) async {
    return Process.run('flutter', [
      'drive',
      '--dart-define=testing_mode=true',
      '--dart-define=CI=true',
      '--dart-define=ANALYTICS_DISABLED=true',
      '--driver=test_driver/integration_test.dart',
      '--target=$testsDirectory/$test',
      if (_args.verbose) '-v',
      '-d',
      _args.device,
      '--${_args.runMode}',
      if (_args.runMode == 'profile') '--profile-memory=memory_profile.json',
      '--${_args.pub ? '' : 'no-'}pub',
      '--${_args.keepRunning ? '' : 'no-'}keep-app-running',
      '--timeout=600',
    ], runInShell: true);
  }

  Future<ProcessResult> _runWebServerTest(String test) async {
    return Process.run('flutter', [
      'drive',
      '--dart-define=testing_mode=true',
      '--dart-define=CI=true',
      '--dart-define=ANALYTICS_DISABLED=true',
      '--driver=test_driver/integration_test.dart',
      '--target=$testsDirectory/$test',
      if (_args.verbose) '-v',
      '-d',
      _args.device,
      '--browser-dimension',
      _browserDimension,
      '--${_args.displayMode}',
      '--${_args.runMode}',
      if (_args.runMode == 'profile') '--profile-memory=memory_profile.json',
      '--browser-name',
      _args.browserName,
      if (_chromeBinaryPath != null) '--chrome-binary=$_chromeBinaryPath',
      '--${_args.pub ? '' : 'no-'}pub',
      '--${_args.keepRunning ? '' : 'no-'}keep-app-running',
      '--driver-port=${_args.driverPort}',
      '--timeout=600',
    ], runInShell: true);
  }

  bool _didAnyTestFail(ProcessResult result) {
    final caseInvariantConsoleOutput =
        result.stdout.toString().toLowerCase() +
        result.stderr.toString().toLowerCase();

    return caseInvariantConsoleOutput.contains('failure details') ||
        caseInvariantConsoleOutput.contains('test failed') ||
        !caseInvariantConsoleOutput.contains('all tests passed');
  }
}

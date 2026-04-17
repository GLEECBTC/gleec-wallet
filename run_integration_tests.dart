// ignore_for_file: avoid_print

import 'dart:io';

import 'package:args/args.dart';

import 'test_integration/integration_test_arguments.dart';
import 'test_integration/runners/drivers/web_browser_driver.dart';
import 'test_integration/runners/integration_test_runner.dart';

Future<void> main(List<String> args) async {
  final ArgParser parser = _configureArgParser();
  IntegrationTestArguments testArgs = IntegrationTestArguments.fromArgs(
    parser.parse(args),
  );
  // TODO!: re-enable suspended assets test when issues are figured out
  final Set<String> testsList = getTestsList(
    false,
  ); //testArgs.isWeb && testArgs.isChrome);
  bool didTestFail = false;
  WebBrowserDriver? driver;
  const testsWithUrlBlocking = [
    'suspended_assets_test/suspended_assets_test.dart',
  ];

  if (testArgs.runHelp) {
    print(parser.usage);
    exit(0);
  }

  if (testArgs.testToRun.isNotEmpty) {
    testsList
      ..clear()
      ..add(testArgs.testToRun);
  }

  driver = testArgs.isWeb
      ? createWebBrowserDriver(
          browser: WebBrowser.fromName(testArgs.browserName),
          port: testArgs.driverPort,
        )
      : null;
  _registerProcessSignalHandlers(driver);

  // Block electrum servers for the suspended assets test to force an
  // activation error for coins relient on the domain
  final bool isUrlBlockedTest = testsWithUrlBlocking.any(
    (test) => testsList.contains(test),
  );
  if (testArgs.isWeb && testArgs.isChrome && isUrlBlockedTest) {
    await driver?.blockUrl('*.cipig.net');
    // `flutter pub get` is required between tests, since blocking domains
    // modifies the flutter_tools package, which needs to be rebuilt
    testArgs = testArgs.copyWith(pub: true, concurrent: false);
  }

  try {
    final testRunner = IntegrationTestRunner(
      testArgs,
      testsDirectory: 'test_integration/tests',
    );
    await driver?.start();

    final testFutures = testsList.map((test) async {
      await testRunner.runTest(test);
      await driver?.reset(); // reset configuration changes
    });

    if (testArgs.concurrent) {
      await Future.wait(testFutures);
    } else {
      for (final testFuture in testFutures) {
        await testFuture;
      }
    }
  } on ProcessException catch (e, s) {
    print('TEST FAILED: ${e.executable} ${e.arguments.join(' ')}');
    print('$e: \n$s');
    didTestFail = true;
  } catch (e, s) {
    print('$e: \n$s');
    didTestFail = true;
  } finally {
    await driver?.stop();
  }

  exit(didTestFail ? 1 : 0);
}

void _registerProcessSignalHandlers(WebBrowserDriver? driver) {
  ProcessSignal.sigint.watch().listen((_) {
    print('Caught SIGINT, shutting down...');
    if (driver != null) cleanup(driver);
  });

  ProcessSignal.sigterm.watch().listen((_) {
    print('Caught SIGTERM, shutting down...');
    if (driver != null) cleanup(driver);
  });
}

// leaving the args here for now so that the available options and default
// values are easy to find and modify
ArgParser _configureArgParser() {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', help: 'Show help message and exit')
    ..addFlag('verbose', abbr: 'v', help: 'Print verbose output')
    ..addOption(
      'testToRun',
      abbr: 't',
      defaultsTo: '',
      help:
          'Specify a single testfile to run, if option is not used, '
          'all available tests will be run instead; option usage '
          'example: -t "design_tests/theme_test.dart"',
    )
    ..addOption(
      'browserDimension',
      abbr: 'b',
      defaultsTo: '1024,1400',
      help: 'Set device window(screen) dimensions: height, width',
    )
    ..addOption(
      'displayMode',
      abbr: 'd',
      defaultsTo: 'no-headless',
      help:
          'Set to "headless" for headless mode usage, defaults to no-headless',
      allowed: ['headless', 'no-headless'],
    )
    ..addOption(
      'device',
      abbr: 'D',
      defaultsTo: 'web-server',
      help: 'Set device to run tests on',
      allowedHelp: {
        'web-server': 'Web server (default)',
        'chrome': 'Test Chrome',
        'linux': 'Test native Linux application',
        'macos': 'Test native macOS application',
        'windows': 'Test native Windows application',
        'ios': 'iOS',
        'android': 'Android',
      },
    )
    ..addOption(
      'runMode',
      abbr: 'm',
      defaultsTo: 'profile',
      help: 'App build mode selectrion',
      allowed: ['release', 'debug', 'profile'],
    )
    ..addOption(
      'browser-name',
      abbr: 'n',
      defaultsTo: 'chrome',
      help: 'Set browser to run tests on',
      allowed: ['chrome', 'safari', 'firefox'],
    )
    ..addOption(
      'driver-port',
      abbr: 'p',
      defaultsTo: '4444',
      help: 'Port to use to start and communicate with the web browser driver',
    )
    ..addFlag(
      'pub',
      negatable: false,
      help: 'Run pub get before running each test group',
    )
    ..addFlag('wasm', help: 'Compile web integration tests to WebAssembly')
    ..addFlag(
      'concurrent',
      abbr: 'c',
      help:
          'Run tests concurrently. This is not recommended with the current '
          'flutter build steps and transformers.',
    )
    ..addFlag('keep-running', abbr: 'k');
  return parser;
}

// ignore: avoid_positional_boolean_parameters ? there's only one parameter
Set<String> getTestsList(bool runSuspendedAssetsTest) {
  // omit './test_integration/tests/' part of path to testfile
  return {
    // Suspended assets tests rely on blocking network requests to electrum
    // servers, which is only supported on web platforms at this time.
    // The previous approach was to modify coin_config.json, but this is no
    // longer possible with it being managed by an external package. Any changes
    // to the file in the `build/` directory will be overwritten.
    if (runSuspendedAssetsTest)
      'suspended_assets_test/suspended_assets_test.dart',
    'wallets_tests/wallets_tests.dart',
    'wallets_manager_tests/wallets_manager_tests.dart',
    'dex_tests/dex_tests.dart',
    'misc_tests/misc_tests.dart',
    'fiat_onramp_tests/fiat_onramp_tests.dart',
  };
}

Future<void> cleanup(WebBrowserDriver driver) async {
  await driver.stop();
  exit(0);
}

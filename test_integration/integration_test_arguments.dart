import 'package:args/args.dart';

class IntegrationTestArguments {
  const IntegrationTestArguments({
    required this.runHelp,
    required this.verbose,
    required this.pub,
    required this.wasm,
    required this.testToRun,
    required this.browserDimension,
    required this.displayMode,
    required this.device,
    required this.runMode,
    required this.browserName,
    required this.concurrent,
    required this.keepRunning,
    required this.driverPort,
  });

  factory IntegrationTestArguments.fromArgs(ArgResults results) {
    return IntegrationTestArguments(
      runHelp: results['help'] as bool,
      verbose: results['verbose'] as bool? ?? false,
      testToRun: results['testToRun'] as String,
      wasm: results['wasm'] as bool? ?? false,
      browserDimension: results['browserDimension'] as String,
      displayMode: results['displayMode'] as String,
      device: results['device'] as String,
      runMode: results['runMode'] as String,
      browserName: results['browser-name'] as String,
      pub: results['pub'] as bool? ?? false,
      concurrent: results['concurrent'] as bool? ?? false,
      keepRunning: results['keep-running'] as bool? ?? false,
      driverPort: int.tryParse(results['driver-port'] as String? ?? '') ?? 4444,
    );
  }

  final bool runHelp;
  final bool verbose;
  final bool pub;
  final bool wasm;
  final String testToRun;
  final String browserDimension;
  final String displayMode;
  final String device;
  final String runMode;
  final String browserName;
  final bool concurrent;
  final bool keepRunning;
  final int driverPort;

  bool get isChrome => browserName == 'chrome';
  bool get isWeb => device == 'web-server';

  IntegrationTestArguments copyWith({
    bool? runHelp,
    bool? verbose,
    bool? pub,
    bool? wasm,
    String? testToRun,
    String? browserDimension,
    String? displayMode,
    String? device,
    String? runMode,
    String? browserName,
    bool? concurrent,
    bool? keepRunning,
    int? driverPort,
  }) {
    return IntegrationTestArguments(
      runHelp: runHelp ?? this.runHelp,
      verbose: verbose ?? this.verbose,
      pub: pub ?? this.pub,
      wasm: wasm ?? this.wasm,
      testToRun: testToRun ?? this.testToRun,
      browserDimension: browserDimension ?? this.browserDimension,
      displayMode: displayMode ?? this.displayMode,
      device: device ?? this.device,
      runMode: runMode ?? this.runMode,
      browserName: browserName ?? this.browserName,
      concurrent: concurrent ?? this.concurrent,
      keepRunning: keepRunning ?? this.keepRunning,
      driverPort: driverPort ?? this.driverPort,
    );
  }
}

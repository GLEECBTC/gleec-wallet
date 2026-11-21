// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'web_browser_driver.dart';

mixin WebDriverProcessMixin {
  int? _processId;
  String get driverName;
  int get port;

  bool get isRunning => _processId != null;

  Future<void> startDriver(String executableName, List<String> args) async {
    if (await isPortInUse(port)) {
      print('Port $port is already in use. Please stop the running $driverName'
          ' or use a different port.');
      print('Continuing tests with the prcoess currently using the port');
      return;
    }

    final isProcessActive =
        await _isProcessRunningByName(executableName) && _processId != null;
    if (isRunning || isProcessActive) {
      print('Attempting to stop running $driverName with PID $_processId');
      await stopDriver();
      if (isRunning || await _isProcessRunningByName(executableName)) {
        print('Failed to stop running $driverName. Please try closing it with '
            'Task Manager (Windows) or Activity Monitor (macOS)');
        return;
      }
    }

    final driverPath = WebBrowserDriver.findDriverExecutable(executableName);
    print('Running: $driverPath ${args.join(' ')}');
    final process = await Process.start(driverPath, args);
    _processId = process.pid;

    _captureStream(process.stdout, 'stdout').ignore();
    _captureStream(process.stderr, 'stderr').ignore();
    int? exitCode;
    unawaited(
      process.exitCode.then((code) {
        exitCode = code;
      }),
    );

    const startupTimeout = Duration(seconds: 15);
    final startup = Stopwatch()..start();
    while (exitCode == null && startup.elapsed < startupTimeout) {
      if (await _isDriverListening(port) && exitCode == null) {
        print('$driverName started on port $port (PID: ${process.pid})');
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    final startupExitCode = exitCode;
    if (startupExitCode != null) {
      _processId = null;
      throw ProcessException(
        driverPath,
        args,
        '$driverName (PID ${process.pid}) exited before opening port $port',
        startupExitCode,
      );
    }
    await stopDriver();
    throw ProcessException(
      driverPath,
      args,
      '$driverName (PID ${process.pid}) did not open port $port '
      'within ${startupTimeout.inSeconds} seconds',
    );
  }

  Future<void> stopDriver() async {
    if (_processId == null) {
      print('Cannot stop $driverName: no pid - likely not running or started');
      return;
    }

    try {
      print('Attempting to stop $driverName with PID $_processId');
      if (Platform.isWindows) {
        await _killWindowsProcess(_processId!);
      } else {
        await _killUnixProcess(_processId!);
      }
      _processId = null;
    } catch (e) {
      print('Error stopping $driverName: $e');
    }

    print('$driverName stopped');
  }

  Future<void> _killUnixProcess(int pid) async {
    final result = await Process.run('kill', ['-9', pid.toString()]);
    if (result.exitCode != 0) {
      print(
        'Warning: Failed to kill $driverName process: ${result.stderr}',
      );
    }
  }

  Future<void> _killWindowsProcess(int pid) async {
    final result = await Process.run(
      'taskkill',
      ['/F', '/PID', pid.toString()],
    );
    if (result.exitCode != 0) {
      print(
        'Warning: Failed to kill $driverName process: ${result.stderr}',
      );
    }
  }
}

Future<bool> _isDriverListening(int port) async {
  try {
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
      timeout: const Duration(seconds: 1),
    );
    socket.destroy();
  } on SocketException catch (_) {
    return false;
  }

  return true;
}

Future<bool> _isProcessRunningByName(String processName) async {
  bool isRunning;
  if (Platform.isWindows) {
    isRunning = await _isWindowsProcessRunningByName(processName);
  } else {
    isRunning = await _isUnixProcessRunningByName(processName);
  }
  return isRunning;
}

Future<bool> _isUnixProcessRunningByName(String processName) async {
  final result = await Process.run('ps', ['-A']);
  if (result.exitCode != 0) {
    return false;
  }
  return result.stdout.contains(processName);
}

Future<bool> _isWindowsProcessRunningByName(String processName) async {
  final result = await Process.run('tasklist', []);
  if (result.exitCode != 0) {
    return false;
  }
  return result.stdout.contains(processName);
}

Future<bool> isPortInUse(int port) async {
  try {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    await server.close();
    return false;
  } on SocketException {
    return true;
  }
}

Future<void> _captureStream(Stream<List<int>> stream, String streamName) async {
  await for (final line
      in stream.transform(utf8.decoder).transform(const LineSplitter())) {
    print('[$streamName] $line');
  }
}

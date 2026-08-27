import 'dart:io' show Platform;

/// Native environment block for the frame-perf document.
Map<String, dynamic> platformEnvironment() => <String, dynamic>{
      'os': Platform.operatingSystem,
      'os_version': Platform.operatingSystemVersion,
      'processors': Platform.numberOfProcessors,
      'dart_version': Platform.version,
    };

/// Web has no `dart:io` Platform. The fields exist so the document keeps one
/// shape across targets; a web run is never baseline-worthy anyway.
Map<String, dynamic> platformEnvironment() => <String, dynamic>{
      'os': 'web',
      'os_version': 'unknown',
      'processors': null,
      'dart_version': 'unknown',
    };

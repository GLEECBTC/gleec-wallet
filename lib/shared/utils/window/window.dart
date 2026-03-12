export 'window_stub.dart'
    if (dart.library.io) './window_native.dart'
    if (dart.library.js_interop) './window_web.dart';

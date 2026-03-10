import 'dart:async';

import 'platform_web_api_implementation.dart'
    if (dart.library.js_interop) 'platform_web_api_web.dart'
    if (dart.library.io) 'platform_web_api_stub.dart';

/// Abstract interface for browser-only APIs used by Flutter web runtime code.
abstract class PlatformWebApi {
  void setElementDisplay(String elementId, String display);

  void addElementClass(String elementId, String className);

  void removeElement(String elementId);

  StreamSubscription<void> onPopState(void Function() callback);

  factory PlatformWebApi() => createPlatformWebApi();
}

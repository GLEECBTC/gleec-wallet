import 'dart:async';

import 'platform_web_api.dart';

class PlatformWebApiStub implements PlatformWebApi {
  @override
  void addElementClass(String elementId, String className) {}

  @override
  StreamSubscription<void> onPopState(void Function() callback) {
    return Stream<void>.empty().listen((_) {});
  }

  @override
  void removeElement(String elementId) {}

  @override
  void setElementDisplay(String elementId, String display) {}
}

PlatformWebApi createPlatformWebApi() => PlatformWebApiStub();

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'platform_web_api.dart';

@JS()
extension type _StyledElement._(web.Element _) implements web.Element {
  external web.CSSStyleDeclaration get style;
}

class PlatformWebApiWeb implements PlatformWebApi {
  @override
  void setElementDisplay(String elementId, String display) {
    final element = web.document.getElementById(elementId);
    if (element != null) {
      _StyledElement._(element).style.display = display;
    }
  }

  @override
  void addElementClass(String elementId, String className) {
    final element = web.document.getElementById(elementId);
    element?.classList.add(className);
  }

  @override
  void removeElement(String elementId) {
    final element = web.document.getElementById(elementId);
    element?.remove();
  }

  @override
  StreamSubscription<void> onPopState(void Function() callback) {
    return web.window.onPopState.listen((_) => callback());
  }
}

PlatformWebApi createPlatformWebApi() => PlatformWebApiWeb();

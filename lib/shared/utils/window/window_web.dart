import 'dart:js_interop';

import 'package:web/web.dart' as web;

String getOriginUrl() {
  return web.window.location.origin;
}

void showMessageBeforeUnload(String message) {
  web.window.onbeforeunload = (web.BeforeUnloadEvent event) {
    event
      ..preventDefault()
      ..returnValue = message;
  }.toJS;
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_dex/app_config/app_config.dart';

String getOriginUrl() {
  return 'https://app.gleec.com';
}

/// Shows a confirmation dialog when the user attempts to close the application.
///
/// On native platforms there is no direct equivalent to the browser
/// `onbeforeunload` event, however we can intercept the back button or window
/// close requests using a [WidgetsBindingObserver].
class _BeforeUnloadObserver with WidgetsBindingObserver {
  _BeforeUnloadObserver(this.message);

  final String message;
  bool _dialogShown = false;

  @override
  Future<bool> didPopRoute() async {
    if (_dialogShown) return true;

    final context = scaffoldKey.currentContext;
    if (context == null) return true;

    _dialogShown = true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    _dialogShown = false;

    if (result == true) {
      // SystemNavigator.pop works on mobile; on desktop fall back to exit(0).
      await SystemNavigator.pop();
      if (!Platform.isAndroid && !Platform.isIOS) exit(0);
    }
    return true;
  }
}

_BeforeUnloadObserver? _observer;

void showMessageBeforeUnload(String message) {
  _observer ??= _BeforeUnloadObserver(message);
  WidgetsBinding.instance.addObserver(_observer!);
}

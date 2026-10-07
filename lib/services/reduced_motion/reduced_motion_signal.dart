import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:web_dex/shared/utils/window/window.dart' as window;

/// The system "reduce motion" setting on the platforms whose Flutter engine
/// does not report it: web, macOS and Windows.
///
/// Android and Linux set `MediaQuery.disableAnimations` themselves, and iOS
/// sets `AccessibilityFeatures.reduceMotion`; `ReducedMotionScope` reads both.
class ReducedMotionSignal extends ValueNotifier<bool> {
  ReducedMotionSignal({
    MethodChannel channel = const MethodChannel('gleec/reduced-motion'),
    bool isWeb = kIsWeb,
    TargetPlatform? platform,
    bool Function() webQuery = window.prefersReducedMotion,
    void Function() Function(void Function(bool reduce)) watchWeb =
        window.watchReducedMotion,
  }) : _channel = channel,
       super(false) {
    if (isWeb) {
      value = webQuery();
      _stopWatchingWeb = watchWeb(_set);
      return;
    }
    final target = platform ?? defaultTargetPlatform;
    if (target == TargetPlatform.macOS || target == TargetPlatform.windows) {
      _listening = true;
      _channel.setMethodCallHandler(_onCall);
      unawaited(_read());
    }
  }

  final MethodChannel _channel;
  void Function()? _stopWatchingWeb;
  bool _listening = false;
  bool _disposed = false;

  // Never awaited on the way to the first frame, so a runner without the
  // channel only costs the setting, not startup.
  Future<void> _read() async {
    try {
      _set(await _channel.invokeMethod<bool>('get') ?? false);
    } on MissingPluginException {
      // A runner built before the channel existed.
    } on PlatformException {
      // The runner could not read the setting; keep motion on.
    }
  }

  Future<void> _onCall(MethodCall call) async {
    if (call.method == 'changed' && call.arguments is bool) {
      _set(call.arguments as bool);
    }
  }

  void _set(bool reduce) {
    if (!_disposed) value = reduce;
  }

  @override
  void dispose() {
    _disposed = true;
    _stopWatchingWeb?.call();
    if (_listening) _channel.setMethodCallHandler(null);
    super.dispose();
  }
}

import 'package:flutter/services.dart';

/// Small device controls the move screens need. Both are best effort: a
/// platform without them simply does nothing.
abstract interface class DeviceControls {
  /// Keeps the screen from locking while a code waits to be scanned or
  /// compared. Always release it when the code goes.
  Future<void> keepScreenOn(bool on);

  /// Opens this app's page in the system Settings, for example to allow the
  /// camera after it was refused. False when it could not be opened.
  Future<bool> openAppSettings();
}

final class MethodChannelDeviceControls implements DeviceControls {
  const MethodChannelDeviceControls({
    MethodChannel channel = const MethodChannel('gleec.wallet/device_controls'),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<void> keepScreenOn(bool on) async {
    try {
      await _channel.invokeMethod<void>('keepScreenOn', {'on': on});
    } on Object {
      // The screen may still lock; the code then clears as on a timeout.
    }
  }

  @override
  Future<bool> openAppSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openSettings') ?? false;
    } on Object {
      return false;
    }
  }
}

import Flutter
import UIKit

/// Keeps the screen on while a move code is shown, and opens the app's page
/// in Settings, for example after the camera was refused.
final class DeviceControlsBridge {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "gleec.wallet/device_controls", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "keepScreenOn":
        let on = (call.arguments as? [String: Any])?["on"] as? Bool ?? false
        DispatchQueue.main.async {
          UIApplication.shared.isIdleTimerDisabled = on
          result(nil)
        }
      case "openSettings":
        DispatchQueue.main.async {
          guard let url = URL(string: UIApplication.openSettingsURLString) else {
            result(false)
            return
          }
          UIApplication.shared.open(url) { opened in result(opened) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var reducedMotionChannel: FlutterMethodChannel?
  private var reducedMotionObserver: NSObjectProtocol?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerReducedMotion(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  deinit {
    if let observer = reducedMotionObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }
  }

  /// Reports System Settings > Accessibility > Display > Reduce motion, which
  /// the Flutter engine does not pass to the app on macOS.
  private func registerReducedMotion(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "gleec/reduced-motion", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      if call.method == "get" {
        result(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    reducedMotionObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
      object: nil,
      queue: .main
    ) { _ in
      channel.invokeMethod(
        "changed", arguments: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
    reducedMotionChannel = channel
  }
}

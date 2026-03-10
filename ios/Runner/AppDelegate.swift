import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var fdMonitorChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    NSLog("🔴 AppDelegate: didFinishLaunchingWithOptions REACHED")

    #if DEBUG
    NSLog("AppDelegate: DEBUG build detected, auto-starting FD Monitor...")
    FdMonitor.shared.start(intervalSeconds: 60.0)
    #else
    NSLog("AppDelegate: RELEASE build, FD Monitor NOT auto-started (use Flutter to start manually)")
    #endif

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    NSLog("AppDelegate: Setting up FD Monitor channel...")
    setupFdMonitorChannel(binaryMessenger: engineBridge.applicationRegistrar.messenger())
  }

  private func setupFdMonitorChannel(binaryMessenger: FlutterBinaryMessenger) {
    fdMonitorChannel = FlutterMethodChannel(
      name: "com.komodo.wallet/fd_monitor",
      binaryMessenger: binaryMessenger
    )

    fdMonitorChannel?.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      self?.handleFdMonitorMethodCall(call: call, result: result)
    }
  }

  private func handleFdMonitorMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      let intervalSeconds: TimeInterval
      if let args = call.arguments as? [String: Any],
         let interval = args["intervalSeconds"] as? Double {
        intervalSeconds = interval
      } else {
        intervalSeconds = 60.0
      }
      FdMonitor.shared.start(intervalSeconds: intervalSeconds)
      result(["success": true, "message": "FD Monitor started with interval: \(intervalSeconds)s"])

    case "stop":
      FdMonitor.shared.stop()
      result(["success": true, "message": "FD Monitor stopped"])

    case "getCurrentCount":
      let count = FdMonitor.shared.getCurrentCount()
      result(count)

    case "logDetailedStatus":
      FdMonitor.shared.logDetailedStatus()
      result(["success": true, "message": "Detailed FD status logged"])

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

import AuthenticationServices
import Foundation
#if os(iOS)
import Flutter
#else
import FlutterMacOS
#endif

/// Google sign-in for the Drive app-data folder, in the system's web sign-in
/// sheet. Dart builds the PKCE request and redeems the code; this returns the
/// callback URL, which carries that code, and never logs it.
final class GoogleDriveAuthBridge: NSObject {
  private let channel: FlutterMethodChannel
  private var session: GoogleSignInSession?
  private var pendingResult: FlutterResult?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "gleec.wallet/google_drive_auth", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(Self.error("unavailable")); return }
      self.handle(call, result: result)
    }
  }

  private static func error(_ code: String) -> FlutterError {
    FlutterError(code: code, message: "Google sign-in could not be completed", details: nil)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "authorize" else { result(FlutterMethodNotImplemented); return }
    guard session == nil else { result(Self.error("busy")); return }
    let args = call.arguments as? [String: Any] ?? [:]
    // Only Google's sign-in page, returning to an OAuth client's own scheme.
    guard let text = args["url"] as? String, text.utf8.count <= 4096,
          let url = URL(string: text), url.scheme == "https", url.host == "accounts.google.com",
          url.user == nil, url.password == nil, url.port == nil,
          let scheme = args["callbackScheme"] as? String, Self.isClientScheme(scheme) else {
      result(Self.error("unavailable")); return
    }
    pendingResult = result
    let started = GoogleSignInSession(url: url, callbackScheme: scheme) { [weak self] callbackUrl, failure in
      self?.finish(callbackUrl: callbackUrl, failure: failure)
    }
    session = started
    if !started.start() { finish(callbackUrl: nil, failure: "unavailable") }
  }

  private func finish(callbackUrl: String?, failure: String?) {
    guard let result = pendingResult else { return }
    pendingResult = nil
    session = nil
    if let callbackUrl = callbackUrl {
      result(["callbackUrl": callbackUrl])
    } else {
      result(Self.error(failure ?? "unavailable"))
    }
  }

  /// The reversed iOS client id, e.g. `com.googleusercontent.apps.1234-abcd`.
  private static func isClientScheme(_ scheme: String) -> Bool {
    let prefix = "com.googleusercontent.apps."
    guard scheme.hasPrefix(prefix), scheme.utf8.count <= 160 else { return false }
    let id = scheme.utf8.dropFirst(prefix.utf8.count)
    return !id.isEmpty && id.allSatisfy {
      ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x2D
    }
  }
}

/// Owns the session and presents it: the system holds the provider weakly.
private final class GoogleSignInSession: NSObject, ASWebAuthenticationPresentationContextProviding {
  private let callbackScheme: String
  private var session: ASWebAuthenticationSession?
  private var completion: ((String?, String?) -> Void)?

  init(url: URL, callbackScheme: String, completion: @escaping (String?, String?) -> Void) {
    self.callbackScheme = callbackScheme
    self.completion = completion
    super.init()
    let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { [weak self] url, error in
      DispatchQueue.main.async { self?.complete(url, error) }
    }
    session.presentationContextProvider = self
    // Shares the browser's Google sign-in rather than asking for the password again.
    session.prefersEphemeralWebBrowserSession = false
    self.session = session
  }

  func start() -> Bool { session?.start() ?? false }

  private func complete(_ url: URL?, _ error: Error?) {
    let done = completion
    completion = nil
    session = nil
    if let url = url, url.scheme?.lowercased() == callbackScheme.lowercased() {
      done?(url.absoluteString, nil)
    } else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
      done?(nil, "canceled")
    } else {
      done?(nil, "unavailable")
    }
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    walletPresentationAnchor()
  }
}

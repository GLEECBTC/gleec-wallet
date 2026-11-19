import AuthenticationServices
import CryptoKit
import Foundation
import LocalAuthentication
#if os(iOS)
import Flutter
import UIKit
#else
import FlutterMacOS
import AppKit
import Security
#endif

/// One user-verified passkey assertion or creation at a time, evaluating the
/// WebAuthn PRF extension. It stores nothing and never sees the wallet
/// credential: the Dart passkey tier checks the reply, derives its key and
/// wipes the output.
final class WalletPasskeyBridge: NSObject {
  private let channel: FlutterMethodChannel
  private var ceremony: AnyObject?
  private var pendingResult: FlutterResult?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "gleec.wallet/passkey", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(Self.error("unavailable")); return }
      self.handle(call, result: result)
    }
  }

  private static func error(_ code: String) -> FlutterError {
    FlutterError(code: code, message: "Passkey request could not be completed", details: nil)
  }

  /// PRF needs iOS 18 or macOS 15. On iOS a passcode must be set: system
  /// passkeys cannot be used without one. On macOS the app must also carry
  /// the associated-domains entitlement, which only a provisioned build has;
  /// without it every request fails, so it is not offered.
  private var supported: Bool {
    guard #available(iOS 18.0, macOS 15.0, *) else { return false }
    #if os(macOS)
    guard let task = SecTaskCreateFromSelf(nil),
          let value = SecTaskCopyValueForEntitlement(
            task, "com.apple.developer.associated-domains" as CFString, nil),
          let domains = value as? [String] else { return false }
    return domains.contains { $0.hasPrefix("webcredentials:") }
    #else
    return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    #endif
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "support":
      result(["available": supported])
    case "cancel":
      cancel()
      result(nil)
    case "getAssertion":
      begin(call.arguments as? [String: Any] ?? [:], result: result)
    case "register":
      register(call.arguments as? [String: Any] ?? [:], result: result)
    case "reportRemoved":
      reportRemoved(call.arguments as? [String: Any] ?? [:])
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func begin(_ args: [String: Any], result: @escaping FlutterResult) {
    guard #available(iOS 18.0, macOS 15.0, *), supported else { result(Self.error("unavailable")); return }
    guard ceremony == nil else { result(Self.error("busy")); return }
    guard let rpId = args["rpId"] as? String, !rpId.isEmpty, rpId.utf8.count <= 253,
          let challenge = (args["challenge"] as? FlutterStandardTypedData)?.data, challenge.count >= 16,
          let salt = (args["salt"] as? FlutterStandardTypedData)?.data, salt.count == 32,
          let allowed = args["allowCredentials"] as? [FlutterStandardTypedData], allowed.count <= 16 else {
      result(Self.error("invalidResponse")); return
    }
    pendingResult = result
    let started = PasskeyCeremony(
      rpId: rpId, challenge: challenge, salt: salt,
      allowCredentials: allowed.map { $0.data }
    ) { [weak self] outcome in self?.finish(outcome) }
    ceremony = started
    started.start()
  }

  /// Creates a discoverable, user-verified passkey and evaluates PRF where the
  /// provider supports it at creation. Dart checks the reply.
  private func register(_ args: [String: Any], result: @escaping FlutterResult) {
    guard #available(iOS 18.0, macOS 15.0, *), supported else { result(Self.error("unavailable")); return }
    guard ceremony == nil else { result(Self.error("busy")); return }
    guard let rpId = args["rpId"] as? String, !rpId.isEmpty, rpId.utf8.count <= 253,
          let challenge = (args["challenge"] as? FlutterStandardTypedData)?.data, challenge.count >= 16,
          let userId = (args["userId"] as? FlutterStandardTypedData)?.data, (1...64).contains(userId.count),
          let userName = args["userName"] as? String, !userName.isEmpty, userName.utf8.count <= 1024,
          let displayName = args["displayName"] as? String, !displayName.isEmpty,
          displayName.utf8.count <= 1024,
          let salt = (args["prfSalt"] as? FlutterStandardTypedData)?.data, salt.count == 32 else {
      result(Self.error("invalidResponse")); return
    }
    pendingResult = result
    let started = PasskeyRegistrationCeremony(
      rpId: rpId, challenge: challenge, userId: userId, userName: userName,
      displayName: displayName, salt: salt
    ) { [weak self] outcome in self?.finish(outcome) }
    ceremony = started
    started.start()
  }

  /// Best effort, answered at once: the password manager may hide or delete
  /// the passkey later, or never. Older systems have no such signal.
  private func reportRemoved(_ args: [String: Any]) {
    // Toolchains older than these can ship an SDK predating each type.
    #if compiler(>=6.2)
    guard let rpId = args["rpId"] as? String, !rpId.isEmpty, rpId.utf8.count <= 253,
          let credentialId = (args["credentialId"] as? FlutterStandardTypedData)?.data,
          (1...1023).contains(credentialId.count) else { return }
    #if compiler(>=6.3)
    if #available(iOS 26.2, macOS 26.2, *) {
      Task {
        try? await ASCredentialDataManager().reportUnknownPublicKeyCredential(
          relyingPartyIdentifier: rpId, credentialID: credentialId)
      }
      return
    }
    #endif
    if #available(iOS 26.0, macOS 26.0, *) {
      Task {
        try? await ASCredentialUpdater().reportUnknownPublicKeyCredential(
          relyingPartyIdentifier: rpId, credentialID: credentialId)
      }
    }
    #endif
  }

  private func finish(_ outcome: Result<[String: Any], PasskeyFailure>) {
    guard let result = pendingResult else { return }
    pendingResult = nil
    ceremony = nil
    switch outcome {
    case .success(let value): result(value)
    case .failure(let failure): result(Self.error(failure.code))
    }
  }

  /// Answers the waiting call at once. The system's own cancellation
  /// callback arrives later and finds nothing to answer.
  private func cancel() {
    if #available(iOS 18.0, macOS 15.0, *), let running = ceremony as? PasskeyCeremony {
      running.cancel()
    }
    if #available(iOS 18.0, macOS 15.0, *), let running = ceremony as? PasskeyRegistrationCeremony {
      running.cancel()
    }
    finish(.failure(PasskeyFailure(code: "canceled")))
  }
}

struct PasskeyFailure: Error { let code: String }

@available(iOS 18.0, macOS 15.0, *)
private final class PasskeyCeremony: NSObject, ASAuthorizationControllerDelegate,
  ASAuthorizationControllerPresentationContextProviding {
  private let controller: ASAuthorizationController
  private var completion: ((Result<[String: Any], PasskeyFailure>) -> Void)?

  init(rpId: String, challenge: Data, salt: Data, allowCredentials: [Data],
       completion: @escaping (Result<[String: Any], PasskeyFailure>) -> Void) {
    let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpId)
    let request = provider.createCredentialAssertionRequest(challenge: challenge)
    // A PRF evaluated without verification uses a different secret and
    // would not open the envelope, so verification is never optional.
    request.userVerificationPreference = .required
    request.allowedCredentials = allowCredentials.map {
      ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0)
    }
    request.prf = .inputValues(.saltInput1(salt))
    controller = ASAuthorizationController(authorizationRequests: [request])
    self.completion = completion
    super.init()
    controller.delegate = self
    controller.presentationContextProvider = self
  }

  func start() { controller.performRequests() }

  func cancel() {
    completion = nil
    controller.cancel()
  }

  private func finish(_ outcome: Result<[String: Any], PasskeyFailure>) {
    let done = completion
    completion = nil
    done?(outcome)
  }

  func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
    #if os(iOS)
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
    return windows.first { $0.isKeyWindow } ?? windows.first ?? ASPresentationAnchor()
    #else
    return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
    #endif
  }

  func authorizationController(controller: ASAuthorizationController,
                               didCompleteWithAuthorization authorization: ASAuthorization) {
    guard let assertion = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
      finish(.failure(PasskeyFailure(code: "invalidResponse"))); return
    }
    guard let prf = assertion.prf else { finish(.failure(PasskeyFailure(code: "prfUnavailable"))); return }
    let output = prf.first.withUnsafeBytes { Data($0) }
    finish(.success([
      "credentialId": FlutterStandardTypedData(bytes: assertion.credentialID),
      "userHandle": FlutterStandardTypedData(bytes: assertion.userID),
      "authenticatorData": FlutterStandardTypedData(bytes: assertion.rawAuthenticatorData),
      "clientDataJSON": FlutterStandardTypedData(bytes: assertion.rawClientDataJSON),
      "signature": FlutterStandardTypedData(bytes: assertion.signature),
      "prf": FlutterStandardTypedData(bytes: output),
    ]))
  }

  func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
    let code: String
    switch (error as? ASAuthorizationError)?.code {
    // The system does not distinguish dismissal from finding no passkey.
    case .canceled?: code = "canceled"
    case .invalidResponse?: code = "invalidResponse"
    default: code = "unavailable"
    }
    finish(.failure(PasskeyFailure(code: code)))
  }
}

/// The window a system sheet attaches to.
func walletPresentationAnchor() -> ASPresentationAnchor {
  #if os(iOS)
  let windows = UIApplication.shared.connectedScenes
    .compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
  return windows.first { $0.isKeyWindow } ?? windows.first ?? ASPresentationAnchor()
  #else
  return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
  #endif
}

@available(iOS 18.0, macOS 15.0, *)
private final class PasskeyRegistrationCeremony: NSObject, ASAuthorizationControllerDelegate,
  ASAuthorizationControllerPresentationContextProviding {
  private let controller: ASAuthorizationController
  private var completion: ((Result<[String: Any], PasskeyFailure>) -> Void)?

  init(rpId: String, challenge: Data, userId: Data, userName: String, displayName: String, salt: Data,
       completion: @escaping (Result<[String: Any], PasskeyFailure>) -> Void) {
    let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpId)
    let request = provider.createCredentialRegistrationRequest(challenge: challenge, name: userName, userID: userId)
    request.displayName = displayName
    // The PRF key differs without verification, as for assertions.
    request.userVerificationPreference = .required
    request.attestationPreference = .none
    request.prf = .inputValues(.init(saltInput1: salt))
    controller = ASAuthorizationController(authorizationRequests: [request])
    self.completion = completion
    super.init()
    controller.delegate = self
    controller.presentationContextProvider = self
  }

  func start() { controller.performRequests() }

  func cancel() {
    completion = nil
    controller.cancel()
  }

  private func finish(_ outcome: Result<[String: Any], PasskeyFailure>) {
    let done = completion
    completion = nil
    done?(outcome)
  }

  func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
    walletPresentationAnchor()
  }

  func authorizationController(controller: ASAuthorizationController,
                               didCompleteWithAuthorization authorization: ASAuthorization) {
    guard let registration = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration,
          let attestation = registration.rawAttestationObject else {
      finish(.failure(PasskeyFailure(code: "invalidResponse"))); return
    }
    var value: [String: Any] = [
      "credentialId": FlutterStandardTypedData(bytes: registration.credentialID),
      "clientDataJSON": FlutterStandardTypedData(bytes: registration.rawClientDataJSON),
      "attestationObject": FlutterStandardTypedData(bytes: attestation),
      // The API reports none. A passkey made here is internal and usable over
      // hybrid; one made on a phone over hybrid lives on that phone.
      "transports": registration.attachment == .crossPlatform ? ["hybrid"] : ["hybrid", "internal"],
      "prfFirst": NSNull(),
    ]
    // Without a value here Dart compares two sign-ins instead.
    if let prf = registration.prf, prf.isSupported, let first = prf.first {
      value["prfFirst"] = FlutterStandardTypedData(bytes: first.withUnsafeBytes { Data($0) })
    }
    finish(.success(value))
  }

  func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
    let code: String
    switch (error as? ASAuthorizationError)?.code {
    case .canceled?: code = "canceled"
    case .invalidResponse?: code = "invalidResponse"
    default: code = "unavailable"
    }
    finish(.failure(PasskeyFailure(code: code)))
  }
}

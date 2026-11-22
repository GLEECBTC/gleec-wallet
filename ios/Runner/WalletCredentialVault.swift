import Foundation
import LocalAuthentication
import Security
import AuthenticationServices
import Darwin
#if os(iOS)
import Flutter
import UIKit
#else
import FlutterMacOS
import AppKit
#endif

/// Device-local credentials. Authentication is enforced by Keychain access
/// control, never by a Boolean preceding an unrestricted Keychain read.
final class WalletCredentialVault {
  private let channel: FlutterMethodChannel
  private let queue = DispatchQueue(label: "com.gleec.wallet.credential-vault")
  private let service = "com.gleec.wallet.credential-vault.v1"
  private var pending: Pending?
  private var observers: [NSObjectProtocol] = []
  private var saveTask: Task<Void, Never>?
  // A cancellation and a durable mutation are linearized by this lock. The
  // worker queue never reads main-thread-only `pending`.
  private let operationLock = NSLock()
  private var activeOperation: UUID?
  private var deletionAuthorizations: [String: DeletionAuthorization] = [:]
  private var deletionReadAuthorizations: [String: DeletionAuthorization] = [:]
  private var enrollmentReadbacks: [String: EnrollmentReadback] = [:]

  private struct RecordSnapshot: Equatable {
    let metadata: Data
    let persistentReference: Data?
  }

  private struct DeletionAuthorization {
    let key: String
    let snapshot: RecordSnapshot?
    let expires: TimeInterval
  }

  private struct EnrollmentReadback {
    let context: LAContext
    let snapshot: RecordSnapshot
    let expires: TimeInterval
  }

  private final class AuthenticationOutcome {
    var success = false
    var code = "unavailable"
  }

  private struct Pending {
    let id: UUID
    let context: LAContext
    let result: FlutterResult
  }

  private struct Failure: Error { let code: String }

  // Unlike wall time or an awake-only timer, continuous mach time also ages
  // deletion grants while the device sleeps.
  private func monotonicTime() -> TimeInterval {
    var timebase = mach_timebase_info_data_t()
    mach_timebase_info(&timebase)
    return Double(mach_continuous_time()) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
  }

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "gleec.wallet/credential_vault", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(FlutterError(code: "unavailable", message: "Credential storage unavailable", details: nil)); return }
      self.handle(call, result: result)
    }
    #if os(iOS)
    observers.append(NotificationCenter.default.addObserver(
      forName: UIApplication.protectedDataWillBecomeUnavailableNotification,
      object: nil, queue: .main
    ) { [weak self] _ in self?.deviceLocked() })
    #else
    for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.screensDidSleepNotification] {
      observers.append(NSWorkspace.shared.notificationCenter.addObserver(
        forName: name, object: nil, queue: .main
      ) { [weak self] _ in self?.deviceLocked() })
    }
    #endif
  }

  deinit {
    pending?.context.invalidate()
    for grant in enrollmentReadbacks.values { grant.context.invalidate() }
    saveTask?.cancel()
    #if os(iOS)
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    #else
    for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    #endif
  }

  private func deviceLocked() {
    cancelPending()
    channel.invokeMethod("deviceLocked", arguments: nil)
  }

  private func cancelPending() {
    operationLock.lock()
    activeOperation = nil
    deletionAuthorizations.removeAll()
    deletionReadAuthorizations.removeAll()
    for grant in enrollmentReadbacks.values { grant.context.invalidate() }
    enrollmentReadbacks.removeAll()
    operationLock.unlock()
    saveTask?.cancel()
    saveTask = nil
    guard let operation = pending else { return }
    pending = nil
    operation.context.invalidate()
    operation.result(FlutterError(code: "canceled", message: "Authentication canceled", details: nil))
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "cancel" { cancelPending(); result(nil); return }
    if call.method == "repairInvalidated" {
      result(FlutterError(code: "unavailable", message: "Credential repair unavailable", details: nil)); return
    }
    if call.method == "capabilities" {
      let available = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
      result(["available": true, "protection": available ? "authenticationBound" : "osAccountProtected", "deviceAuthentication": available])
      return
    }
    guard pending == nil else { result(FlutterError(code: "busy", message: "Another authentication is in progress", details: nil)); return }
    let args = call.arguments as? [String: Any] ?? [:]
    if call.method == "savePassword" { savePassword(args, result: result); return }
    guard ["metadata", "read", "write", "delete", "prepareDelete"].contains(call.method) else { result(FlutterMethodNotImplemented); return }
    guard let key = args["key"] as? String, !key.isEmpty, key.utf8.count <= 512, !key.contains("\0") else {
      result(FlutterError(code: "storageFailed", message: "Invalid credential request", details: nil)); return
    }
    let authenticated = args["requireAuthentication"] as? Bool ?? false
    var context = LAContext()
    var readbackSnapshot: RecordSnapshot?
    operationLock.lock()
    for (storedKey, grant) in enrollmentReadbacks where grant.expires < monotonicTime() {
      grant.context.invalidate()
      enrollmentReadbacks.removeValue(forKey: storedKey)
    }
    if call.method == "read", authenticated, args["purpose"] as? String == "verifyWrite",
       let grant = enrollmentReadbacks.removeValue(forKey: key) {
      context = grant.context
      readbackSnapshot = grant.snapshot
    }
    operationLock.unlock()
    context.localizedReason = args["reason"] as? String ?? "Unlock your Gleec wallet"
    context.touchIDAuthenticationAllowableReuseDuration = 0
    let operation = Pending(id: UUID(), context: context, result: result)
    pending = operation
    operationLock.lock()
    activeOperation = operation.id
    operationLock.unlock()
    let value = args["value"] as? String
    let expectedReadback = readbackSnapshot
    queue.async { [weak self] in
      guard let self = self else { return }
      let outcome: Result<Any?, Error>
      do {
        try self.withCurrentOperation(operation.id) {}
        switch call.method {
        case "metadata":
          context.interactionNotAllowed = true
          if let attributes = try self.attributes(key, context: context) {
            let info = try self.storedMetadata(attributes)
            outcome = .success(["protection": info.protected ? "authenticationBound" : "osAccountProtected", "enrolled": info.protected, "revision": info.revision])
          } else { outcome = .success(nil) }
        case "read":
          let snapshot = try self.snapshot(key, context: context)
          if let expected = expectedReadback, snapshot != expected { throw Failure(code: "busy") }
          let value = try self.read(key, requireAuthentication: authenticated, context: context, expected: expectedReadback)
          if args["purpose"] as? String == "delete" {
            try self.withCurrentOperation(operation.id) {
              context.interactionNotAllowed = true
              try self.checkSnapshot(key, expected: snapshot, context: context)
              self.deletionReadAuthorizations[key] = DeletionAuthorization(
                key: key, snapshot: snapshot, expires: self.monotonicTime() + 60)
            }
          }
          outcome = .success(value)
        case "write":
          guard let value = value, value.utf8.count <= 65536 else { throw Failure(code: "storageFailed") }
          try self.write(key, value: value, authenticated: authenticated, operation: operation)
          outcome = .success(nil)
        case "prepareDelete":
          let snapshot = try self.snapshot(key, context: context)
          let priorAuthorization: DeletionAuthorization? = try self.withCurrentOperation(operation.id) {
            guard let grant = self.deletionReadAuthorizations.removeValue(forKey: key),
                  grant.snapshot == snapshot, grant.expires >= self.monotonicTime() else { return nil }
            return grant
          }
          if priorAuthorization == nil { _ = try self.read(key, requireAuthentication: false, context: context) }
          let token = try self.withCurrentOperation(operation.id) {
            context.interactionNotAllowed = true
            try self.checkSnapshot(key, expected: snapshot, context: context)
            let token = UUID().uuidString
            self.deletionAuthorizations[token] = DeletionAuthorization(
              key: key, snapshot: snapshot, expires: priorAuthorization?.expires ?? (self.monotonicTime() + 60))
            return token
          }
          outcome = .success(token)
        default:
          // Deletion is not inherently authenticated by SecItemDelete. Read
          // first, or consume a prior, revision-bound one-use authorization.
          let authorization = args["authorization"] as? String
          let snapshot = try self.snapshot(key, context: context)
          if authorization == nil { _ = try self.read(key, requireAuthentication: false, context: context) }
          try self.withCurrentOperation(operation.id) {
            context.interactionNotAllowed = true
            if let token = authorization {
              guard let grant = self.deletionAuthorizations.removeValue(forKey: token),
                    grant.key == key, grant.snapshot == snapshot,
                    grant.expires >= self.monotonicTime() else { throw Failure(code: "invalidated") }
            }
            try self.checkSnapshot(key, expected: snapshot, context: context)
            if let snapshot = snapshot {
              let status = SecItemDelete(self.matchingQuery(key, snapshot: snapshot) as CFDictionary)
              guard status == errSecSuccess else { throw self.failure(status) }
            }
          }
          outcome = .success(nil)
        }
      } catch { outcome = .failure(error) }
      DispatchQueue.main.async { self.finish(operation.id, outcome: outcome) }
    }
  }

  private func finish(_ id: UUID, outcome: Result<Any?, Error>) {
    guard let operation = pending, operation.id == id else { return }
    pending = nil
    operationLock.lock()
    if activeOperation == id { activeOperation = nil }
    let retainedForReadback = enrollmentReadbacks.values.contains { $0.context === operation.context }
    operationLock.unlock()
    saveTask = nil
    if !retainedForReadback { operation.context.invalidate() }
    switch outcome {
    case .success(let value): operation.result(value)
    case .failure(let error):
      let code = (error as? Failure)?.code ?? "storageFailed"
      operation.result(FlutterError(code: code, message: "Credential operation could not be completed", details: nil))
    }
  }

  private func withCurrentOperation<T>(_ id: UUID, _ body: () throws -> T) throws -> T {
    operationLock.lock()
    defer { operationLock.unlock() }
    guard activeOperation == id else { throw Failure(code: "canceled") }
    return try body()
  }

  private func query(_ key: String) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecAttrSynchronizable as String: false,
    ]
    #if os(macOS)
    query[kSecUseDataProtectionKeychain as String] = true
    #endif
    return query
  }

  private func attributes(_ key: String, context: LAContext) throws -> [String: Any]? {
    var request = query(key)
    request[kSecReturnAttributes as String] = true
    request[kSecReturnPersistentRef as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    request[kSecUseAuthenticationContext as String] = context
    var value: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &value)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let result = value as? [String: Any] else { throw failure(status) }
    return result
  }

  private func snapshot(_ key: String, context: LAContext) throws -> RecordSnapshot? {
    guard let values = try attributes(key, context: context) else { return nil }
    return try snapshot(values)
  }

  private func snapshot(_ values: [String: Any]) throws -> RecordSnapshot {
    _ = try storedMetadata(values)
    guard let metadata = values[kSecAttrGeneric as String] as? Data else { throw Failure(code: "invalidated") }
    return RecordSnapshot(metadata: metadata, persistentReference: values[kSecValuePersistentRef as String] as? Data)
  }

  private func checkSnapshot(_ key: String, expected: RecordSnapshot?, context: LAContext) throws {
    guard try snapshot(key, context: context) == expected else { throw Failure(code: "busy") }
  }

  private func matchingQuery(_ key: String, snapshot: RecordSnapshot) -> [String: Any] {
    var request = query(key)
    request[kSecAttrGeneric as String] = snapshot.metadata
    if let reference = snapshot.persistentReference { request[kSecMatchItemList as String] = [reference] }
    return request
  }

  private func read(_ key: String, requireAuthentication: Bool, context: LAContext, expected: RecordSnapshot? = nil) throws -> String? {
    guard let metadata = try attributes(key, context: context) else { return nil }
    let isProtected = try storedMetadata(metadata).protected
    guard !requireAuthentication || isProtected else { throw Failure(code: "invalidated") }
    let snapshot = try snapshot(metadata)
    if let expected = expected, snapshot != expected { throw Failure(code: "busy") }
    var request = matchingQuery(key, snapshot: snapshot)
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    request[kSecUseAuthenticationContext as String] = context
    var value: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &value)
    guard status == errSecSuccess, var data = value as? Data else { throw failure(status) }
    defer { data.resetBytes(in: 0..<data.count) }
    guard let string = String(data: data, encoding: .utf8) else { throw Failure(code: "storageFailed") }
    return string
  }

  private func write(_ key: String, value: String, authenticated: Bool, operation: Pending) throws {
    let context = operation.context
    let existing = try attributes(key, context: context)
    let snapshot = try existing.map(self.snapshot)
    let previous = try existing.map(storedMetadata)
    let wasProtected = previous?.protected ?? false
    // A caller cannot weaken an existing record by changing a Dart argument.
    guard !wasProtected || authenticated else { throw Failure(code: "invalidated") }
    if wasProtected { _ = try read(key, requireAuthentication: true, context: context) }
    else if authenticated { try authorizeNewProtection(context) }
    var data = Data(value.utf8)
    defer { data.resetBytes(in: 0..<data.count) }
    let metadata = try JSONSerialization.data(withJSONObject: ["version": 1, "protected": authenticated, "revision": (previous?.revision ?? 0) + 1, "recordId": UUID().uuidString], options: .sortedKeys)
    var values: [String: Any] = [kSecValueData as String: data, kSecAttrGeneric as String: metadata]
    if authenticated {
      guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { throw Failure(code: "unavailable") }
      #if os(iOS)
      let accessibility = kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
      #else
      let accessibility = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      #endif
      guard let control = SecAccessControlCreateWithFlags(nil, accessibility, .userPresence, nil) else { throw Failure(code: "unavailable") }
      values[kSecAttrAccessControl as String] = control
    } else {
      values[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    }
    try withCurrentOperation(operation.id) {
      // Authorization has completed. The commit cannot open another OS dialog
      // while the cancellation lock is held.
      context.interactionNotAllowed = true
      try checkSnapshot(key, expected: snapshot, context: context)
      let status: OSStatus
      if let snapshot = snapshot {
        var request = matchingQuery(key, snapshot: snapshot)
        request[kSecUseAuthenticationContext as String] = context
        status = SecItemUpdate(request as CFDictionary, values as CFDictionary)
      } else {
        var request = query(key)
        request[kSecUseAuthenticationContext as String] = context
        values.forEach { request[$0.key] = $0.value }
        status = SecItemAdd(request as CFDictionary, nil)
      }
      guard status == errSecSuccess else { throw failure(status) }
      if authenticated {
        guard let stored = try self.snapshot(key, context: context) else { throw Failure(code: "storageFailed") }
        enrollmentReadbacks.removeValue(forKey: key)?.context.invalidate()
        enrollmentReadbacks[key] = EnrollmentReadback(
          context: context, snapshot: stored, expires: monotonicTime() + 30)
      }
    }
  }

  private func authorizeNewProtection(_ context: LAContext) throws {
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { throw Failure(code: "unavailable") }
    // This runs on the worker queue. The main thread remains free to cancel,
    // which invalidates this LAContext before the guarded Keychain commit.
    let completed = DispatchSemaphore(value: 0)
    let outcome = AuthenticationOutcome()
    context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Protect your Gleec wallet") { success, error in
      outcome.success = success
      if let error = error as? LAError {
        switch error.code {
        case .userCancel, .appCancel, .systemCancel, .invalidContext: outcome.code = "canceled"
        case .biometryLockout: outcome.code = "lockedOut"
        default: outcome.code = "unavailable"
        }
      }
      completed.signal()
    }
    completed.wait()
    guard outcome.success else { throw Failure(code: outcome.code) }
  }

  private func storedMetadata(_ attributes: [String: Any]) throws -> (protected: Bool, revision: Int) {
    guard let data = attributes[kSecAttrGeneric as String] as? Data,
          let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          json["version"] as? Int == 1, let protected = json["protected"] as? Bool,
          let revision = json["revision"] as? Int, revision > 0 else { throw Failure(code: "invalidated") }
    return (protected, revision)
  }

  private func failure(_ status: OSStatus) -> Failure {
    switch status {
    case errSecUserCanceled: return Failure(code: "canceled")
    // Keychain's auth-failed status does not distinguish denial from biometric
    // lockout. Do not invent a lockout diagnosis from this ambiguous result.
    case errSecAuthFailed: return Failure(code: "unavailable")
    case errSecInteractionNotAllowed, errSecNotAvailable: return Failure(code: "unavailable")
    case errSecItemNotFound, errSecDecode: return Failure(code: "invalidated")
    default: return Failure(code: "storageFailed")
    }
  }

  private func savePassword(_ args: [String: Any], result: @escaping FlutterResult) {
    #if os(iOS)
    guard let username = args["username"] as? String, let password = args["password"] as? String,
          !username.isEmpty, !password.isEmpty else { result("unavailable"); return }
    let operation = Pending(id: UUID(), context: LAContext(), result: result)
    pending = operation
    // Use the explicit preferred-manager save API where the SDK and OS expose
    // it. Associated-domain verification is still owned by the operating system.
    // Xcode toolchains before Swift 6.3 can ship an SDK predating this type.
    // They continue to compile the shared-web-credential compatibility path.
    #if compiler(>=6.3)
    if #available(iOS 26.2, *), let anchor = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene }).flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) {
      saveTask = Task { @MainActor [weak self] in
        guard let self = self else { return }
        do {
          try await ASCredentialDataManager().save(
            password: ASPasswordCredential(user: username, password: password),
            for: ASAutoFillURLScope(host: "dex.gleec.com"),
            title: args["title"] as? String, anchor: anchor)
          self.finish(operation.id, outcome: .success("accepted"))
        } catch {
          // The provider may not distinguish cancellation from policy refusal.
          self.finish(operation.id, outcome: .success(Task.isCancelled ? "declined" : "unknown"))
        }
      }
      return
    }
    #endif
    SecAddSharedWebCredential("dex.gleec.com" as CFString, username as CFString, password as CFString) { [weak self] error in
      let outcome: String
      if let error = error {
        outcome = CFErrorGetCode(error) == Int(errSecUserCanceled) ? "declined" : "unavailable"
      } else { outcome = "accepted" }
      DispatchQueue.main.async { self?.finish(operation.id, outcome: .success(outcome)) }
    }
    #else
    result("unavailable")
    #endif
  }
}

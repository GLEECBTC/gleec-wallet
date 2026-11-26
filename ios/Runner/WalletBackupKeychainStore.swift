import Foundation
import Security
#if os(iOS)
import Flutter
#else
import FlutterMacOS
#endif

/// Sealed passkey-backup records as synchronizable Keychain items, which
/// iCloud Keychain carries to the account's other Apple devices. A record is
/// ciphertext under the passkey: this store never sees a key or a seed, and
/// never logs a record.
final class WalletBackupKeychainStore {
  private static let service = "com.gleec.wallet.passkey-backup.v1"
  private static let maxRecordBytes = 16 * 1024
  private static let maxRecords = 256
  private let channel: FlutterMethodChannel
  private let queue = DispatchQueue(label: "com.gleec.wallet.backup-store")

  private struct Failure: Error { let code: String }

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "gleec.wallet/backup_store", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(Self.error("unavailable")); return }
      self.handle(call, result: result)
    }
  }

  private static func error(_ code: String) -> FlutterError {
    FlutterError(code: code, message: "Backup storage could not be completed", details: nil)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let work: () throws -> Any?
    switch call.method {
    case "isAvailable":
      work = { self.isAvailable() }
    case "list":
      work = { try self.list() }
    case "write":
      guard let id = Self.recordId(args["id"]),
            let data = (args["data"] as? FlutterStandardTypedData)?.data,
            !data.isEmpty, data.count <= Self.maxRecordBytes else {
        result(Self.error("storageFailed")); return
      }
      work = { try self.write(id, data: data); return nil }
    case "delete":
      guard let id = Self.recordId(args["id"]) else { result(Self.error("storageFailed")); return }
      work = { try self.delete(id); return nil }
    default:
      result(FlutterMethodNotImplemented); return
    }
    // Keychain calls can block; replies go back on the platform thread.
    queue.async {
      let outcome = Result { try work() }
      DispatchQueue.main.async {
        switch outcome {
        case .success(let value): result(value)
        case .failure(let error): result(Self.error((error as? Failure)?.code ?? "storageFailed"))
        }
      }
    }
  }

  /// A record id is base64url of 16 random bytes.
  private static func recordId(_ value: Any?) -> String? {
    guard let id = value as? String, isRecordId(id) else { return nil }
    return id
  }

  private static func isRecordId(_ id: String) -> Bool {
    id.utf8.count == 22 && id.utf8.allSatisfy {
      ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x30 && $0 <= 0x39)
        || $0 == 0x2D || $0 == 0x5F
    }
  }

  private func query(_ id: String? = nil) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrSynchronizable as String: true,
    ]
    if let id = id { query[kSecAttrAccount as String] = id }
    #if os(macOS)
    query[kSecUseDataProtectionKeychain as String] = true
    #endif
    return query
  }

  /// Whether this build can reach the synchronizable keychain at all. Apps
  /// cannot see whether iCloud Keychain sync is on; until it is, items stay
  /// on this device.
  private func isAvailable() -> Bool {
    var request = query()
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    let status = SecItemCopyMatching(request as CFDictionary, nil)
    return status == errSecSuccess || status == errSecItemNotFound
  }

  private func list() throws -> [[String: Any]] {
    var request = query()
    request[kSecMatchLimit as String] = kSecMatchLimitAll
    request[kSecReturnAttributes as String] = true
    var value: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &value)
    if status == errSecItemNotFound { return [] }
    guard status == errSecSuccess, let items = value as? [[String: Any]] else { throw failure(status) }
    // One malformed item must not hide the others.
    let ids = items.compactMap { $0[kSecAttrAccount as String] as? String }.filter(Self.isRecordId)
    var records: [[String: Any]] = []
    for id in Set(ids).sorted().prefix(Self.maxRecords) {
      guard let data = try read(id), !data.isEmpty, data.count <= Self.maxRecordBytes else { continue }
      records.append(["id": id, "data": FlutterStandardTypedData(bytes: data)])
    }
    return records
  }

  private func read(_ id: String) throws -> Data? {
    var request = query(id)
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    request[kSecReturnData as String] = true
    var value: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &value)
    guard status == errSecSuccess else {
      // Only a locked or unreachable keychain fails the whole listing.
      let failure = self.failure(status)
      if failure.code == "unavailable" { throw failure }
      return nil
    }
    return value as? Data
  }

  private func write(_ id: String, data: Data) throws {
    var item = query(id)
    item[kSecValueData as String] = data
    // Synchronizable items cannot be ThisDeviceOnly.
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    let status = SecItemAdd(item as CFDictionary, nil)
    guard status == errSecDuplicateItem else {
      guard status == errSecSuccess else { throw failure(status) }
      return
    }
    let changes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]
    let updated = SecItemUpdate(query(id) as CFDictionary, changes as CFDictionary)
    guard updated == errSecSuccess else { throw failure(updated) }
  }

  /// Deleting an absent record succeeds: another device may have removed it.
  private func delete(_ id: String) throws {
    let status = SecItemDelete(query(id) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
  }

  private func failure(_ status: OSStatus) -> Failure {
    switch status {
    // Locked before first unlock, or a build without a keychain entitlement.
    case errSecInteractionNotAllowed, errSecNotAvailable, errSecMissingEntitlement:
      return Failure(code: "unavailable")
    default:
      return Failure(code: "storageFailed")
    }
  }
}

/// Non-web stub for the persistent-storage request.
///
/// Eviction is a browser problem. On native, wallet data lives in the app
/// sandbox and is only removed when the user removes the app, so there is
/// nothing to ask for and the real implementation is never compiled in.
///
/// See `storage_persistence_web.dart` for the contract these must both satisfy.
/// A conditional import must present an identical top-level API on both sides -
/// the analyzer resolves this file, so anything missing here fails the build
/// for every platform, not just native.
library;

/// The outcome of asking the browser to keep this origin's storage.
enum StoragePersistence {
  /// Already persistent; nothing was asked.
  alreadyPersistent,

  /// The browser granted persistence.
  granted,

  /// The browser refused. Worth retrying later - engagement heuristics change,
  /// and a denial is not sticky.
  denied,

  /// No such API here. Never worth retrying.
  unsupported,
}

/// Always [StoragePersistence.unsupported] off web.
Future<StoragePersistence> requestPersistentStorage() async =>
    StoragePersistence.unsupported;

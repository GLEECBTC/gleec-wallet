import 'package:web_dex/services/wallet_transfer/wallet_transfer_secret.dart';

/// Where a sealed backup record lives. The record is encrypted under the
/// passkey either way; the store only decides which devices can find it.
enum BackupStoreKind {
  /// A synchronizable Keychain item: every Apple device on the account.
  iCloudKeychain,

  /// The app's hidden folder in the user's Google Drive.
  googleDrive,

  /// A file the user saves and keeps themselves.
  file,
}

/// Why a backup action did not complete. Each maps to one message and one
/// next step in the UI.
enum PasskeyBackupFailure {
  notConfigured,
  unavailable,
  canceled,

  /// The chosen password manager returns no PRF key.
  prfUnavailable,

  /// The passkey stays on this device, so it cannot restore anywhere else.
  localOnly,

  /// The passkey was made on another device over QR. Keys over that route
  /// have differed from on-device ones, so a backup needs a passkey saved in
  /// this device's password manager.
  createdElsewhere,

  /// The passkey gave a different key the second time.
  notReproducible,
  storeUnavailable,
  storageFailed,
  noBackupFound,

  /// The chosen passkey is not the one this backup was sealed to, or it
  /// produced a different key on this device.
  wrongPasskey,
  damaged,

  /// Sealed for another relying party (another build or host).
  otherRelyingParty,
  newerVersion,
}

final class PasskeyBackupException implements Exception {
  const PasskeyBackupException(this.failure);

  final PasskeyBackupFailure failure;

  @override
  String toString() => 'PasskeyBackupException(${failure.name})';
}

/// A sealed record as found in a store. [raw] is ciphertext plus a public
/// header; nothing in it names the wallet.
final class StoredBackup {
  const StoredBackup({
    required this.id,
    required this.store,
    required this.created,
    required this.raw,
  });

  final String id;
  final BackupStoreKind store;
  final DateTime created;
  final String raw;
}

/// Holds sealed records. Implementations never see a key or a seed.
abstract interface class BackupRecordStore {
  BackupStoreKind get kind;

  Future<bool> isAvailable();

  /// Gets the store ready before any passkey prompt, so a creation never
  /// asks for a sign-in between them (Google Drive). A no-op elsewhere.
  Future<void> prepare();

  /// May ask the user to sign in (Google Drive).
  Future<List<StoredBackup>> list();

  Future<void> write(String id, String raw);

  Future<void> delete(String id);
}

/// Whether a backup can be relied on yet.
enum PasskeyBackupEntryState {
  ready,

  /// Creation stopped before the stored copy was proven to open (the app
  /// was closed mid-way). Offer Check, which finishes it, or Remove.
  unfinished,

  /// A file backup the user has not saved anywhere yet. It exists only in
  /// this app until they do.
  fileNotSaved,
}

/// A backup this device made for one of its wallets.
final class PasskeyBackupEntry {
  const PasskeyBackupEntry({
    required this.id,
    required this.walletKey,
    required this.store,
    required this.created,
    required this.synced,
    this.providerName,
    this.checkedHere,
    this.state = PasskeyBackupEntryState.ready,
  });

  final PasskeyBackupEntryState state;

  final String id;
  final String walletKey;
  final BackupStoreKind store;
  final DateTime created;

  /// The signed backup-state flag at creation: the passkey syncs.
  final bool synced;

  /// A hint from the unauthenticated AAGUID, e.g. "Google Password
  /// Manager". Never used for a security decision.
  final String? providerName;

  /// When this device last proved it can open the backup.
  final DateTime? checkedHere;
}

final class PasskeyBackupAvailability {
  const PasskeyBackupAvailability({
    required this.canCreate,
    required this.canRestore,
    required this.stores,
  });

  static const none = PasskeyBackupAvailability(
    canCreate: false,
    canRestore: false,
    stores: [],
  );

  final bool canCreate;
  final bool canRestore;

  /// Stores usable on this device, in the order to offer them.
  final List<BackupStoreKind> stores;
}

/// What the screens drive. Every method throws [PasskeyBackupException] or
/// `WalletAccessException`; none returns a partial result.
abstract interface class PasskeyBackupController {
  Future<PasskeyBackupAvailability> availability();

  Future<List<PasskeyBackupEntry>> backupsFor(String walletKey);

  /// Creates a passkey, seals [secret] to it, writes it to [store], then
  /// proves the stored copy opens with a second sign-in. Nothing is kept
  /// unless every step passed.
  Future<PasskeyBackupEntry> create({
    required String walletKey,
    required WalletTransferSecret secret,
    required BackupStoreKind store,
  });

  /// Opens the backup on this device without importing anything.
  Future<DateTime> check(PasskeyBackupEntry entry);

  /// Deletes the record and tells the password manager the passkey is no
  /// longer used. Copies made earlier cannot be recalled.
  Future<void> remove(PasskeyBackupEntry entry);

  /// The sealed record, for the user to save as a file.
  Future<String> exportFile(PasskeyBackupEntry entry);

  /// The user saved a file backup's record somewhere; until then it is
  /// [PasskeyBackupEntryState.fileNotSaved].
  Future<void> markFileSaved(PasskeyBackupEntry entry);

  Future<List<StoredBackup>> find(BackupStoreKind store);

  /// Validates a file the user picked.
  StoredBackup parseFile(String raw);

  /// One passkey prompt; throws [PasskeyBackupFailure.wrongPasskey] when
  /// the chosen passkey does not open it.
  Future<WalletTransferSecret> unlock(StoredBackup backup);

  Future<void> cancel();
}

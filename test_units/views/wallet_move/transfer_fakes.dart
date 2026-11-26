import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/services/device/device_controls.dart';
import 'package:web_dex/services/file_loader/guarded_file_saver.dart';
import 'package:web_dex/services/wallet_backup/passkey_backup_types.dart';
import 'package:web_dex/services/wallet_move/wallet_move_types.dart';
import 'package:web_dex/services/wallet_transfer/wallet_transfer_config.dart';
import 'package:web_dex/services/wallet_transfer/wallet_transfer_secret.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';
import 'package:web_dex/views/wallet_move/transfer_scanner.dart';

// Public BIP39 test vector, never a funded wallet.
const transferTestSeed =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

WalletTransferSecret transferSecret({
  String name = 'Savings',
  TransferWalletType type = TransferWalletType.hd,
  bool phraseConfirmed = true,
}) => WalletTransferSecret(
  walletName: name,
  type: type,
  seed: transferTestSeed,
  phraseConfirmed: phraseConfirmed,
);

KdfUser transferUser({
  String name = 'Savings',
  String type = 'hdwallet',
  String evidence = 'phraseConfirmed',
  String hash = 'transfer-hash',
  String entryId = 'entry-1',
}) => KdfUser(
  walletId: WalletId.withPubkeyHash(
    name,
    AuthOptions(
      derivationMethod: type == 'hdwallet'
          ? DerivationMethod.hdWallet
          : DerivationMethod.iguana,
    ),
    hash,
  ),
  isBip39Seed: true,
  metadata: {
    'type': type,
    'recovery_evidence': evidence,
    '_wallet_entry_id': entryId,
  },
);

class TransferAuth extends Cubit<AuthBlocState> implements AuthBloc {
  TransferAuth([AuthBlocState? initial])
    : super(initial ?? AuthBlocState.initial());

  final events = <AuthBlocEvent>[];

  @override
  void add(AuthBlocEvent event) => events.add(event);

  void push(AuthBlocState state) => emit(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Names in [taken] are in use; everything non-empty is valid.
class TransferWallets extends Fake implements WalletsRepository {
  final taken = <String>{};

  @override
  String? validateWalletName(String name) =>
      name.trim().isEmpty ? 'Enter a name' : null;

  @override
  Future<String?> validateWalletNameUniqueness(String name) async =>
      taken.contains(name.trim()) ? 'taken' : null;
}

class FakeMoveOffer implements WalletMoveOffer {
  FakeMoveOffer(this.code, this.expiresAt, this._open);

  @override
  final String code;
  @override
  final DateTime expiresAt;
  final WalletTransferSecret Function(String reply) _open;
  final opened = <String>[];
  bool disposed = false;

  @override
  WalletTransferSecret open(String replyCode) {
    opened.add(replyCode);
    if (disposed) throw const WalletMoveException(WalletMoveFailure.wrongStep);
    return _open(replyCode);
  }

  @override
  void dispose() => disposed = true;
}

class FakeMoveProtocol implements WalletMoveProtocol {
  FakeMoveProtocol({required this.now});

  final DateTime Function() now;
  final offers = <FakeMoveOffer>[];
  final sealed = <(String, WalletTransferSecret)>[];

  /// What an offer does with a scanned reply.
  WalletTransferSecret Function(String reply) openReply = (_) =>
      transferSecret();
  WalletMoveFailure? sealFailure;

  /// The check code for any reply. [checkFailure] refuses the reply at
  /// once, as a malformed one is; [checkGate] holds the code back, as the
  /// real derivation takes a moment; [checkError] fails it later.
  String check = '12345678';
  WalletMoveFailure? checkFailure;
  Completer<void>? checkGate;
  Object? checkError;
  final checked = <String>[];

  @override
  WalletMoveOffer createOffer() {
    final offer = FakeMoveOffer(
      'GLEECMOVE1O.offer-${offers.length}',
      now().add(const Duration(minutes: 10)),
      (reply) => openReply(reply),
    );
    offers.add(offer);
    return offer;
  }

  /// Offers validated before the old phone asks for the wallet's lock. A
  /// [sealFailure] refuses the offer here too, as the real protocol's
  /// parsing does.
  final offersChecked = <String>[];

  @override
  void checkOffer(String offerCode) {
    offersChecked.add(offerCode);
    if (sealFailure case final failure?) throw WalletMoveException(failure);
  }

  @override
  String seal({
    required String offerCode,
    required WalletTransferSecret secret,
  }) {
    if (sealFailure case final failure?) throw WalletMoveException(failure);
    sealed.add((offerCode, secret));
    return 'GLEECMOVE1R.reply-for-$offerCode';
  }

  @override
  Future<String> checkCode(String replyCode) {
    checked.add(replyCode);
    if (checkFailure case final failure?) throw WalletMoveException(failure);
    final gate = checkGate;
    final error = checkError;
    return Future(() async {
      await gate?.future;
      if (error != null) throw error;
      return check;
    });
  }
}

/// Records what the move screens ask of the device.
class FakeDeviceControls implements DeviceControls {
  final screenOn = <bool>[];
  int settingsOpened = 0;

  bool get isScreenKeptOn => screenOn.isNotEmpty && screenOn.last;

  @override
  Future<void> keepScreenOn(bool on) async => screenOn.add(on);

  @override
  Future<bool> openAppSettings() async {
    settingsOpened++;
    return true;
  }
}

/// Hands out scan results in order; an empty queue is a closed camera.
class FakeScanner {
  final results = <TransferScan>[];
  final instructions = <String>[];

  void add(String code) => results.add(TransferScanned(code));

  Future<TransferScan> call(BuildContext context, String instruction) async {
    instructions.add(instruction);
    return results.isEmpty ? const TransferScanCanceled() : results.removeAt(0);
  }
}

PasskeyBackupEntry backupEntry({
  String id = 'backup-1',
  BackupStoreKind store = BackupStoreKind.iCloudKeychain,
  bool synced = true,
  String? providerName = 'Apple Passwords',
  DateTime? checkedHere,
  PasskeyBackupEntryState state = PasskeyBackupEntryState.ready,
}) => PasskeyBackupEntry(
  id: id,
  walletKey: 'entry-1',
  store: store,
  created: DateTime.utc(2026, 11, 18, 12),
  synced: synced,
  providerName: providerName,
  checkedHere: checkedHere,
  state: state,
);

StoredBackup storedBackup(String id, {int day = 18, BackupStoreKind? store}) =>
    StoredBackup(
      id: id,
      store: store ?? BackupStoreKind.iCloudKeychain,
      created: DateTime.utc(2026, 11, day),
      raw: 'sealed-$id',
    );

class FakeBackupController implements PasskeyBackupController {
  PasskeyBackupAvailability available = const PasskeyBackupAvailability(
    canCreate: true,
    canRestore: true,
    stores: [BackupStoreKind.iCloudKeychain, BackupStoreKind.file],
  );
  List<PasskeyBackupEntry> entries = [];
  Map<BackupStoreKind, List<StoredBackup>> found = {};
  WalletTransferSecret unlocked = transferSecret();

  Object? createError;
  Object? checkError;
  Object? unlockError;
  Object? findError;
  Object? parseError;
  Object? availabilityError;
  Completer<void>? createGate;
  Completer<void>? findGate;

  final created = <(String, WalletTransferSecret, BackupStoreKind)>[];
  final checked = <String>[];
  final removed = <String>[];
  final markedSaved = <String>[];
  final unlockedIds = <String>[];
  int cancels = 0;

  @override
  Future<PasskeyBackupAvailability> availability() async {
    if (availabilityError case final error?) throw error;
    return available;
  }

  @override
  Future<List<PasskeyBackupEntry>> backupsFor(String walletKey) async =>
      entries.where((entry) => entry.walletKey == walletKey).toList();

  @override
  Future<PasskeyBackupEntry> create({
    required String walletKey,
    required WalletTransferSecret secret,
    required BackupStoreKind store,
  }) async {
    created.add((walletKey, secret, store));
    await createGate?.future;
    if (createError case final error?) throw error;
    final entry = backupEntry(
      id: 'made-${created.length}',
      store: store,
      state: store == BackupStoreKind.file
          ? PasskeyBackupEntryState.fileNotSaved
          : PasskeyBackupEntryState.ready,
    );
    entries = [...entries, entry];
    return entry;
  }

  @override
  Future<DateTime> check(PasskeyBackupEntry entry) async {
    checked.add(entry.id);
    if (checkError case final error?) throw error;
    final at = DateTime.utc(2026, 11, 19);
    entries = [
      for (final item in entries)
        item.id == entry.id
            ? backupEntry(id: item.id, store: item.store, checkedHere: at)
            : item,
    ];
    return at;
  }

  @override
  Future<void> markFileSaved(PasskeyBackupEntry entry) async {
    markedSaved.add(entry.id);
    entries = [
      for (final item in entries)
        item.id == entry.id
            ? backupEntry(id: item.id, store: item.store)
            : item,
    ];
  }

  @override
  Future<void> remove(PasskeyBackupEntry entry) async {
    removed.add(entry.id);
    entries = entries.where((item) => item.id != entry.id).toList();
  }

  @override
  Future<String> exportFile(PasskeyBackupEntry entry) async =>
      'sealed-${entry.id}';

  @override
  Future<List<StoredBackup>> find(BackupStoreKind store) async {
    await findGate?.future;
    if (findError case final error?) throw error;
    return found[store] ?? const [];
  }

  @override
  StoredBackup parseFile(String raw) {
    if (parseError case final error?) throw error;
    return storedBackup('from-file', store: BackupStoreKind.file);
  }

  @override
  Future<WalletTransferSecret> unlock(StoredBackup backup) async {
    unlockedIds.add(backup.id);
    if (unlockError case final error?) throw error;
    return unlocked;
  }

  @override
  Future<void> cancel() async => cancels++;
}

class FakeFileSaver extends GuardedFileSaver {
  FakeFileSaver([this.outcome = FileSaveOutcome.completed]);

  FileSaveOutcome outcome;
  final saves = <(String, String)>[];

  @override
  Future<FileSaveOutcome> save({
    required String fileName,
    required String data,
    required Future<void> Function() beforeWrite,
    required void Function() beforeCommit,
    GuardedDestinationSelector? selectDestination,
  }) async {
    await beforeWrite();
    beforeCommit();
    saves.add((fileName, data));
    return outcome;
  }
}

class _English extends AssetLoader {
  const _English();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/en.json').readAsStringSync())
          as Map<String, dynamic>;
}

/// Pumps [child] the way a settings flow page shows it, with the transfer
/// services this feature reads. Returns the screenshot controller.
Future<ScreenshotSensitivityController> pumpTransferScreen(
  WidgetTester tester,
  Widget child, {
  required TransferAuth auth,
  WalletMoveProtocol? protocol,
  PasskeyBackupController? backups,
  WalletTransferConfig config = const WalletTransferConfig(
    moveEnabled: true,
    passkeyBackupEnabled: true,
    backupRpId: 'backup.example',
  ),
  DeviceControls? device,
  List<RepositoryProvider<Object?>> extra = const [],
  Size size = const Size(420, 1400),
  double textScale = 1,
}) async {
  // Progress indicators hold still under reduced motion, so screens that
  // wait on a prompt can settle.
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final sensitivity = ScreenshotSensitivityController();
  addTearDown(sensitivity.dispose);
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      startLocale: const Locale('en'),
      fallbackLocale: const Locale('en'),
      saveLocale: false,
      path: 'assets/translations',
      assetLoader: const _English(),
      child: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<WalletTransferConfig>.value(value: config),
          if (protocol != null)
            RepositoryProvider<WalletMoveProtocol>.value(value: protocol),
          if (backups != null)
            RepositoryProvider<PasskeyBackupController>.value(value: backups),
          RepositoryProvider<DeviceControls>.value(
            value: device ?? FakeDeviceControls(),
          ),
          ...extra,
        ],
        child: BlocProvider<AuthBloc>.value(
          value: auth,
          child: ScreenshotSensitivity(
            controller: sensitivity,
            child: Builder(
              builder: (context) => MaterialApp(
                theme: theme.global.dark,
                locale: context.locale,
                supportedLocales: context.supportedLocales,
                localizationsDelegates: context.localizationDelegates,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    disableAnimations: true,
                    textScaler: TextScaler.linear(textScale),
                  ),
                  child: child!,
                ),
                home: Scaffold(
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return sensitivity;
}

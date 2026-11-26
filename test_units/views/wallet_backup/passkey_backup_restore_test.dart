import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
// Reset translations after the shared harness loads the real English strings.
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/services/file_loader/file_loader.dart';
import 'package:web_dex/services/wallet_backup/passkey_backup_types.dart';
import 'package:web_dex/views/wallet_backup/passkey_backup_restore.dart';
import 'package:web_dex/views/wallet_backup/passkey_backup_text.dart';

import '../../support/legal_onboarding_harness.dart';
import '../wallet_move/transfer_fakes.dart';

class _Picker extends Fake implements FileLoader {
  String? rejection;
  final types = <LoadFileType?>[];

  @override
  Future<void> upload({
    required void Function(String name, String? content) onUpload,
    required void Function(String) onError,
    LoadFileType? fileType,
  }) async {
    types.add(fileType);
    final error = rejection;
    error == null ? onUpload('backup.json', '{}') : onError(error);
  }
}

typedef _Restore = ({
  FakeBackupController controller,
  TransferAuth auth,
  _Picker picker,
});

void main() {
  group('PasskeyBackupRestore', () {
    setUpAll(() async {
      // The analyzer does not recognize the test_units directory as test code.
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
    });
    tearDown(() => Localization.load(const Locale('en')));

    final notice = find.byKey(const Key('passkey-backup-restore-notice'));
    Finder place(BackupStoreKind store) =>
        find.byKey(ValueKey('passkey-backup-restore-${store.name}'));
    Finder backupRow(String id) =>
        find.byKey(ValueKey('passkey-backup-found-$id'));

    Future<_Restore> pumpRestore(WidgetTester tester) async {
      final controller = FakeBackupController()
        ..available = const PasskeyBackupAvailability(
          canCreate: true,
          canRestore: true,
          stores: [
            BackupStoreKind.iCloudKeychain,
            BackupStoreKind.googleDrive,
            BackupStoreKind.file,
          ],
        );
      final auth = TransferAuth();
      addTearDown(auth.close);
      final picker = _Picker();
      await LegalFormHarness().pump(
        tester,
        MultiRepositoryProvider(
          providers: [
            RepositoryProvider<PasskeyBackupController>.value(
              value: controller,
            ),
            RepositoryProvider<WalletsRepository>.value(
              value: TransferWallets(),
            ),
          ],
          child: BlocProvider<AuthBloc>.value(
            value: auth,
            child: PasskeyBackupRestore(onCancel: () {}, fileLoader: picker),
          ),
        ),
        size: const Size(420, 1400),
        contentWidth: 360,
        disableAnimations: true,
      );
      return (controller: controller, auth: auth, picker: picker);
    }

    Future<void> tapAndSettle(WidgetTester tester, Finder target) async {
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    testWidgets('offers the places this device can look', (tester) async {
      await pumpRestore(tester);
      for (final store in BackupStoreKind.values) {
        expect(place(store), findsOneWidget, reason: store.name);
      }
      expect(
        find.text('passkeyBackupRestoreFromDriveHint'.tr()),
        findsOneWidget,
      );
    });

    testWidgets('finds backups newest first, opens one, then reviews it', (
      tester,
    ) async {
      final restore = await pumpRestore(tester);
      restore.controller.found[BackupStoreKind.iCloudKeychain] = [
        storedBackup('older', day: 1),
        storedBackup('newer', day: 18),
      ];
      await tapAndSettle(tester, place(BackupStoreKind.iCloudKeychain));
      expect(find.text('passkeyBackupRestoreFoundHint'.tr()), findsOneWidget);
      expect(
        tester.getTopLeft(backupRow('newer')).dy,
        lessThan(tester.getTopLeft(backupRow('older')).dy),
      );
      // Nothing is unlocked until a backup is picked.
      expect(restore.controller.unlockedIds, isEmpty);

      await tapAndSettle(tester, backupRow('newer'));
      expect(restore.controller.unlockedIds, ['newer']);
      expect(find.text('walletTransferReviewTitle'.tr()), findsOneWidget);
      expect(find.text('walletTransferKeepPhrase'.tr()), findsOneWidget);
      await tapAndSettle(
        tester,
        find.byKey(const Key('transfer-review-import')),
      );
      final event = restore.auth.events.single as AuthManagedImportRequested;
      expect(event.source, ManagedImportSource.passkeyBackup);
      expect(event.walletName, 'Savings');
    });

    testWidgets('nothing found says where it looked and what else to try', (
      tester,
    ) async {
      await pumpRestore(tester);
      await tapAndSettle(tester, place(BackupStoreKind.googleDrive));
      expect(
        find.text(
          'passkeyBackupRestoreNoneFound'.tr(
            args: [passkeyBackupStoreName(BackupStoreKind.googleDrive)],
          ),
        ),
        findsOneWidget,
      );
      expect(place(BackupStoreKind.iCloudKeychain), findsOneWidget);
    });

    testWidgets('a place that cannot be reached is named', (tester) async {
      final restore = await pumpRestore(tester);
      const error = PasskeyBackupException(
        PasskeyBackupFailure.storeUnavailable,
      );
      restore.controller.findError = error;
      await tapAndSettle(tester, place(BackupStoreKind.googleDrive));
      expect(
        find.text(
          passkeyBackupFailureText(error, store: BackupStoreKind.googleDrive),
        ),
        findsOneWidget,
      );
    });

    for (final failure in [
      PasskeyBackupFailure.wrongPasskey,
      PasskeyBackupFailure.damaged,
      PasskeyBackupFailure.otherRelyingParty,
      PasskeyBackupFailure.newerVersion,
      PasskeyBackupFailure.canceled,
    ]) {
      testWidgets('a ${failure.name} unlock says what to do next', (
        tester,
      ) async {
        final restore = await pumpRestore(tester);
        restore.controller.found[BackupStoreKind.iCloudKeychain] = [
          storedBackup('only'),
        ];
        final error = PasskeyBackupException(failure);
        restore.controller.unlockError = error;
        await tapAndSettle(tester, place(BackupStoreKind.iCloudKeychain));
        await tapAndSettle(tester, backupRow('only'));
        expect(
          find.text(
            passkeyBackupFailureText(
              error,
              store: BackupStoreKind.iCloudKeychain,
            ),
          ),
          findsOneWidget,
        );
        // Still on the list, so another backup or another try is one tap.
        expect(backupRow('only'), findsOneWidget);
        expect(restore.auth.events, isEmpty);
      });
    }

    testWidgets('a search can be called off', (tester) async {
      final restore = await pumpRestore(tester);
      final gate = Completer<void>();
      restore.controller.findGate = gate;
      restore.controller.found[BackupStoreKind.iCloudKeychain] = [
        storedBackup('late'),
      ];
      await tapAndSettle(tester, place(BackupStoreKind.iCloudKeychain));
      expect(find.text('passkeyBackupRestoreSearching'.tr()), findsWidgets);
      await tapAndSettle(
        tester,
        find.byKey(const Key('passkey-backup-restore-wait-cancel')),
      );
      expect(place(BackupStoreKind.iCloudKeychain), findsOneWidget);
      // What the search finds afterwards goes nowhere.
      gate.complete();
      await tester.pumpAndSettle();
      expect(backupRow('late'), findsNothing);
    });

    testWidgets('places that could not be loaded offer a retry', (
      tester,
    ) async {
      final controller = FakeBackupController()
        ..availabilityError = const PasskeyBackupException(
          PasskeyBackupFailure.unavailable,
        );
      final auth = TransferAuth();
      addTearDown(auth.close);
      await LegalFormHarness().pump(
        tester,
        MultiRepositoryProvider(
          providers: [
            RepositoryProvider<PasskeyBackupController>.value(
              value: controller,
            ),
            RepositoryProvider<WalletsRepository>.value(
              value: TransferWallets(),
            ),
          ],
          child: BlocProvider<AuthBloc>.value(
            value: auth,
            child: PasskeyBackupRestore(onCancel: () {}),
          ),
        ),
        size: const Size(420, 1400),
        contentWidth: 360,
        disableAnimations: true,
      );
      expect(notice, findsOneWidget);
      expect(place(BackupStoreKind.file), findsNothing);
      controller.availabilityError = null;
      await tapAndSettle(
        tester,
        find.byKey(const Key('passkey-backup-restore-retry')),
      );
      expect(place(BackupStoreKind.iCloudKeychain), findsOneWidget);
      expect(
        find.byKey(const Key('passkey-backup-restore-retry')),
        findsNothing,
      );
    });

    testWidgets('a backup this password manager cannot open says what to '
        'try', (tester) async {
      final restore = await pumpRestore(tester);
      restore.controller.found[BackupStoreKind.iCloudKeychain] = [
        storedBackup('only'),
      ];
      restore.controller.unlockError = const PasskeyBackupException(
        PasskeyBackupFailure.prfUnavailable,
      );
      await tapAndSettle(tester, place(BackupStoreKind.iCloudKeychain));
      await tapAndSettle(tester, backupRow('only'));
      expect(
        find.text('passkeyBackupRestorePrfUnavailable'.tr()),
        findsOneWidget,
      );
    });

    testWidgets('opens a backup file of any extension', (tester) async {
      final restore = await pumpRestore(tester);
      await tapAndSettle(tester, place(BackupStoreKind.file));
      expect(restore.picker.types, [null]);
      await tapAndSettle(tester, backupRow('from-file'));
      expect(restore.controller.unlockedIds, ['from-file']);
      expect(find.text('walletTransferReviewTitle'.tr()), findsOneWidget);
    });

    testWidgets('a file that is not a backup is refused', (tester) async {
      final restore = await pumpRestore(tester);
      const error = PasskeyBackupException(PasskeyBackupFailure.damaged);
      restore.controller.parseError = error;
      await tapAndSettle(tester, place(BackupStoreKind.file));
      expect(find.text(passkeyBackupFailureText(error)), findsOneWidget);
      expect(backupRow('from-file'), findsNothing);
    });

    testWidgets('a file the picker cannot read is explained', (tester) async {
      final restore = await pumpRestore(tester);
      restore.picker.rejection = 'Unsupported file type';
      await tapAndSettle(tester, place(BackupStoreKind.file));
      expect(notice, findsOneWidget);
      expect(
        find.text('passkeyBackupRestoreFileRejected'.tr()),
        findsOneWidget,
      );
    });
  });
}

import 'package:easy_localization/easy_localization.dart';
// Reset translations after the harness loads the real English strings.
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/services/file_loader/guarded_file_saver.dart';
import 'package:web_dex/services/wallet_backup/passkey_backup_types.dart';
import 'package:web_dex/views/wallet_backup/passkey_backup_section.dart';
import 'package:web_dex/views/wallet_backup/passkey_backup_setup.dart';
import 'package:web_dex/views/wallet_backup/passkey_backup_text.dart';

import '../wallet_move/transfer_fakes.dart';

void main() {
  group('PasskeyBackupSection', () {
    setUpAll(() async {
      // The analyzer does not recognize the test_units directory as test code.
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
    });
    tearDown(() => Localization.load(const Locale('en')));

    final section = find.byKey(const Key('passkey-backup-section'));

    Future<(FakeBackupController, FakeFileSaver)> pumpSection(
      WidgetTester tester, {
      List<PasskeyBackupEntry> entries = const [],
      String walletType = 'hdwallet',
      bool provideController = true,
    }) async {
      final controller = FakeBackupController()..entries = [...entries];
      final saver = FakeFileSaver();
      final auth = TransferAuth(
        AuthBlocState.loggedIn(transferUser(type: walletType)),
      );
      addTearDown(auth.close);
      await pumpTransferScreen(
        tester,
        PasskeyBackupSection(fileSaver: saver),
        auth: auth,
        backups: provideController ? controller : null,
      );
      return (controller, saver);
    }

    Future<void> tapAndSettle(WidgetTester tester, Finder target) async {
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    testWidgets('stays hidden where it cannot work', (tester) async {
      await pumpSection(tester, provideController: false);
      expect(section, findsNothing);
    });

    testWidgets('stays hidden when this device cannot make backups', (
      tester,
    ) async {
      final controller = FakeBackupController()
        ..available = PasskeyBackupAvailability.none;
      final auth = TransferAuth(AuthBlocState.loggedIn(transferUser()));
      addTearDown(auth.close);
      await pumpTransferScreen(
        tester,
        const PasskeyBackupSection(),
        auth: auth,
        backups: controller,
      );
      expect(section, findsNothing);
    });

    testWidgets('stays hidden for a wallet without a seed of its own', (
      tester,
    ) async {
      await pumpSection(tester, walletType: 'trezor');
      expect(section, findsNothing);
    });

    testWidgets('says it is off and offers set-up', (tester) async {
      await pumpSection(tester);
      expect(section, findsOneWidget);
      expect(find.text('passkeyBackupStatusOff'.tr()), findsOneWidget);
      expect(find.text('passkeyBackupSetUp'.tr()), findsOneWidget);
    });

    testWidgets('lists each backup: where, what holds it, sync and checks', (
      tester,
    ) async {
      await pumpSection(
        tester,
        entries: [
          backupEntry(),
          backupEntry(
            id: 'backup-2',
            store: BackupStoreKind.googleDrive,
            synced: false,
            providerName: null,
          ),
        ],
      );
      expect(find.text('passkeyBackupStatusOff'.tr()), findsNothing);
      expect(find.text('passkeyBackupAddAnother'.tr()), findsOneWidget);
      expect(
        find.text(passkeyBackupStoreName(BackupStoreKind.iCloudKeychain)),
        findsOneWidget,
      );
      expect(
        find.text(passkeyBackupStoreName(BackupStoreKind.googleDrive)),
        findsOneWidget,
      );
      expect(
        find.text('passkeyBackupEntryProvider'.tr(args: ['Apple Passwords'])),
        findsOneWidget,
      );
      expect(
        find.text('passkeyBackupEntryProviderUnknown'.tr()),
        findsOneWidget,
      );
      expect(find.text('passkeyBackupEntrySynced'.tr()), findsOneWidget);
      expect(find.text('passkeyBackupEntryNotSynced'.tr()), findsOneWidget);
      expect(find.text('passkeyBackupEntryNotChecked'.tr()), findsNWidgets(2));
      expect(find.byKey(const Key('passkey-backup-check')), findsNWidgets(2));
    });

    testWidgets('checking proves the backup opens on this device', (
      tester,
    ) async {
      final (controller, _) = await pumpSection(
        tester,
        entries: [backupEntry()],
      );
      await tapAndSettle(tester, find.byKey(const Key('passkey-backup-check')));
      expect(controller.checked, ['backup-1']);
      expect(find.text('passkeyBackupCheckOk'.tr()), findsOneWidget);
      expect(
        find.text(
          'passkeyBackupEntryChecked'.tr(
            args: [passkeyBackupDate(DateTime.utc(2026, 11, 19))],
          ),
        ),
        findsOneWidget,
      );
    });

    for (final failure in [
      PasskeyBackupFailure.wrongPasskey,
      PasskeyBackupFailure.canceled,
      PasskeyBackupFailure.storeUnavailable,
    ]) {
      testWidgets('a failed check (${failure.name}) says why', (tester) async {
        final (controller, _) = await pumpSection(
          tester,
          entries: [backupEntry()],
        );
        final error = PasskeyBackupException(failure);
        controller.checkError = error;
        await tapAndSettle(
          tester,
          find.byKey(const Key('passkey-backup-check')),
        );
        expect(
          find.text(
            passkeyBackupFailureText(
              error,
              store: BackupStoreKind.iCloudKeychain,
            ),
          ),
          findsOneWidget,
        );
      });
    }

    testWidgets('removing asks first, honestly, and can be called off', (
      tester,
    ) async {
      final (controller, _) = await pumpSection(
        tester,
        entries: [backupEntry()],
      );
      final remove = find.byKey(const Key('passkey-backup-remove'));
      await tapAndSettle(tester, remove);
      expect(find.text('passkeyBackupRemoveBody'.tr()), findsOneWidget);
      await tapAndSettle(
        tester,
        find.byKey(const Key('passkey-backup-remove-cancel')),
      );
      expect(controller.removed, isEmpty);

      await tapAndSettle(tester, remove);
      await tapAndSettle(
        tester,
        find.byKey(const Key('passkey-backup-remove-confirm')),
      );
      expect(controller.removed, ['backup-1']);
      expect(find.text('passkeyBackupRemoved'.tr()), findsOneWidget);
      expect(find.text('passkeyBackupStatusOff'.tr()), findsOneWidget);
    });

    testWidgets('a copy is saved through the guarded file save', (
      tester,
    ) async {
      final (_, saver) = await pumpSection(tester, entries: [backupEntry()]);
      final save = find.byKey(const Key('passkey-backup-save-file'));
      await tapAndSettle(tester, save);
      expect(saver.saves, [
        ('gleec-passkey-backup-backup-1.json', 'sealed-backup-1'),
      ]);
      expect(find.text('passkeyBackupFileSaved'.tr()), findsOneWidget);

      saver.outcome = FileSaveOutcome.cancelled;
      await tapAndSettle(tester, save);
      expect(find.text('passkeyBackupFileCanceled'.tr()), findsOneWidget);
    });

    testWidgets('an unsaved file backup leads with saving it', (tester) async {
      final (controller, saver) = await pumpSection(
        tester,
        entries: [
          backupEntry(
            store: BackupStoreKind.file,
            state: PasskeyBackupEntryState.fileNotSaved,
            checkedHere: DateTime.utc(2026, 11, 19),
          ),
        ],
      );
      expect(find.text('passkeyBackupEntryFileNotSaved'.tr()), findsOneWidget);
      // Never presented as checked or ready while it exists only here.
      expect(
        find.byKey(const Key('passkey-backup-entry-checked')),
        findsNothing,
      );
      expect(find.byKey(const Key('passkey-backup-check')), findsNothing);
      final save = find.byKey(const Key('passkey-backup-save-file'));
      expect(tester.widget(save), isA<UiPrimaryButton>());

      await tapAndSettle(tester, save);
      expect(saver.saves, hasLength(1));
      expect(controller.markedSaved, ['backup-1']);
      expect(find.text('passkeyBackupEntryFileNotSaved'.tr()), findsNothing);
      expect(find.text('passkeyBackupFileSaved'.tr()), findsOneWidget);
    });

    testWidgets('a cancelled save leaves the file backup unsaved', (
      tester,
    ) async {
      final (controller, saver) = await pumpSection(
        tester,
        entries: [
          backupEntry(
            store: BackupStoreKind.file,
            state: PasskeyBackupEntryState.fileNotSaved,
          ),
        ],
      );
      saver.outcome = FileSaveOutcome.cancelled;
      await tapAndSettle(
        tester,
        find.byKey(const Key('passkey-backup-save-file')),
      );
      expect(controller.markedSaved, isEmpty);
      expect(find.text('passkeyBackupEntryFileNotSaved'.tr()), findsOneWidget);
    });

    testWidgets('an unfinished backup offers a check to finish it', (
      tester,
    ) async {
      final (controller, _) = await pumpSection(
        tester,
        entries: [backupEntry(state: PasskeyBackupEntryState.unfinished)],
      );
      expect(find.text('passkeyBackupEntryUnfinished'.tr()), findsOneWidget);
      expect(
        find.byKey(const Key('passkey-backup-entry-checked')),
        findsNothing,
      );
      // An unproven record is not handed out as a file.
      expect(find.byKey(const Key('passkey-backup-save-file')), findsNothing);
      expect(find.byKey(const Key('passkey-backup-remove')), findsOneWidget);

      await tapAndSettle(tester, find.byKey(const Key('passkey-backup-check')));
      expect(controller.checked, ['backup-1']);
      expect(find.text('passkeyBackupEntryUnfinished'.tr()), findsNothing);
      expect(
        find.byKey(const Key('passkey-backup-entry-checked')),
        findsOneWidget,
      );
    });

    testWidgets('each action is read out with the backup it acts on', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpSection(tester, entries: [backupEntry()]);
      final made = passkeyBackupDate(DateTime.utc(2026, 11, 18, 12));
      for (final key in [
        'passkeyBackupCheckNamed',
        'passkeyBackupSaveFileNamed',
        'passkeyBackupRemoveNamed',
      ]) {
        expect(
          find.bySemanticsLabel(key.tr(args: [made])),
          findsOneWidget,
          reason: key,
        );
      }
      semantics.dispose();
    });

    testWidgets('removing a file backup says a saved file still opens', (
      tester,
    ) async {
      await pumpSection(
        tester,
        entries: [backupEntry(store: BackupStoreKind.file)],
      );
      await tapAndSettle(
        tester,
        find.byKey(const Key('passkey-backup-remove')),
      );
      expect(
        find.byKey(const Key('passkey-backup-remove-file-note')),
        findsOneWidget,
      );
    });

    testWidgets('a synced backup needs no note about files', (tester) async {
      await pumpSection(tester, entries: [backupEntry()]);
      await tapAndSettle(
        tester,
        find.byKey(const Key('passkey-backup-remove')),
      );
      expect(find.text('passkeyBackupRemoveBody'.tr()), findsOneWidget);
      expect(
        find.byKey(const Key('passkey-backup-remove-file-note')),
        findsNothing,
      );
    });

    testWidgets('set-up opens the setup flow', (tester) async {
      await pumpSection(tester);
      await tapAndSettle(
        tester,
        find.byKey(const Key('passkey-backup-set-up')),
      );
      expect(find.byType(PasskeyBackupSetup), findsOneWidget);
    });
  });
}

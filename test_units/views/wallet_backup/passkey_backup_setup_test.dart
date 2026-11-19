import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
// Reset translations after the harness loads the real English strings.
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/services/file_loader/guarded_file_saver.dart';
import 'package:web_dex/services/wallet_backup/passkey_backup_types.dart';
import 'package:web_dex/views/wallet_backup/passkey_backup_setup.dart';
import 'package:web_dex/views/wallet_backup/passkey_backup_text.dart';
import 'package:web_dex/views/wallet_move/read_wallet_transfer_secret.dart';
import 'package:web_dex/views/wallet_move/transfer_widgets.dart';

import '../wallet_move/transfer_fakes.dart';

typedef _Setup = ({
  FakeBackupController controller,
  FakeFileSaver saver,
  List<int> closes,
});

void main() {
  group('PasskeyBackupSetup', () {
    setUpAll(() async {
      // The analyzer does not recognize the test_units directory as test code.
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
    });
    tearDown(() => Localization.load(const Locale('en')));

    const allStores = [
      BackupStoreKind.iCloudKeychain,
      BackupStoreKind.googleDrive,
      BackupStoreKind.file,
    ];
    final explainContinue = find.byKey(
      const Key('passkey-backup-explain-continue'),
    );
    final storeContinue = find.byKey(
      const Key('passkey-backup-store-continue'),
    );
    final create = find.byKey(const Key('passkey-backup-create'));
    final setupNotice = find.byKey(const Key('passkey-backup-setup-notice'));

    Future<_Setup> pumpSetup(
      WidgetTester tester, {
      List<BackupStoreKind> stores = allStores,
      WalletSecretRead? read,
    }) async {
      final controller = FakeBackupController();
      final saver = FakeFileSaver();
      final closes = <int>[];
      final auth = TransferAuth(AuthBlocState.loggedIn(transferUser()));
      addTearDown(auth.close);
      await pumpTransferScreen(
        tester,
        PasskeyBackupSetup(
          controller: controller,
          stores: stores,
          walletKey: 'entry-1',
          fileSaver: saver,
          onClose: () => closes.add(1),
          readSecret: (_) async => read ?? WalletSecretReady(transferSecret()),
        ),
        auth: auth,
        backups: controller,
      );
      return (controller: controller, saver: saver, closes: closes);
    }

    Future<void> tapAndSettle(WidgetTester tester, Finder target) async {
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    BackupStoreKind? chosenStore(WidgetTester tester) => tester
        .widget<RadioGroup<BackupStoreKind>>(
          find.byType(RadioGroup<BackupStoreKind>),
        )
        .groupValue;

    for (final ios in [true, false]) {
      testWidgets(
        'explains what it does, where it works and who can restore it',
        (tester) async {
          await pumpSetup(tester);
          for (final key in [
            'passkeyBackupSetupWhat',
            'passkeyBackupSetupWhere',
            'passkeyBackupSetupWhoYou',
            'passkeyBackupSetupWhoShared',
            'passkeyBackupSetupWhoAccount',
            'passkeyBackupSetupKeepPhrase',
          ]) {
            expect(find.text(key.tr()), findsOneWidget, reason: key);
          }
          expect(
            find.byKey(const Key('passkey-backup-stolen-device-tip')),
            ios ? findsOneWidget : findsNothing,
          );
        },
        variant: TargetPlatformVariant.only(
          ios ? TargetPlatform.iOS : TargetPlatform.android,
        ),
      );
    }

    testWidgets('the Stolen Device tip is for iPhone, not iPad', (
      tester,
    ) async {
      final controller = FakeBackupController();
      final auth = TransferAuth(AuthBlocState.loggedIn(transferUser()));
      addTearDown(auth.close);
      await pumpTransferScreen(
        tester,
        PasskeyBackupSetup(
          controller: controller,
          stores: allStores,
          walletKey: 'entry-1',
          onClose: () {},
        ),
        auth: auth,
        backups: controller,
        size: const Size(1024, 1366),
      );
      expect(
        find.byKey(const Key('passkey-backup-stolen-device-tip')),
        findsNothing,
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    for (final (store, keys) in [
      (
        BackupStoreKind.googleDrive,
        [
          'passkeyBackupPromptAuthorize',
          'passkeyBackupPromptDrive',
          'passkeyBackupPromptCreate',
          'passkeyBackupPromptConfirm',
          'passkeyBackupPromptSavedDrive',
        ],
      ),
      (
        BackupStoreKind.iCloudKeychain,
        [
          'passkeyBackupPromptAuthorize',
          'passkeyBackupPromptCreate',
          'passkeyBackupPromptConfirm',
          'passkeyBackupPromptSavedICloud',
        ],
      ),
      (
        BackupStoreKind.file,
        [
          'passkeyBackupPromptAuthorize',
          'passkeyBackupPromptCreate',
          'passkeyBackupPromptConfirm',
          'passkeyBackupPromptSaveFile',
        ],
      ),
    ]) {
      testWidgets('${store.name} prompts are listed in the order they open', (
        tester,
      ) async {
        await pumpSetup(tester, stores: [store]);
        await tapAndSettle(tester, explainContinue);
        final tops = [
          for (final key in keys) tester.getTopLeft(find.text(key.tr())).dy,
        ];
        expect(tops, orderedEquals([...tops]..sort()));
        expect(find.byType(TransferStep), findsNWidgets(keys.length));
      });
    }

    testWidgets('iCloud Keychain is the default where it is offered', (
      tester,
    ) async {
      await pumpSetup(tester);
      await tapAndSettle(tester, explainContinue);
      expect(chosenStore(tester), BackupStoreKind.iCloudKeychain);
      expect(find.text('passkeyBackupStoreICloudHint'.tr()), findsOneWidget);
    });

    testWidgets('Google Drive is the default without iCloud Keychain', (
      tester,
    ) async {
      await pumpSetup(
        tester,
        stores: const [BackupStoreKind.googleDrive, BackupStoreKind.file],
      );
      await tapAndSettle(tester, explainContinue);
      expect(chosenStore(tester), BackupStoreKind.googleDrive);
      // Drive announces its own sign-in before the prompts start.
      await tapAndSettle(tester, storeContinue);
      expect(find.text('passkeyBackupPromptDrive'.tr()), findsOneWidget);
    });

    testWidgets('one place needs no choice', (tester) async {
      await pumpSetup(tester, stores: const [BackupStoreKind.file]);
      await tapAndSettle(tester, explainContinue);
      expect(find.byType(RadioGroup<BackupStoreKind>), findsNothing);
      expect(find.text('passkeyBackupPromptsTitle'.tr()), findsOneWidget);
    });

    testWidgets('names each prompt before the first, then creates it', (
      tester,
    ) async {
      final setup = await pumpSetup(tester);
      await tapAndSettle(tester, explainContinue);
      await tapAndSettle(
        tester,
        find.byKey(const ValueKey('passkey-backup-store-googleDrive')),
      );
      await tapAndSettle(tester, storeContinue);
      for (final key in [
        'passkeyBackupPromptAuthorize',
        'passkeyBackupPromptCreate',
        'passkeyBackupPromptConfirm',
      ]) {
        expect(find.text(key.tr()), findsOneWidget, reason: key);
      }
      expect(setup.controller.created, isEmpty);

      await tapAndSettle(tester, create);
      final (walletKey, secret, store) = setup.controller.created.single;
      expect(walletKey, 'entry-1');
      expect(secret.seed, transferTestSeed);
      expect(store, BackupStoreKind.googleDrive);
      expect(find.text('passkeyBackupDoneTitle'.tr()), findsOneWidget);
      expect(find.text('passkeyBackupDoneDrive'.tr()), findsOneWidget);
      expect(find.text('passkeyBackupDoneNext'.tr()), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const Key('passkey-backup-done')));
      expect(setup.closes, [1]);
    });

    for (final failure in PasskeyBackupFailure.values) {
      testWidgets('a ${failure.name} failure has its own message', (
        tester,
      ) async {
        final setup = await pumpSetup(tester);
        final error = PasskeyBackupException(failure);
        setup.controller.createError = error;
        await tapAndSettle(tester, explainContinue);
        await tapAndSettle(tester, storeContinue);
        await tapAndSettle(tester, create);
        expect(
          find.text(
            passkeyBackupFailureText(
              error,
              store: BackupStoreKind.iCloudKeychain,
            ),
          ),
          findsOneWidget,
        );
        expect(find.text('passkeyBackupDoneTitle'.tr()), findsNothing);
        // The way forward is the same button, now offering a retry.
        expect(
          find.descendant(of: create, matching: find.text('tryAgain'.tr())),
          findsOneWidget,
        );
      });
    }

    testWidgets('an interrupted authorization creates nothing', (tester) async {
      final setup = await pumpSetup(
        tester,
        read: const WalletSecretNotRead(WalletSecretUnread.interrupted),
      );
      await tapAndSettle(tester, explainContinue);
      await tapAndSettle(tester, storeContinue);
      await tapAndSettle(tester, create);
      expect(setup.controller.created, isEmpty);
      expect(find.text('passkeyBackupFailureInterrupted'.tr()), findsOneWidget);
    });

    testWidgets('a closed authorization creates nothing and says nothing', (
      tester,
    ) async {
      final setup = await pumpSetup(
        tester,
        read: const WalletSecretNotRead(WalletSecretUnread.canceled),
      );
      await tapAndSettle(tester, explainContinue);
      await tapAndSettle(tester, storeContinue);
      await tapAndSettle(tester, create);
      expect(setup.controller.created, isEmpty);
      expect(setupNotice, findsNothing);
    });

    testWidgets('a file backup opens the save dialog straight away', (
      tester,
    ) async {
      final setup = await pumpSetup(
        tester,
        stores: const [BackupStoreKind.file],
      );
      await tapAndSettle(tester, explainContinue);
      await tapAndSettle(tester, create);
      // No second tap: until it is saved, it exists only in this app.
      expect(setup.saver.saves, [
        ('gleec-passkey-backup-made-1.json', 'sealed-made-1'),
      ]);
      expect(setup.controller.markedSaved, ['made-1']);
      expect(find.text('passkeyBackupDoneFile'.tr()), findsOneWidget);
      expect(find.text('passkeyBackupFileSaved'.tr()), findsOneWidget);
      expect(find.byKey(const Key('passkey-backup-done')), findsOneWidget);
    });

    testWidgets('a file backup whose save was cancelled can be saved later', (
      tester,
    ) async {
      final setup = await pumpSetup(
        tester,
        stores: const [BackupStoreKind.file],
      );
      setup.saver.outcome = FileSaveOutcome.cancelled;
      await tapAndSettle(tester, explainContinue);
      await tapAndSettle(tester, create);
      expect(setup.saver.saves, hasLength(1));
      expect(setup.controller.markedSaved, isEmpty);
      expect(find.text('passkeyBackupFileCanceled'.tr()), findsOneWidget);
      expect(find.byKey(const Key('passkey-backup-done')), findsNothing);

      setup.saver.outcome = FileSaveOutcome.completed;
      await tapAndSettle(
        tester,
        find.byKey(const Key('passkey-backup-done-save-file')),
      );
      expect(setup.controller.markedSaved, ['made-1']);
      expect(find.byKey(const Key('passkey-backup-done')), findsOneWidget);
    });

    testWidgets('a synced store needs no file', (tester) async {
      final setup = await pumpSetup(tester);
      await tapAndSettle(tester, explainContinue);
      await tapAndSettle(tester, storeContinue);
      await tapAndSettle(tester, create);
      expect(setup.saver.saves, isEmpty);
      expect(setup.controller.markedSaved, isEmpty);
    });

    testWidgets('every step fits a phone at twice the text size', (
      tester,
    ) async {
      final controller = FakeBackupController();
      final auth = TransferAuth(AuthBlocState.loggedIn(transferUser()));
      addTearDown(auth.close);
      await pumpTransferScreen(
        tester,
        PasskeyBackupSetup(
          controller: controller,
          stores: allStores,
          walletKey: 'entry-1',
          onClose: () {},
          readSecret: (_) async => WalletSecretReady(transferSecret()),
        ),
        auth: auth,
        backups: controller,
        size: const Size(360, 3200),
        textScale: 2,
      );
      for (final step in [explainContinue, storeContinue, create]) {
        expect(tester.takeException(), isNull);
        await tapAndSettle(tester, step);
      }
      expect(find.text('passkeyBackupDoneTitle'.tr()), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cancel while the prompts are open stops them', (tester) async {
      final setup = await pumpSetup(tester);
      final gate = Completer<void>();
      setup.controller.createGate = gate;
      await tapAndSettle(tester, explainContinue);
      await tapAndSettle(tester, storeContinue);
      await tapAndSettle(tester, create);
      expect(find.text('passkeyBackupWorking'.tr()), findsOneWidget);
      await tapAndSettle(
        tester,
        find.byKey(const Key('passkey-backup-working-cancel')),
      );
      expect(setup.controller.cancels, 1);
      setup.controller.createError = const PasskeyBackupException(
        PasskeyBackupFailure.canceled,
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('passkeyBackupFailureCanceled'.tr()), findsOneWidget);
    });
  });
}

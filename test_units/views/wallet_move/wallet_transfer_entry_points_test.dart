import 'package:easy_localization/easy_localization.dart';
// Reset translations after the shared harness loads the real English strings.
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/services/wallet_backup/passkey_backup_types.dart';
import 'package:web_dex/services/wallet_move/wallet_move_types.dart';
import 'package:web_dex/services/wallet_transfer/wallet_transfer_config.dart';
import 'package:web_dex/views/wallet_backup/passkey_backup_restore.dart';
import 'package:web_dex/views/wallet_move/wallet_move_receive.dart';
import 'package:web_dex/views/wallet_move/wallet_move_send.dart';
import 'package:web_dex/views/wallet_move/wallet_transfer_settings.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_import_wrapper.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_simple_import.dart';

import '../../support/legal_onboarding_harness.dart';
import 'transfer_fakes.dart';

void main() {
  group('Wallet transfer entry points', () {
    setUpAll(() async {
      // The analyzer does not recognize the test_units directory as test code.
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
    });
    tearDown(() => Localization.load(const Locale('en')));

    final moveOption = find.byKey(const Key('wallet-move-import-option'));
    final restoreOption = find.byKey(const Key('passkey-backup-import-option'));
    const on = WalletTransferConfig(
      moveEnabled: true,
      passkeyBackupEnabled: true,
      backupRpId: 'backup.example',
    );

    Future<void> pumpImport(
      WidgetTester tester, {
      WalletTransferConfig config = on,
      bool canRestore = true,
    }) async {
      final controller = FakeBackupController()
        ..available = PasskeyBackupAvailability(
          canCreate: canRestore,
          canRestore: canRestore,
          stores: const [BackupStoreKind.file],
        );
      await LegalFormHarness().pump(
        tester,
        MultiRepositoryProvider(
          providers: [
            RepositoryProvider<WalletTransferConfig>.value(value: config),
            RepositoryProvider<WalletMoveProtocol>.value(
              value: FakeMoveProtocol(now: DateTime.now),
            ),
            RepositoryProvider<PasskeyBackupController>.value(
              value: controller,
            ),
          ],
          child: WalletImportWrapper(
            onImport: ({
              required name,
              required password,
              required walletConfig,
            }) {},
            onCancel: () {},
          ),
        ),
        size: const Size(420, 1800),
        contentWidth: 360,
        disableAnimations: true,
      );
    }

    Future<void> tapAndSettle(WidgetTester tester, Finder target) async {
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    testWidgets('the import screen offers both, and each returns to it', (
      tester,
    ) async {
      await pumpImport(tester);
      expect(moveOption, findsOneWidget);
      expect(restoreOption, findsOneWidget);

      await tapAndSettle(tester, moveOption);
      expect(find.byType(WalletMoveReceive), findsOneWidget);
      await tapAndSettle(
        tester,
        find.byKey(const Key('wallet-move-receive-cancel')),
      );
      expect(find.byType(WalletSimpleImport), findsOneWidget);

      await tapAndSettle(tester, restoreOption);
      expect(find.byType(PasskeyBackupRestore), findsOneWidget);
      await tapAndSettle(
        tester,
        find.byKey(const Key('passkey-backup-restore-cancel')),
      );
      expect(find.byType(WalletSimpleImport), findsOneWidget);
    });

    testWidgets('neither is offered while switched off', (tester) async {
      await pumpImport(
        tester,
        config: const WalletTransferConfig(),
        canRestore: false,
      );
      expect(moveOption, findsNothing);
      expect(restoreOption, findsNothing);
    });

    testWidgets('moving is not offered without a phone camera', (tester) async {
      await pumpImport(tester);
      expect(moveOption, findsNothing);
      expect(restoreOption, findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    Future<void> pumpSettings(WidgetTester tester, String walletType) async {
      final auth = TransferAuth(
        AuthBlocState.loggedIn(transferUser(type: walletType)),
      );
      addTearDown(auth.close);
      await pumpTransferScreen(
        tester,
        const WalletTransferSettings(),
        auth: auth,
        protocol: FakeMoveProtocol(now: DateTime.now),
        backups: FakeBackupController(),
      );
    }

    testWidgets('Security settings offers both for a wallet with a seed', (
      tester,
    ) async {
      await pumpSettings(tester, 'iguana');
      expect(
        find.byKey(const Key('wallet-move-settings-section')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('passkey-backup-section')), findsOneWidget);
      await tapAndSettle(
        tester,
        find.byKey(const Key('wallet-move-settings-start')),
      );
      expect(find.byType(WalletMoveSend), findsOneWidget);
    });

    testWidgets('Security settings offers neither for a hardware wallet', (
      tester,
    ) async {
      await pumpSettings(tester, 'trezor');
      expect(
        find.byKey(const Key('wallet-move-settings-section')),
        findsNothing,
      );
      expect(find.byKey(const Key('passkey-backup-section')), findsNothing);
    });
  });
}

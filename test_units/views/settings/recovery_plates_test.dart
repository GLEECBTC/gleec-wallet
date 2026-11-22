// The analyzer does not treat test_units as tests, so @visibleForTesting
// members read as violations here.
// ignore_for_file: invalid_use_of_visible_for_testing_member
// ignore_for_file: invalid_use_of_protected_member

import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_event.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/views/settings/widgets/security_settings/plate_seed_backup.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_action_plate.dart';

import '../../support/legal_onboarding_harness.dart';
import '../../support/wallet_access_ui_fixture.dart';

/// A wallet whose password the user chose, unlike the fixture's default.
class _ChosenPasswordAccess extends AccessibilityAccess {
  @override
  Future<WalletAccessStatus> status({WalletId? walletId}) async =>
      const WalletAccessStatus(
        entryId: 'accessibility-entry',
        protection: CredentialProtection.password,
        hasManagedCredential: false,
        requiresAuthentication: true,
      );
}

/// A generated password the user can look up: their password manager took it.
class _SavedGeneratedPasswordAccess extends AccessibilityAccess {
  @override
  Future<WalletAccessStatus> status({WalletId? walletId}) async =>
      const WalletAccessStatus(
        entryId: 'accessibility-entry',
        protection: CredentialProtection.passkey,
        hasManagedCredential: true,
        requiresAuthentication: true,
        generatedPassword: true,
        passwordManager: PasswordManagerOutcome.accepted,
      );
}

Future<AccessibilitySecurity> _pumpPlates(
  WidgetTester tester, {
  Map<String, Object?> metadata = const {},
  AccessibilityAccess? access,
  double textScale = 1,
  Brightness brightness = Brightness.dark,
}) async {
  final harness = LegalFormHarness();
  final security = AccessibilitySecurity();
  addTearDown(security.close);
  if (access != null) addTearDown(access.unlockCoordinator.dispose);
  harness.auth.emit(
    AuthBlocState.loggedIn(
      KdfUser(
        walletId: accessibilityUser().walletId,
        isBip39Seed: true,
        metadata: {'type': 'hdwallet', ...metadata},
      ),
    ),
  );
  final plates = BlocProvider<SecuritySettingsBloc>.value(
    value: security,
    child: PlateSeedBackup(onViewSeedPressed: (_) {}),
  );
  await harness.pump(
    tester,
    access == null
        ? plates
        : RepositoryProvider<WalletAccessService>.value(
            value: access,
            child: plates,
          ),
    size: const Size(1280, 900),
    textScale: textScale,
    brightness: brightness,
    disableAnimations: true,
  );
  return security;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  tearDown(() => Localization.load(const Locale('en')));

  group('Recovery phrase and wallet file plates', () {
    for (final (metadata, status, action, warned) in [
      (
        {'recovery_evidence': 'phraseConfirmed'},
        'authRecoveryReady',
        'viewSeedPhrase',
        false,
      ),
      (
        {'recovery_evidence': 'phraseSupplied'},
        'authRecoveryImported',
        'viewSeedPhrase',
        false,
      ),
      // Confirmed in a version that kept no evidence of it.
      (
        {'has_backup': true},
        'authRecoveryLegacyUnconfirmed',
        'authConfirmRecoveryPhrase',
        true,
      ),
      (
        {'recovery_evidence': 'encryptedFileExported'},
        'authRecoveryFileOnly',
        'authConfirmRecoveryPhrase',
        true,
      ),
      (
        {'recovery_evidence': 'none'},
        'authRecoveryNotBackedUp',
        'seedBackupGateBackUpNow',
        true,
      ),
    ]) {
      testWidgets('$metadata reads "$status" with "$action"', (tester) async {
        await _pumpPlates(tester, metadata: metadata);
        // The status is its own row, not the first line of the body.
        expect(
          find.descendant(
            of: find.byKey(const Key('recovery-phrase-status')),
            matching: find.text(status.tr()),
          ),
          findsOneWidget,
        );
        expect(find.text('authRecoveryPhraseDescription'.tr()), findsOneWidget);
        expect(find.text(action.tr()), findsOneWidget);
        expect(
          tester
              .widget<SecurityActionPlate>(
                find.byType(SecurityActionPlate).first,
              )
              .showWarningIndicator,
          warned,
        );
      });
    }

    testWidgets(
      'a file locked by a password the user never saw is not offered; a '
      'wallet password is',
      (tester) async {
        final security = await _pumpPlates(
          tester,
          access: AccessibilityAccess(),
        );
        expect(find.byKey(const Key('wallet-file-download')), findsNothing);
        expect(
          find.byKey(const Key('wallet-file-needs-password')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('wallet-file-set-password')));
        expect(security.events.whereType<PasswordUpdateEvent>(), hasLength(1));
      },
    );

    testWidgets('a generated password saved to a password manager keeps the '
        'download', (tester) async {
      await _pumpPlates(tester, access: _SavedGeneratedPasswordAccess());
      expect(find.byKey(const Key('wallet-file-set-password')), findsNothing);
      expect(find.byKey(const Key('wallet-file-needs-password')), findsNothing);
      expect(find.byKey(const Key('wallet-file-download')), findsOneWidget);
    });

    testWidgets('a password the user chose keeps the download', (tester) async {
      await _pumpPlates(tester, access: _ChosenPasswordAccess());
      expect(find.byKey(const Key('wallet-file-set-password')), findsNothing);
      expect(find.byKey(const Key('wallet-file-needs-password')), findsNothing);
      final download = find.byKey(const Key('wallet-file-download'));
      expect(
        tester
            .getSemantics(download)
            .getSemanticsData()
            .flagsCollection
            .isEnabled
            .toBoolOrNull(),
        isTrue,
      );
    });

    for (final brightness in Brightness.values) {
      for (final scale in [2.0, 3.0]) {
        testWidgets(
          'plates $brightness ${scale}x keep every label at large text',
          (tester) async {
            await _pumpPlates(tester, textScale: scale, brightness: brightness);
            for (final label in [
              'authRecoveryPhraseTitle',
              'authRecoveryNotBackedUp',
              'authEncryptedWalletFileTitle',
              'authEncryptedWalletFileDescription',
            ]) {
              final text = find.text(label.tr());
              await tester.ensureVisible(text);
              await tester.pumpAndSettle();
              expect(text, findsOneWidget);
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });
}

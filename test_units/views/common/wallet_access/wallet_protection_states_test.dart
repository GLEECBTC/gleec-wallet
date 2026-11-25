import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_event.dart';
import 'package:web_dex/bloc/wallet_protection/wallet_protection_bloc.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/services/wallet_access/wallet_lock_policy.dart';
import 'package:web_dex/views/common/wallet_access/wallet_protection_panel.dart';
import 'package:web_dex/views/common/wallet_access/wallet_setup_card.dart';
import 'package:web_dex/views/common/wallet_password_dialog/password_dialog_content.dart';
import 'package:web_dex/views/settings/widgets/security_settings/device_protection_section.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_section_card.dart';
import 'package:web_dex/views/settings/widgets/security_settings/wallet_display_name_section.dart';
import 'package:web_dex/views/settings/widgets/security_settings/wallet_removal_section.dart';

import '../../../support/legal_onboarding_harness.dart';
import '../../../support/wallet_access_ui_fixture.dart';

const _passkeyBrowser = CredentialCapabilities(
  available: true,
  protection: CredentialProtection.browserLocal,
  passkeyCandidate: true,
);
const _plainBrowser = CredentialCapabilities(
  available: true,
  protection: CredentialProtection.browserLocal,
);
const _deviceUnlock = CredentialCapabilities(
  available: true,
  protection: CredentialProtection.authenticationBound,
  deviceAuthentication: true,
);
const _bothMethods = CredentialCapabilities(
  available: true,
  protection: CredentialProtection.authenticationBound,
  deviceAuthentication: true,
  passkeyCandidate: true,
);
const _noDeviceUnlock = CredentialCapabilities(
  available: true,
  protection: CredentialProtection.appLocal,
);

class _Access extends AccessibilityAccess {
  _Access(this.caps, {bool locked = false, this.passkey = false}) {
    this.protected = locked;
  }

  CredentialCapabilities caps;
  bool passkey;

  /// What locks the wallet when it is not a passkey.
  CredentialProtection lockedBy = CredentialProtection.authenticationBound;
  WalletAccessFailure? statusFailure;
  Completer<void>? statusGate;
  WalletAccessFailure? authorizeFailure;
  WalletAccessFailure? enrollFailure;
  final graces = <Duration>[];

  @override
  Future<WalletAccessStatus> status({WalletId? walletId}) async {
    await statusGate?.future;
    if (statusFailure case final failure?) throw WalletAccessException(failure);
    return WalletAccessStatus(
      entryId: 'accessibility-entry',
      protection: passkey
          ? CredentialProtection.passkey
          : this.protected
          ? lockedBy
          : caps.protection,
      hasManagedCredential: true,
      requiresAuthentication: this.protected,
      generatedPassword: true,
    );
  }

  @override
  Future<CredentialCapabilities> capabilities() async => caps;

  @override
  Future<String> authorize({
    required WalletId walletId,
    String? password,
    String reason = 'Unlock your wallet',
  }) async {
    if (authorizeFailure case final failure?) {
      throw WalletAccessException(failure);
    }
    return super.authorize(walletId: walletId, password: password);
  }

  @override
  Future<void> setBackgroundGrace(Duration duration) async {
    graces.add(duration);
    unlockCoordinator.setBackgroundGrace(duration);
  }

  @override
  Future<void> enrollPasskey({
    required WalletId walletId,
    String? password,
  }) async {
    if (enrollFailure case final failure?) throw WalletAccessException(failure);
    passkey = true;
    this.protected = true;
  }
}

bool _isPrimary(String key) => find
    .descendant(of: find.byKey(Key(key)), matching: find.byType(ElevatedButton))
    .evaluate()
    .isNotEmpty;

/// The Security settings section, wide enough to put its action beside it.
Future<AccessibilitySecurity> _pumpSection(
  WidgetTester tester,
  _Access access, {
  double width = 760,
}) async {
  final harness = LegalFormHarness();
  final security = AccessibilitySecurity();
  // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
  harness.auth.emit(AuthBlocState.loggedIn(accessibilityUser()));
  addTearDown(access.unlockCoordinator.dispose);
  addTearDown(security.close);
  await harness.pump(
    tester,
    RepositoryProvider<WalletAccessService>.value(
      value: access,
      child: BlocProvider<SecuritySettingsBloc>.value(
        value: security,
        child: const DeviceProtectionSection(),
      ),
    ),
    size: const Size(900, 1400),
    contentWidth: width,
    disableAnimations: true,
  );
  return security;
}

/// Answers the authorization dialog a lock-timing change opens.
Future<void> _authorize(WidgetTester tester) async {
  tester
      .widget<PasswordDialogContent>(find.byType(PasswordDialogContent))
      .onSuccess('synthetic-typed-password');
  await tester.pump(const Duration(milliseconds: 150));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Wallet lock and setup checklist states', () {
    setUpAll(() async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
    });
    tearDown(() => Localization.load(const Locale('en')));

    for (final (lockDone, backupLeads, backupPrimary) in [
      (false, false, false),
      (true, false, true),
      (false, true, true),
    ]) {
      testWidgets('exactly one step is primary (lock done: $lockDone, '
          'backup leads: $backupLeads)', (tester) async {
        await LegalFormHarness().pump(
          tester,
          WalletSetupCard(
            hasRecoveryPhrase: false,
            hasDeviceProtection: lockDone,
            onBackup: () {},
            onProtect: () {},
            backupLeads: backupLeads,
          ),
        );
        expect(_isPrimary('wallet-setup-backup'), backupPrimary);
        if (lockDone) {
          // A finished step is one quiet line, not another action.
          expect(find.text('authProtectionEnabled'.tr()), findsOneWidget);
          expect(find.byKey(const Key('wallet-setup-protect')), findsNothing);
        } else {
          expect(_isPrimary('wallet-setup-protect'), !backupPrimary);
        }
        // Real buttons, not the look of body text.
        expect(find.byType(TextButton), findsNothing);
      });
    }

    testWidgets('a backed-up phrase collapses to a done line', (tester) async {
      await LegalFormHarness().pump(
        tester,
        WalletSetupCard(
          hasRecoveryPhrase: true,
          hasDeviceProtection: false,
          onBackup: () {},
          onProtect: () {},
        ),
      );
      expect(find.text('authRecoveryBackedUp'.tr()), findsOneWidget);
      expect(find.byKey(const Key('wallet-setup-backup')), findsNothing);
      expect(_isPrimary('wallet-setup-protect'), isTrue);
    });

    for (final (platform, caps, reason) in [
      (TargetPlatform.android, _plainBrowser, 'authLockUnavailablePasskeys'),
      (
        TargetPlatform.android,
        _noDeviceUnlock,
        'authLockUnavailableScreenLock',
      ),
      (TargetPlatform.iOS, _noDeviceUnlock, 'authLockUnavailableScreenLock'),
      (TargetPlatform.linux, _noDeviceUnlock, 'authLockUnavailablePlatform'),
    ]) {
      testWidgets(
        'where no one-step lock exists ($reason on ${platform.name}) the '
        'section says why and offers a wallet password',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          try {
            final security = await _pumpSection(tester, _Access(caps));
            expect(find.text('authUnprotectedTitle'.tr()), findsOneWidget);
            expect(find.text(reason.tr()), findsOneWidget);
            await tester.tap(find.byKey(const Key('set-wallet-password')));
            await tester.pump();
            expect(
              security.events.whereType<PasswordUpdateEvent>(),
              hasLength(1),
            );
            expect(tester.takeException(), isNull);
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        },
      );
    }

    testWidgets('the checklist step sends the same case to a wallet password', (
      tester,
    ) async {
      final access = _Access(_plainBrowser);
      addTearDown(access.unlockCoordinator.dispose);
      var passwordRequests = 0;
      await LegalFormHarness().pump(
        tester,
        BlocProvider(
          create: (_) => WalletProtectionBloc(
            access: access,
            walletId: accessibilityUser().walletId,
          ),
          child: WalletProtectionPanel(
            onOpenSettings: () => fail('the list is not the destination'),
            onSetPassword: () => passwordRequests++,
          ),
        ),
      );
      expect(find.text('authLockUnavailablePasskeys'.tr()), findsOneWidget);
      await tester.tap(find.text('authSetWalletPassword'.tr()));
      expect(passwordRequests, 1);
    });

    testWidgets(
      'the settings section is title, one sentence, one supporting line and '
      'its actions',
      (tester) async {
        final access = _Access(_bothMethods);
        await _pumpSection(tester, access);
        expect(find.text('authPasskeySetupTitle'.tr()), findsOneWidget);
        expect(find.text('authPasskeySetupDescription'.tr()), findsOneWidget);
        expect(find.text('authPasskeyLocalScopeCompact'.tr()), findsOneWidget);
        for (final retired in [
          'authPasskeyLocalScope',
          'authPasskeySetupConfirmations',
          'authPasswordManagerAutomatic',
          'authPasswordManagerUnavailable',
        ]) {
          expect(find.text(retired.tr()), findsNothing, reason: retired);
        }
        expect(_isPrimary('enable-passkey-unlock'), isTrue);
        expect(_isPrimary('enable-device-unlock'), isFalse);
        expect(find.byType(OutlinedButton), findsNothing);
      },
    );

    testWidgets(
      'a wallet that fell back to the password created for it is told so and '
      'offered its lock again',
      (tester) async {
        // What the service reports once the system invalidates device unlock.
        final access = _Access(_deviceUnlock, locked: true)
          ..lockedBy = CredentialProtection.password;
        await _pumpSection(tester, access);
        expect(find.text('authDeviceUnlockOffTitle'.tr()), findsOneWidget);
        expect(
          find.text('authDeviceUnlockOffDescription'.tr()),
          findsOneWidget,
        );
        // Nobody chose this password, so it is not called a personal one.
        expect(find.text('authPasswordProtected'.tr()), findsNothing);
        expect(_isPrimary('enable-device-unlock'), isTrue);
      },
    );

    testWidgets('a failed check can be retried, with visible progress', (
      tester,
    ) async {
      final access = _Access(_passkeyBrowser)
        ..statusFailure = WalletAccessFailure.storageFailed;
      await _pumpSection(tester, access);
      expect(find.text('authProtectionCheckFailed'.tr()), findsOneWidget);
      // No change was asked for, so none is reported as failed.
      expect(find.text('authProtectionFailed'.tr()), findsNothing);
      expect(find.text('authPasskeyUnsupported'.tr()), findsNothing);

      access
        ..statusFailure = null
        ..statusGate = Completer<void>();
      await tester.tap(find.byKey(const Key('wallet-protection-retry')));
      await tester.pump();
      expect(find.text('authProtectionChecking'.tr()), findsOneWidget);
      access.statusGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('authProtectionCheckFailed'.tr()), findsNothing);
      expect(find.text('authPasskeySetupTitle'.tr()), findsOneWidget);
    });

    testWidgets('only a failed passkey setup blames the browser', (
      tester,
    ) async {
      final access = _Access(_passkeyBrowser)
        ..enrollFailure = WalletAccessFailure.prfUnavailable;
      await _pumpSection(tester, access);
      await tester.tap(find.byKey(const Key('enable-passkey-unlock')));
      await tester.pumpAndSettle();
      expect(find.text('authPasskeyUnsupported'.tr()), findsOneWidget);
    });

    testWidgets(
      'lock timing offers every interval and asks nothing for the current one',
      (tester) async {
        final access = _Access(_passkeyBrowser, locked: true, passkey: true);
        await _pumpSection(tester, access);
        expect(
          find.byType(RadioListTile<int>),
          findsNWidgets(walletLockGraceOptions.length),
        );
        // Already in force: no authentication, no change.
        await tester.tap(find.text('authLockThirtySeconds'.tr()));
        await tester.pumpAndSettle();
        expect(find.byType(PasswordDialogContent), findsNothing);
        expect(access.authorized, isEmpty);

        await tester.tap(find.text('authLockFiveMinutes'.tr()));
        await tester.pumpAndSettle();
        await _authorize(tester);
        expect(access.graces, [const Duration(minutes: 5)]);
        expect(find.text('authLockPreferenceSaved'.tr()), findsOneWidget);
        expect(
          tester
              .widget<RadioGroup<int>>(find.byType(RadioGroup<int>))
              .groupValue,
          300,
        );
      },
    );

    testWidgets(
      'a lock-timing change that fails is not reported as a passkey problem',
      (tester) async {
        final access = _Access(_passkeyBrowser, locked: true, passkey: true)
          ..authorizeFailure = WalletAccessFailure.unavailable;
        await _pumpSection(tester, access);
        await tester.tap(find.text('authLockImmediately'.tr()));
        await tester.pumpAndSettle();
        await _authorize(tester);
        expect(access.graces, isEmpty);
        expect(find.text('authPasskeyUnsupported'.tr()), findsNothing);
        expect(find.text('authDeviceUnlockFailed'.tr()), findsOneWidget);
      },
    );

    for (final width in [320.0, 760.0]) {
      testWidgets(
        'the wallet lock, name and removal sections share the plates\' '
        'surface at $width dp',
        (tester) async {
          final harness = LegalFormHarness();
          final access = _Access(_passkeyBrowser, locked: true, passkey: true);
          addTearDown(access.unlockCoordinator.dispose);
          // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
          harness.auth.emit(AuthBlocState.loggedIn(accessibilityUser()));
          await harness.pump(
            tester,
            RepositoryProvider<WalletAccessService>.value(
              value: access,
              child: const Column(
                children: [
                  DeviceProtectionSection(),
                  WalletDisplayNameSection(),
                  WalletRemovalSection(),
                ],
              ),
            ),
            size: const Size(900, 2400),
            contentWidth: width,
            disableAnimations: true,
          );
          expect(find.byType(SecuritySectionCard), findsNWidgets(3));
          for (final material in [Card, OutlinedButton, FilledButton]) {
            expect(find.byType(material), findsNothing, reason: '$material');
          }
          for (final key in [
            'replace-passkey-using-password',
            'rename-wallet',
            'settings-delete-wallet',
          ]) {
            final control = find.byKey(Key(key));
            await tester.ensureVisible(control);
            await tester.pumpAndSettle();
            expect(tester.getSize(control).height, greaterThanOrEqualTo(48));
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}

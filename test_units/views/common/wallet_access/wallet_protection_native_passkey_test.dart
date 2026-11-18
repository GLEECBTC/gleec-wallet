import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_bloc.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/views/common/wallet_password_dialog/password_dialog_content.dart';
import 'package:web_dex/views/settings/widgets/security_settings/device_protection_section.dart';

import '../../../support/legal_onboarding_harness.dart';
import '../../../support/wallet_access_ui_fixture.dart';

const _deviceAndPasskeys = CredentialCapabilities(
  available: true,
  protection: CredentialProtection.authenticationBound,
  deviceAuthentication: true,
  existingPasskeyCandidate: true,
);
const _passkeysOnly = CredentialCapabilities(
  available: true,
  protection: CredentialProtection.osAccountProtected,
  existingPasskeyCandidate: true,
);

/// Linux: security keys, and no device unlock to go back to.
const _securityKeys = CredentialCapabilities(
  available: true,
  protection: CredentialProtection.osAccountProtected,
  existingPasskeyCandidate: true,
  unattendedReturn: true,
);
const _deviceOnly = CredentialCapabilities(
  available: true,
  protection: CredentialProtection.authenticationBound,
  deviceAuthentication: true,
);

/// A native app's wallet access, recording what the section asked for.
class _NativeAccess extends AccessibilityAccess {
  _NativeAccess(this.caps, {this.lock});

  final CredentialCapabilities caps;

  /// What locks the wallet; null when nothing does yet.
  CredentialProtection? lock;

  /// The lock that stopped working, when the wallet fell back to its
  /// generated password.
  CredentialProtection? lost;
  WalletAccessFailure? failure;
  final requests = <(String, String?)>[];

  @override
  Future<WalletAccessStatus> status({WalletId? walletId}) async =>
      WalletAccessStatus(
        entryId: 'accessibility-entry',
        protection: lost != null
            ? CredentialProtection.password
            : lock ?? caps.protection,
        hasManagedCredential: lost == null,
        requiresAuthentication: lock != null || lost != null,
        generatedPassword: true,
        lostProtection: lost,
      );

  @override
  Future<CredentialCapabilities> capabilities() async => caps;

  void _record(String action, String? password, CredentialProtection next) {
    requests.add((action, password));
    if (failure case final failure?) throw WalletAccessException(failure);
    lock = next;
  }

  @override
  Future<void> useExistingPasskey({
    required WalletId walletId,
    String? password,
  }) async => _record('existing', password, CredentialProtection.passkey);

  @override
  Future<void> enrollDevice({
    required WalletId walletId,
    String? password,
  }) async =>
      _record('device', password, CredentialProtection.authenticationBound);

  @override
  Future<void> stopUsingPasskey({
    required WalletId walletId,
    required String password,
  }) async => _record('passwordOnly', password, CredentialProtection.password);

  @override
  Future<void> useDeviceStorageInstead({required WalletId walletId}) async {
    requests.add(('deviceStorage', null));
    if (failure case final failure?) throw WalletAccessException(failure);
    lock = null;
  }

  @override
  Future<void> replacePasskeyUsingPassword({
    required WalletId walletId,
    required String password,
  }) async => _record('replace', password, CredentialProtection.passkey);
}

bool _isPrimary(String key) => find
    .descendant(of: find.byKey(Key(key)), matching: find.byType(ElevatedButton))
    .evaluate()
    .isNotEmpty;

Future<void> _pumpSection(WidgetTester tester, _NativeAccess access) async {
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
    contentWidth: 760,
    disableAnimations: true,
  );
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('native passkey reuse in Security settings', () {
    testWidgets('device unlock offers an existing passkey as an alternative', (
      tester,
    ) async {
      final access = _NativeAccess(
        _deviceAndPasskeys,
        lock: CredentialProtection.authenticationBound,
      );
      await _pumpSection(tester, access);
      expect(find.byKey(const Key('use-existing-passkey')), findsOneWidget);
      expect(_isPrimary('use-existing-passkey'), isFalse);

      await _tap(tester, 'use-existing-passkey');
      // A stored credential authorizes the change; nothing is typed.
      expect(access.requests, [('existing', null)]);
      expect(find.text('authExistingPasskeyReady'.tr()), findsOneWidget);
      expect(find.text('authPasskeyProtectedDevice'.tr()), findsOneWidget);
    });

    testWidgets('where device unlock is missing, the password still leads', (
      tester,
    ) async {
      // Most people hold no passkey for the web wallet, so one is never the
      // only way offered to lock the wallet.
      await _pumpSection(tester, _NativeAccess(_passkeysOnly));
      expect(find.text('authUnprotectedTitle'.tr()), findsOneWidget);
      expect(_isPrimary('set-wallet-password'), isTrue);
      expect(find.byKey(const Key('use-existing-passkey')), findsOneWidget);
      expect(_isPrimary('use-existing-passkey'), isFalse);
    });

    testWidgets('names a lost passkey as the lock that stopped working', (
      tester,
    ) async {
      await _pumpSection(
        tester,
        _NativeAccess(_deviceAndPasskeys)..lost = CredentialProtection.passkey,
      );
      expect(find.text('authPasskeyOffTitle'.tr()), findsOneWidget);
      expect(
        find.text('authExistingPasskeyOffDescription'.tr()),
        findsOneWidget,
      );
      expect(_isPrimary('enable-device-unlock'), isTrue);
      expect(find.byKey(const Key('use-existing-passkey')), findsOneWidget);
    });

    testWidgets('names lost device unlock as such', (tester) async {
      await _pumpSection(
        tester,
        _NativeAccess(_deviceAndPasskeys)
          ..lost = CredentialProtection.authenticationBound,
      );
      expect(find.text('authDeviceUnlockOffTitle'.tr()), findsOneWidget);
    });

    testWidgets('a passkey-protected wallet keeps two ways back', (
      tester,
    ) async {
      final access = _NativeAccess(
        _deviceAndPasskeys,
        lock: CredentialProtection.passkey,
      );
      await _pumpSection(tester, access);
      expect(find.text('authPasskeyProtectedDevice'.tr()), findsOneWidget);
      expect(find.byKey(const Key('switch-to-device-unlock')), findsOneWidget);
      expect(find.byKey(const Key('use-existing-passkey')), findsNothing);
      expect(
        find.text('authPasskeyLostDeviceGeneratedDescription'.tr()),
        findsOneWidget,
      );
      expect(
        find.text('authChooseAnotherPasskeyWithPassword'.tr()),
        findsOneWidget,
      );
      expect(find.byKey(const Key('stop-using-passkey')), findsOneWidget);

      await _tap(tester, 'device-unlock-using-password');
      tester
          .widget<PasswordDialogContent>(find.byType(PasswordDialogContent))
          .onSuccess('synthetic-typed-password');
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(access.requests, [('device', 'synthetic-typed-password')]);
    });

    testWidgets('a lost passkey can leave the wallet on its password alone', (
      tester,
    ) async {
      final access = _NativeAccess(
        _passkeysOnly,
        lock: CredentialProtection.passkey,
      );
      await _pumpSection(tester, access);
      expect(
        find.byKey(const Key('device-unlock-using-password')),
        findsNothing,
      );
      await _tap(tester, 'stop-using-passkey');
      tester
          .widget<PasswordDialogContent>(find.byType(PasswordDialogContent))
          .onSuccess('synthetic-typed-password');
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(access.requests, [('passwordOnly', 'synthetic-typed-password')]);
      expect(find.text('authPasskeyRemoved'.tr()), findsOneWidget);
    });

    testWidgets('switching back to device unlock asks for nothing typed', (
      tester,
    ) async {
      final access = _NativeAccess(
        _deviceAndPasskeys,
        lock: CredentialProtection.passkey,
      );
      await _pumpSection(tester, access);
      await _tap(tester, 'switch-to-device-unlock');
      expect(access.requests, [('device', null)]);
      expect(find.text('authProtectionEnabled'.tr()), findsOneWidget);
    });

    testWidgets('without device unlock, the passkey leads back to storage', (
      tester,
    ) async {
      final access = _NativeAccess(
        _securityKeys,
        lock: CredentialProtection.passkey,
      );
      await _pumpSection(tester, access);
      expect(find.byKey(const Key('switch-to-device-unlock')), findsNothing);
      expect(_isPrimary('use-device-storage'), isFalse);

      await _tap(tester, 'use-device-storage');
      // The passkey authorizes it; nothing is typed.
      expect(access.requests, [('deviceStorage', null)]);
      expect(find.text('authOpenedWithoutPasskey'.tr()), findsOneWidget);
      expect(find.byKey(const Key('use-device-storage')), findsNothing);
    });

    testWidgets('where device unlock exists, storage is not the way back', (
      tester,
    ) async {
      await _pumpSection(
        tester,
        _NativeAccess(_deviceAndPasskeys, lock: CredentialProtection.passkey),
      );
      expect(find.byKey(const Key('switch-to-device-unlock')), findsOneWidget);
      expect(find.byKey(const Key('use-device-storage')), findsNothing);
    });

    testWidgets('says plainly when no passkey was found', (tester) async {
      final access = _NativeAccess(
        _deviceAndPasskeys,
        lock: CredentialProtection.authenticationBound,
      )..failure = WalletAccessFailure.passkeyNotFound;
      await _pumpSection(tester, access);
      await _tap(tester, 'use-existing-passkey');
      expect(find.text('authExistingPasskeyNotFound'.tr()), findsOneWidget);
      expect(find.text('authDeviceProtected'.tr()), findsOneWidget);
    });

    testWidgets('without the capability nothing about passkeys appears', (
      tester,
    ) async {
      await _pumpSection(
        tester,
        _NativeAccess(
          _deviceOnly,
          lock: CredentialProtection.authenticationBound,
        ),
      );
      expect(find.byKey(const Key('use-existing-passkey')), findsNothing);
      expect(find.byKey(const Key('switch-to-device-unlock')), findsNothing);
    });
  });
}

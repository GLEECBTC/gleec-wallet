import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/wallet_protection/wallet_protection_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/views/settings/widgets/security_settings/plate_seed_backup.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/views/common/wallet_access/wallet_protection_panel.dart';
import 'package:web_dex/views/common/wallet_access/wallet_setup_card.dart';
import 'package:web_dex/views/wallets_manager/widgets/creation_password_fields.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_simple_import.dart';

import '../../../support/legal_onboarding_harness.dart';
import '../../../support/wallet_access_ui_fixture.dart';

class _SetupAccess extends AccessibilityAccess {
  _SetupAccess() {
    this.protected = false;
  }
  bool supported = true;
  WalletAccessFailure? enrollmentFailure;
  int enrollments = 0;
  Completer<void>? enrollmentPending;
  @override
  Future<WalletAccessStatus> status({WalletId? walletId}) async =>
      WalletAccessStatus(
        entryId: 'accessibility-entry',
        protection: this.protected
            ? CredentialProtection.passkey
            : CredentialProtection.browserLocal,
        hasManagedCredential: true,
        requiresAuthentication: this.protected,
        generatedPassword: true,
      );
  @override
  Future<CredentialCapabilities> capabilities() async => CredentialCapabilities(
    available: true,
    protection: CredentialProtection.browserLocal,
    passkeyCandidate: supported,
  );
  @override
  Future<void> enrollPasskey({
    required WalletId walletId,
    String? password,
  }) async {
    enrollments++;
    await enrollmentPending?.future;
    if (enrollmentFailure != null) {
      throw WalletAccessException(enrollmentFailure!);
    }
    this.protected = true;
  }
}

class _ManagerSetupAccess extends _SetupAccess {
  bool pending = true;
  final activity = StreamController<void>.broadcast(sync: true);
  @override
  bool get isPasswordManagerPending => pending;
  @override
  Stream<void> get changes => activity.stream;
}

Widget _setup(
  _SetupAccess access, {
  Key? captureKey,
  VoidCallback? onSettings,
}) => BlocProvider(
  create: (_) => WalletProtectionBloc(
    access: access,
    walletId: accessibilityUser().walletId,
  ),
  child: RepaintBoundary(
    key: captureKey,
    child: _CaptureCanvas(
      child: SizedBox.expand(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: BlocBuilder<WalletProtectionBloc, WalletProtectionState>(
                builder: (context, state) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Gleec Wallet',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 20),
                    WalletSetupCard(
                      hasRecoveryPhrase: false,
                      hasDeviceProtection:
                          state.status?.requiresAuthentication ?? false,
                      onBackup: () {},
                      onProtect: () {},
                      recoveryDescription: 'authRecoveryIndependent'.tr(),
                      protectionSetup: WalletProtectionPanel(
                        onOpenSettings: onSettings,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text('Wallet overview'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

class _CaptureCanvas extends StatelessWidget {
  const _CaptureCanvas({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      Material(color: Theme.of(context).scaffoldBackgroundColor, child: child);
}

Future<void> _capture(WidgetTester tester, Key key, String name) async {
  final directory = Platform.environment['AUTH_UX_CAPTURE_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Authentication setup flow', () {
    setUpAll(() async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
      if (Platform.environment['AUTH_UX_CAPTURE_DIR'] == null) return;
      final font = FontLoader('Manrope');
      for (final weight in ['Regular', 'Medium', 'Bold']) {
        font.addFont(rootBundle.load('assets/fonts/Manrope-$weight.ttf'));
      }
      await font.load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
    tearDown(() => Localization.load(const Locale('en')));

    testWidgets(
      'provider completion enables one explicit setup action without an extra save control',
      (tester) async {
        final access = _ManagerSetupAccess();
        addTearDown(access.unlockCoordinator.dispose);
        addTearDown(access.activity.close);
        await LegalFormHarness().pump(
          tester,
          _setup(access),
          disableAnimations: true,
          scrollable: false,
          size: const Size(390, 844),
        );
        final action = find.byKey(const Key('wallet-setup-protect'));
        ElevatedButton button() => tester.widget<ElevatedButton>(
          find.descendant(of: action, matching: find.byType(ElevatedButton)),
        );
        expect(button().onPressed, isNull);
        expect(access.enrollments, 0);
        expect(find.text('authPasswordManagerPending'.tr()), findsOneWidget);
        access.pending = false;
        access.activity.add(null);
        await tester.pumpAndSettle();
        expect(button().onPressed, isNotNull);
        expect(find.text('authPasswordManagerPending'.tr()), findsNothing);
        expect(access.enrollments, 0);
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(access.enrollments, 1);
        expect(find.text('authPasskeyReadyTitle'.tr()), findsOneWidget);
        expect(find.byKey(const Key('wallet-setup-backup')), findsOneWidget);
      },
    );

    for (final brightness in Brightness.values) {
      for (final size in [const Size(390, 844), const Size(1280, 900)]) {
        for (final phase in [
          'ready',
          'waiting',
          'creating',
          'canceled',
          'protected',
        ]) {
          testWidgets(
            'inline setup $phase $brightness $size is optional and recovery stays independent',
            (tester) async {
              final access =
                  (phase == 'waiting' ? _ManagerSetupAccess() : _SetupAccess())
                    ..protected = phase == 'protected';
              if (access is _ManagerSetupAccess) {
                addTearDown(access.activity.close);
              }
              addTearDown(access.unlockCoordinator.dispose);
              if (phase == 'canceled') {
                access.enrollmentFailure = WalletAccessFailure.canceled;
              }
              if (phase == 'creating')
                access.enrollmentPending = Completer<void>();
              const key = Key('setup-state-capture');
              await LegalFormHarness().pump(
                tester,
                _setup(access, captureKey: key),
                size: size,
                scrollable: false,
                brightness: brightness,
                textScale: size.width < 500 ? 1.25 : 1,
                disableAnimations: true,
              );
              if (phase == 'canceled') {
                await tester.tap(find.byKey(const Key('wallet-setup-protect')));
                await tester.pumpAndSettle();
                expect(
                  find.text('authProtectionCanceled'.tr()),
                  findsOneWidget,
                );
                expect(access.enrollments, 1);
              }
              if (phase == 'creating') {
                await tester.tap(find.byKey(const Key('wallet-setup-protect')));
                await tester.pumpAndSettle();
                expect(
                  find.text('authPasskeySetupPending'.tr()),
                  findsOneWidget,
                );
                expect(access.enrollments, 1);
              }
              expect(
                find.byKey(const Key('wallet-setup-backup')),
                findsOneWidget,
              );
              expect(find.text('Wallet overview'), findsOneWidget);
              expect(find.byType(AlertDialog), findsNothing);
              expect(find.byType(TextField), findsNothing);
              expect(
                find.text('authPersonalPasswordOptional'.tr()),
                findsNothing,
              );
              if (phase == 'protected') {
                expect(find.text('authPasskeyReadyTitle'.tr()), findsOneWidget);
                expect(
                  find.byKey(const Key('wallet-setup-protect')),
                  findsNothing,
                );
              } else if (phase == 'waiting' || phase == 'creating') {
                final action = find.byKey(const Key('wallet-setup-protect'));
                expect(
                  tester
                      .widget<ElevatedButton>(
                        find.descendant(
                          of: action,
                          matching: find.byType(ElevatedButton),
                        ),
                      )
                      .onPressed,
                  isNull,
                );
                expect(
                  find.text(
                    (phase == 'waiting'
                            ? 'authPasswordManagerPending'
                            : 'authPasskeySetupPending')
                        .tr(),
                  ),
                  findsOneWidget,
                );
              } else {
                final action = find.byKey(const Key('wallet-setup-protect'));
                await tester.ensureVisible(action);
                expect(action.hitTestable(), findsOneWidget);
              }
              expect(tester.takeException(), isNull);
              // Only public status/empty-wallet UI is captured. Never secret forms.
              await _capture(
                tester,
                key,
                'setup-$phase-${brightness.name}-${size.width.toInt()}',
              );
              if (phase == 'creating') {
                access.enrollmentPending!.complete();
                await tester.pumpAndSettle();
                expect(find.text('authPasskeySetupPending'.tr()), findsNothing);
                expect(find.text('authPasskeyReadyTitle'.tr()), findsOneWidget);
              }
            },
          );
        }
      }
    }

    for (final brightness in Brightness.values) {
      for (final profile in [
        (const Size(320, 568), 2.0),
        (const Size(844, 390), 3.0),
        (const Size(1280, 900), 2.0),
      ]) {
        final (size, scale) = profile;
        testWidgets(
          'direct passkey action $brightness $size ${scale}x stays readable and reachable',
          (tester) async {
            final access = _SetupAccess();
            addTearDown(access.unlockCoordinator.dispose);
            await LegalFormHarness().pump(
              tester,
              _setup(access),
              size: size,
              textScale: scale,
              brightness: brightness,
              scrollable: false,
              disableAnimations: true,
            );
            final button = find.byKey(const Key('wallet-setup-protect'));
            await tester.ensureVisible(button);
            await tester.pumpAndSettle();
            final label = find.descendant(
              of: button,
              matching: find.text('authCreatePasskey'.tr()),
            );
            expect(
              tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
              isFalse,
            );
            expect(button.hitTestable(), findsOneWidget);
            expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    for (final brightness in Brightness.values) {
      for (final scale in [2.0, 3.0]) {
        testWidgets(
          'recovery panels $brightness ${scale}x fit a narrow column in a wide window',
          (tester) async {
            final harness = LegalFormHarness();
            // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
            harness.auth.emit(AuthBlocState.loggedIn(accessibilityUser()));
            await harness.pump(
              tester,
              PlateSeedBackup(onViewSeedPressed: (_) {}),
              size: const Size(1280, 900),
              contentWidth: 320,
              textScale: scale,
              brightness: brightness,
              disableAnimations: true,
            );
            for (final label in [
              'authRecoveryPhraseTitle',
              'authEncryptedWalletFileTitle',
            ]) {
              final title = find.text(label.tr());
              await tester.ensureVisible(title);
              await tester.pumpAndSettle();
              expect(title, findsOneWidget);
            }
            expect(
              find.text('authEncryptedWalletFileDescription'.tr()),
              findsOneWidget,
            );
            expect(
              find.textContaining('authRecoveryNotReady'.tr()),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets(
      'unsupported browser has an accurate status and settings fallback',
      (tester) async {
        final access = _SetupAccess()..supported = false;
        addTearDown(access.unlockCoordinator.dispose);
        var settings = 0;
        await LegalFormHarness().pump(
          tester,
          _setup(access, onSettings: () => settings++),
          scrollable: false,
        );
        expect(find.text('authCreatePasskey'.tr()), findsNothing);
        expect(find.text('authBrowserUnprotected'.tr()), findsOneWidget);
        await tester.tap(find.byKey(const Key('wallet-setup-protect')));
        await tester.pumpAndSettle();
        expect(settings, 1);
        expect(access.enrollments, 0);
      },
    );

    testWidgets(
      'recovery phrase input remasks on inactivity and never enables keyboard learning',
      (tester) async {
        await LegalFormHarness().pump(
          tester,
          WalletSimpleImport(
            onImport:
                ({
                  required name,
                  required password,
                  required walletConfig,
                  required rememberMe,
                }) {},
            onUploadFiles: ({required fileName, required fileData}) {},
            onCancel: () {},
          ),
        );
        final finder = find.descendant(
          of: find.byKey(const Key('import-seed-field')),
          matching: find.byType(EditableText),
        );
        expect(tester.widget<EditableText>(finder).enableSuggestions, isFalse);
        expect(
          tester.widget<EditableText>(finder).enableIMEPersonalizedLearning,
          isFalse,
        );
        await tester.tap(find.byTooltip('authShowRecoveryPhrase'.tr()));
        await tester.pump();
        expect(tester.widget<EditableText>(finder).obscureText, isFalse);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        expect(tester.widget<EditableText>(finder).obscureText, isTrue);
        expect(find.byTooltip('authShowRecoveryPhrase'.tr()), findsOneWidget);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      },
    );

    testWidgets('new password keeps paste/autofill and remasks on background', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await LegalFormHarness().pump(
        tester,
        CreationPasswordFields(passwordController: controller),
      );
      final finder = find.descendant(
        of: find.byKey(const Key('create-password-field')),
        matching: find.byType(EditableText),
      );
      final field = tester.widget<EditableText>(finder);
      expect(field.enableInteractiveSelection, isTrue);
      expect(field.autofillHints, contains(AutofillHints.newPassword));
      expect(field.enableSuggestions, isFalse);
      expect(field.enableIMEPersonalizedLearning, isFalse);
      await tester.tap(find.byTooltip('authShowPassword'.tr()));
      await tester.pump();
      expect(tester.widget<EditableText>(finder).obscureText, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(tester.widget<EditableText>(finder).obscureText, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
  });
}

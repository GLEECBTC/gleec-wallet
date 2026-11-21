import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart'
    show WalletDeletionCommittedException;
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/views/settings/widgets/security_settings/wallet_removal_section.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_deleting.dart';

import '../../support/legal_onboarding_harness.dart';
import '../../support/wallet_access_ui_fixture.dart';

KdfUser _user() => KdfUser(
  walletId: accessibilityUser().walletId,
  isBip39Seed: true,
  metadata: const {'type': 'hdwallet', '_wallet_entry_id': 'removal-fixture'},
);

class _PendingTransfers extends Fake
    implements PendingGaslessTransferRepository {
  @override
  Future<List<PendingGaslessTransfer>> list(WalletId walletId) async => [];
}

class _RemovalAccess extends AccessibilityAccess {
  _RemovalAccess(this.auth);
  final LegalFormAuth auth;
  final deletionProofs = <(Wallet, String?)>[];
  @override
  Future<String> credentialForDeletion(
    Wallet wallet, {
    String? password,
  }) async {
    deletionProofs.add((wallet, password));
    if (auth.state.currentUser?.walletId != accessibilityUser().walletId) {
      throw const WalletAccessException(
        WalletAccessFailure.walletMustBeUnlocked,
      );
    }
    if (password == null) {
      throw const WalletAccessException(WalletAccessFailure.canceled);
    }
    if (password != 'synthetic-removal-password') {
      throw const WalletAccessException(WalletAccessFailure.incorrectPassword);
    }
    return password;
  }
}

class _Wallets extends Fake implements WalletsRepository {
  _Wallets(this.auth) {
    manager = WalletDeletionManager(
      readWallets: () async => [_user()],
      pendingTransfers: _PendingTransfers(),
      deleteWallet:
          ({
            required walletName,
            required password,
            required validateTarget,
          }) async {},
    );
  }
  final LegalFormAuth auth;
  late final WalletDeletionManager manager;
  WalletDeletionReview? review;
  bool metadataCleanupFailed = false;
  final deletions = <(Wallet, String, WalletDeletionReview?)>[];
  @override
  Future<WalletDeletionReview?> prepareWalletDeletion(Wallet wallet) async =>
      review = await manager.prepare(wallet.name);
  @override
  Future<WalletDeletionResult> deleteWallet(
    Wallet wallet, {
    required String password,
    WalletDeletionReview? acknowledgedReview,
  }) async {
    deletions.add((wallet, password, acknowledgedReview));
    // Model the engine lifecycle update after successful reviewed removal.
    // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
    auth.emit(AuthBlocState.initial());
    if (metadataCleanupFailed) {
      throw WalletDeletionCommittedException(
        walletId: _user().walletId,
        entryId: 'removal-fixture',
      );
    }
    return const WalletDeletionResult(WalletDeletionStatus.deleted);
  }
}

Future<(_RemovalAccess, _Wallets, LegalFormAuth)> _pump(
  WidgetTester tester, {
  Brightness brightness = Brightness.dark,
  double textScale = 1,
}) async {
  final auth = LegalFormAuth();
  // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
  auth.emit(AuthBlocState.loggedIn(_user()));
  final access = _RemovalAccess(auth);
  final wallets = _Wallets(auth);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await auth.close();
    await access.unlockCoordinator.dispose();
  });
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      saveLocale: false,
      path: 'assets/translations',
      assetLoader: const LegalEnglishLoader(),
      child: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<WalletAccessService>.value(value: access),
          RepositoryProvider<WalletsRepository>.value(value: wallets),
        ],
        child: BlocProvider<AuthBloc>.value(
          value: auth,
          child: Builder(
            builder: (context) => MaterialApp(
              theme: brightness == Brightness.dark
                  ? theme.global.dark
                  : theme.global.light,
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
              home: const Scaffold(
                body: SingleChildScrollView(child: WalletRemovalSection()),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (access, wallets, auth);
}

Future<void> _open(WidgetTester tester) async {
  final action = find.byKey(const Key('settings-delete-wallet'));
  await tester.ensureVisible(action);
  await tester.tap(action);
  await tester.pumpAndSettle();
}

Future<void> _submitPassword(WidgetTester tester, String password) async {
  await tester.ensureVisible(find.text('authUsePassword'.tr()));
  await tester.tap(find.text('authUsePassword'.tr()));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('delete-wallet-password')));
  await tester.enterText(
    find.byKey(const Key('delete-wallet-password')),
    password,
  );
  await tester.ensureVisible(find.byType(UiPrimaryButton));
  await tester.tap(find.byType(UiPrimaryButton));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Active wallet removal from Security settings', () {
    setUpAll(() async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
    });
    tearDown(() => Localization.load(const Locale('en')));

    for (final brightness in Brightness.values) {
      testWidgets('review entry is reachable at 200% text in $brightness', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final (access, wallets, auth) = await _pump(
          tester,
          brightness: brightness,
          textScale: 2,
        );
        final action = find.byKey(const Key('settings-delete-wallet'));
        await tester.ensureVisible(action);
        expect(action.hitTestable(), findsOneWidget);
        expect(auth.events, isEmpty);
        expect(access.deletionProofs, isEmpty);
        expect(wallets.deletions, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      'opens the existing review and cancellation preserves the active wallet',
      (tester) async {
        final (access, wallets, auth) = await _pump(tester);
        await _open(tester);
        expect(find.byType(WalletDeleting), findsOneWidget);
        expect(find.text('deleteWalletInfo'.tr()), findsOneWidget);
        expect(
          find.text('authRemoveWalletActivityWarning'.tr()),
          findsOneWidget,
        );
        expect(wallets.review?.walletId, accessibilityUser().walletId);
        expect(auth.state.currentUser?.walletId, accessibilityUser().walletId);
        expect(auth.events, isEmpty);
        expect(access.deletionProofs, isEmpty);
        await tester.ensureVisible(find.text('cancel'.tr()));
        await tester.tap(find.text('cancel'.tr()));
        await tester.pumpAndSettle();
        expect(find.byType(WalletDeleting), findsNothing);
        expect(wallets.deletions, isEmpty);
        expect(auth.state.currentUser?.walletId, accessibilityUser().walletId);
        expect(auth.events, isEmpty);
      },
    );

    testWidgets('wrong password cannot remove or sign out the active wallet', (
      tester,
    ) async {
      final (access, wallets, auth) = await _pump(tester);
      await _open(tester);
      await _submitPassword(tester, 'wrong');
      expect(access.deletionProofs.single.$2, 'wrong');
      expect(wallets.deletions, isEmpty);
      expect(auth.state.currentUser?.walletId, accessibilityUser().walletId);
      expect(auth.events, isEmpty);
      expect(find.text('passwordNotAccepted'.tr()), findsOneWidget);
    });

    testWidgets('canceled provider authorization preserves the active wallet', (
      tester,
    ) async {
      final (access, wallets, auth) = await _pump(tester);
      await _open(tester);
      await tester.ensureVisible(find.byType(UiPrimaryButton));
      await tester.tap(find.byType(UiPrimaryButton));
      await tester.pumpAndSettle();
      expect(access.deletionProofs.single.$2, isNull);
      expect(wallets.deletions, isEmpty);
      expect(auth.state.currentUser?.walletId, accessibilityUser().walletId);
      expect(auth.events, isEmpty);
      expect(find.text('authUnlockCanceled'.tr()), findsOneWidget);
    });

    testWidgets(
      'verified removal delegates the same review and closes after completion',
      (tester) async {
        final (access, wallets, auth) = await _pump(tester);
        await _open(tester);
        await _submitPassword(tester, 'synthetic-removal-password');
        expect(
          access.deletionProofs.single.$1.name,
          accessibilityUser().walletId.name,
        );
        expect(
          wallets.deletions.single.$1.name,
          accessibilityUser().walletId.name,
        );
        expect(wallets.deletions.single.$2, 'synthetic-removal-password');
        expect(identical(wallets.deletions.single.$3, wallets.review), isTrue);
        expect(find.byType(WalletDeleting), findsNothing);
        expect(find.byKey(const Key('settings-delete-wallet')), findsNothing);
        expect(auth.state.currentUser, isNull);
        expect(
          auth.events,
          isEmpty,
          reason: 'widgets must not preemptively sign out',
        );
      },
    );

    testWidgets(
      'committed removal closes the review and explains remaining settings cleanup',
      (tester) async {
        final (_, wallets, auth) = await _pump(tester);
        wallets.metadataCleanupFailed = true;
        await _open(tester);
        await _submitPassword(tester, 'synthetic-removal-password');
        expect(wallets.deletions, hasLength(1));
        expect(find.byType(WalletDeleting), findsNothing);
        expect(find.byType(UiPrimaryButton), findsNothing);
        expect(find.byKey(const Key('settings-delete-wallet')), findsNothing);
        expect(
          find.text('authWalletRemovedSettingsPending'.tr()),
          findsOneWidget,
        );
        expect(find.text('passwordNotAccepted'.tr()), findsNothing);
        expect(auth.state.currentUser, isNull);
        expect(auth.events, isEmpty);
      },
    );
  });
}

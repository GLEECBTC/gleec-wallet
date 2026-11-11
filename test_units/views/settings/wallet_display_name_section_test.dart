import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/views/settings/widgets/security_settings/wallet_display_name_section.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_list_item.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_login.dart';

import '../../support/legal_onboarding_harness.dart';

class _RenameAccess extends Fake implements WalletAccessService {
  final renamed = <(WalletId, String, String?)>[];
  WalletAccessFailure? failure;
  @override
  Future<WalletAccessStatus> status({WalletId? walletId}) async =>
      const WalletAccessStatus(
        entryId: 'immutable-entry',
        protection: CredentialProtection.authenticationBound,
        hasManagedCredential: true,
        requiresAuthentication: true,
        generatedPassword: true,
      );
  @override
  Future<WalletAccessStatus> statusForWallet(Wallet wallet) => status();
  @override
  Future<void> renameDisplayName({
    required WalletId walletId,
    required String name,
    String? password,
  }) async {
    if (failure != null) throw WalletAccessException(failure!);
    renamed.add((walletId, name, password));
  }
}

KdfUser _user() => KdfUser(
  walletId: WalletId.withPubkeyHash(
    'Gleec Wallet',
    const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
    'synthetic-identity',
  ),
  isBip39Seed: true,
  metadata: const {'type': 'hdwallet', 'display_name': 'Holiday wallet'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Wallet display name', () {
    setUpAll(() async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
    });
    tearDown(() => Localization.load(const Locale('en')));

    testWidgets(
      'managed wallet renames without exposing or typing its password',
      (tester) async {
        final harness = LegalFormHarness();
        final access = _RenameAccess();
        final user = _user();
        // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
        harness.auth.emit(AuthBlocState.loggedIn(user));
        await harness.pump(
          tester,
          RepositoryProvider<WalletAccessService>.value(
            value: access,
            child: const WalletDisplayNameSection(),
          ),
        );
        expect(find.text('Holiday wallet'), findsOneWidget);
        expect(find.byType(TextFormField), findsNothing);
        await tester.tap(find.byKey(const Key('rename-wallet')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('wallet-display-name-input')),
          'Travel savings',
        );
        await tester.tap(find.byKey(const Key('save-wallet-display-name')));
        await tester.pumpAndSettle();
        expect(access.renamed, [(user.walletId, 'Travel savings', null)]);
        expect(user.walletId.name, 'Gleec Wallet');
        expect(user.walletId.pubkeyHash, 'synthetic-identity');
        expect(find.text('Travel savings'), findsOneWidget);
        expect(
          find.byKey(const Key('confirmation-showing-seed-phrase')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'empty name is rejected and canceled authorization preserves label',
      (tester) async {
        final harness = LegalFormHarness();
        final access = _RenameAccess()..failure = WalletAccessFailure.canceled;
        // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
        harness.auth.emit(AuthBlocState.loggedIn(_user()));
        await harness.pump(
          tester,
          RepositoryProvider<WalletAccessService>.value(
            value: access,
            child: const WalletDisplayNameSection(),
          ),
        );
        await tester.tap(find.byKey(const Key('rename-wallet')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('wallet-display-name-input')),
          '  ',
        );
        await tester.tap(find.byKey(const Key('save-wallet-display-name')));
        await tester.pumpAndSettle();
        expect(access.renamed, isEmpty);
        expect(find.text('authRenameWalletNameRequired'.tr()), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('wallet-display-name-input')),
          'New name',
        );
        await tester.tap(find.byKey(const Key('save-wallet-display-name')));
        await tester.pumpAndSettle();
        expect(find.text('authUnlockCanceled'.tr()), findsOneWidget);
        expect(access.renamed, isEmpty);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('Holiday wallet'), findsOneWidget);
      },
    );

    for (final failure in [
      WalletAccessFailure.invalidName,
      WalletAccessFailure.nameAlreadyUsed,
    ]) {
      testWidgets('reports $failure without changing the visible name', (
        tester,
      ) async {
        final harness = LegalFormHarness();
        final access = _RenameAccess()..failure = failure;
        // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
        harness.auth.emit(AuthBlocState.loggedIn(_user()));
        await harness.pump(
          tester,
          RepositoryProvider<WalletAccessService>.value(
            value: access,
            child: const WalletDisplayNameSection(),
          ),
        );
        await tester.tap(find.byKey(const Key('rename-wallet')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('wallet-display-name-input')),
          'Already used',
        );
        await tester.tap(find.byKey(const Key('save-wallet-display-name')));
        await tester.pumpAndSettle();
        expect(
          find.text(
            (failure == WalletAccessFailure.invalidName
                    ? 'authRenameWalletNameInvalid'
                    : 'authRenameWalletNameUsed')
                .tr(),
          ),
          findsOneWidget,
        );
        expect(access.renamed, isEmpty);
      });
    }

    testWidgets(
      'wallet selection uses display label while preserving selected identity',
      (tester) async {
        final harness = LegalFormHarness();
        final wallet = _user().wallet;
        Wallet? selected;
        await harness.pump(
          tester,
          WalletListItem(
            wallet: wallet,
            onClick: (value, _) => selected = value,
          ),
        );
        expect(find.text('Holiday wallet'), findsOneWidget);
        await tester.tap(find.text('Holiday wallet'));
        expect(selected, same(wallet));
        expect(selected!.name, 'Gleec Wallet');
      },
    );

    testWidgets(
      'managed login displays the label and submits the original wallet',
      (tester) async {
        final harness = LegalFormHarness();
        final wallet = _user().wallet;
        await harness.pump(
          tester,
          RepositoryProvider<WalletAccessService>.value(
            value: _RenameAccess(),
            child: WalletLogIn(
              wallet: wallet,
              onLogin: (_, _, _) {},
              onCancel: () {},
            ),
          ),
        );
        expect(find.text('Holiday wallet'), findsOneWidget);
        await tester.tap(find.byKey(const Key('managed-wallet-unlock')));
        await tester.pumpAndSettle();
        final event = harness.auth.events
            .whereType<AuthManagedSignInRequested>()
            .single;
        expect(event.wallet, same(wallet));
        expect(event.wallet.name, 'Gleec Wallet');
      },
    );
  });
}

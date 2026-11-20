import 'package:easy_localization/easy_localization.dart';
// Reset translations after the shared harness loads the real English strings.
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/model/wallets_manager_models.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_list_item.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallets_list.dart';

import '../../../support/legal_onboarding_harness.dart';

Wallet _wallet(String name) => Wallet(
  id: name,
  name: name,
  config: WalletConfig(
    seedPhrase: '',
    activatedCoins: const [],
    hasBackup: false,
    type: WalletType.hdwallet,
    provenance: WalletProvenance.generated,
    createdAt: DateTime.utc(2026, 10, 2),
  ),
);

void main() {
  setUpAll(() async {
    // The analyzer does not recognize the test_units directory as test code.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  tearDown(() => Localization.load(const Locale('en')));

  final menu = find.byKey(const Key('wallet-list-item-menu'));
  final remove = find.byKey(const Key('wallet-list-item-remove'));

  testWidgets(
    'the row opens the wallet and removal is one labelled menu away',
    (tester) async {
      final actions = <WalletsManagerExistWalletAction>[];
      await LegalFormHarness().pump(
        tester,
        WalletListItem(
          wallet: _wallet('Everyday wallet'),
          onClick: (_, action) => actions.add(action),
        ),
      );
      // Opening is the visible action; the tag is localised.
      expect(find.byIcon(UiListActionRow.defaultTrailingIcon), findsOneWidget);
      expect(find.text('authWalletTagGenerated'.tr()), findsOneWidget);
      await tester.tap(find.text('Everyday wallet'));
      expect(actions, [WalletsManagerExistWalletAction.logIn]);

      expect(find.byTooltip('authWalletOptions'.tr()), findsOneWidget);
      expect(tester.getSize(menu).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(menu).height, greaterThanOrEqualTo(48));
      expect(remove, findsNothing);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      // Opening the menu neither opens nor removes the wallet.
      expect(actions, hasLength(1));
      expect(find.text('authRemoveFromThisDevice'.tr()), findsOneWidget);
      expect(tester.getSize(remove).height, greaterThanOrEqualTo(48));
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(actions, [
        WalletsManagerExistWalletAction.logIn,
        WalletsManagerExistWalletAction.delete,
      ]);
    },
    // Desktop themes default to a compact icon button.
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.macOS,
    }),
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'rows grow and tags wrap at 320 dp and 200% text ($brightness)',
      (tester) async {
        await LegalFormHarness().pump(
          tester,
          WalletsList(
            walletType: WalletType.iguana,
            wallets: [_wallet('Everyday wallet'), _wallet('Savings')],
            onWalletClick: (_, _) {},
          ),
          size: const Size(320, 568),
          textScale: 2,
          brightness: brightness,
        );
        expect(tester.takeException(), isNull);
        final row = find.byType(WalletListItem).first;
        expect(tester.getSize(row).height, greaterThan(68));
        // Still one tap from opening, with its menu and chevron in view.
        expect(
          find.descendant(of: row, matching: menu).hitTestable(),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: row,
            matching: find.byIcon(UiListActionRow.defaultTrailingIcon),
          ),
          findsOneWidget,
        );
      },
    );
  }
}

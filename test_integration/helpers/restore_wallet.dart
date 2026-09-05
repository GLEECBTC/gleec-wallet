// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart'
    show MnemonicValidator;
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/model/wallet.dart';

import '../common/widget_tester_action_extensions.dart';
import '../common/widget_tester_pump_extension.dart';
import 'connect_wallet.dart';
import 'get_funded_wif.dart';

Future<void> restoreWalletToTest(WidgetTester tester) async {
  print('🔍 RESTORE WALLET: Starting wallet restoration test');

  final validator = MnemonicValidator();
  await validator.init();

  // Restores wallet to be used in following tests
  final String testSeed = getFundedWif();
  const String walletName = 'my-wallet';
  const String password = 'pppaaasssDDD555444@@@';
  final Finder importWalletButton = find.byKey(
    const Key('import-wallet-button'),
  );
  final Finder nameField = find.byKey(const Key('name-wallet-field'));
  final Finder passwordField = find.byKey(const Key('create-password-field'));
  final Finder passwordConfirmField = find.byKey(
    const Key('create-password-field-confirm'),
  );
  final Finder importSeedField = find.byKey(const Key('import-seed-field'));
  final Finder importConfirmButton = find.byKey(
    const Key('confirm-seed-button'),
  );
  final Finder walletsManagerWrapper = find.byKey(
    const Key('wallets-manager-wrapper'),
  );
  final Finder allowCustomSeedCheckbox = find.byKey(
    const Key('checkbox-custom-seed'),
  );
  final Finder customSeedDialogInput = find.byKey(
    const Key('custom-seed-dialog-input'),
  );
  final Finder customSeedDialogOkButton = find.byKey(
    const Key('custom-seed-dialog-ok-button'),
  );
  const String confirmCustomSeedText = 'I Understand';

  await tester.pumpAndSettle();
  print('🔍 RESTORE WALLET: Connecting wallet');
  isMobile
      ? await tapOnMobileConnectWallet(tester, WalletType.iguana)
      : await tapOnAppBarConnectWallet(tester, WalletType.iguana);

  print('🔍 RESTORE WALLET: Tapping import wallet button');
  await tester.ensureVisible(importWalletButton);
  await tester.tap(importWalletButton);
  await tester.pumpAndSettle();

  print('🔍 RESTORE WALLET: Entering wallet details');
  await tester.tapAndPump(nameField);
  await tester.enterText(nameField, walletName);
  await tester.enterText(importSeedField, testSeed);
  await tester.pump();

  // A custom seed is anything that is NOT a valid BIP39 mnemonic - a WIF key
  // from `getFundedWif()` is exactly that. The app only renders the
  // custom-seed toggle in that case (`_shouldShowCustomSeedToggle` in
  // wallet_simple_import.dart), and without confirming it `_allowCustomSeed`
  // stays false, seed validation fails, and the confirm button never enables.
  final isCustomSeed = !validator.validateBip39(testSeed);

  if (isCustomSeed) {
    print('🔍 RESTORE WALLET: Handling custom seed input');
    await tester.tapAndPump(allowCustomSeedCheckbox);
    await tester.enterText(customSeedDialogInput, confirmCustomSeedText);
    await tester.pumpNFrames(5);
    await tester.tapAndPump(customSeedDialogOkButton);
  }

  print('🔍 RESTORE WALLET: Confirming wallet creation');
  await tester.dragUntilVisible(
    importConfirmButton,
    walletsManagerWrapper,
    const Offset(0, -15),
  );
  await tester.pumpNFrames(10);
  await tester.tapAndPump(importConfirmButton);

  print('🔍 RESTORE WALLET: Setting up password');
  await tester.enterText(passwordField, password);
  await tester.enterText(passwordConfirmField, password);
  await tester.dragUntilVisible(
    importConfirmButton,
    walletsManagerWrapper,
    const Offset(0, -15),
  );
  await tester.pumpNFrames(10);
  await tester.tap(importConfirmButton);

  print('🔍 RESTORE WALLET: Waiting for completion');
  await tester.pumpUntilDisappear(walletsManagerWrapper);
  print('🔍 RESTORE WALLET: Wallet restoration completed');
}

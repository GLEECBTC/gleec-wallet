// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/main.dart' as app;
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/views/common/header/actions/account_switcher.dart';

import '../../common/widget_tester_action_extensions.dart';
import '../../common/widget_tester_pump_extension.dart';
import '../../helpers/accept_alpha_warning.dart';
import '../../helpers/connect_wallet.dart';

Future<void> testCreateWallet(WidgetTester tester) async {
  print('🔍 CREATE WALLET: Starting wallet creation test');

  final Finder createWalletButton = find.byKey(
    const Key('create-wallet-button'),
  );
  final Finder walletsManagerWrapper = find.byKey(
    const Key('wallets-manager-wrapper'),
  );

  print('🔍 CREATE WALLET: Connecting wallet');
  isMobile
      ? await tapOnMobileConnectWallet(tester, WalletType.iguana)
      : await tapOnAppBarConnectWallet(tester, WalletType.iguana);

  // One application action creates a durable wallet with generated details.
  // The entry records legal acceptance; no creation form is required.
  expect(createWalletButton, findsOneWidget);
  final auth = tester.element(createWalletButton).read<AuthBloc>();
  expect(find.byKey(const Key('name-wallet-field')), findsNothing);
  expect(find.byKey(const Key('create-password-field')), findsNothing);
  await tester.tapAndPump(createWalletButton);
  await tester.pumpUntilDisappear(walletsManagerWrapper);

  final user = auth.state.currentUser;
  expect(user, isNotNull);
  expect(user!.walletId.name, isNotEmpty);
  expect(user.walletId.pubkeyHash, isNotEmpty);
  expect(find.byKey(const Key('create-password-field')), findsNothing);
  if (!isMobile) {
    expect(
      find.widgetWithText(AccountSwitcher, user.wallet.displayName),
      findsOneWidget,
    );
  }
  print('🔍 CREATE WALLET: Wallet creation completed');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Run Wallet Creation tests:', (WidgetTester tester) async {
    print('🔍 WALLET TESTS: Starting wallet creation test suite');
    tester.testTextInput.register();
    await app.main();
    await tester.pumpAndSettle();

    print('🔍 WALLET TESTS: Accepting alpha warning');
    await acceptAlphaWarning(tester);

    print('🔍 WALLET TESTS: Running wallet creation test');
    await testCreateWallet(tester);
    await tester.pumpAndSettle();

    print('🔍 WALLET TESTS: All wallet creation tests completed');
  }, semanticsEnabled: false);
}

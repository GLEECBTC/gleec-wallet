// ignore_for_file: avoid_print

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_dex/main.dart' as app;
import 'package:web_dex/views/fiat/fiat_payment_method_card.dart';

import '../../common/widget_tester_action_extensions.dart';
import '../../helpers/accept_alpha_warning.dart';
import '../../helpers/restore_wallet.dart';

Future<void> testFiatFormInputs(
  WidgetTester tester, {
  String provider = 'Banxa',
  bool submitOrder = false,
}) async {
  print('🔍 FIAT FORM TEST: Starting fiat form test');
  final Finder fiatFinder = find.byKey(const Key('main-menu-fiat'));

  await tester.tap(fiatFinder);
  print('🔍 FIAT FORM TEST: Tapped fiat menu item');
  // wait for fiat form to load fiat currencies, coin list, and payment methods
  await tester.pumpAndSettle();

  await _testFiatAmountField(tester);
  await _testPaymentMethodSelection(tester, provider, fiat: 'USD', coin: 'BTC');
  await _testFiatSelection(tester);
  await _testPaymentMethodSelection(tester, provider, fiat: 'EUR', coin: 'BTC');
  await _testCoinSelection(tester);
  await _testPaymentMethodSelection(tester, provider, fiat: 'EUR', coin: 'LTC');
  // Creating a provider order is separate from the read-only quote gate.
  // The explicit checkout target preserves that check for a supervised run.
  if (submitOrder) await _testSubmit(tester);
}

Future<void> _testSubmit(WidgetTester tester) async {
  print('🔍 FIAT FORM TEST: Testing form submission');
  final Finder submitFinder = find.byKey(
    const Key('fiat-onramp-submit-button'),
  );
  final Finder webviewFinder = find.byKey(const Key('flutter-in-app-webview'));

  expect(submitFinder, findsOneWidget, reason: 'Submit button not found');
  await tester.tap(submitFinder);
  print('🔍 FIAT FORM TEST: Tapped submit button');
  await tester.pumpAndSettle();
  expect(webviewFinder, findsOneWidget, reason: 'Webview not found');
  print('🔍 FIAT FORM TEST: Verified webview loaded');
}

Future<void> _testFiatAmountField(WidgetTester tester) async {
  print('🔍 FIAT FORM TEST: Testing fiat amount field');
  final Finder fiatAmountFinder = find.byKey(
    const Key('fiat-amount-form-field'),
  );

  await tester.tapAndPump(fiatAmountFinder);
  await tester.enterText(fiatAmountFinder, '50');
  print('🔍 FIAT FORM TEST: Entered fiat amount: 50');
  await tester.pump();
  await tester.pumpAndSettle(); // wait for payment methods to populate
}

Future<void> _testFiatSelection(WidgetTester tester) async {
  print('🔍 FIAT FORM TEST: Testing fiat currency selection');
  final Finder fiatDropdownFinder = find.byKey(
    const Key('fiat-onramp-fiat-dropdown'),
  );
  final Finder usdIconFinder = find.byKey(
    const Key('fiat-onramp-currency-item-USD'),
  );
  final Finder eurIconFinder = find.byKey(
    const Key('fiat-onramp-currency-item-EUR'),
  );

  await tester.tapAndPump(fiatDropdownFinder);
  expect(usdIconFinder, findsOneWidget, reason: 'USD icon not found');
  expect(eurIconFinder, findsOneWidget, reason: 'EUR icon not found');
  print('🔍 FIAT FORM TEST: Verified USD and EUR options');
  await tester.tapAndPump(eurIconFinder);
  print('🔍 FIAT FORM TEST: Selected EUR');
  await tester.pumpAndSettle(); // wait for payment methods to populate
}

Future<void> _testCoinSelection(WidgetTester tester) async {
  print('🔍 FIAT FORM TEST: Testing coin selection');
  final Finder coinDropdownFinder = find.byKey(
    const Key('fiat-onramp-coin-dropdown'),
  );
  final Finder btcIconFinder = find.byKey(
    const Key('fiat-onramp-currency-item-BTC'),
  );
  final Finder ltcIconFinder = find.byKey(
    const Key('fiat-onramp-currency-item-LTC'),
  );

  await tester.tapAndPump(coinDropdownFinder);
  expect(btcIconFinder, findsOneWidget, reason: 'BTC icon not found');
  print('🔍 FIAT FORM TEST: Verified BTC option');
  await _tapCurrencyItem(tester, ltcIconFinder);
  print('🔍 FIAT FORM TEST: Selected LTC');
  await tester.pumpAndSettle(); // wait for payment methods to populate
}

Future<void> _tapCurrencyItem(WidgetTester tester, Finder asset) async {
  print('🔍 FIAT FORM TEST: Tapping currency item');
  final Finder list = find.byKey(const Key('fiat-onramp-currency-list'));
  final Finder dialog = find.byKey(const Key('fiat-onramp-currency-dialog'));

  expect(
    dialog,
    findsOneWidget,
    reason: 'Fiat onramp currency dialog not found',
  );
  expect(list, findsOneWidget, reason: 'Fiat onramp currency list not found');
  print('🔍 FIAT FORM TEST: Verified currency dialog and list');
  await tester.dragUntilVisible(asset, list, const Offset(0, -50));
  await tester.pumpAndSettle();
  await tester.tapAndPump(asset);
}

Future<void> _testPaymentMethodSelection(
  WidgetTester tester,
  String provider, {
  required String fiat,
  required String coin,
}) async {
  final methodFinder = find.byKey(
    Key('fiat-payment-method-${provider.toLowerCase()}-0'),
  );
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  // A default method card can exist before its network quote. Wait for the
  // requested currencies and amount, rather than accepting a placeholder or
  // the previous selection's quote. Never require the other provider.
  while (true) {
    await tester.pump(const Duration(milliseconds: 250));
    if (tester.any(methodFinder)) {
      final card = tester.widget<FiatPaymentMethodCard>(methodFinder);
      final method = card.paymentMethodData;
      final price = method.priceInfo;
      if (method.providerId == provider &&
          price.fiatCode == fiat &&
          price.coinCode == coin &&
          price.fiatAmount == Decimal.fromInt(50) &&
          price.coinAmount > Decimal.zero &&
          price.spotPriceIncludingFee > Decimal.zero) {
        await tester.tapAndPump(methodFinder);
        final selected = tester
            .widget<FiatPaymentMethodCard>(methodFinder)
            .selectedPaymentMethod;
        expect(selected?.providerId, provider);
        expect(selected?.id, method.id);
        print('Verified $provider $fiat 50 -> $coin quote and selection');
        return;
      }
    }
    if (!DateTime.now().isBefore(deadline)) {
      throw TestFailure(
        '$provider did not render a usable $fiat 50 -> $coin quote within 45s. '
        'Check its payment-method and price responses on fiat-ramps.gleec.com; '
        'a placeholder, zero amount or stale quote is not a passing result.',
      );
    }
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Run fiat form tests:', (WidgetTester tester) async {
    tester.testTextInput.register();
    await app.main();
    await tester.pumpAndSettle();
    await acceptAlphaWarning(tester);
    await restoreWalletToTest(tester);
    await testFiatFormInputs(tester);

    print('END fiat form TESTS');
  }, semanticsEnabled: false);
}

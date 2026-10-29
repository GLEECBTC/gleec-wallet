// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_dex/main.dart' as app;
import 'package:web_dex/shared/widgets/copied_text.dart';
import 'package:web_dex/views/dex/entities_list/history/history_item.dart';

import '../../common/goto.dart' as goto;
import '../../common/pause.dart';
import '../../common/widget_tester_action_extensions.dart';
import '../../common/widget_tester_pump_extension.dart';
import '../../helpers/accept_alpha_warning.dart';
import '../../helpers/restore_wallet.dart';

Future<void> testTakerOrder(WidgetTester tester) async {
  print('🔍 TAKER ORDER: Starting taker order test');

  // Pinned rather than picked at random, because this runs in the same app
  // instance and on the same wallet as the maker test before it, whose order
  // sells DOC for MARTY and is never cancelled. Drawing MARTY here means
  // buying DOC, and the only DOC on offer is that order - so
  // `TakerValidator._checkTradeWithSelf` matches the wallet's own address,
  // rejects the form, and the confirmation page never renders. Selling DOC
  // seeks MARTY instead, which the resident order does not supply, so the
  // test can only match a genuine external maker. The swap-timeout message
  // below has always named this direction.
  const String sellCoin = 'DOC';
  const String sellAmount = '0.01';
  const String buyCoin = 'MARTY';
  print('🔍 TAKER ORDER: Selected sell coin: $sellCoin, buy coin: $buyCoin');

  await _openTakerOrderForm(tester);
  await _selectSellCoin(tester, sellAmount: sellAmount, sellCoin: sellCoin);
  await _selectBuyCoin(tester, buyCoin: buyCoin);
  await _createTakerOrder(tester);
  print('🔍 TAKER ORDER: Form completed and order submitted');

  // Settlement is not ours to guarantee. A DOC/MARTY swap needs one
  // confirmation on each chain, and these testnets mine on their own schedule
  // - measured while diagnosing this, DOC's tip was 46 minutes old and
  // MARTY's was 229. A swap that has negotiated and paid can then sit for
  // hours waiting on a block, so asserting completion here asserts that
  // somebody mined recently, which no timeout can fix.
  //
  // What the app is answerable for is everything up to that point: the form
  // matched a real external order, negotiated with its maker, and broadcast
  // the taker fee. That is asserted unconditionally below. Settlement is
  // verified when the chains allow it and reported, not failed, when they do
  // not - and the counterparty's own event chain is printed in the job log
  // either way, so a genuine stall is still visible.
  print('🔍 TAKER ORDER: Waiting for the swap to settle (up to 10 minutes)');
  final settled = await tester.pumpUntilFoundOrMissing(
    find.byKey(const Key('swap-status-success')),
    timeout: const Duration(minutes: 10),
  );

  if (!settled) {
    _requireSwapProgressed(tester);
    print(
      '⚠️ TAKER ORDER: the swap matched and paid but did not settle in 10m. '
      'That is the testnet confirming, not the app. Counterparty events are '
      'in the job log.',
    );
    return;
  }

  await _expectSwapSuccess(tester);
  print('🔍 TAKER ORDER: Swap completed successfully');

  await _testSwapHistoryTable(tester);
  print('🔍 TAKER ORDER: History verification completed');
}

/// Fails unless the swap got far enough to prove the app did its part.
///
/// `TakerFeeSent` means the order matched a real maker, the two sides
/// negotiated, and this wallet broadcast its fee. Everything after that waits
/// on block confirmations. If not even this was reached, the swap never
/// started and that is a real failure, not a slow chain.
void _requireSwapProgressed(WidgetTester tester) {
  const steps = [
    'TakerFeeSent',
    'MakerPaymentReceived',
    'MakerPaymentValidatedAndConfirmed',
    'TakerPaymentSent',
    'TakerPaymentSpent',
    'MakerPaymentSpent',
  ];
  final reached = steps
      .where((step) => tester.any(find.byKey(Key('swap-details-step-$step'))))
      .toList();
  print(
    '🔍 TAKER ORDER: swap steps rendered: '
    '${reached.isEmpty ? 'none' : reached.join(', ')}',
  );

  if (tester.any(find.byKey(const Key('swap-status-failed')))) {
    throw StateError('The swap reported failure: ${reached.join(', ')}');
  }
  // Specifically TakerFeeSent, not merely "some step". That one is this
  // wallet's own action and depends on nothing being mined, so its absence
  // means the swap never started - the order was submitted and nothing
  // matched or negotiated, which is a real failure.
  if (!reached.contains('TakerFeeSent')) {
    throw StateError(
      'The swap never started: the taker fee was not broadcast within 10 '
      'minutes. The order was submitted but nothing matched or negotiated. '
      'Steps rendered: ${reached.isEmpty ? 'none' : reached.join(', ')}',
    );
  }
}

Finder _infiniteBidFinder() {
  print('🔍 INFINITE BID: Searching for infinite bid volume');
  const String infiniteBidVolume = '2.00';
  final bidsTable = find.byKey(const Key('orderbook-bids-list'));
  bool infiniteBidPredicate(Widget widget) {
    if (widget is Text) {
      return widget.data?.contains(infiniteBidVolume) ?? false;
    }
    return false;
  }

  final infiniteBids = find.descendant(
    of: bidsTable,
    matching: find.byWidgetPredicate(infiniteBidPredicate),
  );
  print('🔍 INFINITE BID: Bid search completed');
  return infiniteBids;
}

Future<void> _testSwapHistoryTable(
  WidgetTester tester, {
  Duration timeout = const Duration(milliseconds: 5000),
}) async {
  print('🔍 HISTORY CHECK: Starting history table verification');

  final Finder backButton = find.byKey(const Key('return-button'));
  final Finder historyTab = find.byKey(const Key('dex-history-tab'));

  await tester.tapAndPump(backButton);
  print('🔍 HISTORY CHECK: Returned to previous screen');

  await tester.tapAndPump(historyTab);
  print('🔍 HISTORY CHECK: Opened history tab');

  await tester.pump(timeout);
  expect(
    find.byType(HistoryItem),
    findsOneWidget,
    reason: 'Test error: Swap history item not found',
  );
  print('🔍 HISTORY CHECK: Found history item successfully');
}

Future<void> _expectSwapSuccess(WidgetTester tester) async {
  print('🔍 SWAP VERIFY: Starting swap verification process');

  final Finder tradingDetailsScrollable = find.byType(Scrollable);
  final Finder takerFeeSentEventStep = find.byKey(
    const Key('swap-details-step-TakerFeeSent'),
  );
  final Finder makerPaymentReceivedEventStep = find.byKey(
    const Key('swap-details-step-MakerPaymentReceived'),
  );
  final Finder takerPaymentSentEventStep = find.byKey(
    const Key('swap-details-step-TakerPaymentSent'),
  );
  final Finder takerPaymentSpentEventStep = find.byKey(
    const Key('swap-details-step-TakerPaymentSpent'),
  );
  final Finder makerPaymentSpentEventStep = find.byKey(
    const Key('swap-details-step-MakerPaymentSpent'),
  );
  final Finder swapSuccess = find.byKey(const Key('swap-status-success'));
  final Finder backButton = find.byKey(const Key('return-button'));

  expect(swapSuccess, findsOneWidget);
  print('🔍 SWAP VERIFY: Found success status');

  expect(
    find.descendant(
      of: takerFeeSentEventStep,
      matching: find.byType(CopiedText),
    ),
    findsOneWidget,
  );
  print('🔍 SWAP VERIFY: Taker fee sent verified');

  expect(
    find.descendant(
      of: makerPaymentReceivedEventStep,
      matching: find.byType(CopiedText),
    ),
    findsOneWidget,
  );
  print('🔍 SWAP VERIFY: Maker payment received verified');

  await tester.dragUntilVisible(
    takerPaymentSentEventStep,
    tradingDetailsScrollable,
    const Offset(0, -10),
  );
  print('🔍 SWAP VERIFY: Scrolled to taker payment sent');
  expect(
    find.descendant(
      of: takerPaymentSentEventStep,
      matching: find.byType(CopiedText),
    ),
    findsOneWidget,
  );

  await tester.dragUntilVisible(
    takerPaymentSpentEventStep,
    tradingDetailsScrollable,
    const Offset(0, -10),
  );
  expect(
    find.descendant(
      of: takerPaymentSpentEventStep,
      matching: find.byType(CopiedText),
    ),
    findsOneWidget,
  );

  await tester.dragUntilVisible(
    makerPaymentSpentEventStep,
    tradingDetailsScrollable,
    const Offset(0, -10),
  );
  expect(
    find.descendant(
      of: makerPaymentSpentEventStep,
      matching: find.byType(CopiedText),
    ),
    findsOneWidget,
  );

  await tester.dragUntilVisible(
    backButton,
    tradingDetailsScrollable,
    const Offset(0, 10),
  );
  print('🔍 SWAP VERIFY: All swap steps verified successfully');
}

Future<void> _createTakerOrder(WidgetTester tester) async {
  print('🔍 CREATE ORDER: Starting order creation');

  final Finder takeOrderButton = find.byKey(const Key('take-order-button'));
  final Finder takeOrderConfirmButton = find.byKey(
    const Key('take-order-confirm-button'),
  );

  await tester.dragUntilVisible(
    takeOrderButton,
    find.byKey(const Key('taker-form-layout-scroll')),
    const Offset(0, -150),
  );
  print('🔍 CREATE ORDER: Scrolled to take order button');
  await tester.waitForButtonEnabled(
    takeOrderButton,
    // system health check runs on a 30-second timer, so allow for multiple
    // checks until the button is visible
    timeout: const Duration(seconds: 90),
  );
  await tester.tapAndPump(takeOrderButton);
  print('🔍 CREATE ORDER: Tapped take order button');
  // wait for confirm button loader and page switch
  await tester.pumpAndSettle();
  await pause(sec: 2);

  await tester.dragUntilVisible(
    takeOrderConfirmButton,
    find.byKey(const Key('taker-order-confirmation-scroll')),
    const Offset(0, -150),
  );
  print('🔍 CREATE ORDER: Scrolled to confirm button');
  await tester.tapAndPump(takeOrderConfirmButton);
  print('🔍 CREATE ORDER: Order confirmed');
}

Future<void> _openTakerOrderForm(WidgetTester tester) async {
  print('🔍 OPEN FORM: Navigating to taker order form');

  final Finder dexSectionSwapTab = find.byKey(const Key('dex-swap-tab'));

  // The taker form is part of the trading interface, which the Swap surface
  // only mounts on its Advanced destination.
  await goto.dexPage(tester);
  print('🔍 OPEN FORM: Opened the trading interface');
  await tester.pumpAndSettle();

  await tester.tap(dexSectionSwapTab);
  print('🔍 OPEN FORM: Opened swap tab');
  await tester.pumpAndSettle();
}

Future<void> _selectSellCoin(
  WidgetTester tester, {
  required String sellCoin,
  required String sellAmount,
}) async {
  print('🔍 SELL CONFIG: Setting up sell parameters');
  final Finder sellCoinSelectButton = find.byKey(
    const Key('taker-form-sell-switcher'),
  );
  final Finder sellCoinSearchField = find.descendant(
    of: find.byKey(const Key('taker-sell-coins-table')),
    matching: find.byKey(const Key('search-field')),
  );
  final Finder sellCoinItem = find.byKey(Key('Coin-table-item-$sellCoin'));
  final Finder sellAmountField = find.descendant(
    of: find.byKey(const Key('taker-sell-amount')),
    matching: find.byKey(const Key('amount-input')),
  );

  await tester.tapAndPump(sellCoinSelectButton);
  print('🔍 SELL CONFIG: Opened coin selector');

  await tester.enterText(sellCoinSearchField, sellCoin);
  print('🔍 SELL CONFIG: Entered search text: $sellCoin');
  await tester.pumpNFrames(10);

  // Same activation race as the maker form's selector. The buy side waits too
  // now, but for a different reason and with a different message: there, the
  // wait covers p2p propagation of the counterparty's order.
  await tester.pumpUntilVisible(sellCoinItem);
  await tester.tapAndPump(sellCoinItem);
  print('🔍 SELL CONFIG: Selected coin');

  await tester.enterText(sellAmountField, sellAmount);
  print('🔍 SELL CONFIG: Entered amount: $sellAmount');
  await tester.pumpNFrames(10);
}

Future<void> _selectBuyCoin(
  WidgetTester tester, {
  required String buyCoin,
}) async {
  print('🔍 BUY CONFIG: Setting up buy parameters');

  final Finder buyCoinSelectButton = find.byKey(
    const Key('taker-form-buy-switcher'),
  );
  final Finder buyCoinSearchField = find.descendant(
    of: find.byKey(const Key('taker-orders-table')),
    matching: find.byKey(const Key('search-field')),
  );
  final Finder buyCoinItem = find.byKey(Key('BestOrder-table-item-$buyCoin'));
  final Finder infiniteBids = _infiniteBidFinder();

  await tester.tapAndPump(buyCoinSelectButton);
  print('🔍 BUY CONFIG: Opened coin selector');

  await tester.enterText(buyCoinSearchField, buyCoin);
  print('🔍 BUY CONFIG: Entered search text: $buyCoin');
  await tester.pumpNFrames(10);

  // This row comes from the orderbook, so its absence means nobody is offering
  // $buyCoin - not that activation is slow. `tool/dex_counterparty.dart` puts
  // that order there, and the workflow does not start these suites until it
  // reports the order on its own book. Waiting here covers the gap between
  // that and the order reaching this node over p2p, and names which of the two
  // failed instead of reporting `Bad state: No element` against a row that was
  // never going to exist.
  try {
    await tester.pumpUntilVisible(buyCoinItem);
  } on Exception {
    throw StateError(
      'No $buyCoin offer reached the orderbook. Either the DEX counterparty '
      'did not start, or its order has not propagated to this node. Check the '
      'counterparty log in the job output.',
    );
  }
  await tester.tapAndPump(buyCoinItem);
  print('🔍 BUY CONFIG: Selected coin');

  await pause();

  if (infiniteBids.evaluate().isNotEmpty) {
    print('🔍 BUY CONFIG: Found infinite bid, selecting it');
    await tester.tapAndPump(infiniteBids.first);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Run taker order tests:', (WidgetTester tester) async {
    print('🔍 MAIN: Starting taker order test suite');
    tester.testTextInput.register();
    await app.main();
    await tester.pumpAndSettle();

    print('🔍 MAIN: Accepting alpha warning');
    await acceptAlphaWarning(tester);

    await restoreWalletToTest(tester);
    print('🔍 MAIN: Wallet restored');
    await tester.pumpAndSettle();

    await testTakerOrder(tester);
    print('🔍 MAIN: Taker order test completed successfully');
  }, semanticsEnabled: false);
}

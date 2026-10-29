// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common/goto.dart' as goto;

/// Covers where the Swap menu entry lands and what it leaves reachable.
///
/// The surface builds only the selected destination, so arriving on the swap
/// form means the trading interface is genuinely absent from the tree rather
/// than merely hidden. That is the arrangement worth guarding: it is what
/// broke every DEX assertion in this suite when it shipped.
Future<void> testSwapDestinations(WidgetTester tester) async {
  print('TEST SWAP DESTINATIONS');

  final Finder shell = find.byKey(const Key('swap-shell'));
  final Finder swapForm = find.byKey(const Key('swap-amount'));
  final Finder tradingPage = find.byKey(const Key('dex-page'));

  await goto.swapPage(tester);
  expect(shell, findsOneWidget);
  expect(swapForm, findsOneWidget, reason: 'Swap is the landing destination');
  expect(tradingPage, findsNothing);

  // Demoting the trading interface is only acceptable while it stays one tap
  // away. `goto.dexPage` is the navigation the DEX suites now use, so this
  // covers their route without needing a counterparty on the book.
  await goto.dexPage(tester);
  expect(tradingPage, findsOneWidget, reason: 'Advanced mounts the DEX page');
  expect(swapForm, findsNothing);

  // The first widgets those suites reach for once they arrive. Asserting them
  // here means a navigation regression fails in a ten-minute suite rather
  // than a forty-minute one.
  expect(find.byKey(const Key('make-order-tab')), findsOneWidget);
  expect(find.byKey(const Key('dex-swap-tab')), findsOneWidget);

  await goto.swapFormDestination(tester);
  expect(swapForm, findsOneWidget, reason: 'Swap is reachable again');

  print('END SWAP DESTINATIONS TEST');
}

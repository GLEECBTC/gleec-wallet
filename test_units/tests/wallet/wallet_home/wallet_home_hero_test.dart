import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_balance_hero.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_quick_action.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_quick_actions.dart';

import 'wallet_home_harness.dart';

void main() {
  setUpAll(initWalletHomeLocalization);
  group('Wallet home balance', _heroCases);
  group('Wallet home quick actions', _quickActionCases);
}

BalanceHeroContent _hero({
  double? total = 1234.56,
  ({double amount, double percent})? change,
  bool hidden = false,
  VoidCallback? onToggleHidden,
  VoidCallback? onCopy,
}) => BalanceHeroContent(
  total: total,
  change: change,
  hidden: hidden,
  onToggleHidden: onToggleHidden ?? () {},
  onCopy: onCopy,
);

void _heroCases() {
  testWidgets('shows the total with the cents drawn apart', (tester) async {
    await pumpWalletHome(tester, _hero());

    expect(find.text(r'$1,234.56', findRichText: true), findsOneWidget);
    expect(find.bySemanticsLabel(r'$1,234.56'), findsOneWidget);
  });

  testWidgets('shows a rise with its sign, arrow and period', (tester) async {
    await pumpWalletHome(tester, _hero(change: (amount: 12.3, percent: 1.234)));

    expect(find.text(r'+$12.30 (+1.23%)'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    expect(find.text('24h'), findsOneWidget);
  });

  testWidgets('shows a fall with a minus, not by colour alone', (tester) async {
    await pumpWalletHome(tester, _hero(change: (amount: -5, percent: -0.5)));

    expect(find.text('−\$5.00 (−0.50%)'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
  });

  testWidgets('invites a first deposit instead of a flat change', (
    tester,
  ) async {
    await pumpWalletHome(
      tester,
      _hero(total: 0, change: (amount: 0, percent: 0)),
    );

    expect(find.byKey(BalanceHeroContent.emptyHintKey), findsOneWidget);
    expect(find.text('Add crypto to get started'), findsOneWidget);
    expect(find.byKey(BalanceHeroContent.changeKey), findsNothing);
  });

  testWidgets('hides the amounts and offers to show them again', (
    tester,
  ) async {
    var toggled = 0;
    await pumpWalletHome(
      tester,
      _hero(
        hidden: true,
        change: (amount: 1, percent: 1),
        onToggleHidden: () => toggled++,
      ),
    );

    expect(find.text(r'$****'), findsOneWidget);
    expect(find.textContaining('1,234'), findsNothing);
    expect(find.byKey(BalanceHeroContent.changeKey), findsNothing);
    expect(find.byTooltip('Show balances'), findsOneWidget);

    await tester.tap(find.byKey(const Key('balance-summary-privacy-toggle')));
    expect(toggled, 1);
  });

  testWidgets('shows no number while the total is unknown', (tester) async {
    await pumpWalletHome(tester, _hero(total: null));

    expect(find.byKey(const Key('wallet-home-balance')), findsNothing);
    expect(find.textContaining(r'$'), findsNothing);
  });

  testWidgets('copies the total on a long press', (tester) async {
    var copies = 0;
    await pumpWalletHome(tester, _hero(onCopy: () => copies++));

    await tester.longPress(find.byKey(const Key('wallet-home-balance')));
    expect(copies, 1);
  });

  testWidgets('rolls to a new total, and jumps with reduced motion', (
    tester,
  ) async {
    final total = ValueNotifier<double>(100);
    addTearDown(total.dispose);
    Widget hero() => ValueListenableBuilder<double>(
      valueListenable: total,
      builder: (_, value, _) => _hero(total: value),
    );

    await pumpWalletHome(tester, hero());
    total.value = 200;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text(r'$200.00', findRichText: true), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text(r'$200.00', findRichText: true), findsOneWidget);

    await pumpWalletHome(tester, hero(), reduceMotion: true);
    total.value = 300;
    await tester.pump();
    expect(find.text(r'$300.00', findRichText: true), findsOneWidget);
  });
}

void _quickActionCases() {
  late MainMenuValue menuBefore;
  setUp(() => menuBefore = routingState.selectedMenu);
  tearDown(() => routingState.selectedMenu = menuBefore);

  testWidgets('offers Receive, Send, Swap and Buy, in that order', (
    tester,
  ) async {
    await pumpWalletHome(tester, const WalletQuickActions());

    final xs = [
      for (final action in WalletQuickAction.values)
        tester.getCenter(find.byKey(action.key)).dx,
    ];
    expect(xs, orderedEquals([...xs]..sort()));
    for (final label in ['Receive', 'Send', 'Swap', 'Buy']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('fills the highlighted action with the brand colour', (
    tester,
  ) async {
    await pumpWalletHome(
      tester,
      const WalletQuickActions(highlight: WalletQuickAction.receive),
    );

    Color? fill(WalletQuickAction action) => tester
        .widget<Material>(
          find
              .ancestor(
                of: find.byKey(action.key),
                matching: find.byType(Material),
              )
              .first,
        )
        .color;
    expect(fill(WalletQuickAction.receive), SwapPalette.dark.brand);
    expect(fill(WalletQuickAction.send), SwapPalette.dark.surface);
  });

  testWidgets('opens Swap and Buy in their tabs', (tester) async {
    await pumpWalletHome(tester, const WalletQuickActions());

    await tester.tap(find.byKey(WalletQuickAction.swap.key));
    expect(routingState.selectedMenu, MainMenuValue.dex);
    await tester.tap(find.byKey(WalletQuickAction.buy.key));
    expect(routingState.selectedMenu, MainMenuValue.fiat);
  });

  testWidgets('each action is a button a screen reader can press', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpWalletHome(tester, const WalletQuickActions());

    for (final label in ['Receive', 'Send', 'Swap', 'Buy']) {
      expect(
        tester.getSemantics(find.bySemanticsLabel(label)),
        isSemantics(
          label: label,
          isButton: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
    }
    semantics.dispose();
  });

  testWidgets('keeps a Trezor wallet to the wallet-only actions', (
    tester,
  ) async {
    await pumpWalletHome(
      tester,
      const WalletQuickActions(),
      auth: AuthBlocState.loggedIn(walletHomeUser(trezor: true)),
    );

    final before = routingState.selectedMenu;
    await tester.tap(find.byKey(WalletQuickAction.swap.key));
    await tester.tap(find.byKey(WalletQuickAction.buy.key));
    expect(routingState.selectedMenu, before);
    expect(
      find.byTooltip(
        'Trezor currently supports wallet-only mode. '
        'Trading features are disabled.',
      ),
      findsNWidgets(2),
    );
  });
}

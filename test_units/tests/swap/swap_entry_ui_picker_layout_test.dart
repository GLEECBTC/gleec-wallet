import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/pickers/swap_asset_picker.dart';

import 'swap_entry_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers how the picker fits the screen: its header pinned above the list
/// or scrolling with it, the end of the list clearing the keyboard, a row's
/// balance beside or under its title, and the zero-balance switch and a
/// pending activation as they change the list.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpSwapUi();

  late RecordingSwapBloc swap;
  late FakeSwapServices services;

  setUp(() {
    swap = RecordingSwapBloc();
    services = FakeSwapServices();
  });

  tearDown(() => swap.close());

  final tokens = [
    for (var i = 0; i < 12; i++) assetOf('TK$i-ERC20', parent: eth),
  ];
  final tokenCatalog = SwapCatalog(
    sources: [
      SwapSourceAssets(
        source: SwapLiquiditySource.routed,
        quotable: {eth, ...tokens},
      ),
    ],
  );

  SwapAssetPicker picker({
    SwapCatalog? catalog,
    AssetId? selected,
    AssetId? other,
  }) => SwapAssetPicker(
    side: SwapPickerSide.pay,
    catalog: catalog ?? swapTestCatalog,
    selected: selected,
    other: other,
    services: services,
    isBlocked: (_) => false,
  );

  group('the header', () {
    final search = find.byType(TextField);
    final list = find.byType(CustomScrollView);

    Future<double> searchMovesBy(WidgetTester tester) async {
      final before = tester.getTopLeft(search).dy;
      await tester.drag(list, const Offset(0, -150));
      await tester.pumpAndSettle();
      return before - tester.getTopLeft(search).dy;
    }

    Future<void> openLong(
      WidgetTester tester, {
      required Size size,
      double textScale = 1,
    }) async {
      services.activated = {eth, ...tokens};
      await openSwapRoute(
        tester,
        picker(catalog: tokenCatalog),
        bloc: swap,
        services: services,
        size: size,
        textScale: textScale,
      );
    }

    testWidgets('stays pinned above the list on a tall screen', (tester) async {
      await openLong(tester, size: const Size(420, 700));

      expect(find.descendant(of: list, matching: search), findsNothing);
      expect(await searchMovesBy(tester), 0);
    });

    for (final (name, size, scale) in [
      ('at larger text', const Size(420, 900), 1.5),
      ('on a short screen', const Size(420, 450), 1.0),
    ]) {
      testWidgets('scrolls with the list $name', (tester) async {
        await openLong(tester, size: size, textScale: scale);

        expect(find.descendant(of: list, matching: search), findsOneWidget);
        expect(await searchMovesBy(tester), greaterThan(0));
      });
    }
  });

  group('with the keyboard up', () {
    const keyboard = 336.0;

    bool searchFocused() =>
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<TextField>() !=
        null;

    /// Opens the picker in the app's sheet: the plain Scaffold route the other
    /// tests use shrinks for the keyboard, so it never covers the list there.
    Future<void> searchToTheEnd(
      WidgetTester tester, {
      required Size size,
      double top = 0,
      double textScale = 1,
      String query = 'TK',
    }) async {
      services.activated = {eth, ...tokens};
      await emitSwapState(
        tester,
        swap,
        swapBaseForm().copyWith(catalog: tokenCatalog),
      );
      tester.view.padding = FakeViewPadding(top: top);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewInsets);
      await pumpSwapUi(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showSwapAssetPicker(
              context: context,
              side: SwapPickerSide.pay,
              bloc: swap,
              selected: null,
              other: null,
              services: services,
              isBlocked: (_) => false,
            ),
            child: const Text('open'),
          ),
        ),
        bloc: swap,
        services: services,
        size: size,
        textScale: textScale,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), query);
      tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
      await tester.pumpAndSettle();
    }

    for (final (screen, size, top) in [
      ('375x812', const Size(375, 812), 0.0),
      ('390x844 under a notch', const Size(390, 844), 47.0),
    ]) {
      for (final textScale in [1.0, 2.0]) {
        testWidgets('on $screen at ${(textScale * 100).round()}% text, the '
            'last row scrolls above it and the search keeps focus', (
          tester,
        ) async {
          await searchToTheEnd(
            tester,
            size: size,
            top: top,
            textScale: textScale,
          );

          // Tickers sort as text, so TK9 is the last row.
          final lastRow = find
              .ancestor(of: find.text('TK9'), matching: find.byType(InkWell))
              .first;
          expect(
            tester.getRect(lastRow).bottom,
            lessThanOrEqualTo(size.height - keyboard),
          );
          expect(searchFocused(), isTrue);
        });
      }
    }

    testWidgets('a search that finds nothing can be cleared above it', (
      tester,
    ) async {
      const size = Size(375, 667);
      await searchToTheEnd(tester, size: size, top: 20, query: 'ZZZ');

      final clear = find
          .ancestor(
            of: find.text('Clear search'),
            matching: find.byType(TextButton),
          )
          .first;
      expect(
        tester.getRect(clear).bottom,
        lessThanOrEqualTo(size.height - keyboard),
      );
      expect(searchFocused(), isTrue);
    });
  });

  group('a row\'s balance', () {
    final ethOnArbitrum = assetOf(
      'ETH-ARB20',
      subClass: CoinSubClass.arbitrum,
      chainId: 42161,
    );
    final balance = find.text(r'$4,500.00');

    Future<void> openHeld(
      WidgetTester tester, {
      required Size size,
      double textScale = 1,
    }) async {
      services.balances = {eth: d('1.5')};
      await openSwapRoute(
        tester,
        picker(selected: eth, other: ethOnArbitrum),
        bloc: swap,
        services: services,
        size: size,
        textScale: textScale,
      );
    }

    testWidgets('sits beside the title where both fit', (tester) async {
      await openHeld(tester, size: const Size(420, 1600));

      expect(find.text('Same ticker'), findsOneWidget);
      expect(
        tester.getTopLeft(balance).dx,
        greaterThan(tester.getTopRight(find.text('Same ticker')).dx),
      );
      expect(above(tester, find.text('Ethereum').first, balance), isFalse);
    });

    testWidgets('moves under the title, to the end, at 200% text', (
      tester,
    ) async {
      await openHeld(tester, size: const Size(375, 2400), textScale: 2);

      expect(above(tester, find.text('Ethereum').first, balance), isTrue);
      expect(
        tester.getTopRight(balance).dx,
        greaterThan(tester.getTopRight(find.text('Ethereum').first).dx),
      );
    });
  });

  testWidgets('the zero-balance switch hides and counts, then restores', (
    tester,
  ) async {
    services.balances = {eth: d('1.5'), usdc: d('0'), btc: d('0')};
    await openSwapRoute(tester, picker(), bloc: swap, services: services);
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('2 hidden'), findsOneWidget);
    expect(find.text('USDC'), findsNothing);
    // GLEEC's balance has not been read, which is not the same as none.
    expect(find.text('GLEEC'), findsWidgets);
    expect(await services.preferences.hideZeroBalances(), isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('2 hidden'), findsNothing);
    expect(find.text('USDC'), findsOneWidget);
    expect(await services.preferences.hideZeroBalances(), isFalse);
  });

  testWidgets('while one asset activates, no other can be chosen', (
    tester,
  ) async {
    services
      ..activated = {eth, usdc, gleec}
      ..activationGate = Completer<void>();
    final popped = await openSwapRoute(
      tester,
      picker(),
      bloc: swap,
      services: services,
    );

    await tester.tap(find.text('BTC').first);
    await tester.pump();
    expect(find.text('Activating…'), findsOneWidget);

    await tester.tap(find.text('USDC'));
    await tester.pump();
    expect(popped, isEmpty);
    expect(
      tester.getSemantics(find.text('USDC')),
      isSemantics(isButton: true, isEnabled: false),
    );

    services.activationGate!.complete();
    await tester.pumpAndSettle();
    expect(popped, [btc]);
  });
}

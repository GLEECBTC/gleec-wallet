import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/views/swap/swap_shell.dart';

/// Covers the Swap surface's structure.
///
/// The point of these is what is *reachable*. Pointing the menu entry at the
/// swap form is only safe while the full trading interface stays one tap away
/// — the earlier attempt at this arrangement stranded users because its
/// default destination was switched off, not because the arrangement was
/// wrong.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    SwapDestination initial = SwapDestination.swap,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SwapShell(
          initialDestination: initial,
          destinationBuilder: (destination) => Text('body:${destination.name}'),
        ),
      ),
    ),
  );

  testWidgets('opens on the swap form', (tester) async {
    await pump(tester);

    // The question most people arrive with is "turn this into that", not
    // "place a maker order".
    expect(find.text('body:swap'), findsOneWidget);
  });

  testWidgets('keeps the full trading interface one tap away', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const Key('swap-destination-advanced')));
    await tester.pumpAndSettle();

    // Demoting the trading UI is only acceptable while it remains reachable.
    // If this ever fails, the menu entry should not be pointing here.
    expect(find.text('body:advanced'), findsOneWidget);
  });

  testWidgets('reaches history without leaving the surface', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const Key('swap-destination-activity')));
    await tester.pumpAndSettle();

    expect(find.text('body:activity'), findsOneWidget);
  });

  testWidgets('offers exactly the three destinations', (tester) async {
    await pump(tester);

    expect(find.byKey(const Key('swap-destination-switcher')), findsOneWidget);
    expect(find.byKey(const Key('swap-destination-swap')), findsOneWidget);
    expect(find.byKey(const Key('swap-destination-activity')), findsOneWidget);
    expect(find.byKey(const Key('swap-destination-advanced')), findsOneWidget);
  });

  testWidgets('keeps the keys the integration suite navigates by', (
    tester,
  ) async {
    await pump(tester);

    // The UI suite reaches the trading interface by tapping these, and cannot
    // reach it any other way. Losing one turns every DEX assertion into a
    // missing-widget failure a long way from the cause.
    expect(find.byKey(const Key('swap-shell')), findsOneWidget);
    expect(find.byKey(const Key('swap-destination-swap')), findsOneWidget);
    expect(find.byKey(const Key('swap-destination-activity')), findsOneWidget);
    expect(find.byKey(const Key('swap-destination-advanced')), findsOneWidget);

    // The keys sit on the labels inside each destination's tap target, so a
    // tap has to reach the target through them. Asserting they exist would
    // not catch a label that stopped being tappable.
    await tester.tap(find.byKey(const Key('swap-destination-advanced')));
    await tester.pumpAndSettle();
    expect(find.text('body:advanced'), findsOneWidget);

    await tester.tap(find.byKey(const Key('swap-destination-swap')));
    await tester.pumpAndSettle();
    expect(find.text('body:swap'), findsOneWidget);
  });

  testWidgets('can be opened directly on a destination', (tester) async {
    await pump(tester, initial: SwapDestination.advanced);

    // Deep links into trading must not land on the swap form first.
    expect(find.text('body:advanced'), findsOneWidget);
  });
}

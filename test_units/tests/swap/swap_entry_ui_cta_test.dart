// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/taker_form/taker_bloc.dart';
import 'package:web_dex/bloc/taker_form/taker_state.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/entry/swap_amount_cards.dart';
import 'package:web_dex/views/swap/entry/swap_entry_view.dart';
import 'package:web_dex/views/wallets_manager/wallets_manager_wrapper.dart';

import 'swap_entry_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the form's one primary action: it always names the next step,
/// and pressing it takes that step, or waits while nothing can be done.
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

  Future<void> pump(
    WidgetTester tester,
    UnifiedSwapState state, {
    bool settle = true,
    Widget view = const SwapEntryView(),
  }) async {
    swap.emit(state);
    await pumpSwapUi(
      tester,
      view,
      bloc: swap,
      services: services,
      settle: settle,
    );
  }

  Future<void> press(WidgetTester tester) async {
    await tester.tap(swapPrimaryAction);
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester) =>
      swapButtonEnabled(tester, find.text(swapPrimaryLabel(tester)));

  group('before both assets are chosen', () {
    testWidgets('it asks for the asset to pay with, and opens that picker', (
      tester,
    ) async {
      await pump(
        tester,
        swapBaseForm(input: '').copyWith(clearPay: true, clearReceive: true),
      );

      expect(swapPrimaryLabel(tester), 'Select asset');
      // Both pills and the action say the same.
      expect(find.text('Select asset'), findsNWidgets(3));
      expect(find.text(r'$0.00'), findsNWidgets(2));
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
      expect(
        tester.getSemantics(find.byType(SwapAssetPill).first),
        isSemantics(label: 'You pay', isButton: true, hasTapAction: true),
      );

      await press(tester);
      expect(find.text('Choose asset'), findsOneWidget);
      expect(find.text('What you pay with'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Choose asset'), findsNothing);
      expect(swap.events, isEmpty);
    });

    testWidgets('with the pay asset chosen, it opens the receive picker', (
      tester,
    ) async {
      await pump(tester, swapBaseForm().copyWith(clearReceive: true));

      expect(swapPrimaryLabel(tester), 'Select asset');
      expect(
        tester.getSemantics(find.byType(SwapAssetPill).first),
        isSemantics(label: 'You pay: ETH, Ethereum', isButton: true),
      );

      await press(tester);
      expect(find.text('What you receive'), findsOneWidget);
    });
  });

  group('an inactive asset', () {
    final inactive = swapBaseForm().copyWith(
      issue: SwapFormIssue.assetInactive,
      catalog: SwapCatalog(sources: swapTestCatalog.sources, activated: {eth}),
    );

    testWidgets('is activated from the button, then reported to the bloc', (
      tester,
    ) async {
      services.activationGate = Completer<void>();
      await pump(tester, inactive);

      expect(swapPrimaryLabel(tester), 'Activate USDC');
      expect(
        find.text(
          "USDC isn't active in this wallet yet. Activate it to see its "
          'balance and prices.',
        ),
        findsOneWidget,
      );

      await tester.tap(swapPrimaryAction);
      await tester.pump();
      expect(services.activations, [usdc]);
      expect(swapPrimaryBusy(), isTrue);
      expect(enabled(tester), isFalse);
      expect(swap.events, isEmpty);

      services.activationGate!.complete();
      await tester.pumpAndSettle();
      expect(swap.events, [UnifiedSwapAssetActivated(usdc)]);
      expect(swapPrimaryBusy(), isFalse);
      expect(enabled(tester), isTrue);
    });

    testWidgets('that fails to activate says so, and can be tried again', (
      tester,
    ) async {
      services.activationError = StateError('offline');
      await pump(tester, inactive);

      await press(tester);
      expect(find.text("Couldn't activate USDC. Try again."), findsOneWidget);
      expect(swap.events, isEmpty);
      expect(swapPrimaryBusy(), isFalse);

      services.activationError = null;
      await press(tester);
      expect(services.activations, [usdc, usdc]);
      expect(swap.events, [UnifiedSwapAssetActivated(usdc)]);
    });
  });

  group('without a wallet', () {
    const hint = 'Connect a wallet to see balances and prices.';
    final signedOut = swapBaseForm().copyWith(
      signedIn: false,
      issue: SwapFormIssue.signedOut,
      catalog: SwapCatalog(sources: swapTestCatalog.sources, activated: {}),
    );

    testWidgets('asks for a wallet, not an activation', (tester) async {
      var connects = 0;
      await pump(
        tester,
        signedOut,
        view: SwapEntryView(onConnectWallet: () => connects++),
      );

      expect(swapPrimaryLabel(tester), 'Connect wallet');
      expect(find.text(hint), findsOneWidget);
      expect(find.textContaining('Activate'), findsNothing);

      await press(tester);
      expect(connects, 1);
      expect(services.activations, isEmpty);
      expect(swap.events, isEmpty);
    });

    testWidgets("opens the app's wallet manager by default", (tester) async {
      final taker = _FakeTakerBloc();
      addTearDown(taker.close);
      swap.emit(signedOut);
      await pumpSwapUi(
        tester,
        const SwapEntryView(),
        bloc: swap,
        services: services,
        providers: [BlocProvider<TakerBloc>.value(value: taker)],
      );

      await tester.tap(swapPrimaryAction);
      await tester.pump();
      await tester.pump();

      // Only the manager's own dependencies are missing here: the form
      // handed the sign-in to it.
      expect(
        tester.takeException(),
        isA<ProviderNotFoundException>().having(
          (error) => error.widgetType,
          'widgetType',
          WalletsManagerWrapper,
        ),
      );
    });

    testWidgets('still asks for both assets first', (tester) async {
      await pump(tester, signedOut.copyWith(clearReceive: true));

      expect(swapPrimaryLabel(tester), 'Select asset');
      expect(find.text(hint), findsOneWidget);
    });

    testWidgets('picks an asset without activating it', (tester) async {
      services.activated = {};
      await pump(
        tester,
        signedOut.copyWith(
          clearPay: true,
          clearReceive: true,
          clearIssue: true,
        ),
      );

      await tester.tap(find.byType(SwapAssetPill).first);
      await tester.pumpAndSettle();
      expect(find.text('Activate'), findsNothing);

      await tester.tap(find.text('BTC').first);
      await tester.pumpAndSettle();
      expect(swap.events, [UnifiedSwapPayAssetChanged(btc)]);
      expect(services.activations, isEmpty);
    });
  });

  group('a pair that cannot be swapped', () {
    testWidgets('steers to another asset to receive', (tester) async {
      await pump(
        tester,
        swapBaseForm().copyWith(issue: SwapFormIssue.pairUnsupported),
      );

      expect(
        find.text("This pair can't be swapped here. Choose another asset."),
        findsOneWidget,
      );
      expect(swapPrimaryLabel(tester), 'Choose another asset');
      await press(tester);
      expect(find.text('What you receive'), findsOneWidget);
    });

    testWidgets('of one asset twice asks for two different ones', (
      tester,
    ) async {
      await pump(
        tester,
        swapBaseForm(receive: eth).copyWith(issue: SwapFormIssue.sameAsset),
      );

      expect(find.text('Choose two different assets.'), findsOneWidget);
      expect(swapPrimaryLabel(tester), 'Choose another asset');
      await press(tester);
      expect(find.text('What you receive'), findsOneWidget);
    });
  });

  group('while options are checked', () {
    testWidgets('the form waits, with placeholders where the price goes', (
      tester,
    ) async {
      await pump(
        tester,
        swapBaseForm().copyWith(evaluation: SwapEvaluationStatus.checking),
        settle: false,
      );

      expect(swapPrimaryLabel(tester), 'Checking…');
      expect(swapPrimaryBusy(), isTrue);
      expect(enabled(tester), isFalse);
      expect(find.text('Checking swap options…'), findsOneWidget);
      // Two under the cards, one for the amount to receive.
      expect(find.byType(SwapSkeleton), findsNWidgets(3));
    });

    testWidgets('a re-price keeps the current option on screen', (
      tester,
    ) async {
      await pump(
        tester,
        swapPricedForm().copyWith(evaluation: SwapEvaluationStatus.checking),
        settle: false,
      );

      expect(swapPrimaryLabel(tester), 'Checking…');
      expect(find.text('Checking swap options…'), findsOneWidget);
      expect(find.byType(SwapSkeleton), findsNothing);
      expect(find.text('Minimum received'), findsOneWidget);
    });

    testWidgets('an amount not yet sent for pricing waits the same way', (
      tester,
    ) async {
      await pump(tester, swapBaseForm(), settle: false);

      expect(swapPrimaryLabel(tester), 'Checking…');
      expect(swapPrimaryBusy(), isTrue);
    });
  });

  testWidgets('an expired quote is refreshed from the button', (tester) async {
    await pump(
      tester,
      swapPricedForm(evaluation: SwapEvaluationStatus.expired),
    );

    expect(swapPrimaryLabel(tester), 'Refresh quote');
    await press(tester);
    expect(swap.events, [const UnifiedSwapEvaluationRequested()]);
  });

  testWidgets('a failure with no reason given offers a plain retry', (
    tester,
  ) async {
    await pump(
      tester,
      swapBaseForm().copyWith(evaluation: SwapEvaluationStatus.failed),
    );

    expect(swapPrimaryLabel(tester), 'Try again');
    await press(tester);
    expect(swap.events, [const UnifiedSwapEvaluationRequested()]);
  });

  testWidgets('options that cannot be ranked ask for one to be chosen', (
    tester,
  ) async {
    final incomplete = pricingOf(complete: false);
    await pump(
      tester,
      swapPricedForm(
        ranked: [],
        unrankable: [
          quoteOf(id: 'a', pricing: incomplete),
          quoteOf(id: 'b', expected: '2990', pricing: incomplete),
        ],
      ),
    );

    expect(swapPrimaryLabel(tester), 'Select an option');
    expect(find.text('Minimum received'), findsNothing);
    await press(tester);
    expect(swap.events, [const UnifiedSwapAlternativesRequested()]);
    expect(find.text('Choose manually'), findsOneWidget);
  });

  testWidgets('a priced swap opens the review', (tester) async {
    await pump(tester, swapPricedForm());

    expect(swapPrimaryLabel(tester), 'Review swap');
    await press(tester);
    expect(swap.events, [const UnifiedSwapReviewOpened()]);
  });

  group('a wallet short of funds', () {
    testWidgets('without the network coin names that coin, not the token', (
      tester,
    ) async {
      await pump(
        tester,
        swapBaseForm(
          pay: usdc,
          receive: eth,
        ).copyWith(issue: SwapFormIssue.noFeeBalance, feeBalance: d('0')),
      );

      expect(
        find.text(
          'You need some ETH on Ethereum to pay the network fees. This '
          'address has none.',
        ),
        findsOneWidget,
      );
      expect(swapPrimaryLabel(tester), 'Not enough ETH');
      expect(enabled(tester), isFalse);
    });

    testWidgets('an amount that cannot be priced cannot be reviewed', (
      tester,
    ) async {
      await pump(
        tester,
        swapBaseForm(
          input: '1.2.3',
        ).copyWith(issue: SwapFormIssue.amountMalformed),
      );

      expect(find.text('Enter a valid number.'), findsOneWidget);
      expect(swapPrimaryLabel(tester), 'Review swap');
      expect(enabled(tester), isFalse);
    });
  });
}

/// The trading form's bloc, which the wallet manager's success path resets.
class _FakeTakerBloc extends Cubit<TakerState> implements TakerBloc {
  _FakeTakerBloc() : super(TakerState.initial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

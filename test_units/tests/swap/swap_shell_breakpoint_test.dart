// The analyzer does not treat test_units as tests, so test-only members
// read as violations here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/bloc/swap_activity/swap_activity_bloc.dart';
import 'package:web_dex/bloc/system_health/system_health_bloc.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/router/navigators/main_layout/main_layout_router.dart';
import 'package:web_dex/router/navigators/page_content/page_content_router.dart';
import 'package:web_dex/router/navigators/page_menu/page_menu_router.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_pricing.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';
import 'package:web_dex/views/dex/dex_page.dart';
import 'package:web_dex/views/swap/activity/swap_activity_view.dart';
import 'package:web_dex/views/swap/common/swap_buttons.dart';
import 'package:web_dex/views/swap/entry/swap_entry_view.dart';
import 'package:web_dex/views/swap/execution/swap_execution_view.dart';
import 'package:web_dex/views/swap/review/swap_review_view.dart';
import 'package:web_dex/views/swap/swap_page.dart';
import 'package:web_dex/views/swap/swap_shell.dart';

import 'swap_accessibility_checks.dart' show swapFont;
import 'swap_surface_ui_fakes.dart';
import 'swap_test_fixtures.dart';
import 'swap_wiring_coin_fakes.dart' show FakeCoinsBloc;
import 'swap_wiring_fakes.dart'
    show FakeAuthBloc, FakeSdk, FakeSettingsBloc, pumpLocalized, softwareUser;

/// Each width the main layout is crossed to, in order: the phone turned
/// sideways (past 768 px), a window widened past 1024 px, then a phone again.
const _widths = [
  (size: Size(844, 390), screen: ScreenType.tablet),
  (size: Size(1440, 900), screen: ScreenType.desktop),
  (size: Size(390, 844), screen: ScreenType.mobile),
];

/// The swap surface keeps its state when the main layout crosses a
/// breakpoint and moves it to another page router.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the swap surface across layout breakpoints', () {
    late _HeldExecutor executor;
    late SwapExecutionRegistry registry;
    late _PricedServices services;

    setUpAll(loadSurfaceCopy);

    setUp(() {
      executor = _HeldExecutor();
      registry = SwapExecutionRegistry(
        executors: [executor],
        inFlight: () async => const [],
      );
      services = _PricedServices(registry);
      useFreshRoutingState();
      routingState.selectedMenu = MainMenuValue.dex;
    });

    tearDown(() async {
      await registry.dispose();
      await services.dispose();
      resetSurfaceCopy();
    });

    // A busy button spins for as long as it is busy, so this does not wait
    // for the screen to go quiet.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    /// The main layout on a phone, signed in, on Swap with ETH for USDC.
    Future<void> show(WidgetTester tester) async {
      services.requestIntent((
        pay: 'ETH',
        receive: 'USDC-ERC20',
        amount: null,
        fiat: false,
      ));
      final auth = FakeAuthBloc(AuthBlocState.loggedIn(softwareUser()));
      final settings = FakeSettingsBloc();
      final coins = FakeCoinsBloc();
      addTearDown(auth.close);
      addTearDown(settings.close);
      addTearDown(coins.close);
      await pumpLocalized(
        tester,
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthBloc>.value(value: auth),
            BlocProvider<SettingsBloc>.value(value: settings),
            BlocProvider<CoinsBloc>.value(value: coins),
            BlocProvider<TradingStatusBloc>.value(
              value: FakeTradingStatusBloc(),
            ),
            BlocProvider<SystemHealthBloc>.value(value: FakeSystemHealthBloc()),
          ],
          child: MultiRepositoryProvider(
            providers: [
              RepositoryProvider<KomodoDefiSdk>.value(value: FakeSdk()),
              RepositoryProvider<SwapServices>.value(value: services),
            ],
            child: const Scaffold(body: MainLayoutRouter()),
          ),
        ),
        size: _widths.last.size,
        theme: ThemeData(brightness: Brightness.dark, fontFamily: swapFont),
      );
      await settle(tester);
    }

    // The shell provides both blocs to every destination.
    BuildContext shell(WidgetTester tester) =>
        tester.element(find.byKey(const Key('swap-shell')));

    UnifiedSwapBloc form(WidgetTester tester) =>
        BlocProvider.of<UnifiedSwapBloc>(shell(tester));

    SwapActivityBloc activity(WidgetTester tester) =>
        BlocProvider.of<SwapActivityBloc>(shell(tester));

    Future<void> typeAmount(WidgetTester tester) async {
      await tester.enterText(find.byKey(const Key('swap-amount')), '1');
      await settle(tester);
      expect(form(tester).state.selectedQuote, isNotNull);
    }

    Future<void> openReview(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('swap-primary-action')));
      await settle(tester);
      expect(form(tester).state.view, UnifiedSwapView.review);
    }

    State router(WidgetTester tester) => tester.state(
      find.ancestor(
        of: find.byType(SwapShell),
        matching: find.byWidgetPredicate(
          (widget) => widget is PageMenuRouter || widget is PageContentRouter,
        ),
      ),
    );

    /// Crosses every breakpoint in turn and, at each width, checks that the
    /// shell moved to that layout's own page router with the same blocs,
    /// then runs [expectKept].
    Future<void> crossBreakpoints(
      WidgetTester tester,
      void Function(String width, ScreenType screen) expectKept,
    ) async {
      final swap = form(tester);
      final history = activity(tester);
      var host = router(tester);
      for (final width in _widths) {
        tester.view.physicalSize = width.size;
        await settle(tester);

        final reason = '${width.size}';
        expect(screenType, width.screen, reason: reason);
        final next = router(tester);
        expect(next, isNot(same(host)), reason: reason);
        expect(
          next.widget,
          width.screen == ScreenType.mobile
              ? isA<PageMenuRouter>()
              : isA<PageContentRouter>(),
          reason: reason,
        );
        host = next;
        expect(form(tester), same(swap), reason: reason);
        expect(activity(tester), same(history), reason: reason);
        expect(swap.isClosed, isFalse, reason: reason);
        expectKept(reason, width.screen);
      }
    }

    testWidgets('keeps a typed amount and its price', (tester) async {
      await show(tester);
      await typeAmount(tester);
      final quote = form(tester).state.selectedQuote;

      await crossBreakpoints(tester, (width, _) {
        final state = form(tester).state;
        expect(state.inputText, '1', reason: width);
        expect(state.selectedQuote, quote, reason: width);
        final field = tester.widget<TextField>(
          find.byKey(const Key('swap-amount')),
        );
        expect(field.controller!.text, '1', reason: width);
        // Still typing: a phone turned mid-entry keeps its keyboard.
        expect(field.focusNode!.hasFocus, isTrue, reason: width);
      });
    });

    testWidgets('keeps an open review, beside the form once there is room', (
      tester,
    ) async {
      await show(tester);
      await typeAmount(tester);
      await openReview(tester);
      final review = form(tester).state.review;

      await crossBreakpoints(tester, (width, screen) {
        final state = form(tester).state;
        expect(state.view, UnifiedSwapView.review, reason: width);
        expect(state.review, review, reason: width);
        expect(find.byType(SwapReviewView), findsOneWidget, reason: width);
        expect(
          find.byType(SwapEntryView),
          screen == ScreenType.desktop ? findsOneWidget : findsNothing,
          reason: width,
        );
      });
    });

    testWidgets('keeps an unanswered start blocking another, then shows the '
        'swap it started', (tester) async {
      await show(tester);
      await typeAmount(tester);
      await openReview(tester);
      await tester.tap(find.byKey(const Key('swap-start')));
      await settle(tester);
      expect(form(tester).state.review?.status, SwapReviewStatus.starting);

      await crossBreakpoints(tester, (width, _) {
        expect(
          form(tester).state.review?.status,
          SwapReviewStatus.starting,
          reason: width,
        );
        expect(
          tester.widget<SwapButton>(find.byKey(const Key('swap-start'))).busy,
          isTrue,
          reason: width,
        );
      });
      await tester.tap(
        find.byKey(const Key('swap-start')),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(executor.starts, 1);

      executor.answer();
      await settle(tester);
      expect(form(tester).state.view, UnifiedSwapView.progress);
      final id = form(tester).state.activeExecutionId;
      expect(id, 'routed-1');

      await crossBreakpoints(tester, (width, _) {
        final state = form(tester).state;
        expect(state.view, UnifiedSwapView.progress, reason: width);
        expect(state.activeExecutionId, id, reason: width);
        expect(find.byType(SwapExecutionView), findsOneWidget, reason: width);
      });
      expect(executor.starts, 1);
    });

    testWidgets('stays on the destination it was showing', (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const Key('swap-destination-activity')));
      await settle(tester);
      expect(find.byType(SwapActivityView), findsOneWidget);

      await crossBreakpoints(tester, (width, _) {
        expect(find.byType(SwapActivityView), findsOneWidget, reason: width);
        expect(find.byType(SwapPage), findsNothing, reason: width);
      });
    });

    testWidgets('builds a new trading page for each screen type', (
      tester,
    ) async {
      // Only the trading page's own dependencies are missing here, so each
      // one built reports them.
      final missingDependencies = isA<FlutterError>().having(
        (error) => error.message,
        'message',
        contains('TradingEntitiesBloc'),
      );
      await show(tester);
      await tester.tap(find.byKey(const Key('swap-destination-advanced')));
      await settle(tester);
      expect(tester.takeException(), missingDependencies);
      var page = tester.state(find.byType(DexPage));

      await crossBreakpoints(tester, (width, _) {
        expect(tester.takeException(), missingDependencies, reason: width);
        final next = tester.state(find.byType(DexPage));
        expect(next, isNot(same(page)), reason: width);
        page = next;
      });
    });
  });
}

/// Swap services whose one source prices any pair it is asked for.
class _PricedServices extends SurfaceServices {
  _PricedServices(super.registry);

  @override
  UnifiedSwapRepository createRepository({
    required bool Function(AssetId from, AssetId to) tradingAllowed,
    required bool Function() clockValid,
  }) => UnifiedSwapRepository(
    sources: [
      FakeQuoteSource(
        SwapLiquiditySource.routed,
        respond: (request) => [
          SwapQuoteAvailable(
            quoteOf(
              from: request.from,
              to: request.to,
              quotedAt: DateTime.now(),
            ),
          ),
        ],
      ),
    ],
    pricing: SwapPricingService(FakePriceSource({eth: d('3000')})),
  );

  @override
  Future<Decimal?> spendableBalance(AssetId id) async => d('2');

  @override
  Future<String?> addressOf(AssetId id) async => '0xaddress';

  @override
  AssetId? resolveAsset(String ticker) => {eth.id: eth, usdc.id: usdc}[ticker];
}

/// A routed executor whose start waits for the test to answer it.
class _HeldExecutor extends FakeExecutor {
  _HeldExecutor() : super(SwapLiquiditySource.routed);

  // Made by the start itself, so it belongs to the test's fake clock.
  Completer<void>? _answer;
  var starts = 0;

  void answer() => _answer!.complete();

  @override
  Future<SwapExecutionHandle> start(SwapQuote quote) async {
    starts++;
    await (_answer ??= Completer<void>()).future;
    return super.start(quote);
  }
}

// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
// No public API resets the package's global translations between groups.
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/atomic_swap_execution.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_order_book_offers.dart';
import 'package:web_dex/shared/swap/swap_preferences.dart';
import 'package:web_dex/shared/swap/swap_pricing.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/shared/swap/swap_terms_repository.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';
import 'package:web_dex/views/swap/common/swap_links.dart';
import 'package:web_dex/views/swap/entry/swap_entry_view.dart';
import 'package:web_dex/views/swap/execution/swap_evidence_sheet.dart';
import 'package:web_dex/views/swap/execution/swap_execution_view.dart';
import 'package:web_dex/views/swap/pickers/swap_asset_picker.dart';
import 'package:web_dex/views/swap/pickers/swap_options_sheet.dart';
import 'package:web_dex/views/swap/pickers/swap_slippage_sheet.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

import 'swap_accessibility_checks.dart';
import 'swap_test_fixtures.dart';

part 'swap_accessibility_progress.dart';
part 'swap_accessibility_services.dart';
part 'swap_accessibility_sheets.dart';

typedef _Layout = ({String name, Size size, bool dark, double textScale});

const List<_Layout> _layouts = [
  (name: '375 dark', size: Size(375, 812), dark: true, textScale: 1),
  (name: '390 dark', size: Size(390, 844), dark: true, textScale: 1),
  (name: '768 light', size: Size(768, 1024), dark: false, textScale: 1),
  (name: '1024 dark', size: Size(1024, 768), dark: true, textScale: 1),
  (name: '1440 light', size: Size(1440, 900), dark: false, textScale: 1),
  (name: '375 light 200%', size: Size(375, 812), dark: false, textScale: 2),
  (name: '1024 dark 200%', size: Size(1024, 768), dark: true, textScale: 2),
];

/// Every new and changed swap state at each width the UX standard names, in
/// both themes and at 200% text, measured in the app's font: no overflow or
/// cut text, every control at least 48 dp, and every control labelled and
/// pressable by a screen reader.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final gleecEvm = assetOf(
    'GLEEC',
    subClass: CoinSubClass.grc20,
    chainId: 11169,
  );
  final paxg = assetOf('PAXG-ERC20', parent: eth);
  final ethOnArbitrum = assetOf(
    'ETH-ARB20',
    subClass: CoinSubClass.arbitrum,
    chainId: 42161,
  );
  final catalog = SwapCatalog(
    sources: [
      SwapSourceAssets(
        source: SwapLiquiditySource.atomic,
        quotable: {eth, usdc, gleecEvm, btc},
      ),
      SwapSourceAssets(
        source: SwapLiquiditySource.routed,
        quotable: {eth, usdc, paxg},
        status: SwapCatalogStatus.stale,
      ),
    ],
  );

  late SwapExecutionRegistry registry;
  late UnifiedSwapBloc swap;
  late SwapShellController shell;
  late _Services services;

  setUpAll(() async {
    await loadSwapFont();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  setUp(() {
    registry = SwapExecutionRegistry(
      executors: [FakeExecutor(SwapLiquiditySource.routed)],
      inFlight: () async => const [],
    );
    services = _Services(registry, {eth, usdc, gleecEvm, btc, paxg});
    final storage = MemoryStorage();
    swap = UnifiedSwapBloc(
      repository: UnifiedSwapRepository(
        sources: [FakeQuoteSource(SwapLiquiditySource.routed)],
        pricing: SwapPricingService(FakePriceSource({eth: d('3000')})),
      ),
      registry: registry,
      terms: SwapTermsRepository(walletKey: () async => 'w', storage: storage),
      preferences: SwapPreferences(
        walletKey: () async => 'w',
        storage: storage,
      ),
      spendableBalance: (_) async => d('2'),
      addressOf: (_) async => null,
      resolveAsset: (_) => null,
    );
    shell = SwapShellController();
  });

  tearDown(() async {
    await swap.close();
    await registry.dispose();
    shell.dispose();
    Localization.load(const Locale('en'));
  });

  Future<void> pump(WidgetTester tester, _Layout layout, Widget child) async {
    tester.view.physicalSize = layout.size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        saveLocale: false,
        path: 'assets/translations',
        assetLoader: const _EnglishAssetLoader(),
        child: Builder(
          builder: (context) => MaterialApp(
            theme: ThemeData(
              brightness: layout.dark ? Brightness.dark : Brightness.light,
              fontFamily: swapFont,
            ),
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            builder: (context, app) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(layout.textScale)),
              child: app!,
            ),
            home: RepositoryProvider<SwapServices>.value(
              value: services,
              child: BlocProvider<UnifiedSwapBloc>.value(
                value: swap,
                child: SwapShellScope(
                  controller: shell,
                  child: Scaffold(body: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  UnifiedSwapState form({
    AssetId? pay,
    AssetId? receive,
    SwapFormIssue? issue,
    SwapEvaluationStatus evaluation = SwapEvaluationStatus.ready,
    SwapQuoteFailure? failure,
    List<SwapQuoteFailure> failures = const [],
    Decimal? feeBalance,
  }) {
    final quote = quoteOf(from: pay ?? eth, to: receive ?? usdc);
    final ready = evaluation == SwapEvaluationStatus.ready;
    return UnifiedSwapState(
      loadingAssets: false,
      catalog: catalog,
      pay: pay ?? eth,
      receive: receive ?? usdc,
      inputText: '1',
      balance: d('2'),
      feeBalance: feeBalance,
      issue: issue,
      evaluation: evaluation,
      quotes: ready
          ? UnifiedSwapQuotes(
              ranked: [quote],
              unrankable: const [],
              failures: failures,
            )
          : null,
      selectedId: ready ? quote.id : null,
      failure: failure,
      failures: failures,
    );
  }

  final entryStates = <String, UnifiedSwapState Function()>{
    'pair unsupported': () => form(
      pay: gleecEvm,
      receive: paxg,
      issue: SwapFormIssue.pairUnsupported,
      evaluation: SwapEvaluationStatus.idle,
    ),
    'asset inactive': () =>
        form(
          issue: SwapFormIssue.assetInactive,
          evaluation: SwapEvaluationStatus.idle,
        ).copyWith(
          catalog: SwapCatalog(sources: catalog.sources, activated: {usdc}),
        ),
    'no network coin': () => form(
      pay: usdc,
      receive: eth,
      feeBalance: Decimal.zero,
      issue: SwapFormIssue.noFeeBalance,
      evaluation: SwapEvaluationStatus.idle,
    ),
    'no offer, other source unanswered': () => form(
      evaluation: SwapEvaluationStatus.failed,
      failure: const SwapQuoteFailure(
        source: SwapLiquiditySource.atomic,
        kind: SwapQuoteFailureKind.noRoute,
      ),
      failures: const [
        SwapQuoteFailure(
          source: SwapLiquiditySource.atomic,
          kind: SwapQuoteFailureKind.noRoute,
        ),
        SwapQuoteFailure(
          source: SwapLiquiditySource.routed,
          kind: SwapQuoteFailureKind.rateLimited,
        ),
      ],
    ),
    'no one offering an order-book pair': () =>
        form(
          receive: gleecEvm,
          issue: SwapFormIssue.noOffers,
          evaluation: SwapEvaluationStatus.idle,
        ).copyWith(
          hints: SwapOrderBookHints(
            pair: (eth, gleecEvm),
            offers: const SwapOrderBookOffers(),
            watching: true,
            receiveCounts: SwapOfferCounts(gleecEvm, {btc: true, usdc: true}),
          ),
        ),
    'no one offering it, and no longer checking': () =>
        form(
          receive: gleecEvm,
          issue: SwapFormIssue.noOffers,
          evaluation: SwapEvaluationStatus.idle,
        ).copyWith(
          hints: SwapOrderBookHints(
            pair: (eth, gleecEvm),
            offers: const SwapOrderBookOffers(),
          ),
        ),
    'options with a paused source': () => form(
      failures: const [
        SwapQuoteFailure(
          source: SwapLiquiditySource.routed,
          kind: SwapQuoteFailureKind.rateLimited,
        ),
      ],
    ),
    'priced, but more than the balance': () =>
        form(issue: SwapFormIssue.insufficient),
    'more than this address holds, with more at others': () {
      services.elsewhere[eth] = d('2.9');
      return form(issue: SwapFormIssue.insufficient);
    },
    'a hardware wallet': () => form(
      evaluation: SwapEvaluationStatus.idle,
    ).copyWith(tradingEnabled: false, hardwareWallet: true),
    'signed out': () =>
        form(
          issue: SwapFormIssue.signedOut,
          evaluation: SwapEvaluationStatus.idle,
        ).copyWith(
          signedIn: false,
          clearBalance: true,
          catalog: SwapCatalog(sources: catalog.sources, activated: {}),
        ),
    'just signed in, the dollar amount kept': () =>
        form(
          issue: SwapFormIssue.assetInactive,
          evaluation: SwapEvaluationStatus.idle,
        ).copyWith(
          inputText: '250',
          amountMode: SwapAmountMode.fiat,
          catalog: SwapCatalog(sources: catalog.sources, activated: {eth}),
        ),
  };

  for (final layout in _layouts) {
    group(layout.name, () {
      for (final MapEntry(key: name, value: state) in entryStates.entries) {
        testWidgets('entry: $name', (tester) async {
          swap.emit(state());
          await pump(tester, layout, const SwapEntryView());
          await expectSwapAccessible(tester, largeText: layout.textScale > 1);
          expect(
            tester.getSemantics(find.byKey(const Key('swap-amount'))),
            isSemantics(label: 'Amount to pay', isTextField: true),
          );
        });
      }

      // Apart from the states above: with no amount typed, the field also
      // announces its placeholder.
      testWidgets('entry: an order-book pair before an amount', (tester) async {
        swap.emit(
          form(
            receive: gleecEvm,
            issue: SwapFormIssue.amountMissing,
            evaluation: SwapEvaluationStatus.idle,
          ).copyWith(
            inputText: '',
            hints: SwapOrderBookHints(
              pair: (eth, gleecEvm),
              offers: SwapOrderBookOffers([SwapOfferBand(d('0.5'), d('2'))]),
            ),
          ),
        );
        await pump(tester, layout, const SwapEntryView());
        await expectSwapAccessible(tester, largeText: layout.textScale > 1);
        expect(find.text('Offers take 0.5 ETH to 2 ETH.'), findsOneWidget);
      });

      testWidgets('entry: Max still asking what fees need', (tester) async {
        swap.emit(form());
        await pump(tester, layout, const SwapEntryView());
        swap.emit(
          form(
            evaluation: SwapEvaluationStatus.idle,
          ).copyWith(inputText: '2', checkingMax: true),
        );
        // The spinners never settle: one pump delivers the state, one draws.
        await tester.pump();
        await tester.pump();
        expect(
          find.descendant(
            of: find.widgetWithText(TextButton, 'Max'),
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget,
        );
        await expectSwapAccessible(tester, largeText: layout.textScale > 1);
      });

      testWidgets('picker: paying, with a held asset selected', (tester) async {
        services.balances[eth] = d('1.5');
        await pump(
          tester,
          layout,
          SwapAssetPicker(
            side: SwapPickerSide.pay,
            catalog: catalog,
            selected: eth,
            other: ethOnArbitrum,
            services: services,
            isBlocked: (_) => false,
          ),
        );
        expect(find.text('Same ticker'), findsOneWidget);
        // Wherever the balance sits, the row stays one button, read whole.
        final row = tester.getSemantics(find.text('Selected'));
        expect(tester.getSemantics(find.text(r'$4,500.00')), same(row));
        expect(
          row,
          isSemantics(isButton: true, isSelected: true, hasTapAction: true),
        );
        await expectSwapAccessible(tester, largeText: layout.textScale > 1);
      });

      testWidgets('picker: unreachable group and incomplete notice', (
        tester,
      ) async {
        await pump(
          tester,
          layout,
          SwapAssetPicker(
            side: SwapPickerSide.receive,
            catalog: catalog,
            selected: null,
            other: gleecEvm,
            services: services,
            isBlocked: (_) => false,
            onRetryCatalog: () {},
          ),
        );
        await expectSwapAccessible(tester, largeText: layout.textScale > 1);
      });

      testWidgets('picker: paying, with every asset hidden', (tester) async {
        services.balances = {for (final id in catalog.assets) id: Decimal.zero};
        await services.preferences.rememberHideZeroBalances(true);
        await pump(
          tester,
          layout,
          SwapAssetPicker(
            side: SwapPickerSide.pay,
            catalog: catalog,
            selected: null,
            other: null,
            services: services,
            isBlocked: (_) => false,
          ),
        );
        // At large text the header scrolls with the list, pushing this down.
        await tester.scrollUntilVisible(
          find.text('Show all assets'),
          200,
          scrollable: find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await expectSwapAccessible(tester, largeText: layout.textScale > 1);
      });

      testWidgets('picker: signed out', (tester) async {
        await pump(
          tester,
          layout,
          SwapAssetPicker(
            side: SwapPickerSide.pay,
            catalog: catalog,
            selected: eth,
            other: null,
            services: services,
            isBlocked: (_) => false,
            signedIn: false,
          ),
        );
        expect(find.text('Activate'), findsNothing);
        await expectSwapAccessible(tester, largeText: layout.textScale > 1);
      });

      testWidgets('picker: while an asset activates', (tester) async {
        services = _Services(registry, {eth});
        await pump(
          tester,
          layout,
          SwapAssetPicker(
            side: SwapPickerSide.pay,
            catalog: catalog,
            selected: null,
            other: null,
            services: services,
            isBlocked: (_) => false,
          ),
        );
        final inactive = find.text('BTC').first;
        await tester.scrollUntilVisible(
          inactive,
          200,
          scrollable: find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        await tester.tap(inactive);
        // The spinner never settles, so pump once rather than settle.
        await tester.pump();
        expect(find.text('Activating…'), findsOneWidget);
        await expectSwapAccessible(tester, largeText: layout.textScale > 1);
      });

      _sheetCases(layout, pump: pump, services: () => services);
      testWidgets('comparison with the slippage setting', (tester) async {
        swap.emit(form());
        await pump(tester, layout, const SwapOptionsSheet());
        expect(find.textContaining('Slippage'), findsWidgets);
        await expectSwapAccessible(tester, largeText: layout.textScale > 1);
      });

      testWidgets('slippage: a custom value out of range', (tester) async {
        await pump(
          tester,
          layout,
          SwapSlippageSheet(initial: 0.03, onSave: (_) {}),
        );
        await tester.enterText(find.byType(TextField), '9');
        await tester.pumpAndSettle();
        await expectSwapAccessible(tester, largeText: layout.textScale > 1);
      });

      testWidgets('progress: an order-book swap whose status is delayed', (
        tester,
      ) async {
        await pump(
          tester,
          layout,
          SwapExecutionView(
            id: 'a-1',
            context: SwapExecutionContext.flow,
            source: SwapLiquiditySource.atomic,
            initial: atomicSnapshot(
              uuid: 'a-1',
              stage: SwapProgressStage.exchanging,
              movement: SwapFundsMovement.sent,
              accepted: quoteOf(
                source: SwapLiquiditySource.atomic,
                routeKind: SwapRouteKind.direct,
                order: null,
                stages: [
                  const SwapRouteStage(kind: SwapRouteStageKind.prepare),
                  SwapRouteStage(kind: SwapRouteStageKind.send, asset: eth),
                  SwapRouteStage(
                    kind: SwapRouteStageKind.exchange,
                    asset: usdc,
                  ),
                  SwapRouteStage(kind: SwapRouteStageKind.receive, asset: usdc),
                ],
              ),
              networks: services.networks(),
              resolveAsset: (_) => null,
              delayedSince: DateTime(2026, 9, 28),
            ),
          ),
        );
        expect(find.text('Status update delayed'), findsOneWidget);
        await expectSwapAccessible(tester, largeText: layout.textScale > 1);
      });
      _progressCases(layout, pump: pump);

      for (final (name, url, details) in [
        (
          'a link',
          'https://etherscan.io/tx/'
              '0x5520d7f51c8e3108fa2d9c6220bf4aa8f9c17b91e4c3a1b2c3d4e5f6a7b8c9d0',
          null,
        ),
        (
          'support by email',
          'mailto:info@gleec.com?subject=GLEEC%20Wallet%20Support',
          'Swap ID: swap-1',
        ),
      ]) {
        testWidgets('link: the device cannot open $name', (tester) async {
          await pump(
            tester,
            layout,
            SwapLinkFailedDialog(url: url, details: details),
          );
          await expectSwapAccessible(tester, largeText: layout.textScale > 1);

          _acceptClipboard(tester);
          await tester.tap(find.text('Copy'));
          await tester.pumpAndSettle();
          expect(find.textContaining('copied'), findsWidgets);
          await expectSwapAccessible(tester, largeText: layout.textScale > 1);
        });
      }
    });
  }
}

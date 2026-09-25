// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:convert';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
// No public API resets the package's global translations between groups.
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_preferences.dart';
import 'package:web_dex/shared/swap/swap_pricing.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/shared/swap/swap_terms_repository.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';
import 'package:web_dex/views/swap/entry/swap_entry_view.dart';
import 'package:web_dex/views/swap/pickers/swap_asset_picker.dart';
import 'package:web_dex/views/swap/pickers/swap_options_sheet.dart';
import 'package:web_dex/views/swap/pickers/swap_slippage_sheet.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

import 'swap_accessibility_checks.dart';
import 'swap_test_fixtures.dart';

class _EnglishAssetLoader extends AssetLoader {
  const _EnglishAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/en.json').readAsStringSync())
          as Map<String, dynamic>;
}

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
    });
  }
}

class _Services implements SwapServices {
  _Services(this.registry, this._activated);

  @override
  final SwapExecutionRegistry registry;

  final Set<AssetId> _activated;
  Map<AssetId, Decimal> balances = {};

  @override
  final Set<String> viewing = {};

  @override
  late final SwapPreferences preferences = SwapPreferences(
    walletKey: () async => 'w',
    storage: MemoryStorage(),
  );

  @override
  SwapNetworks networks() => SwapNetworks([eth, usdc, btc]);

  @override
  Future<Set<AssetId>> activatedAssets() async => _activated;

  @override
  bool isTestnet(AssetId id) => false;

  @override
  AssetId? resolveAsset(String ticker) => null;

  @override
  Decimal? usdPrice(AssetId id) => id == eth ? d('3000') : null;

  @override
  Decimal? lastKnownBalance(AssetId id) => balances[id];

  @override
  String? contractOf(AssetId id) => null;

  @override
  Uri? explorerTxUrl(AssetId? asset, String hash) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

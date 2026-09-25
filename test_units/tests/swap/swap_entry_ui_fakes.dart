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
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/bloc/settings/settings_state.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/model/stored_settings.dart';
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

/// The app's font and English copy, set up once per test file.
void setUpSwapUi() {
  setUpAll(() async {
    await loadSwapFont();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  tearDown(() => Localization.load(const Locale('en')));
}

/// The swap bloc as the views see it: it records what they ask of it rather
/// than acting on it, and a test sets its state with `emit`.
class RecordingSwapBloc extends UnifiedSwapBloc {
  RecordingSwapBloc({Map<AssetId, Decimal>? prices})
    : this._(
        SwapExecutionRegistry(executors: const [], inFlight: () async => []),
        prices ?? {eth: d('3000')},
      );

  RecordingSwapBloc._(this._registry, Map<AssetId, Decimal> prices)
    : super(
        repository: UnifiedSwapRepository(
          sources: const [],
          pricing: SwapPricingService(FakePriceSource(prices)),
        ),
        registry: _registry,
        terms: SwapTermsRepository(
          walletKey: () async => 'w',
          storage: MemoryStorage(),
        ),
        preferences: SwapPreferences(
          walletKey: () async => 'w',
          storage: MemoryStorage(),
        ),
        spendableBalance: (_) async => null,
        addressOf: (_) async => null,
        resolveAsset: (_) => null,
      );

  final SwapExecutionRegistry _registry;

  final List<UnifiedSwapEvent> events = [];

  @override
  void add(UnifiedSwapEvent event) => events.add(event);

  @override
  Future<void> close() async {
    await super.close();
    await _registry.dispose();
  }
}

/// What the swap views read from the rest of the app, set per test.
class FakeSwapServices implements SwapServices {
  FakeSwapServices({Set<AssetId>? activated})
    : activated = activated ?? {eth, usdc, btc, gleec};

  Set<AssetId> activated;
  List<AssetId> known = [eth, usdc, btc, gleec];
  Map<AssetId, Decimal> balances = {};
  Map<AssetId, Decimal> prices = {eth: d('3000')};
  Map<AssetId, String> contracts = {};
  Set<AssetId> testnets = {};
  Map<String, AssetId> tickers = {};

  /// Thrown by [activatedAssets]: a picker that cannot read the wallet.
  Object? loadError;

  Object? activationError;

  /// Holds [activate] open until completed.
  Completer<void>? activationGate;

  final List<AssetId> activations = [];

  @override
  late final SwapPreferences preferences = SwapPreferences(
    walletKey: () async => 'w',
    storage: MemoryStorage(),
  );

  @override
  final Set<String> viewing = {};

  @override
  SwapNetworks networks() => SwapNetworks(known);

  @override
  Future<Set<AssetId>> activatedAssets() async {
    final error = loadError;
    if (error != null) throw error;
    return activated;
  }

  @override
  Future<void> activate(AssetId id) async {
    activations.add(id);
    await activationGate?.future;
    final error = activationError;
    if (error != null) throw error;
  }

  @override
  bool isTestnet(AssetId id) => testnets.contains(id);

  @override
  AssetId? resolveAsset(String ticker) => tickers[ticker];

  @override
  Decimal? usdPrice(AssetId id) => prices[id];

  @override
  Decimal? lastKnownBalance(AssetId id) => balances[id];

  @override
  String? contractOf(AssetId id) => contracts[id];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTradingStatusBloc extends Cubit<TradingStatusState>
    implements TradingStatusBloc {
  FakeTradingStatusBloc(Set<AssetId> blocked)
    : super(TradingStatusLoadSuccess(disallowedAssets: blocked));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSettingsBloc extends Cubit<SettingsState> implements SettingsBloc {
  FakeSettingsBloc({required bool testCoins})
    : super(
        SettingsState.fromStored(
          StoredSettings.initial(),
        ).copyWith(testCoinsEnabled: testCoins),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final swapTestCatalog = SwapCatalog(
  sources: [
    SwapSourceAssets(
      source: SwapLiquiditySource.atomic,
      quotable: {eth, usdc, btc, gleec},
    ),
    SwapSourceAssets(source: SwapLiquiditySource.routed, quotable: {eth, usdc}),
  ],
);

/// ETH for USDC with one ETH typed and two spendable, not priced yet.
UnifiedSwapState swapBaseForm({
  AssetId? pay,
  AssetId? receive,
  String input = '1',
}) => UnifiedSwapState(
  loadingAssets: false,
  catalog: swapTestCatalog,
  pay: pay ?? eth,
  receive: receive ?? usdc,
  inputText: input,
  balance: d('2'),
);

/// [swapBaseForm] priced: [ranked] and [unrankable] on offer, and the
/// preselected option chosen unless [selectedId] names another.
UnifiedSwapState swapPricedForm({
  List<SwapQuote>? ranked,
  List<SwapQuote> unrankable = const [],
  List<SwapQuoteFailure> failures = const [],
  String? selectedId,
  SwapEvaluationStatus evaluation = SwapEvaluationStatus.ready,
}) {
  final quotes = UnifiedSwapQuotes(
    ranked: ranked ?? [quoteOf()],
    unrankable: unrankable,
    failures: failures,
  );
  return swapBaseForm().copyWith(
    evaluation: evaluation,
    quotes: quotes,
    selectedId: selectedId ?? quotes.preselected?.id,
    failures: failures,
  );
}

/// Dollar figures for a quote; every cost priced unless [complete] is false.
SwapQuotePricing pricingOf({
  String? pay = '3000',
  String? expected = '3000',
  String? minimum = '2985',
  String? network = '3',
  String? approval,
  String? swap = '0',
  bool complete = true,
}) => SwapQuotePricing(
  payUsd: pay == null ? null : d(pay),
  expectedUsd: expected == null ? null : d(expected),
  minimumUsd: minimum == null ? null : d(minimum),
  networkCostUsd: network == null ? null : d(network),
  approvalNetworkCostUsd: approval == null ? null : d(approval),
  swapCostUsd: swap == null ? null : d(swap),
  isComplete: complete,
);

/// [quote] with the addresses and slippage a quote may report.
SwapQuote quoteWith(
  SwapQuote quote, {
  String? fromAddress,
  String? toAddress,
  double? slippage,
}) => SwapQuote(
  id: quote.id,
  source: quote.source,
  routeKind: quote.routeKind,
  order: quote.order,
  from: quote.from,
  to: quote.to,
  sellAmount: quote.sellAmount,
  expectedReceive: quote.expectedReceive,
  guaranteedReceive: quote.guaranteedReceive,
  fees: quote.fees,
  stages: quote.stages,
  approval: quote.approval,
  fromAddress: fromAddress,
  toAddress: toAddress,
  estimatedDuration: quote.estimatedDuration,
  slippage: slippage,
  quotedAt: quote.quotedAt,
  pricing: quote.pricing,
);

/// Pumps [child] as the swap surface shows it: English, the app's font, a
/// dark theme, and the swap bloc, services and shell above it.
Future<void> pumpSwapUi(
  WidgetTester tester,
  Widget child, {
  required UnifiedSwapBloc bloc,
  required SwapServices services,
  SwapShellController? shell,
  List<BlocProvider> providers = const [],
  Size size = const Size(420, 1600),
  double textScale = 1,
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = shell ?? SwapShellController();
  if (shell == null) addTearDown(controller.dispose);
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
            brightness: Brightness.dark,
            fontFamily: swapFont,
            // Copying sizes its snack bar on a wide screen type, which only a
            // floating one accepts, and an earlier test may leave it wide.
            snackBarTheme: const SnackBarThemeData(
              behavior: SnackBarBehavior.floating,
            ),
          ),
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          builder: (context, app) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              supportsAnnounce: true,
            ),
            child: app!,
          ),
          home: RepositoryProvider<SwapServices>.value(
            value: services,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<UnifiedSwapBloc>.value(value: bloc),
                ...providers,
              ],
              child: SwapShellScope(
                controller: controller,
                child: Scaffold(body: child),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

/// Emits [state] from [bloc] and draws the frame it causes: one pump
/// delivers the state, the next draws it.
Future<void> emitSwapState(
  WidgetTester tester,
  UnifiedSwapBloc bloc,
  UnifiedSwapState state,
) async {
  bloc.emit(state);
  await tester.pump();
  await tester.pump();
}

/// Pumps a page whose "open" button pushes [page] as a route, opens it,
/// and returns what the route pops with.
Future<List<Object?>> openSwapRoute(
  WidgetTester tester,
  Widget page, {
  required UnifiedSwapBloc bloc,
  required SwapServices services,
  Size size = const Size(420, 1600),
  double textScale = 1,
}) async {
  final popped = <Object?>[];
  await pumpSwapUi(
    tester,
    Builder(
      builder: (context) => TextButton(
        onPressed: () async => popped.add(
          await Navigator.of(context).push<Object?>(
            MaterialPageRoute(builder: (_) => Scaffold(body: page)),
          ),
        ),
        child: const Text('open'),
      ),
    ),
    bloc: bloc,
    services: services,
    size: size,
    textScale: textScale,
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return popped;
}

/// Records what is copied to the clipboard for the rest of the test.
List<String> recordClipboard(WidgetTester tester) {
  final copied = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      copied.add((call.arguments as Map)['text'] as String);
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return copied;
}

/// Whether the button showing [text] can be pressed.
bool swapButtonEnabled(WidgetTester tester, Finder text) =>
    tester
        .widget<TextButton>(
          find.ancestor(of: text, matching: find.byType(TextButton)).first,
        )
        .onPressed !=
    null;

final Finder swapPrimaryAction = find.byKey(const Key('swap-primary-action'));

String swapPrimaryLabel(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(of: swapPrimaryAction, matching: find.byType(Text)),
    )
    .map((text) => text.data)
    .join();

bool swapPrimaryBusy() => find
    .descendant(
      of: swapPrimaryAction,
      matching: find.byType(CircularProgressIndicator),
    )
    .evaluate()
    .isNotEmpty;

bool sameRow(WidgetTester tester, Finder a, Finder b) =>
    (tester.getTopLeft(a).dy - tester.getTopLeft(b).dy).abs() < 1;

bool above(WidgetTester tester, Finder a, Finder b) =>
    tester.getBottomLeft(a).dy <= tester.getTopLeft(b).dy;

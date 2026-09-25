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
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:web_dex/bloc/system_health/system_health_bloc.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_history_repository.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_preferences.dart';
import 'package:web_dex/shared/swap/swap_pricing.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/shared/swap/swap_terms_repository.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

import 'swap_accessibility_checks.dart';
import 'swap_test_fixtures.dart';

/// A token the fixtures lack: what a route can deliver instead of USDC.
final weth = assetOf('WETH-ERC20', parent: eth);

class _EnglishAssetLoader extends AssetLoader {
  const _EnglishAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/en.json').readAsStringSync())
          as Map<String, dynamic>;
}

/// Loads the app's font and English copy, once per test file.
Future<void> loadSurfaceCopy() async {
  await loadSwapFont();
  // The analyzer does not treat test_units as tests.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  await EasyLocalization.ensureInitialized();
}

/// Puts back the English copy a test may have replaced.
void resetSurfaceCopy() => Localization.load(const Locale('en'));

/// Gives the current test fresh app routes, putting the app's back after.
void useFreshRoutingState() {
  final previous = routingState;
  routingState = RoutingState();
  addTearDown(() => routingState = previous);
}

/// Wraps a surface under test in something it reads: a provider, a scope.
typedef SurfaceWrap = Widget Function(Widget child);

/// Pumps [child] the way the app shows the swap surface: English copy, the
/// app's font, and whatever [services], [swap] bloc and [shell] it reads.
Future<void> pumpSurface(
  WidgetTester tester,
  Widget child, {
  SwapServices? services,
  UnifiedSwapBloc? swap,
  SwapShellController? shell,
  List<SurfaceWrap> wrap = const [],
  Size size = const Size(420, 1600),
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  var body = child;
  if (shell != null) body = SwapShellScope(controller: shell, child: body);
  if (swap != null) {
    body = BlocProvider<UnifiedSwapBloc>.value(value: swap, child: body);
  }
  for (final outer in wrap.reversed) {
    body = outer(body);
  }
  if (services != null) {
    body = RepositoryProvider<SwapServices>.value(value: services, child: body);
  }
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
          theme: ThemeData(brightness: Brightness.dark, fontFamily: swapFont),
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          home: Scaffold(body: body),
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

/// Every text under [finder], in order.
List<String> textsOf(WidgetTester tester, Finder finder) => tester
    .widgetList<Text>(find.descendant(of: finder, matching: find.byType(Text)))
    .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
    .toList();

/// The swap services, answered from memory, with the app's own intent and
/// open-request hand-offs.
class SurfaceServices implements SwapServices {
  SurfaceServices(this.registry, {SwapHistoryRepository? history})
    : history = history ?? ScriptedHistory();

  @override
  final SwapExecutionRegistry registry;

  @override
  SwapHistoryRepository history;

  @override
  final Set<String> viewing = {};

  @override
  String? lastRouteIntent;

  @override
  late final SwapTermsRepository terms = SwapTermsRepository(
    walletKey: () async => 'w',
    storage: MemoryStorage(),
  );

  @override
  late final SwapPreferences preferences = SwapPreferences(
    walletKey: () async => 'w',
    storage: MemoryStorage(),
  );

  /// Explorer links by transaction hash; a hash without one has no link.
  Map<String, Uri> explorer = {};

  /// Which asset each explorer link was asked for, by hash.
  final Map<String, AssetId?> explorerAsked = {};

  /// The trading and clock checks the shell handed the quote repository.
  bool Function(AssetId from, AssetId to)? tradingAllowed;
  bool Function()? clockValid;

  final StreamController<SwapIntent> _intents =
      StreamController<SwapIntent>.broadcast();
  final StreamController<SwapExecutionRef> _openRequests =
      StreamController<SwapExecutionRef>.broadcast();
  SwapIntent? _pendingIntent;
  SwapExecutionRef? _pendingOpen;

  @override
  void requestIntent(SwapIntent intent) {
    _pendingIntent = intent;
    _intents.add(intent);
  }

  @override
  Stream<SwapIntent> get intents => _intents.stream;

  @override
  SwapIntent? takePendingIntent() {
    final pending = _pendingIntent;
    _pendingIntent = null;
    return pending;
  }

  @override
  void requestOpen(SwapExecutionRef ref) {
    _pendingOpen = ref;
    _openRequests.add(ref);
  }

  @override
  Stream<SwapExecutionRef> get openRequests => _openRequests.stream;

  @override
  SwapExecutionRef? takePendingOpen() {
    final pending = _pendingOpen;
    _pendingOpen = null;
    return pending;
  }

  @override
  UnifiedSwapRepository createRepository({
    required bool Function(AssetId from, AssetId to) tradingAllowed,
    required bool Function() clockValid,
  }) {
    this.tradingAllowed = tradingAllowed;
    this.clockValid = clockValid;
    return UnifiedSwapRepository(
      sources: [FakeQuoteSource(SwapLiquiditySource.routed, tradable: {})],
      pricing: SwapPricingService(FakePriceSource({eth: d('3000')})),
    );
  }

  @override
  SwapNetworks networks() => SwapNetworks([eth, usdc, btc, gleec]);

  @override
  Uri? explorerTxUrl(AssetId? asset, String hash) {
    explorerAsked[hash] = asset;
    return explorer[hash];
  }

  @override
  Future<Decimal?> spendableBalance(AssetId id) async => null;

  @override
  Future<String?> addressOf(AssetId id) async => null;

  @override
  AssetId? resolveAsset(String ticker) => null;

  @override
  Future<List<SwapHolding>> holdings() async => const [];

  @override
  Future<Set<AssetId>> activatedAssets() async => {eth, usdc};

  @override
  bool isTestnet(AssetId id) => false;

  @override
  Decimal? usdPrice(AssetId id) => id == eth ? d('3000') : null;

  @override
  Decimal? lastKnownBalance(AssetId id) => null;

  @override
  String? contractOf(AssetId id) => null;

  @override
  Future<void> dispose() async {
    await _intents.close();
    await _openRequests.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// History answered from a script: what each filter holds, which sources
/// fail, and an optional gate that holds a load open.
class ScriptedHistory implements SwapHistoryRepository {
  List<SwapExecutionSnapshot> entries = [];
  Set<SwapLiquiditySource> failedSources = {};
  bool hasMore = false;
  Object? error;
  Completer<void>? gate;
  final List<({SwapActivityFilter filter, int limit})> loads = [];

  @override
  Future<SwapActivityPage> load({
    required SwapActivityFilter filter,
    int limit = 25,
  }) async {
    loads.add((filter: filter, limit: limit));
    await gate?.future;
    if (error case final Object error) throw error;
    return SwapActivityPage(
      entries: [
        for (final entry in entries)
          if (SwapHistoryRepository.matches(entry, filter)) entry,
      ],
      failedSources: failedSources,
      hasMore: hasMore,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// An executor whose resume the test can hold open.
class GatedExecutor extends FakeExecutor {
  GatedExecutor(super.source);

  Completer<void>? resumeGate;

  @override
  Future<SwapExecutionHandle?> resume(String id) async {
    await resumeGate?.future;
    return super.resume(id);
  }
}

/// A handle whose cancel the test answers.
class GatedHandle extends FakeHandle {
  GatedHandle(super.latest);

  final Completer<void> cancelGate = Completer<void>();

  @override
  Future<void> cancel() async {
    await super.cancel();
    await cancelGate.future;
  }
}

/// The swap form's bloc, recording what the surface asks of it instead of
/// acting on it.
class RecordingSwapBloc extends UnifiedSwapBloc {
  RecordingSwapBloc(SwapExecutionRegistry registry)
    : super(
        repository: UnifiedSwapRepository(
          sources: [FakeQuoteSource(SwapLiquiditySource.routed)],
          pricing: SwapPricingService(FakePriceSource({eth: d('3000')})),
        ),
        registry: registry,
        terms: SwapTermsRepository(
          walletKey: () async => 'w',
          storage: MemoryStorage(),
        ),
        preferences: SwapPreferences(
          walletKey: () async => 'w',
          storage: MemoryStorage(),
        ),
        spendableBalance: (_) async => d('2'),
        addressOf: (_) async => null,
        resolveAsset: (_) => null,
      );

  final List<UnifiedSwapEvent> events = [];

  @override
  void add(UnifiedSwapEvent event) => events.add(event);
}

/// Every event added to any bloc, and every bloc closed.
class RecordingBlocObserver extends BlocObserver {
  final List<Object?> events = [];
  final List<BlocBase<dynamic>> closed = [];

  Iterable<T> eventsOf<T>() => events.whereType<T>();

  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    events.add(event);
  }

  @override
  void onClose(BlocBase<dynamic> bloc) {
    super.onClose(bloc);
    closed.add(bloc);
  }
}

/// Opens nothing; remembers every URL it was asked to.
class RecordingUrlLauncher extends UrlLauncherPlatform {
  final List<String> launched = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

/// Routes URL launches to a [RecordingUrlLauncher] for the current test.
RecordingUrlLauncher recordUrlLaunches() {
  final previous = UrlLauncherPlatform.instance;
  final launcher = RecordingUrlLauncher();
  UrlLauncherPlatform.instance = launcher;
  addTearDown(() => UrlLauncherPlatform.instance = previous);
  return launcher;
}

/// Collects what is copied to the clipboard in the current test.
List<String> recordClipboard() {
  final copied = <String>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
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

/// A bloc's state, set by the test.
mixin _SetState<S> {
  late S _state;
  final StreamController<S> _states = StreamController<S>.broadcast();

  S get state => _state;

  Stream<S> get stream => _states.stream;

  void push(S state) {
    _state = state;
    _states.add(state);
  }
}

/// Trading availability the test sets.
class FakeTradingStatusBloc
    with _SetState<TradingStatusState>
    implements TradingStatusBloc {
  FakeTradingStatusBloc([TradingStatusState? initial]) {
    _state = initial ?? TradingStatusLoadSuccess();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A device clock check the test sets.
class FakeSystemHealthBloc
    with _SetState<SystemHealthState>
    implements SystemHealthBloc {
  FakeSystemHealthBloc([SystemHealthState? initial]) {
    _state = initial ?? SystemHealthLoadSuccess(true);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// [base] with the parts [snapshotOf] cannot set: missing assets, amounts
/// and addresses, timestamps, and the full evidence.
SwapExecutionSnapshot reshaped(
  SwapExecutionSnapshot base, {
  bool noFrom = false,
  bool noTo = false,
  bool noSellAmount = false,
  bool noFromAddress = false,
  bool noToAddress = false,
  DateTime? createdAt,
  DateTime? updatedAt,
  SwapEvidence? evidence,
}) => SwapExecutionSnapshot(
  id: base.id,
  source: base.source,
  routeKind: base.routeKind,
  from: noFrom ? null : base.from,
  fromTicker: base.fromTicker,
  to: noTo ? null : base.to,
  toTicker: base.toTicker,
  sellAmount: noSellAmount ? null : base.sellAmount,
  expectedReceive: base.expectedReceive,
  minimumReceive: base.minimumReceive,
  fromAddress: noFromAddress ? null : base.fromAddress,
  toAddress: noToAddress ? null : base.toAddress,
  stage: base.stage,
  outcome: base.outcome,
  fundsMovement: base.fundsMovement,
  canCancel: base.canCancel,
  approval: base.approval,
  approvalRemains: base.approvalRemains,
  stages: base.stages,
  estimatedDuration: base.estimatedDuration,
  createdAt: createdAt ?? base.createdAt,
  updatedAt: updatedAt ?? base.updatedAt,
  finishedAt: base.finishedAt,
  delayedSince: base.delayedSince,
  evidence: evidence ?? base.evidence,
);

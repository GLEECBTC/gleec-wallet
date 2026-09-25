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
import 'package:web_dex/bloc/swap_activity/swap_activity_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_history_repository.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_preferences.dart';
import 'package:web_dex/shared/swap/swap_pricing.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/shared/swap/swap_terms_repository.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';
import 'package:web_dex/views/swap/activity/swap_activity_view.dart';
import 'package:web_dex/views/swap/entry/swap_entry_view.dart';
import 'package:web_dex/views/swap/entry/swap_quote_strip.dart';
import 'package:web_dex/views/swap/execution/swap_execution_view.dart';
import 'package:web_dex/views/swap/review/swap_review_view.dart';
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

/// What the swap screens are allowed to say about someone's money, and what
/// they let them do next.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SwapExecutionRegistry registry;
  late FakeExecutor routedExecutor;
  late _FakeServices services;
  late UnifiedSwapBloc swap;
  late SwapShellController shell;

  setUpAll(() async {
    await loadSwapFont();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  setUp(() {
    routedExecutor = FakeExecutor(SwapLiquiditySource.routed);
    registry = SwapExecutionRegistry(
      executors: [routedExecutor],
      inFlight: () async => const [],
    );
    services = _FakeServices(registry);
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

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    SwapActivityBloc? activity,
    Size size = const Size(420, 1600),
  }) async {
    tester.view.physicalSize = size;
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
            theme: ThemeData(brightness: Brightness.dark, fontFamily: swapFont),
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: RepositoryProvider<SwapServices>.value(
              value: services,
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<UnifiedSwapBloc>.value(value: swap),
                  if (activity != null)
                    BlocProvider<SwapActivityBloc>.value(value: activity),
                ],
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
    await expectSwapAccessible(tester);
  }

  UnifiedSwapState formState({
    String input = '1',
    SwapEvaluationStatus evaluation = SwapEvaluationStatus.ready,
    SwapQuote? quote,
    SwapQuoteFailure? failure,
    SwapFormIssue? issue,
    bool tradingEnabled = true,
  }) {
    final selected = quote ?? quoteOf();
    final ready =
        evaluation == SwapEvaluationStatus.ready ||
        evaluation == SwapEvaluationStatus.expired;
    return UnifiedSwapState(
      loadingAssets: false,
      pay: eth,
      receive: usdc,
      inputText: input,
      balance: d('2'),
      issue: issue,
      evaluation: evaluation,
      quotes: ready
          ? UnifiedSwapQuotes(
              ranked: [selected],
              unrankable: const [],
              failures: const [],
            )
          : null,
      selectedId: ready ? selected.id : null,
      failure: failure,
      tradingEnabled: tradingEnabled,
    );
  }

  Finder primary() => find.byKey(const Key('swap-primary-action'));

  String primaryLabel(WidgetTester tester) => tester
      .widgetList<Text>(
        find.descendant(of: primary(), matching: find.byType(Text)),
      )
      .map((t) => t.data)
      .join();

  bool primaryEnabled(WidgetTester tester) =>
      tester
          .widget<TextButton>(
            find.descendant(of: primary(), matching: find.byType(TextButton)),
          )
          .onPressed !=
      null;

  group('entry', () {
    testWidgets('asks for an amount before anything else', (tester) async {
      swap.emit(
        formState(
          input: '',
          issue: SwapFormIssue.amountMissing,
        ).copyWith(evaluation: SwapEvaluationStatus.idle, clearQuotes: true),
      );
      await pump(tester, const SwapEntryView());

      expect(find.byKey(const Key('swap-amount')), findsOneWidget);
      expect(primaryLabel(tester), 'Enter amount');
      expect(primaryEnabled(tester), isFalse);
    });

    testWidgets('leads with the guaranteed minimum and offers review', (
      tester,
    ) async {
      swap.emit(formState());
      await pump(tester, const SwapEntryView());

      expect(find.text('Minimum received'), findsOneWidget);
      expect(find.text('2,985 USDC'), findsOneWidget);
      expect(primaryLabel(tester), 'Review swap');
      expect(primaryEnabled(tester), isTrue);
    });

    testWidgets('explains a missing route and offers a retry', (tester) async {
      swap.emit(
        formState(
          evaluation: SwapEvaluationStatus.failed,
          failure: const SwapQuoteFailure(
            source: SwapLiquiditySource.routed,
            kind: SwapQuoteFailureKind.noRoute,
          ),
        ),
      );
      await pump(tester, const SwapEntryView());

      expect(
        find.text('No swap is available for this amount and pair right now.'),
        findsOneWidget,
      );
      expect(primaryLabel(tester), 'Try again');
    });

    testWidgets('an expired quote must be refreshed, not reviewed', (
      tester,
    ) async {
      swap.emit(formState(evaluation: SwapEvaluationStatus.expired));
      await pump(tester, const SwapEntryView());

      expect(primaryLabel(tester), 'Refresh quote');
      expect(find.text('Quote expired'), findsOneWidget);
    });

    testWidgets('trading unavailable here blocks the swap', (tester) async {
      swap.emit(formState(tradingEnabled: false));
      await pump(tester, const SwapEntryView());

      expect(primaryEnabled(tester), isFalse);
      expect(find.text('Trading unavailable in your location'), findsWidgets);
    });

    testWidgets('prices an amount that is too much, but only to look at', (
      tester,
    ) async {
      swap.emit(formState(input: '5', issue: SwapFormIssue.insufficient));
      await pump(tester, const SwapEntryView());

      expect(
        find.text('Only 2 ETH is spendable at this address.'),
        findsOneWidget,
      );
      expect(find.byType(SwapQuoteStrip), findsOneWidget);
      expect(
        find.descendant(of: primary(), matching: find.text('Not enough ETH')),
        findsOneWidget,
      );
      expect(primaryEnabled(tester), isFalse);
    });

    testWidgets('that price is not kept fresh, but can be refreshed', (
      tester,
    ) async {
      swap.emit(
        formState(
          input: '5',
          issue: SwapFormIssue.insufficient,
          evaluation: SwapEvaluationStatus.expired,
        ),
      );
      await pump(tester, const SwapEntryView());

      expect(
        find.descendant(of: primary(), matching: find.text('Refresh quote')),
        findsOneWidget,
      );
      expect(primaryEnabled(tester), isTrue);
    });
  });

  group('review', () {
    UnifiedSwapState reviewState(SwapReview review) =>
        formState().copyWith(view: UnifiedSwapView.review, review: review);

    testWidgets('asks for an exact permission, never unlimited', (
      tester,
    ) async {
      final quote = quoteOf(
        from: usdc,
        to: eth,
        sell: '1250',
        expected: '0.41',
        guaranteed: '0.4',
        approval: SwapApprovalRequirement(
          asset: usdc,
          exactAmount: d('1250'),
          resetsFirst: false,
        ),
      );
      swap.emit(
        reviewState(SwapReview(quote: quote, status: SwapReviewStatus.ready)),
      );
      await pump(tester, const SwapReviewView());

      expect(find.text("You'll receive at least"), findsOneWidget);
      expect(find.text('Approve exactly 1,250 USDC & start'), findsOneWidget);
      expect(find.text('Exact approval only'), findsOneWidget);
    });

    testWidgets('a first routed swap shows the provider terms', (tester) async {
      swap.emit(
        reviewState(
          SwapReview(
            quote: quoteOf(),
            status: SwapReviewStatus.ready,
            termsRequired: true,
          ),
        ),
      );
      await pump(tester, const SwapReviewView());

      expect(find.byKey(const Key('swap-terms-link')), findsOneWidget);
    });

    testWidgets('a lost start answer points to Activity, never restarts', (
      tester,
    ) async {
      swap.emit(
        reviewState(
          SwapReview(quote: quoteOf(), status: SwapReviewStatus.unconfirmed),
        ),
      );
      await pump(tester, const SwapReviewView());

      expect(find.text('View in Activity'), findsOneWidget);
      expect(find.byKey(const Key('swap-start')), findsNothing);
      expect(
        find.text("We couldn't confirm whether this swap started"),
        findsOneWidget,
      );
    });

    testWidgets('shows old against new when the outcome moved', (tester) async {
      swap.emit(
        reviewState(
          SwapReview(
            quote: quoteOf(guaranteed: '2900'),
            previous: quoteOf(),
            status: SwapReviewStatus.materialUpdate,
          ),
        ),
      );
      await pump(tester, const SwapReviewView());

      expect(
        find.text('Minimum changed from 2,985 USDC to 2,900 USDC.'),
        findsOneWidget,
      );
      expect(find.text('Accept updated quote'), findsOneWidget);
    });
  });

  group('outcomes', () {
    Future<void> pumpOutcome(
      WidgetTester tester,
      SwapExecutionSnapshot snapshot,
    ) async {
      routedExecutor.resumable[snapshot.id] = FakeHandle(snapshot);
      await pump(
        tester,
        SwapExecutionView(
          id: snapshot.id,
          source: SwapLiquiditySource.routed,
          initial: snapshot,
          context: SwapExecutionContext.activity,
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
    }

    testWidgets('a completion says what arrived and where', (tester) async {
      await pumpOutcome(tester, snapshotOf(outcome: completed()));

      expect(find.text('You received 3,001 USDC'), findsOneWidget);
    });

    testWidgets('a failure answers the three questions', (tester) async {
      await pumpOutcome(
        tester,
        snapshotOf(
          fundsMovement: SwapFundsMovement.sent,
          outcome: failed(SwapFailureReason.routeFailed),
        ),
      );

      expect(find.text('WHAT HAPPENED?'), findsOneWidget);
      expect(find.text('WHERE ARE THE FUNDS?'), findsOneWidget);
      expect(find.text('WHAT CAN I DO NOW?'), findsOneWidget);
      expect(find.text('Contact Gleec support'), findsOneWidget);
    });

    testWidgets('a running swap can be left, and cancelled only when safe', (
      tester,
    ) async {
      await pumpOutcome(
        tester,
        snapshotOf(
          stage: SwapProgressStage.preparing,
          fundsMovement: SwapFundsMovement.none,
          canCancel: true,
        ),
      );

      expect(
        find.text('You can leave this screen. The swap continues in Activity.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('swap-cancel')), findsOneWidget);
    });
  });

  group('activity', () {
    testWidgets('an empty Active view says where swaps will appear', (
      tester,
    ) async {
      // The bloc runs in the real zone; creating, settling and closing it
      // inside the fake-async test body would hang the runner.
      final activity = (await tester.runAsync(() async {
        final bloc = SwapActivityBloc(
          history: _EmptyHistory(),
          registry: registry,
        )..add(const SwapActivityStarted());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return bloc;
      }))!;
      addTearDown(() => tester.runAsync(activity.close));
      await pump(tester, const SwapActivityView(), activity: activity);

      expect(find.text('No active swaps'), findsOneWidget);
      expect(find.text('Start a swap'), findsOneWidget);
    });
  });
}

class _FakeServices implements SwapServices {
  _FakeServices(this.registry);

  @override
  final SwapExecutionRegistry registry;

  @override
  final Set<String> viewing = {};

  @override
  SwapNetworks networks() => SwapNetworks([eth, usdc, btc, gleec]);

  @override
  Decimal? usdPrice(AssetId id) => id == eth ? d('3000') : null;

  @override
  String? contractOf(AssetId id) => null;

  @override
  Uri? explorerTxUrl(AssetId? asset, String hash) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyHistory implements SwapHistoryRepository {
  @override
  Future<SwapActivityPage> load({
    required SwapActivityFilter filter,
    int limit = 25,
  }) async =>
      const SwapActivityPage(entries: [], failedSources: {}, hasMore: false);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

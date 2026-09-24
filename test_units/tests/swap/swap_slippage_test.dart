// The analyzer does not treat test_units as tests, so test-only members
// read as violations here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
// No public API resets the package's global translations between groups.
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_preferences.dart';
import 'package:web_dex/shared/swap/swap_pricing.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/swap/swap_terms_repository.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';
import 'package:web_dex/views/swap/pickers/swap_slippage_sheet.dart';

import 'swap_test_fixtures.dart';

class _EnglishAssetLoader extends AssetLoader {
  const _EnglishAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/en.json').readAsStringSync())
          as Map<String, dynamic>;
}

/// Covers how far a cross-network route may fill below its expected amount:
/// chosen deliberately, kept within a range that protects the user, and
/// applied to every price after the change.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the form re-prices with the chosen slippage', () {
    late FakeQuoteSource routed;
    late SwapExecutionRegistry registry;

    setUp(() {
      routed = FakeQuoteSource(
        SwapLiquiditySource.routed,
        respond: (request) => [
          SwapQuoteAvailable(
            quoteOf(
              from: request.from,
              to: request.to,
              quotedAt: DateTime(2026),
            ),
          ),
        ],
      );
      registry = SwapExecutionRegistry(
        executors: [FakeExecutor(SwapLiquiditySource.routed)],
        inFlight: () async => const [],
      );
    });

    tearDown(() => registry.dispose());

    Future<UnifiedSwapBloc> open() async {
      final storage = MemoryStorage();
      final bloc =
          UnifiedSwapBloc(
              repository: UnifiedSwapRepository(
                sources: [
                  routed,
                  FakeQuoteSource(
                    SwapLiquiditySource.atomic,
                    results: [
                      rejected(
                        SwapQuoteFailureKind.noRoute,
                        source: SwapLiquiditySource.atomic,
                      ),
                    ],
                  ),
                ],
                pricing: SwapPricingService(FakePriceSource()),
              ),
              registry: registry,
              terms: SwapTermsRepository(
                walletKey: () async => 'w',
                storage: storage,
              ),
              preferences: SwapPreferences(
                walletKey: () async => 'w',
                storage: storage,
              ),
              spendableBalance: (_) async => d('2'),
              addressOf: (_) async => '0xaddress',
              resolveAsset: (ticker) => {eth.id: eth, usdc.id: usdc}[ticker],
              debounce: Duration.zero,
              now: () => DateTime(2026),
            )
            ..add(const UnifiedSwapStarted())
            ..add(
              const UnifiedSwapIntentApplied(
                pay: 'ETH',
                receive: 'USDC-ERC20',
                amount: '1',
              ),
            );
      addTearDown(bloc.close);
      await pumpEventQueue(times: 50);
      return bloc;
    }

    test('the default is KDF\'s, and a change prices again with it', () async {
      final bloc = await open();
      expect(routed.requests.last.slippage, swapDefaultSlippage);

      bloc.add(const UnifiedSwapSlippageChanged(0.01));
      await pumpEventQueue(times: 50);

      expect(bloc.state.slippage, 0.01);
      expect(routed.requests.last.slippage, 0.01);
    });

    test('a value outside the offered range is held to it', () async {
      final bloc = await open();
      bloc.add(const UnifiedSwapSlippageChanged(0.3));
      await pumpEventQueue(times: 50);
      expect(bloc.state.slippage, swapMaxSlippage);
    });
  });

  test('percentages keep the places that matter', () {
    expect(slippageText(0.005), '0.5%');
    expect(slippageText(0.0005), '0.05%');
    expect(slippageText(0.01), '1%');
    expect(slippageText(0.05), '5%');
  });

  group('the setting', () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
    });

    tearDown(() => Localization.load(const Locale('en')));

    Future<List<double>> pump(WidgetTester tester, double initial) async {
      tester.view.physicalSize = const Size(420, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final saved = <double>[];
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
              theme: ThemeData.dark(),
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: Scaffold(
                body: SwapSlippageSheet(initial: initial, onSave: saved.add),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return saved;
    }

    testWidgets('a preset saves at once, and a high one is warned about', (
      tester,
    ) async {
      final saved = await pump(tester, 0.005);
      await tester.tap(find.text('2%'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Above 1%'), findsOneWidget);
      await tester.tap(find.text('Use 2%'));
      expect(saved, [0.02]);
    });

    testWidgets('a custom value outside 0.05% to 5% cannot be saved', (
      tester,
    ) async {
      final saved = await pump(tester, 0.005);
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '9');
      await tester.pumpAndSettle();

      expect(find.text('Enter a value from 0.05% to 5%.'), findsOneWidget);
      await tester.tap(find.text('Slippage').last);
      expect(saved, isEmpty);

      await tester.enterText(find.byType(TextField), '0.3');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use 0.3%'));
      expect(saved.single, closeTo(0.003, 1e-12));
    });
  });
}

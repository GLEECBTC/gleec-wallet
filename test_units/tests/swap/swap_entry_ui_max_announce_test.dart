import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/views/swap/entry/swap_entry_view.dart';

import 'swap_bloc_fakes.dart';
import 'swap_entry_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers what the form says once Max lands, with the real bloc behind it:
/// the fake bloc of the other form tests cannot re-price what Max applied.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpSwapUi();

  const maxApplied = 'Maximum amount applied with network fees kept back';

  testWidgets('a routed Max is announced once, not each time it is priced', (
    tester,
  ) async {
    final h = _WidgetClockHarness(() => tester.binding.clock.now());
    try {
      final bloc = h.build()
        ..add(const UnifiedSwapStarted())
        ..add(
          const UnifiedSwapIntentApplied(
            pay: 'ETH',
            receive: 'USDC-ERC20',
            amount: '1',
          ),
        );
      await pumpSwapUi(
        tester,
        const SwapEntryView(),
        bloc: bloc,
        services: FakeSwapServices(),
        settle: false,
      );
      await _settle(tester);
      expect(bloc.state.selectedQuote!.source, SwapLiquiditySource.routed);
      tester.takeAnnouncements();

      // As the aggregator answers it: its own source, and its quote not yet
      // priced in dollars.
      h.routed.max = SwapMaxAmount(
        amount: d('1.99'),
        reservedForFees: d('0.01'),
        feeAsset: eth,
        source: SwapLiquiditySource.routed,
        quote: quoteOf(
          id: 'routed-1.99',
          sell: '1.99',
          quotedAt: h.now(),
          pricing: const SwapQuotePricing(),
        ),
      );
      await tester.tap(find.text('Max'));
      await _settle(tester);

      expect(bloc.state.inputText, '1.99');
      expect(bloc.state.evaluation, SwapEvaluationStatus.ready);
      expect(_spoken(tester).where((m) => m == maxApplied), hasLength(1));

      // The form keeps the price fresh; the same Max is not news.
      await tester.pump(const Duration(seconds: 30));
      await _settle(tester);

      expect(h.routed.requests.last.maxSource, SwapLiquiditySource.routed);
      expect(h.routed.requests.last.automatic, isTrue);
      expect(bloc.state.inputText, '1.99');
      expect(_spoken(tester), isNot(contains(maxApplied)));

      // A Max that moved is.
      h.routed.respond = (request) => [
        SwapQuoteAvailable(
          quoteOf(id: 'routed-1.98', sell: '1.98', quotedAt: h.now()),
        ),
      ];
      await tester.pump(const Duration(seconds: 30));
      await _settle(tester);

      expect(bloc.state.inputText, '1.98');
      expect(_spoken(tester).where((m) => m == maxApplied), hasLength(1));
    } finally {
      h.dispose();
      await tester.pump();
    }
  });
}

/// Lets the bloc's handlers, its zero-delay timers and the frames they cause
/// all run.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(Duration.zero);
  }
}

List<String> _spoken(WidgetTester tester) =>
    tester.takeAnnouncements().map((a) => a.message).toList();

/// The bloc harness on the widget test's own fake clock, which only
/// [WidgetTester.pump] moves on.
class _WidgetClockHarness extends SwapBlocHarness {
  _WidgetClockHarness(this._clock) : super(FakeAsync());

  final DateTime Function() _clock;

  @override
  DateTime now() => _clock();
}

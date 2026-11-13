// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/entry/swap_entry_view.dart';

import 'swap_entry_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers what the form says about the wallet itself: a hardware wallet
/// can't swap at all, and a swap spends from one address of an HD wallet.
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

  Future<void> pump(WidgetTester tester, UnifiedSwapState state) async {
    swap.emit(state);
    await pumpSwapUi(
      tester,
      const SwapEntryView(),
      bloc: swap,
      services: services,
    );
  }

  List<String> lines(WidgetTester tester) => [
    for (final line in tester.widgetList<SwapHelperLine>(
      find.byType(SwapHelperLine),
    ))
      line.text,
  ];

  group('a hardware wallet', () {
    const notice =
        'Trezor currently supports wallet-only mode. Trading and swaps are '
        'unavailable for now.';
    final hardware = swapBaseForm().copyWith(
      tradingEnabled: false,
      hardwareWallet: true,
    );

    testWidgets('is told swaps are unavailable, with nothing to press', (
      tester,
    ) async {
      await pump(tester, hardware);

      expect(find.text(notice), findsOneWidget);
      expect(find.text('Trading unavailable in your location'), findsNothing);
      expect(swapPrimaryLabel(tester), 'Swaps unavailable');
      expect(
        swapButtonEnabled(tester, find.text('Swaps unavailable')),
        isFalse,
      );
    });

    testWidgets('is told so before any asset is chosen', (tester) async {
      await pump(tester, hardware.copyWith(clearPay: true, clearReceive: true));

      expect(find.text(notice), findsOneWidget);
      expect(swapPrimaryLabel(tester), 'Swaps unavailable');
    });
  });

  group('funds at other addresses', () {
    final short = swapPricedForm().copyWith(
      inputText: '3',
      issue: SwapFormIssue.insufficient,
    );

    testWidgets('a shortfall says what they hold, and why it is not used', (
      tester,
    ) async {
      services.elsewhere[eth] = d('2.9');
      await pump(tester, short);

      expect(lines(tester), [
        'Only 2 ETH is spendable at this address.',
        'This wallet holds another 2.9 ETH at other addresses. Swaps spend '
            'only from this one, so move funds here first.',
      ]);
      expect(swapPrimaryLabel(tester), 'Not enough ETH');
    });

    testWidgets('nothing held there, or nothing known, adds nothing', (
      tester,
    ) async {
      services.elsewhere[eth] = d('0');
      await pump(tester, short);
      expect(lines(tester), ['Only 2 ETH is spendable at this address.']);

      services.elsewhere.clear();
      await pump(tester, short.copyWith(inputText: '4'));
      expect(lines(tester), ['Only 2 ETH is spendable at this address.']);
    });
  });
}

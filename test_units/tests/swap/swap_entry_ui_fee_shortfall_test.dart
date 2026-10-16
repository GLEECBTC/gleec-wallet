// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/entry/swap_entry_view.dart';

import 'swap_entry_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the line under the cards when fees paid on top of the amount are
/// what the pay balance falls short of.
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

  SwapFeeComponent onTop(String amount, AssetId asset, SwapFeeKind kind) =>
      SwapFeeComponent(
        kind: kind,
        amount: d(amount),
        deductedFromReceive: false,
        asset: asset,
      );

  /// Selling [sell] USDC with a provider fee of 0.25 USDC on top.
  UnifiedSwapState sellingUsdc(String sell) =>
      swapPricedForm(
        ranked: [
          quoteOf(
            from: usdc,
            to: eth,
            sell: sell,
            expected: '0.033',
            guaranteed: '0.032',
            fees: [
              onTop('0.001', eth, SwapFeeKind.network),
              onTop('0.25', usdc, SwapFeeKind.swap),
            ],
          ),
        ],
      ).copyWith(
        pay: usdc,
        receive: eth,
        inputText: sell,
        balance: d('100'),
        feeBalance: d('1'),
        issue: SwapFormIssue.insufficient,
      );

  testWidgets('a fee in the pay asset names what the swap needs with it', (
    tester,
  ) async {
    await pump(tester, sellingUsdc('99.8'));

    expect(lines(tester), [
      'You need about 100.05 USDC for this swap and its fees. This '
          'address has 100 USDC.',
    ]);
    expect(swapPrimaryLabel(tester), 'Not enough USDC');
  });

  testWidgets('more than the balance still says what is spendable', (
    tester,
  ) async {
    await pump(tester, sellingUsdc('120'));

    expect(lines(tester), ['Only 100 USDC is spendable at this address.']);
  });

  testWidgets('gas on top of a whole balance is named the same way', (
    tester,
  ) async {
    await pump(
      tester,
      swapPricedForm(
        ranked: [quoteOf(sell: '2')],
      ).copyWith(inputText: '2', issue: SwapFormIssue.insufficient),
    );

    expect(lines(tester), [
      'You need about 2.001 ETH for this swap and its fees. This address '
          'has 2 ETH.',
    ]);
    expect(swapPrimaryLabel(tester), 'Not enough ETH');
  });

  testWidgets('the gas to refund a failed swap is named when it counts', (
    tester,
  ) async {
    await pump(
      tester,
      swapPricedForm(
        ranked: [quoteOf(sell: '2', refundReserve: '0.0005')],
      ).copyWith(
        inputText: '2',
        balance: d('2.001'),
        issue: SwapFormIssue.insufficient,
      ),
    );

    expect(lines(tester), [
      'You need about 2.0015 ETH for this swap, its fees and the gas to '
          'refund it if it fails. This address has 2.001 ETH.',
    ]);
  });

  testWidgets('after Max, which kept that gas back, only fees are named', (
    tester,
  ) async {
    // Max kept 0.01 ETH back; fees have since risen to 0.02 ETH.
    await pump(
      tester,
      swapPricedForm(
        ranked: [
          quoteOf(
            sell: '2',
            fees: [onTop('0.02', eth, SwapFeeKind.network)],
            refundReserve: '0.0005',
          ),
        ],
      ).copyWith(
        inputText: '2',
        balance: d('2.01'),
        maxApplied: SwapMaxAmount(
          amount: d('2'),
          reservedForFees: d('0.01'),
          feeAsset: eth,
          coversRefund: true,
        ),
        issue: SwapFormIssue.insufficient,
      ),
    );

    expect(lines(tester), [
      'You need about 2.02 ETH for this swap and its fees. This address '
          'has 2.01 ETH.',
    ]);
  });
}

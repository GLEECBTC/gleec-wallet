import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/atomic_swap_source.dart';
import 'package:web_dex/shared/swap/routed_swap_source.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

import 'swap_bloc_fakes.dart';
import 'swap_src_fakes.dart';
import 'swap_test_fixtures.dart';

final _networks = SwapNetworks([eth, usdc, btc]);

RoutedSwapCost _gas(String amount) => RoutedSwapCost(
  label: 'Network fee',
  amount: d(amount),
  kind: RoutedSwapCostKind.gas,
  isDeductedFromReceive: false,
  assetId: eth,
);

/// A provider fee of a LI.FI route: [onTop] for `included: false`, as
/// Squid's gas receiver fee is.
RoutedSwapCost _providerFee(
  String amount,
  AssetId asset, {
  required bool onTop,
}) => RoutedSwapCost(
  label: 'Gas receiver fee',
  amount: d(amount),
  kind: RoutedSwapCostKind.providerFee,
  isDeductedFromReceive: !onTop,
  assetId: asset,
);

List<SwapQuoteResult> _routed(
  SwapQuoteRequest request,
  DateTime now,
  List<RoutedSwapCost> costs,
) => [
  SwapQuoteAvailable(
    routedQuoteFromOffer(
      offerOf(
        from: request.from,
        to: request.to,
        sell: request.amount.toString(),
        expected: '0.033',
        guaranteed: '0.032',
        costs: costs,
        quotedAt: now,
      ),
      networks: _networks,
    ),
  ),
];

/// The order-book source selling ETH at [price]: its preimage puts 0.02185 ETH
/// of trading fee and gas on top of 1 ETH, and [claim] to claim what arrives.
/// Refunding the payment takes 0.00125 ETH more.
AtomicSwapQuoteSource _book(
  SwapBlocHarness h,
  String price,
  PreimageCoinFee claim, {
  String kdfMax = '1',
}) => AtomicSwapQuoteSource(
  trading: SrcTrading()
    ..maxTaker = kdfMax
    ..bids = [bidOf(price, '0.01', '5')]
    ..preimage = preimageOf(
      takerFee: coinFeeOf('ETH', '0.02'),
      feeToSendTakerFee: coinFeeOf('ETH', '0.0003'),
      baseCoinFee: coinFeeOf('ETH', '0.00155'),
      relCoinFee: claim,
    ),
  networks: () => _networks,
  now: h.now,
);

/// Selling ETH for BTC, whose claim comes out of the BTC that arrives.
AtomicSwapQuoteSource _ethForBtc(SwapBlocHarness h, {String kdfMax = '1'}) =>
    _book(
      h,
      '0.05',
      coinFeeOf('BTC', '0.00001', fromVolume: true),
      kdfMax: kdfMax,
    );

/// Selling ETH for a token on Ethereum, whose claim the ETH pays.
AtomicSwapQuoteSource _ethForUsdc(SwapBlocHarness h, {String kdfMax = '1'}) =>
    _book(h, '3000', coinFeeOf('ETH', '0.002'), kdfMax: kdfMax);

/// [source]'s quote for selling 1 ETH for [to].
SwapQuote _bookQuote(
  SwapBlocHarness h,
  AtomicSwapQuoteSource source,
  AssetId to,
) {
  final results = h.resolve(
    source.quote(SwapQuoteRequest(from: eth, to: to, amount: d('1'))),
  );
  return (results.single as SwapQuoteAvailable).quote;
}

/// Only the order book prices, and only 1 ETH, as [quote].
void _onlyTheBook(SwapBlocHarness h, SwapQuote quote) {
  h.routed
    ..respond = null
    ..results = [rejected(SwapQuoteFailureKind.noRoute)];
  h.atomic.respond = (request) => [
    if (request.amount == quote.sellAmount)
      SwapQuoteAvailable(quote)
    else
      rejected(
        SwapQuoteFailureKind.noRoute,
        source: SwapLiquiditySource.atomic,
      ),
  ];
}

/// Covers the form's checks that depend on prices and fees rather than on
/// the typed text alone.
void main() {
  swapBlocTest('a dollar amount with no price to convert it is named', (h) {
    final bloc = h.open()..add(const UnifiedSwapAmountModeToggled());
    h.settle();
    h.prices.prices.remove(eth);

    bloc.add(const UnifiedSwapAmountChanged('100'));
    h.settle();

    expect(bloc.state.issue, SwapFormIssue.fiatUnavailable);
    expect(bloc.amountOf(bloc.state), isNull);
    expect(h.routed.requests, hasLength(1));
  });

  swapBlocTest('permission gas counts against the network coin', (h) {
    h.balances[eth] = d('0.0025');
    h.routed.respond = (request) => [
      SwapQuoteAvailable(
        quoteOf(
          from: usdc,
          to: eth,
          sell: request.amount.toString(),
          quotedAt: h.now(),
          fees: [
            feeOf(amount: '0.002', kind: SwapFeeKind.approvalNetwork),
            feeOf(),
          ],
        ),
      ),
    ];
    final bloc = h.open(pay: 'USDC-ERC20', receive: 'ETH', amount: '100');

    expect(bloc.state.selectedQuote, isNotNull);
    expect(bloc.state.issue, SwapFormIssue.insufficientForFees);
    expect(bloc.state.canReview, isFalse);
  });

  swapBlocTest('a failed price keeps checking the amount itself', (h) {
    h.routed
      ..respond = null
      ..results = [rejected(SwapQuoteFailureKind.noRoute)];
    final bloc = h.open(amount: '3');

    expect(bloc.state.evaluation, SwapEvaluationStatus.failed);
    expect(bloc.state.issue, SwapFormIssue.insufficient);
  });

  group('fees paid on top of a route', () {
    swapBlocTest('a provider fee in the network coin counts with its gas', (h) {
      h.balances[eth] = d('0.0025');
      h.routed.respond = (request) => _routed(request, h.now(), [
        _gas('0.001'),
        _providerFee('0.002', eth, onTop: true),
      ]);
      final bloc = h.open(pay: 'USDC-ERC20', receive: 'ETH', amount: '100');

      expect(bloc.state.selectedQuote, isNotNull);
      expect(bloc.state.issue, SwapFormIssue.insufficientForFees);
      expect(bloc.state.canReview, isFalse);

      h.balances[eth] = d('0.003');
      bloc.add(const UnifiedSwapBalancesRefreshed());
      h.settle();

      expect(bloc.state.issue, isNull);
      expect(bloc.state.canReview, isTrue);
    });

    swapBlocTest('a provider fee in the pay asset adds to what is spent', (h) {
      h.balances[usdc] = d('100');
      h.balances[eth] = d('0.001');
      h.routed.respond = (request) => _routed(request, h.now(), [
        _gas('0.001'),
        _providerFee('0.25', usdc, onTop: true),
      ]);
      final bloc = h.open(pay: 'USDC-ERC20', receive: 'ETH', amount: '99.8');

      expect(bloc.state.issue, SwapFormIssue.insufficient);
      expect(bloc.state.canReview, isFalse);
      expect(bloc.spendOf(bloc.state), (
        amount: d('99.8'),
        fees: d('0.25'),
        refundReserve: d('0'),
      ));

      bloc.add(const UnifiedSwapAmountChanged('99.75'));
      h.settle();

      expect(bloc.state.selectedQuote!.sellAmount, d('99.75'));
      expect(bloc.state.issue, isNull);
    });

    swapBlocTest('fees taken from what arrives still do not count', (h) {
      h.balances[eth] = d('0.0015');
      h.balances[usdc] = d('100');
      h.routed.respond = (request) => _routed(request, h.now(), [
        _gas('0.001'),
        _providerFee('0.002', eth, onTop: false),
        _providerFee('0.25', usdc, onTop: false),
      ]);
      final bloc = h.open(pay: 'USDC-ERC20', receive: 'ETH', amount: '100');

      expect(bloc.state.issue, isNull);
      expect(bloc.state.canReview, isTrue);
      expect(bloc.spendOf(bloc.state)!.fees, d('0'));
    });
  });

  group('the order book', () {
    // Each balance is KDF's Max plus what KDF keeps back: the 2% trading fee,
    // the preimage's 0.00185 ETH of gas and 0.00125 ETH to refund. The 0.002
    // ETH claim takes Max for USDC from KDF's 1.002 down to 1.
    for (final (pair, receive, book, kdfMax, balance) in [
      ('BTC', btc, _ethForBtc, '1', '1.0231'),
      ('a token on its network', usdc, _ethForUsdc, '1.002', '1.02514'),
    ]) {
      swapBlocTest('Max on ETH for $pair reviews with every fee counted', (h) {
        final source = book(h, kdfMax: kdfMax);
        _onlyTheBook(h, _bookQuote(h, source, receive));
        h.balances[eth] = d(balance);
        h.atomic.max = h.resolve(
          source.maxAmount(from: eth, to: receive, balance: d(balance)),
        );
        final bloc = h.open(pay: 'ETH', receive: receive.id, amount: '0.5')
          ..add(const UnifiedSwapMaxRequested());
        h.settle();

        expect(bloc.state.inputText, '1');
        expect(bloc.state.selectedQuote!.source, SwapLiquiditySource.atomic);
        expect(bloc.state.issue, isNull);
        expect(bloc.state.canReview, isTrue);
      });
    }

    swapBlocTest('its trading fee counts with its gas, and the refund', (h) {
      _onlyTheBook(h, _bookQuote(h, _ethForBtc(h), btc));
      // Enough for KDF's own checks, which leave the refund out.
      h.balances[eth] = d('1.02185');
      final bloc = h.open(pay: 'ETH', receive: 'BTC');

      expect(bloc.spendOf(bloc.state), (
        amount: d('1'),
        fees: d('0.02185'),
        refundReserve: d('0.00125'),
      ));
      expect(bloc.state.issue, SwapFormIssue.insufficient);

      h.balances[eth] = d('1.0231');
      bloc.add(const UnifiedSwapBalancesRefreshed());
      h.settle();

      expect(bloc.state.issue, isNull);
    });

    swapBlocTest('so does the gas to claim a token, which covers a refund', (
      h,
    ) {
      _onlyTheBook(h, _bookQuote(h, _ethForUsdc(h), usdc));
      h.balances[eth] = d('1.02384');
      final bloc = h.open(pay: 'ETH', receive: 'USDC-ERC20');

      expect(bloc.spendOf(bloc.state), (
        amount: d('1'),
        fees: d('0.02385'),
        refundReserve: d('0'),
      ));
      expect(bloc.state.issue, SwapFormIssue.insufficient);
    });

    swapBlocTest('Max is not refused when gas has risen since it was read', (
      h,
    ) {
      // KDF's Max came from cheaper gas: at the quote's price, it leaves
      // 0.0001 ETH less than the refund takes.
      final source = _ethForBtc(h);
      _onlyTheBook(h, _bookQuote(h, source, btc));
      h.balances[eth] = d('1.023');
      h.atomic.max = h.resolve(
        source.maxAmount(from: eth, to: btc, balance: d('1.023')),
      );
      final bloc = h.open(pay: 'ETH', receive: 'BTC', amount: '0.5')
        ..add(const UnifiedSwapMaxRequested());
      h.settle();

      expect(bloc.state.inputText, '1');
      expect(bloc.spendOf(bloc.state)!.refundReserve, d('0'));
      expect(bloc.state.issue, isNull);

      // Typed, the same amount is no longer KDF's Max.
      bloc.add(const UnifiedSwapAmountChanged('1.0'));
      h.settle();

      expect(bloc.spendOf(bloc.state)!.refundReserve, d('0.00125'));
      expect(bloc.state.issue, SwapFormIssue.insufficient);
    });
  });
}

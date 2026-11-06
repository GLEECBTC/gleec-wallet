// The analyzer does not treat test_units as tests, so @visibleForTesting
// members read as violations here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/shared/swap/atomic_swap_source.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

import 'swap_exec_atomic_fakes.dart';
import 'swap_src_fakes.dart';
import 'swap_test_fixtures.dart';

/// The DASH bid in the SDK's captured v2 `orderbook` response
/// (komodo_defi_rpc_methods/test/fixtures/orderbook/orderbook_response.json):
/// a maker selling DASH at 3930.7010814803 DGB. A bid's price is the inverse
/// of the maker's, and KDF's 100-digit decimal of this one rounds up.
const _decimal =
    '0.0002544075418788651605521516540338523799763700988224165198319218986992'
    '534200426899830070024093907274001';
final _fraction = Fraction(numer: '10000000000', denom: '39307010814803');
final _exact = Rational(
  BigInt.from(10000000000),
  BigInt.parse('39307010814803'),
);

/// The maker's own price, in DGB per DASH.
final _makerPrice = Rational.one / _exact;

OrderInfo _dashBid(Fraction? fraction) => OrderInfo(
  price: NumericValue(decimal: _decimal, fraction: fraction),
  baseMinVolume: NumericValue(decimal: '0'),
  baseMaxVolume: NumericValue(decimal: '5'),
);

/// KDF's check of a taker `sell` against a maker order
/// (lp_ordermatch.rs, `match_with_request`): the taker offers `volume`, asks
/// `volume × price`, and matches when offered over asked is at least the
/// maker's price, compared exactly.
bool _makerAccepts(Rational price, {Rational? volume}) {
  final offered = volume ?? Rational.one;
  return offered / (offered * price) >= _makerPrice;
}

/// Covers the price an order-book swap's order asks: the matched bid's exact
/// fraction, since an order at KDF's rounded decimal can match no maker.
void main() {
  group('atomic: the order asks the bid\'s exact price', () {
    test('the best bid carries its fraction, not its rounded decimal', () {
      final best = AtomicSwapQuoteSource.bestFillingBid([
        _dashBid(_fraction),
      ], d('1'));

      expect(best!.orderPrice, _exact);
      expect(best.price, d(_decimal));
      expect(Rational.parse(_decimal) > _exact, isTrue);
      expect(_makerAccepts(Rational.parse(_decimal)), isFalse);
      expect(_makerAccepts(best.orderPrice), isTrue);
      expect(
        _makerAccepts(best.orderPrice, volume: Rational.parse('0.37')),
        isTrue,
      );
    });

    test('a bid sent without a fraction asks its decimal', () {
      final best = AtomicSwapQuoteSource.bestFillingBid([
        bidOf('20', '0', '5'),
      ], d('1'));

      expect(best!.orderPrice, Rational.fromInt(20));
    });

    test('a fraction that disagrees with its decimal is not traded on', () {
      final best = AtomicSwapQuoteSource.bestFillingBid([
        _dashBid(Fraction(numer: '1', denom: '3930')),
      ], d('1'));

      expect(best, isNull);
    });

    test('the quote\'s plan carries the exact price, its figures the '
        'decimal', () async {
      final source = AtomicSwapQuoteSource(
        trading: SrcTrading()..bids = [_dashBid(_fraction)],
        networks: () => SwapNetworks([eth, btc]),
        addressOf: (asset) async => '${asset.id}-address',
        now: () => DateTime(2026, 10, 19),
      );

      final results = await source.quote(
        SwapQuoteRequest(from: btc, to: eth, amount: d('1')),
      );

      final quote = (results.single as SwapQuoteAvailable).quote;
      final plan = quote.payload! as AtomicSwapPlan;
      expect(plan.orderPrice, _exact);
      expect(plan.price, d(_decimal));
      expect(quote.guaranteedReceive, d(_decimal));
    });

    test('the order is placed at the plan\'s exact price', () async {
      await onFakeClock((rig) {
        rig.start(
          quoteOf(
            id: 'atomic',
            source: SwapLiquiditySource.atomic,
            routeKind: SwapRouteKind.direct,
            order: null,
            payload: AtomicSwapPlan(
              base: eth,
              rel: usdc,
              volume: d('1'),
              price: d(_decimal),
              orderPrice: _exact,
            ),
          ),
        );

        expect(rig.dex.sells.single.price, _exact);
      });
    });
  });
}

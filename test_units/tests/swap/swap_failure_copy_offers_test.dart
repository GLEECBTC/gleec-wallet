import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/swap/swap_order_book_offers.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/views/swap/common/swap_failure_copy.dart';

import 'swap_test_fixtures.dart';

/// Covers an amount no order or route takes: the copy names the bound, and
/// offers an amount that fills when the wallet can pay it.
///
/// Without a loaded translation, copy renders as its key.
void main() {
  final offers = SwapOrderBookOffers([
    SwapOfferBand(d('0.5'), d('2')),
    SwapOfferBand(d('6'), d('4500.129')),
  ]);

  SwapQuoteFailure orderBook(
    SwapQuoteFailureKind kind, {
    String? minimum,
    String? maximum,
  }) => SwapQuoteFailure(
    source: SwapLiquiditySource.atomic,
    kind: kind,
    minimum: minimum == null ? null : d(minimum),
    maximum: maximum == null ? null : d(maximum),
    offers: offers,
  );

  group('bounds', () {
    test('below the smallest offer, it offers that offer', () {
      final copy = SwapFailureCopy.of(
        orderBook(SwapQuoteFailureKind.belowMinimum, minimum: '0.5'),
        btc,
      );

      expect(copy.message, LocaleKeys.swapErrorOffersBelow);
      expect(copy.action, SwapEntryAction.useAmount);
      expect(copy.amount, d('0.5'));
    });

    test('above the largest offer, it offers that offer, as shown', () {
      final copy = SwapFailureCopy.of(
        orderBook(SwapQuoteFailureKind.aboveMaximum, maximum: '4500.129'),
        btc,
      );

      expect(copy.message, LocaleKeys.swapErrorOffersAbove);
      expect(copy.amount, d('4500.12'));
    });

    test('a route\'s own limits keep their wording', () {
      final below = SwapFailureCopy.of(
        SwapQuoteFailure(
          source: SwapLiquiditySource.routed,
          kind: SwapQuoteFailureKind.belowMinimum,
          minimum: d('0.123411'),
        ),
        eth,
      );

      expect(below.message, LocaleKeys.swapErrorBelowMinimum);
      expect(below.amount, d('0.1235'));
    });

    test('a minimum is rounded up within the asset\'s decimals', () {
      final cents = assetOf('CENT', decimals: 2);

      final copy = SwapFailureCopy.of(
        orderBook(SwapQuoteFailureKind.belowMinimum, minimum: '0.123'),
        cents,
      );

      expect(copy.amount, d('0.13'));
    });

    test('a maximum is rounded down within the asset\'s decimals', () {
      final cents = assetOf('CENT', decimals: 2);

      final copy = SwapFailureCopy.of(
        orderBook(SwapQuoteFailureKind.aboveMaximum, maximum: '0.1239'),
        cents,
      );

      expect(copy.amount, d('0.12'));
    });

    test('a bound too small to show is not offered', () {
      final copy = SwapFailureCopy.of(
        orderBook(SwapQuoteFailureKind.aboveMaximum, maximum: '0.000000001'),
        btc,
      );

      expect(copy.action, SwapEntryAction.none);
    });

    test('an amount the wallet cannot pay is not offered', () {
      final copy = SwapFailureCopy.of(
        orderBook(SwapQuoteFailureKind.belowMinimum, minimum: '0.5'),
        btc,
        balance: d('0.4'),
      );

      expect(copy.action, SwapEntryAction.none);
      expect(copy.amount, isNull);
    });

    test('an unknown bound says so and offers nothing', () {
      final copy = SwapFailureCopy.of(
        const SwapQuoteFailure(
          source: SwapLiquiditySource.routed,
          kind: SwapQuoteFailureKind.belowMinimum,
        ),
        eth,
      );

      expect(copy.message, LocaleKeys.swapErrorTooSmall);
      expect(copy.action, SwapEntryAction.none);
    });
  });

  group('between offers', () {
    final gap = orderBook(SwapQuoteFailureKind.noRoute);

    test('names the offers around the amount and offers the lower', () {
      final copy = SwapFailureCopy.of(gap, btc, all: [gap], amount: d('3'));

      expect(copy.message, LocaleKeys.swapErrorOffersGap);
      expect(copy.action, SwapEntryAction.useAmount);
      expect(copy.amount, d('2'));
    });

    test('offers nothing the wallet cannot pay', () {
      final copy = SwapFailureCopy.of(
        gap,
        btc,
        all: [gap],
        amount: d('3'),
        balance: d('1'),
      );

      expect(copy.message, LocaleKeys.swapErrorOffersGap);
      expect(copy.action, SwapEntryAction.none);
    });

    test('without the amount asked, it is a plain miss', () {
      final copy = SwapFailureCopy.of(gap, btc, all: [gap]);

      expect(copy.message, LocaleKeys.swapErrorNoRoute);
      expect(copy.action, SwapEntryAction.retry);
    });

    test('another source that could not look still comes first', () {
      final copy = SwapFailureCopy.of(
        gap,
        btc,
        all: [
          gap,
          const SwapQuoteFailure(
            source: SwapLiquiditySource.routed,
            kind: SwapQuoteFailureKind.timeout,
          ),
        ],
        amount: d('3'),
      );

      expect(copy.message, LocaleKeys.swapErrorNoRouteOrderBook);
    });
  });
}

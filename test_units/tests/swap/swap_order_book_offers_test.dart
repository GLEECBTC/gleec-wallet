import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/swap/swap_order_book_offers.dart';

import 'swap_src_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers how the order book's bids become the amounts one order takes.
void main() {
  SwapOrderBookOffers offersOf(
    List<(String, String)> ranges, {
    String? floor,
  }) => SwapOrderBookOffers.fromBids([
    for (final (min, max) in ranges) bidOf('10', min, max),
  ], floor: floor == null ? null : d(floor));

  group('reading bids', () {
    test('no bids is no offers', () {
      final offers = SwapOrderBookOffers.fromBids(const []);

      expect(offers.isEmpty, isTrue);
      expect(offers.minimum, isNull);
      expect(offers.maximum, isNull);
      expect(offers.fits(d('1')), isFalse);
    });

    test('the wallet\'s own orders are not offers', () {
      final offers = SwapOrderBookOffers.fromBids([
        bidOf('10', '1', '5', mine: true),
      ]);

      expect(offers.isEmpty, isTrue);
    });

    test('orders missing a price or size, or priced at zero, are skipped', () {
      final offers = SwapOrderBookOffers.fromBids([
        bidOf(null, '0', '5'),
        bidOf('10', '0', null),
        bidOf('0', '0', '5'),
        bidOf('abc', '0', '5'),
        bidOf('10', null, '2'),
      ]);

      expect(offers.bands, [SwapOfferBand(d('0'), d('2'))]);
    });

    test('overlapping and touching orders merge into one range', () {
      final offers = offersOf([
        ('4', '6'),
        ('1', '3'),
        ('3', '4.5'),
        ('8', '9'),
      ]);

      expect(offers.bands, [
        SwapOfferBand(d('1'), d('6')),
        SwapOfferBand(d('8'), d('9')),
      ]);
      expect(offers.minimum, d('1'));
      expect(offers.maximum, d('9'));
    });

    test('no range starts below the coin minimum', () {
      final offers = offersOf([('0.1', '0.3'), ('0.2', '2')], floor: '0.5');

      expect(offers.bands, [SwapOfferBand(d('0.5'), d('2'))]);
    });

    test('an order entirely under the coin minimum is no offer', () {
      expect(offersOf([('0.1', '0.3')], floor: '0.5').isEmpty, isTrue);
    });
  });

  group('amounts', () {
    final offers = offersOf([('1', '2'), ('5', '10')]);

    test('an amount inside a range fits, one in a gap does not', () {
      expect(offers.fits(d('1')), isTrue);
      expect(offers.fits(d('10')), isTrue);
      expect(offers.fits(d('3')), isFalse);
      expect(offers.fits(d('11')), isFalse);
    });

    test('the largest amount up to a cap', () {
      expect(offers.largestUpTo(d('3')), d('2'));
      expect(offers.largestUpTo(d('7')), d('7'));
      expect(offers.largestUpTo(d('20')), d('10'));
      expect(offers.largestUpTo(d('0.5')), isNull);
    });

    test('the smallest amount from a floor', () {
      expect(offers.smallestFrom(d('3')), d('5'));
      expect(offers.smallestFrom(d('0.5')), d('1'));
      expect(offers.smallestFrom(d('6')), d('6'));
      expect(offers.smallestFrom(d('11')), isNull);
    });
  });
}

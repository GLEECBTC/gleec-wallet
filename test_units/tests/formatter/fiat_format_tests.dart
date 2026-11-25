import 'package:intl/intl.dart';
import 'package:test/test.dart';
import 'package:web_dex/shared/utils/fiat_format.dart';

void testFiatFormat() {
  group('FiatFormat', () {
    test('formats a held value with cents and grouping', () {
      expect(FiatFormat.amount(0), r'$0.00');
      expect(FiatFormat.amount(1234.5), r'$1,234.50');
      expect(FiatFormat.amount(60251.144), r'$60,251.14');
      expect(FiatFormat.amount(12345678.9), r'$12,345,678.90');
    });

    test('says a positive amount under a cent is under a cent', () {
      expect(FiatFormat.amount(0.004), r'<$0.01');
      expect(FiatFormat.amount(0.005), r'$0.01');
    });

    test('keeps one number style whatever the default locale is', () {
      final previous = Intl.defaultLocale;
      addTearDown(() => Intl.defaultLocale = previous);
      // The locale that drew `$60 251,14` beside `$0.041` on a phone.
      Intl.defaultLocale = 'en_ZA';
      expect(FiatFormat.amount(60251.14), r'$60,251.14');
      expect(FiatFormat.price(0.041), r'$0.041');
      expect(FiatFormat.percent(-0.57), '−0.57%');
    });

    test('splits a held value before its cents', () {
      expect(FiatFormat.amountParts(1234.56), (
        whole: r'$1,234',
        fraction: '.56',
      ));
      expect(FiatFormat.amountParts(0.001), (whole: r'<$0.01', fraction: ''));
    });

    test('signs a change, with a true minus', () {
      expect(FiatFormat.signedAmount(12.3), r'+$12.30');
      expect(FiatFormat.signedAmount(-1234.5), '−\$1,234.50');
      expect(FiatFormat.signedAmount(0.001), r'$0.00');
    });

    test('signs a percent, and leaves a flat one unsigned', () {
      expect(FiatFormat.percent(1.234), '+1.23%');
      expect(FiatFormat.percent(-0.57), '−0.57%');
      expect(FiatFormat.percent(0.004), '0.00%');
      expect(FiatFormat.percent(1234.5), '+1,234.50%');
    });

    test('gives a price the precision its size needs', () {
      expect(FiatFormat.price(60251.14), r'$60,251.14');
      expect(FiatFormat.price(1), r'$1.00');
      expect(FiatFormat.price(0.31), r'$0.31');
      expect(FiatFormat.price(0.3), r'$0.30');
      expect(FiatFormat.price(0.123456), r'$0.1235');
      expect(FiatFormat.price(0.041), r'$0.041');
      expect(FiatFormat.price(0.00052), r'$0.00052');
    });

    test('collapses four or more zeros after the point', () {
      expect(FiatFormat.price(0.0000512345), r'$0.0₄5123');
      expect(FiatFormat.price(0.0000051234), r'$0.0₅5123');
      expect(FiatFormat.price(1.2e-12), r'$0.0₁₁12');
      expect(FiatFormat.spokenPrice(0.0000051234), r'$0.000005123');
    });

    test('rounds a price into the next digit rather than dropping it', () {
      expect(FiatFormat.price(0.099996), r'$0.10');
      expect(FiatFormat.price(0.9999996), r'$1.00');
    });

    test('marks a value it cannot show', () {
      expect(FiatFormat.amount(double.nan), '--');
      expect(FiatFormat.price(double.infinity), '--');
      expect(FiatFormat.percent(double.nan), '--');
    });
  });
}

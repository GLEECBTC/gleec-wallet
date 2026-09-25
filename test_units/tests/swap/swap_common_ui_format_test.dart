import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/views/swap/common/swap_format.dart';

import 'swap_common_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// How the swap surface writes numbers, durations, identifiers and times.
void main() {
  group('swap format', () {
    useEnglishCopy();

    group('token amounts', () {
      test('zero is a plain zero', () {
        expect(SwapFormat.amount(d('0')), '0');
        expect(SwapFormat.amount(d('0.000'), rounding: SwapRounding.up), '0');
      });

      test('thousands and above keep two decimals, grouped', () {
        expect(SwapFormat.amount(d('1234567.891')), '1,234,567.89');
        expect(SwapFormat.amount(d('1000')), '1,000');
        expect(SwapFormat.amount(d('12345.6')), '12,345.6');
      });

      test('units keep four decimals without trailing zeros', () {
        expect(SwapFormat.amount(d('1')), '1');
        expect(SwapFormat.amount(d('12.5')), '12.5');
        expect(SwapFormat.amount(d('999.12345')), '999.1235');
      });

      test('fractions keep four significant digits', () {
        expect(SwapFormat.amount(d('0.5')), '0.5');
        expect(SwapFormat.amount(d('0.123456')), '0.1235');
        expect(SwapFormat.amount(d('0.000123456')), '0.0001235');
      });

      test('never more than eight decimals', () {
        expect(SwapFormat.amount(d('0.0000012345')), '0.00000123');
        expect(SwapFormat.amount(d('0.00000001')), '0.00000001');
      });

      test('a received amount rounds down, a cost rounds up', () {
        expect(
          SwapFormat.amount(d('0.123456'), rounding: SwapRounding.down),
          '0.1234',
        );
        expect(
          SwapFormat.amount(d('0.123401'), rounding: SwapRounding.up),
          '0.1235',
        );
        expect(
          SwapFormat.amount(d('2.99999'), rounding: SwapRounding.down),
          '2.9999',
        );
        expect(
          SwapFormat.amount(d('999.99995'), rounding: SwapRounding.up),
          '1,000',
        );
      });

      test('nearest rounds half away from zero', () {
        expect(SwapFormat.amount(d('1.00005')), '1.0001');
        expect(SwapFormat.amount(d('1.00004')), '1');
      });

      test('dust too small to show reads as less than the smallest step', () {
        expect(
          SwapFormat.amount(d('0.000000001'), rounding: SwapRounding.down),
          '< 0.00000001',
        );
        expect(SwapFormat.amount(d('0.000000004')), '< 0.00000001');
        expect(SwapFormat.amount(d('0.000000005')), '0.00000001');
      });

      test('a dust cost rounds up to the smallest step, never to zero', () {
        expect(
          SwapFormat.amount(d('0.000000001'), rounding: SwapRounding.up),
          '0.00000001',
        );
      });

      test('a negative amount keeps its sign and rounds by magnitude', () {
        expect(SwapFormat.amount(d('-1234.567')), '-1,234.57');
        expect(
          SwapFormat.amount(d('-1234.567'), rounding: SwapRounding.down),
          '-1,234.56',
        );
        expect(
          SwapFormat.amount(d('-1234.561'), rounding: SwapRounding.up),
          '-1,234.57',
        );
        expect(SwapFormat.amount(d('-0.5')), '-0.5');
      });

      test('tokens follow the amount with the ticker and its rounding', () {
        expect(SwapFormat.tokens(d('1250'), 'USDC'), '1,250 USDC');
        expect(
          SwapFormat.tokens(d('0.123456'), 'ETH', rounding: SwapRounding.down),
          '0.1234 ETH',
        );
        expect(
          SwapFormat.tokens(d('0.123401'), 'ETH', rounding: SwapRounding.up),
          '0.1235 ETH',
        );
      });
    });

    group('dollars', () {
      test('two decimals, grouped, with the sign before the dollar', () {
        expect(SwapFormat.usd(d('1204.333')), r'$1,204.33');
        expect(SwapFormat.usd(d('1234567.8')), r'$1,234,567.80');
        expect(SwapFormat.usd(d('0')), r'$0.00');
        expect(SwapFormat.usd(d('0.01')), r'$0.01');
        expect(SwapFormat.usd(d('-12.345')), r'-$12.35');
      });

      test('rounding follows what the figure is', () {
        expect(SwapFormat.usd(d('1204.335')), r'$1,204.34');
        expect(SwapFormat.usd(d('8.741'), rounding: SwapRounding.up), r'$8.75');
        expect(
          SwapFormat.usd(d('3219.428'), rounding: SwapRounding.down),
          r'$3,219.42',
        );
        expect(
          SwapFormat.usd(d('-12.345'), rounding: SwapRounding.down),
          r'-$12.34',
        );
        expect(
          SwapFormat.usd(d('-12.341'), rounding: SwapRounding.up),
          r'-$12.35',
        );
      });

      test('dust of either sign reads as under a cent, even rounded up', () {
        expect(SwapFormat.usd(d('0.004')), r'< $0.01');
        expect(SwapFormat.usd(d('-0.004')), r'< $0.01');
        expect(
          SwapFormat.usd(d('0.009'), rounding: SwapRounding.up),
          r'< $0.01',
        );
      });
    });

    test('a fraction reads as a percentage to one decimal', () {
      expect(SwapFormat.percent(d('0.052')), '5.2%');
      expect(SwapFormat.percent(d('0.05')), '5%');
      expect(SwapFormat.percent(d('0.12345')), '12.3%');
      expect(SwapFormat.percent(d('0.0567')), '5.7%');
      expect(SwapFormat.percent(d('1')), '100%');
      expect(SwapFormat.percent(d('0.00049')), '0%');
      expect(SwapFormat.percent(d('-0.0123')), '-1.2%');
    });

    group('durations', () {
      test('an unknown or empty estimate varies', () {
        expect(SwapFormat.duration(null), 'Varies');
        expect(SwapFormat.duration(Duration.zero), 'Varies');
        expect(SwapFormat.duration(const Duration(seconds: -5)), 'Varies');
      });

      test('under a minute rounds up to five seconds, at most 55', () {
        String of(int ms) => SwapFormat.duration(Duration(milliseconds: ms));
        expect(of(500), 'About 5 sec');
        expect(of(1000), 'About 5 sec');
        expect(of(7000), 'About 10 sec');
        expect(of(45000), 'About 45 sec');
        expect(of(59000), 'About 55 sec');
      });

      test('a minute and a half at most reads as one minute', () {
        expect(
          SwapFormat.duration(const Duration(seconds: 60)),
          'About 1 minute',
        );
        expect(
          SwapFormat.duration(const Duration(seconds: 89)),
          'About 1 minute',
        );
      });

      test('minutes round to the nearest minute', () {
        String of(int s) => SwapFormat.duration(Duration(seconds: s));
        expect(of(90), 'About 2 minutes');
        expect(of(149), 'About 2 minutes');
        expect(of(150), 'About 3 minutes');
        expect(of(3599), 'About 60 minutes');
      });

      test('hours keep one decimal below ten, whole hours above', () {
        String of(int s) => SwapFormat.duration(Duration(seconds: s));
        expect(of(5400), 'About 1.5 hours');
        expect(of(9000), 'About 2.5 hours');
        expect(of(35999), 'About 10 hours');
        expect(of(36000), 'About 10 hours');
        expect(of(45000), 'About 13 hours');
      });

      test('an hour reads in the singular', () {
        expect(SwapFormat.duration(const Duration(hours: 1)), 'About 1 hour');
      });
    });

    test('short identifiers keep their recognisable ends', () {
      expect(SwapFormat.short(swapAddress), '0x5520…7B91');
      expect(SwapFormat.short('0x1234567890abc'), '0x1234…0abc');
      expect(SwapFormat.short('0x1234567890ab'), '0x1234567890ab');
      expect(SwapFormat.short(''), '');
    });

    group('times', () {
      final now = DateTime(2026, 9, 25, 23, 30);

      test('today shows the clock', () {
        expect(SwapFormat.time(DateTime(2026, 9, 25, 9, 5), now: now), '09:05');
      });

      test('earlier this year shows the day and the clock', () {
        expect(
          SwapFormat.time(DateTime(2026, 9, 3, 14, 5), now: now),
          'Sep 3 14:05',
        );
      });

      test('another year shows the full date', () {
        expect(
          SwapFormat.time(DateTime(2025, 12, 31, 23, 59), now: now),
          'Dec 31, 2025 23:59',
        );
      });

      test('a UTC time is shown in local time', () {
        final utc = DateTime.utc(2026, 9, 25, 12);
        expect(
          SwapFormat.time(utc, now: utc),
          DateFormat.Hm().format(utc.toLocal()),
        );
      });

      test('without a reference time it compares with the clock', () {
        expect(
          SwapFormat.time(DateTime(2001, 2, 3, 4, 5)),
          'Feb 3, 2001 04:05',
        );
      });
    });

    test('a ticker drops its network suffix', () {
      expect(SwapFormat.ticker(usdc), 'USDC');
      expect(SwapFormat.ticker(eth), 'ETH');
      expect(SwapFormat.ticker(assetOf('PAXG-ERC20', parent: eth)), 'PAXG');
    });
  });
}

// ignore_for_file: avoid_print

import 'package:test/test.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/utils/formatters.dart';

const ms = LocaleKeys.milliseconds;
const s = LocaleKeys.seconds;
const m = LocaleKeys.minutes;
const h = LocaleKeys.hours;

final locale = DurationLocalization(
  milliseconds: ms,
  seconds: s,
  minutes: m,
  hours: h,
);

void testDurationFormat() {
  test('formatting duration to String', () {
    expect(durationFormat(const Duration(milliseconds: 1), locale), '1$ms');
    expect(durationFormat(const Duration(milliseconds: 999), locale), '999$ms');
    expect(durationFormat(const Duration(milliseconds: 1000), locale), '1$s');
    expect(durationFormat(const Duration(milliseconds: 59000), locale), '59$s');
    expect(durationFormat(const Duration(seconds: 5), locale), '5$s');
    expect(durationFormat(const Duration(seconds: 61), locale), '1$m 1$s');
    expect(durationFormat(const Duration(minutes: 1), locale), '1$m 0$s');
    expect(durationFormat(const Duration(minutes: 59), locale), '59$m 0$s');
    expect(
      durationFormat(const Duration(milliseconds: 119000), locale),
      '1$m 59$s',
    );
    expect(
      durationFormat(const Duration(milliseconds: 987654321), locale),
      '274$h 20$m 54$s',
    );
    expect(durationFormat(const Duration(minutes: 60), locale), '1$h 0$m 0$s');
    expect(durationFormat(const Duration(minutes: 61), locale), '1$h 1$m 0$s');
    expect(
      durationFormat(const Duration(seconds: 8000), locale),
      '2$h 13$m 20$s',
    );
    expect(
      durationFormat(const Duration(seconds: 60000232), locale),
      '16666$h 43$m 52$s',
    );
    expect(
      durationFormat(const Duration(minutes: 176), locale),
      '2$h 56$m 0$s',
    );
    expect(durationFormat(const Duration(hours: 2), locale), '2$h 0$m 0$s');
    expect(
      durationFormat(const Duration(milliseconds: 7200000), locale),
      '2$h 0$m 0$s',
    );
    expect(
      durationFormat(const Duration(hours: 1, seconds: 1), locale),
      '1$h 0$m 1$s',
    );
    expect(
      durationFormat(const Duration(hours: 1, minutes: 1, seconds: 1), locale),
      '1$h 1$m 1$s',
    );
    expect(
      durationFormat(const Duration(days: 1, seconds: 1), locale),
      '24$h 0$m 1$s',
    );
  });
}

// ignore_for_file: avoid_print

import 'package:test/test.dart';
import 'package:web_dex/shared/utils/formatters.dart';

void testFormattedDate() {
  const maxTimestampSecond = 8640000000000;
  const minTimestampSecond = -8639999999999;
  final date = DateTime.now();
  final timezone = date.timeZoneOffset;
  int timestampOffset(int timestamp) =>
      (timestamp * 1000 - timezone.inMilliseconds) ~/ 1000;

  test('formatting date from timestamp', () {
    expect(getFormattedDate(1, true), '01 Jan 1970, 00:00');
    expect(getFormattedDate(1687427558, true), '22 Jun 2023, 09:52');
    expect(getFormattedDate(1692102558, true), '15 Aug 2023, 12:29');
    expect(getFormattedDate(-1500000, true), '14 Dec 1969, 15:20');
    expect(getFormattedDate(-2000000000, true), '16 Aug 1906, 20:26');
    // Maximum value
    expect(getFormattedDate(maxTimestampSecond, true), '13 Sep 275760, 00:00');
    // Minimal value
    expect(
      getFormattedDate(minTimestampSecond, true),
      '20 Apr 271821, 00:00 BC',
    );
  });

  test('negative tests for formatting date', () {
    expect(
      getFormattedDate(timestampOffset(9650000000000)),
      'Date is out of the range',
    );
    expect(
      getFormattedDate(timestampOffset(-9650000000000)),
      'Date is out of the range',
    );
  });
}

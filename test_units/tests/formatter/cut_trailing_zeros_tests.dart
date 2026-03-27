// ignore_for_file: avoid_print

import 'package:test/test.dart';
import 'package:web_dex/shared/utils/formatters.dart';

void testCutTrailingZeros() {
  test('remove trailing zeros in string with zeros tests:', () {
    expect(cutTrailingZeros('0'), '0');
    expect(cutTrailingZeros('0.0'), '0');
    expect(cutTrailingZeros('000.000'), '000');
    expect(cutTrailingZeros('0.0000'), '0');
    expect(cutTrailingZeros('00000.0'), '00000');
  });

  test('remove trailing zeros in string with digits tests:', () {
    expect(cutTrailingZeros('123'), '123');
    expect(cutTrailingZeros('123.123'), '123.123');
    expect(cutTrailingZeros('1.01'), '1.01');
    expect(cutTrailingZeros('1.01000000'), '1.01');
    expect(cutTrailingZeros('1.010000001'), '1.010000001');
    expect(cutTrailingZeros('1.01000010'), '1.0100001');
    expect(cutTrailingZeros('0001.0100000'), '0001.01');
  });
}

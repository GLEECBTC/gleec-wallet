// ignore_for_file: avoid_print

import 'package:test/test.dart';
import 'package:web_dex/shared/utils/formatters.dart';

void testTruncateDecimal() {
  test('truncate decimal according to decimalRange param', () {
    expect(truncateDecimal('0.01', 0), '0');
    expect(truncateDecimal('0.01', 1), '0.0');
    expect(truncateDecimal('0.01', 2), '0.01');
    expect(truncateDecimal('0.01', 3), '0.01');
    // @todo: DmitriiP:  Is it expected behavior?
    expect(
        truncateDecimal('0.00000000000000000001', 19), '0.0000000000000000000');
    expect(truncateDecimal('0.00000000000000000001', 20),
        '0.00000000000000000001');
    expect(truncateDecimal('0.00000000000000000001', 21),
        '0.00000000000000000001');
    expect(truncateDecimal('0.123456789', 8), '0.12345678');
    expect(truncateDecimal('0.123456789', 1), '0.1');
    // todo: Is it expected behavior?
    expect(truncateDecimal('0.1234567099', 8), '0.12345670');
  });

  test('truncateDecimal should truncate decimal part correctly', () {
    // Test cases where decimalRange >= 0
    expect(truncateDecimal("3.14159", 0), "3");
    expect(truncateDecimal("3.14159", 2), "3.14");
    expect(truncateDecimal("3.14159", 5), "3.14159");
    expect(truncateDecimal("123.456789", 2), "123.45");
    expect(truncateDecimal("123.456789", 8), "123.456789");

    // Test cases where decimalRange < 0
    expect(truncateDecimal("3.14159", -1), "3.14159");
    expect(truncateDecimal("123.456789", -5), "123.456789");
  });

  test('truncateDecimal should return original value if no decimal part', () {
    expect(truncateDecimal("42", 2), "42");
    expect(truncateDecimal("1000", 0), "1000");
    expect(truncateDecimal("0", 5), "0");
  });
}

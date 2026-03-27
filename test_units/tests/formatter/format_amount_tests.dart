// ignore_for_file: avoid_print

import 'package:test/test.dart';
import 'package:web_dex/shared/utils/formatters.dart';

void testFormatAmount() {
  test('formatting amount tests:', () {
    expect(formatAmt(0), '0.00');
    expect(formatAmt(-12.3456), '-12.35');
    expect(formatAmt(12.3456), '12.35');
    expect(formatAmt(1.23456), '1.23');
    expect(formatAmt(0.00999), '0.01');
    expect(formatAmt(0.010011), '0.01');
    expect(formatAmt(0.12345), '0.12');

    expect(formatAmt(0.012345), '0.012');
    expect(formatAmt(0.0012345), '0.0012');
    expect(formatAmt(0.00012345), '0.00012');

    expect(formatAmt(0.09876543), '0.099');
    expect(formatAmt(0.009876543), '0.0099');
    expect(formatAmt(0.0009876543), '0.00099');
    expect(formatAmt(0.00009876543), '0.000099');

    expect(formatAmt(123456789012345678.023), '1.23456789012e+17');
    expect(formatAmt(-123456789012345678.023), '-1.23456789012e+17');

    // From top to bottom
    expect(formatAmt(123456789012), '123456789012'); // 12 digits is max
    expect(formatAmt(1234567890123), '1.23456789012e+12'); // 13 digits is max
    expect(formatAmt(12345678901234), '1.23456789012e+13'); // 14 digits is max
    expect(formatAmt(123456789012345), '1.23456789012e+14'); // 15 digits is max
    expect(
        formatAmt(123456789012345.1), '1.23456789012e+14'); // 15 digits is max
    expect(formatAmt(123456789012345.123456789),
        '1.23456789012e+14'); // 15 digits is max
  });
}

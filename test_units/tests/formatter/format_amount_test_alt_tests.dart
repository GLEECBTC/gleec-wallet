import 'package:test/test.dart';
import 'package:web_dex/shared/utils/formatters.dart';

void testToStringAmount() {
  test('formatting amount to String tests:', () {
    expect(toStringAmount(1000000000000.0), '1 trillion');
    expect(toStringAmount(1000000000001.0), '1 trillion');
    expect(toStringAmount(1000000100000.0), '1 trillion');
    expect(toStringAmount(1123456789000.0), '1.12 trillion');
    expect(toStringAmount(1988000000000.0), '1.99 trillion');

    expect(toStringAmount(198800000000.0), '199 billion');
    expect(toStringAmount(194856600000.0), '195 billion');

    expect(toStringAmount(19485660000.0), '19.5 billion');
    expect(toStringAmount(19055660000.0), '19.1 billion');

    expect(toStringAmount(1905566000.0), '1,905,566,000');
    expect(toStringAmount(4915566000.0), '4,915,566,000');
    expect(toStringAmount(9915566000.0), '9,915,566,000');
    expect(toStringAmount(9915566001.0), '9,915,566,001');
    expect(toStringAmount(9915566001.1), '9,915,566,001');

    expect(toStringAmount(100000000.0), '100,000,000');

    expect(toStringAmount(10000002.3), '10,000,002');

    expect(toStringAmount(1050002.9), '1,050,003');

    expect(toStringAmount(105002.6), '105,003');

    expect(toStringAmount(10502.6), '10,503');

    expect(toStringAmount(1502.6), '1,503');
    expect(toStringAmount(1502.4), '1,502');

    expect(toStringAmount(999.6), '999.60');
    expect(toStringAmount(990.612), '990.61');
    expect(toStringAmount(951.619), '951.62');
    expect(toStringAmount(12.009), '12.01');
    expect(toStringAmount(12.009), '12.01');
    expect(toStringAmount(1.0), '1.00');

    expect(toStringAmount(0.9999999999), '1.00');
    expect(toStringAmount(0.7999999999), '0.80');
    expect(toStringAmount(0.0199999999), '0.02');
    expect(toStringAmount(1.123e-1), '0.1123');
    expect(toStringAmount(0.14567e-1), '0.014567');

    expect(toStringAmount(0.00114359999), '0.0011436');
    expect(toStringAmount(0.00001), '0.00001');
    expect(toStringAmount(0.00001001), '0.00001001');
    expect(toStringAmount(0.000010010001), '0.00001001');
    expect(toStringAmount(0.000010017001), '0.00001002');
    expect(toStringAmount(0.000010010999), '0.00001001');
    expect(toStringAmount(0.000000010999), '0.00000001');
    expect(toStringAmount(1.23e-7), '0.00000012');
    expect(toStringAmount(1.23434e-6), '0.00000123');

    expect(toStringAmount(0.000000000999), '9.990e-10');
    expect(toStringAmount(0.000000000001), '1.000e-12');
    expect(toStringAmount(0.00000000000001), '1.000e-14');
    expect(toStringAmount(0.00000000085001), '8.500e-10');
    expect(toStringAmount(1.23e-10), '1.230e-10');
  });
}

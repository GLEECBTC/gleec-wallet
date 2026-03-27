import 'package:test/test.dart';
import 'package:web_dex/shared/utils/utils.dart';

void testCustomDoubleToString() {
  test('doubleToString formats whole number without decimal places', () {
    double value = 12345.0;
    expect(doubleToString(value), equals('12345'));

    value = 0.0;
    expect(doubleToString(value), equals('0'));
  });

  test('doubleToString formats with specified decimal places', () {
    double value = 12.3456789;
    expect(doubleToString(value, 3), equals('12.346'));

    value = 0.123456789;
    expect(doubleToString(value, 5), equals('0.12346'));
  });

  test('doubleToString caps decimal places to 20', () {
    double value = 0.123456789012345678901234567890123456789;
    expect(doubleToString(value, 25).length, equals(19));
  });

  test('doubleToString formats with reduced decimal places', () {
    double value = 123.400;
    expect(doubleToString(value, 5), equals('123.4'));
    expect(doubleToString(value, 6), equals('123.4'));

    value = 9876.00001;
    expect(doubleToString(value, 10), equals('9876.00001'));
    expect(doubleToString(value, 3), equals('9876'));
  });

  test('doubleToString removes trailing zeros and dot if necessary', () {
    double value = 123.45000;
    expect(doubleToString(value), equals('123.45'));

    value = 987600.00000;
    expect(doubleToString(value), equals('987600'));
  });
}

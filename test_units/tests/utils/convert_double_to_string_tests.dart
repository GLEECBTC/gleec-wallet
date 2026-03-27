import 'package:test/test.dart';
import 'package:web_dex/shared/utils/utils.dart';

void testDoubleToString() {
  test('Convert double to string with default fractions', () {
    expect(doubleToString(0), '0');
    expect(doubleToString(1), '1');
    expect(doubleToString(0.0), '0');
    expect(doubleToString(0.000000001), '0');
    expect(doubleToString(0.00000001), '0.00000001');
    expect(doubleToString(100.000000004), '100');
    expect(doubleToString(100.000000005), '100.00000001');
    expect(doubleToString(-1.232e-5), '-0.00001232');
    expect(doubleToString(-1.0023999e-5), '-0.00001002');
    expect(doubleToString(-1.0025999e-5), '-0.00001003');
  });

  test('Convert double to string with custom fractions', () {
    expect(doubleToString(0, 2), '0');
    expect(doubleToString(0.0001, 2), '0');
    expect(doubleToString(1, 2), '1');
    expect(doubleToString(1.00, 2), '1');
    expect(doubleToString(1.01, 2), '1.01');
    expect(doubleToString(1.001, 2), '1');
    expect(doubleToString(1.005, 100), '1.005');
    expect(doubleToString(1.005230020234030434, 17), '1.0052300202340305');
    expect(doubleToString(0.0100, 4), '0.01');
    expect(doubleToString(-0.0100, 4), '-0.01');
    expect(doubleToString(-1.0100e-6, 4), '0');
  });
}

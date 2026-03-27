// ignore_for_file: avoid_print

import 'package:test/test.dart';
import 'package:web_dex/shared/utils/formatters.dart';

void testNumberWithoutExponent() {
  test('convert number from e-notation to simple view tests:', () {
    const one = 1;
    expect(getNumberWithoutExponent(one.toString()), '1');
    const million = 1000000;
    expect(getNumberWithoutExponent(million.toString()), '1000000');
    const e1 = 0.1; // 0.1
    expect(getNumberWithoutExponent(e1.toString()), '0.1');
    const e2 = 0.01; // 0.01
    expect(getNumberWithoutExponent(e2.toString()), '0.01');
    const e3 = 0.001; // 0.001
    expect(getNumberWithoutExponent(e3.toString()), '0.001');
    const e4 = 0.0001; // 0.0001
    expect(getNumberWithoutExponent(e4.toString()), '0.0001');
    const e5 = 0.00001; // 0.00001
    expect(getNumberWithoutExponent(e5.toString()), '0.00001');
    const e6 = 0.000001; // 0.000001
    expect(getNumberWithoutExponent(e6.toString()), '0.000001');
    const e7 = 0.0000001; // 1e-7
    expect(getNumberWithoutExponent(e7.toString()), '0.0000001');
    const e8 = 0.00000001; // 1e-8
    expect(getNumberWithoutExponent(e8.toString()), '0.00000001');
    const e9 = 0.000000001; // 1e-9
    expect(getNumberWithoutExponent(e9.toString()), '0.000000001');
    expect(getNumberWithoutExponent('1e-9'), '0.000000001');
    const e1Alt = 0.5; // 0.1
    expect(getNumberWithoutExponent(e1Alt.toString()), '0.5');
    const e7Alt = 0.000000123; // 1.23e-7
    expect(getNumberWithoutExponent(e7Alt.toString()), '0.000000123');
    expect(getNumberWithoutExponent('1.23e-7'), '0.000000123');
    const e8Alt = 0.000000056; // 5.6e-8
    expect(getNumberWithoutExponent(e8Alt.toString()), '0.000000056');
    expect(getNumberWithoutExponent('5.6e-8'), '0.000000056');
  });

  test('convert number from +e-notation to simple view tests:', () {
    expect(getNumberWithoutExponent("1.23e+2"), "123");
    expect(getNumberWithoutExponent("1e+3"), "1000");
    expect(getNumberWithoutExponent("1.2340e+3"), "1234");
    expect(getNumberWithoutExponent("1.2341e+3"), "1234.1");

    expect(getNumberWithoutExponent('1e+20'), '100000000000000000000');
    expect(getNumberWithoutExponent('-1e+19'), '-10000000000000000000');
    expect(getNumberWithoutExponent('1e+21'), '1000000000000000000000');
    expect(getNumberWithoutExponent('1e+50'),
        '100000000000000000000000000000000000000000000000000');
    expect(getNumberWithoutExponent('1e+100'),
        '10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000');

    expect(getNumberWithoutExponent('-1.2354e+3'), '-1235.4');
    expect(getNumberWithoutExponent('-1.235400002e+5'), '-123540.0002');
    expect(getNumberWithoutExponent('1.235400002e+8'), '123540000.2');
    expect(getNumberWithoutExponent('1.235400002e+9'), '1235400002');
    expect(getNumberWithoutExponent('1.235400002e+10'), '12354000020');
  });
}

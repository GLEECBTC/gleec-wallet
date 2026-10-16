// ignore_for_file: avoid_print

import 'package:rational/rational.dart';
import 'package:test/test.dart';
import 'package:web_dex/shared/utils/formatters.dart';

void testFormatDexAmount() {
  test('formatting double DEX amount tests:', () {
    expect(formatDexAmt(0.0), '0');
    expect(formatDexAmt(0.00), '0');
    expect(formatDexAmt(0.000), '0');
    expect(formatDexAmt(0.0000), '0');
    expect(formatDexAmt(0.1), '0.1');
    expect(formatDexAmt(0.100), '0.1');
    expect(formatDexAmt(0.101), '0.101');
    expect(formatDexAmt(0.1010), '0.101');
    expect(formatDexAmt(0.00000001), '0.00000001');
    expect(formatDexAmt(0.000000001), '0');
    expect(formatDexAmt(000.0), '0');
    expect(formatDexAmt(000.1), '0.1');
    expect(formatDexAmt(000.01), '0.01');
  });

  test('formatting Rational DEX amount tests:', () {
    expect(formatDexAmt(Rational.parse('0.0')), '0');
    expect(formatDexAmt(Rational.parse('0.00')), '0');
    expect(formatDexAmt(Rational.parse('0.000')), '0');
    expect(
      formatDexAmt(Rational(BigInt.from(1), BigInt.from(100000))),
      '0.00001',
    );
    expect(
      formatDexAmt(Rational(BigInt.from(001), BigInt.from(100000))),
      '0.00001',
    );
    expect(
      formatDexAmt(Rational(BigInt.from(101), BigInt.from(100000))),
      '0.00101',
    );
  });

  test('formatting int DEX amount tests:', () {
    expect(formatDexAmt(0), '0');
    expect(formatDexAmt(1), '1');
    expect(formatDexAmt(100), '100');
    expect(formatDexAmt(00100), '100');
  });

  test('formatting String DEX amount tests:', () {
    expect(formatDexAmt('0.00'), '0');
    expect(formatDexAmt('000.0'), '0');
    expect(formatDexAmt('000.0001'), '0.0001');
    expect(formatDexAmt('0.00000001'), '0.00000001');
    expect(formatDexAmt('0.000000001'), '0');
  });
}

// ignore_for_file: avoid_print

import 'package:test/test.dart';
import 'package:web_dex/shared/utils/formatters.dart';

void testLeadingZeros() {
  test('get amount of leading zeros tests:', () {
    expect(getLeadingZeros(0.00012002), 3, reason: '0.00012002');
    expect(getLeadingZeros(22), -2, reason: '22');
    expect(getLeadingZeros(333), -3, reason: '33');
    expect(getLeadingZeros(0.12002), 0, reason: '0.12002');
    expect(getLeadingZeros(0.009999), 2, reason: '0.009999');
    expect(getLeadingZeros(0.0002), 3, reason: '0.0002');
    expect(getLeadingZeros(0.0001), 3, reason: '0.0001');
    expect(getLeadingZeros(0.00001), 4, reason: '0.00001');
    expect(getLeadingZeros(0.000001), 5, reason: '0.000001');
    expect(getLeadingZeros(0.0000001), 6, reason: '0.0000001');
    expect(getLeadingZeros(0.00000001), 7, reason: '0.00000001');
    expect(getLeadingZeros(0.000000001), 8, reason: '0.000000001');
    expect(getLeadingZeros(0.0000000001), 9, reason: '0.0000000001');
    expect(getLeadingZeros(0.00000000001), 10, reason: '0.00000000001');
    expect(getLeadingZeros(0.000000000001), 11, reason: '0.000000000001');
    expect(getLeadingZeros(123456789012345), -15, reason: '123456789012345');
    expect(getLeadingZeros(999999999999999), -15, reason: '999999999999999');
  });
}

// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:test/test.dart';
import 'package:web_dex/shared/utils/formatters.dart';

void testDecimalTextInputFormatter() {
  test('formatter of decimal inputs', () {
    final simple1 = _testItemDecimalRange8('123', '123', '123');
    expect(simple1.$1, simple1.$2);
    final comma2dot = _testItemDecimalRange8('123', '123,', '123.');
    expect(comma2dot.$1, comma2dot.$2);
    final dot2dot = _testItemDecimalRange8('123', '123.', '123.');
    expect(dot2dot.$1, dot2dot.$2);
    final decimalRange8 =
        _testItemDecimalRange8('123.12345678', '123.123456789', '123.12345678');
    expect(decimalRange8.$1, decimalRange8.$2);
    // @todo: DmitriiP : Is it expected behavior?
    final notOnlyDigits = _testItemDecimalRange8('123', '123M', '123M');
    expect(notOnlyDigits.$1, notOnlyDigits.$2);
    final addLeadingZero = _testItemDecimalRange8('', ',', '0.');
    expect(addLeadingZero.$1, addLeadingZero.$2);
  });
}

final formatter = DecimalTextInputFormatter(decimalRange: 8);

(TextEditingValue, TextEditingValue) _testItemDecimalRange8(
    String oldValueText, String newValueText, String matcherText) {
  final TextEditingValue oldValue = TextEditingValue(
      text: oldValueText,
      selection: TextSelection.collapsed(offset: oldValueText.length));
  final TextEditingValue newValue = TextEditingValue(
      text: newValueText,
      selection: TextSelection.collapsed(offset: newValueText.length));
  final TextEditingValue matcher = TextEditingValue(
    text: matcherText,
    selection: TextSelection.collapsed(offset: matcherText.length),
  );

  final result = formatter.formatEditUpdate(oldValue, newValue);
  return (result, matcher);
}

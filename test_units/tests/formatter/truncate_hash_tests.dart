import 'package:test/test.dart';
import 'package:web_dex/shared/utils/formatters.dart';

void testTruncateHash() {
  test('Truncate string in the middle with default params', () {
    expect(
        truncateMiddleSymbols(
            '6d6a62bfbe161a06e1c87bc83ac14f9385ced623d93cec3ad32c0a9be1bb324e'),
        '6d6a...1bb324e');
    expect(
        truncateMiddleSymbols(
            '0x6d6a62bfbe161a06e1c87bc83ac14f9385ced623d93cec3ad32c0a9be1bb324e'),
        '0x6d6a...1bb324e');
    expect(truncateMiddleSymbols('0x6d624e'), '0x6d624e');
    expect(truncateMiddleSymbols('0x6d624f9385c'), '0x6d624f9385c');
    expect(truncateMiddleSymbols('0x6d624f9385c123'), '0x6d624f9385c123');
    expect(truncateMiddleSymbols('0x6d624f9385c1234'), '0x6d62...85c1234');
    expect(truncateMiddleSymbols('1'), '1');
    expect(truncateMiddleSymbols(''), '');
  });

  test('Truncate string in the middle with different params', () {
    expect(
        truncateMiddleSymbols(
            '6d6a62bfbe161a06e1c87bc83ac14f9385ced623d93cec3ad32c0a9be1bb324e',
            1,
            1),
        '6...e');
    expect(
        truncateMiddleSymbols(
            '6d6a62bfbe161a06e1c87bc83ac14f9385ced623d93cec3ad32c0a9be1bb324e',
            10,
            10),
        '6d6a62bfbe...9be1bb324e');
    expect(
        truncateMiddleSymbols(
            '6d6a62bfbe161a06e1c87bc83ac14f9385ced623d93cec3ad32c0a9be1bb324e',
            0,
            10),
        '...9be1bb324e');
    expect(truncateMiddleSymbols('', 0, 10), '');
    expect(truncateMiddleSymbols('1234567890', 0, 10), '1234567890');
    expect(truncateMiddleSymbols('1234567890ABC', 0, 10), '1234567890ABC');
    expect(truncateMiddleSymbols('1234567890ABCD', 0, 10), '...567890ABCD');
  });
}

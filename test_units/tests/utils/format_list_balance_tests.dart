import 'package:test/test.dart';
import 'package:web_dex/shared/utils/balance_format.dart';

void testFormatListBalance() {
  test(
    'formatListBalance groups thousands and keeps 2 decimals from 1,000',
    () {
      expect(formatListBalance(14000.12), '14,000.12');
      expect(formatListBalance(4430), '4,430');
      expect(formatListBalance(123456789.5), '123,456,789.5');
    },
  );

  test('formatListBalance keeps 4 decimals between 1 and 1,000', () {
    expect(formatListBalance(227.5), '227.5');
    expect(formatListBalance(1.23456789), '1.2345');
  });

  test('formatListBalance keeps 4 decimals past the leading zeros', () {
    expect(formatListBalance(0.0123), '0.0123');
    expect(formatListBalance(0.000012345678), '0.00001234');
  });

  test('formatListBalance rounds down, never showing more than is held', () {
    expect(formatListBalance(14772.129), '14,772.12');
    expect(formatListBalance(0.99999), '0.9999');
  });

  test('formatListBalance does not round a short decimal down a step', () {
    // Neither has an exact binary form; rounding down must not show 0.2999.
    expect(formatListBalance(0.3), '0.3');
    expect(formatListBalance(1.1), '1.1');
  });

  test('formatListBalance marks dust below the smallest shown digit', () {
    expect(formatListBalance(1e-10), '< 0.00000001');
  });

  test('formatListBalance shows zero and non-finite values plainly', () {
    expect(formatListBalance(0), '0');
    expect(formatListBalance(double.nan), '--');
  });
}

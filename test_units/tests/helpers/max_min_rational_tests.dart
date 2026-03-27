import 'package:rational/rational.dart';
import 'package:test/test.dart';
import 'package:web_dex/views/dex/dex_helpers.dart';

void testMaxMinRational() {
  test('max rational test', () {
    final List<Rational> list = [
      Rational.fromInt(1),
      Rational.fromInt(2),
      Rational.fromInt(3),
    ];
    expect(maxRational(list), Rational.fromInt(3));
    expect(minRational(list), Rational.fromInt(1));

    final List<Rational> list2 = [
      Rational.fromInt(-1),
      Rational.fromInt(0),
      Rational.fromInt(1),
    ];
    expect(maxRational(list2), Rational.fromInt(1));
    expect(minRational(list2), Rational.fromInt(-1));

    final List<Rational> list3 = [
      Rational.fromInt(-1),
      Rational.fromInt(-2),
      Rational.fromInt(-3),
    ];
    expect(maxRational(list3), Rational.fromInt(-1));
    expect(minRational(list3), Rational.fromInt(-3));

    final List<Rational> list4 = [
      Rational.fromInt(1000000000000),
      Rational.fromInt(2000000000000),
      Rational.fromInt(1999999999999),
    ];
    expect(maxRational(list4), Rational.fromInt(2000000000000));
    expect(minRational(list4), Rational.fromInt(1000000000000));
  });
}

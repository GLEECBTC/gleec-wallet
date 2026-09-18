import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'contrast.dart';

void main() => testContrastHelpers();

/// The contrast helpers gate every theme and screen assertion in this suite,
/// so a bug in them would show up as silent green everywhere rather than as a
/// failure here. These cases pin the maths against published WCAG values.
void testContrastHelpers() {
  group('contrastRatio', () {
    test('black on white is the 21:1 maximum', () {
      expect(
        contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21, 1e-9),
      );
    });

    test('a colour against itself is 1:1', () {
      for (final color in const [
        Color(0xFF000000),
        Color(0xFFFFFFFF),
        Color(0xFF8C41FF),
        Color(0xFF456078),
      ]) {
        expect(contrastRatio(color, color), closeTo(1, 1e-9));
      }
    });

    test('is symmetric in its arguments', () {
      const a = Color(0xFF456078);
      const b = Color(0xFFFBFBFB);
      expect(contrastRatio(a, b), closeTo(contrastRatio(b, a), 1e-12));
    });

    test('reproduces the published #777777-on-white boundary value', () {
      // 4.48:1 - just under AA, the canonical worked example.
      expect(
        contrastRatio(const Color(0xFF777777), const Color(0xFFFFFFFF)),
        closeTo(4.48, 0.01),
      );
    });

    test('rejects a translucent argument rather than guessing a backdrop', () {
      expect(
        () => contrastRatio(const Color(0x80000000), const Color(0xFFFFFFFF)),
        throwsArgumentError,
      );
      expect(
        () => contrastRatio(const Color(0xFF000000), const Color(0x80FFFFFF)),
        throwsArgumentError,
      );
    });
  });

  group('compositeOver', () {
    test('50% black over white lands on mid grey', () {
      final blended = compositeOver(
        const Color(0x80000000),
        const Color(0xFFFFFFFF),
      );
      expect(blended.a, 1.0);
      expect((blended.r * 255).round(), closeTo(128, 1));
      expect((blended.g * 255).round(), closeTo(128, 1));
      expect((blended.b * 255).round(), closeTo(128, 1));
    });

    test('a fully transparent layer leaves the background untouched', () {
      expect(
        compositeOver(const Color(0x00FF0000), const Color(0xFF123456)),
        const Color(0xFF123456),
      );
    });
  });

  group('flattenLayers', () {
    test('composites a three-deep stack front-to-back', () {
      final flattened = flattenLayers(const [
        Color(0xFFFFFFFF),
        Color(0x80000000),
        Color(0x80000000),
      ]);
      // Two 50% black passes over white leave 25% luminance-ish grey.
      expect((flattened.r * 255).round(), closeTo(64, 2));
      expect(flattened.a, 1.0);
    });

    test('rejects a translucent base layer', () {
      expect(
        () => flattenLayers(const [Color(0x80FFFFFF), Color(0xFF000000)]),
        throwsArgumentError,
      );
    });

    test('rejects an empty stack', () {
      expect(() => flattenLayers(const []), throwsArgumentError);
    });
  });

  group('expectContrast', () {
    test('names both colours and the shortfall when it fails', () {
      late final String message;
      try {
        expectContrast(
          const Color(0xFF000000),
          const Color(0xFF141414),
          because: 'deliberately failing case',
        );
        fail('expected the assertion to fail');
      } on TestFailure catch (error) {
        message = error.message ?? '';
      }
      expect(message, contains('#ff000000'));
      expect(message, contains('#ff141414'));
      expect(message, contains('needs 4.5:1'));
      expect(message, contains('deliberately failing case'));
    });
  });
}

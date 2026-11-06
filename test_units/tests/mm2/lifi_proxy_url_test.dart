import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/constants.dart';

void main() {
  group('validatedLifiProxyUrl', () {
    test('leaves KDF on the public API when the define is empty', () {
      expect(validatedLifiProxyUrl(''), isNull);
    });

    test('the built-in endpoint is one KDF can use', () {
      // One refused here would silently fall back to the public API.
      expect(validatedLifiProxyUrl(lifiProxyUrl), lifiProxyUrl);
    });

    test('passes an HTTPS proxy URL through, trimmed', () {
      expect(
        validatedLifiProxyUrl(' https://swap.example.com/lifi/ '),
        'https://swap.example.com/lifi/',
      );
    });

    test('accepts plain HTTP to this machine in a debug build', () {
      expect(
        validatedLifiProxyUrl('http://localhost:8080'),
        'http://localhost:8080',
      );
    });

    for (final url in [
      '   ',
      'swap.example.com',
      'http://swap.example.com',
      'ftp://swap.example.com',
      'https://',
      'https://partner:secret@swap.example.com',
      'https://swap.example.com?apiKey=secret',
      'https://swap.example.com/lifi#v1',
    ]) {
      test('refuses "$url"', () {
        expect(validatedLifiProxyUrl(url), isNull);
      });
    }
  });
}

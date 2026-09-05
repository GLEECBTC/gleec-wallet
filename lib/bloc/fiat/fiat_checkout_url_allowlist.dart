/// Canonical allowlist for fiat on-ramp checkout URLs.
///
/// `assets/web_pages/fiat_widget.html` carries a copy of both lists, because
/// already-shipped desktop and mobile builds fetch that page from production
/// and cannot be re-released. A test fails if the two copies drift apart.
library;

/// Hosts that may serve a fiat checkout page, matched exactly.
const List<String> kFiatCheckoutAllowedHosts = <String>[
  'komodo.banxa.com',
  'komodo.banxa-sandbox.com',
  'app.ramp.network',
  'app.demo.ramp.network',
];

/// Provider domains whose sub-domains are also accepted.
///
/// Banxa and Ramp hand out per-partner sub-domains and rename them at their
/// own discretion, so pinning only the exact hosts above would break the live
/// buy flow the first time either provider moves one. Matching the provider's
/// own domain still requires an attacker to control provider infrastructure,
/// at which point they already control the checkout page itself.
const List<String> kFiatCheckoutAllowedDomains = <String>[
  'banxa.com',
  'banxa-sandbox.com',
  'ramp.network',
];

/// Characters that Dart's URI parser and the browser's WHATWG URL parser
/// disagree about. A URL containing any of them can pass a check here and
/// still resolve to a different host in the browser, which is how
/// "reads as the provider, resolves elsewhere" URLs are built. Nothing
/// legitimate needs them.
final RegExp _kAmbiguousUrlCharacters = RegExp(r'[\\\s\u0000-\u001f\u007f]');

/// Whether [url] is an `https` URL served by an approved fiat provider.
///
/// The authoritative check is the one in `fiat_widget.html`, where the URL
/// actually becomes an iframe `src`; this one keeps a rejected URL from
/// getting that far.
bool isAllowedFiatCheckoutUrl(String? url) {
  if (url == null || url.isEmpty) return false;
  if (_kAmbiguousUrlCharacters.hasMatch(url)) return false;

  final Uri? parsed = Uri.tryParse(url);
  if (parsed == null) return false;
  if (parsed.scheme.toLowerCase() != 'https') return false;
  if (!parsed.hasAuthority) return false;
  // `https://komodo.banxa.com@attacker.example/` authenticates to
  // `attacker.example` while reading as the provider.
  if (parsed.userInfo.isNotEmpty) return false;

  return isAllowedFiatCheckoutHost(parsed.host);
}

/// Whether [host] belongs to an approved fiat provider.
bool isAllowedFiatCheckoutHost(String host) {
  var normalized = host.toLowerCase();
  // A trailing dot is the fully-qualified form of the same host.
  while (normalized.endsWith('.')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  if (normalized.isEmpty) return false;

  if (kFiatCheckoutAllowedHosts.contains(normalized)) return true;

  // The leading dot matters: without it `notbanxa.com` would match
  // `banxa.com`.
  return kFiatCheckoutAllowedDomains.any(
    (domain) => normalized == domain || normalized.endsWith('.$domain'),
  );
}
